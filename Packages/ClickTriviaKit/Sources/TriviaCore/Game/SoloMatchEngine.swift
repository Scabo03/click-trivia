import Foundation
import Observation

/// Il motore della partita in solitaria: macchina a stati osservabile che
/// fa avanzare la sessione, calcola i punti, applica i power-up e assegna
/// i premi di merito.
///
/// Non sa nulla di suoni, aptica o viste: emette `GameEvent` tramite
/// `onEvent` e chi compone l'app li collega al FeedbackCenter. Il tempo è
/// misurato sulla **finestra personale** del giocatore (quella di riferimento
/// della partita, scalata dalla sua `TimingPreference`): i segnali del bonus
/// scoccano lì, e con tempi illimitati o bonus disattivato semplicemente
/// non esistono. Niente timer rigido: allo scadere della finestra non
/// succede nulla, il bonus si esaurisce e basta.
@MainActor
@Observable
public final class SoloMatchEngine {

    public enum Phase: Hashable, Sendable {
        case idle
        /// La domanda è sullo schermo, in attesa di risposta.
        case presenting(questionIndex: Int)
        /// Risposta data: si mostrano esito e spiegazione.
        case reviewing(questionIndex: Int, outcome: AnswerOutcome)
        case finished(MatchResult)
    }

    /// L'esito di una risposta, pronto per essere presentato.
    public struct AnswerOutcome: Hashable, Sendable {
        public let selectedOptionID: AnswerOption.ID?
        public let isCorrect: Bool
        public let awardedPoints: Int
        public let correctOptionID: AnswerOption.ID
        public let explanation: String?
    }

    /// Il riepilogo finale, da riversare nel profilo a fine partita.
    public struct MatchResult: Hashable, Sendable {
        public let session: GameSession
        public let summary: MatchSummary
        public let totalScore: Int
        public let correctCount: Int
        public let questionCount: Int
        public let earnedAwards: [PowerUpAward]
        public let remainingInventory: PowerUpInventory
    }

    public enum EngineError: Error, Equatable, Sendable {
        /// Il power-up non è applicabile ora (es. resterebbe visibile solo
        /// la risposta giusta). Non viene consumato.
        case powerUpNotApplicable
    }

    public let quiz: Quiz
    public let configuration: MatchConfiguration

    public private(set) var phase: Phase = .idle
    public private(set) var inventory: PowerUpInventory
    public private(set) var hiddenOptionIDs: Set<AnswerOption.ID> = []
    public private(set) var totalScore = 0
    public private(set) var streak = 0
    public private(set) var earnedAwards: [PowerUpAward] = []
    /// Inizio della domanda corrente, per il misuratore del bonus nelle viste.
    public private(set) var questionStartDate: Date?

    private let playerID: PlayerProfile.ID
    private let timing: TimingPreference
    private var session: GameSession
    private var powerUpsUsedThisQuestion: [PowerUpKind] = []
    private var correctCount = 0
    private var questionStart: ContinuousClock.Instant?
    private let bonusScheduler = BonusSignalScheduler()
    private let clock = ContinuousClock()

    /// Collegato dal compositore dell'app al FeedbackCenter.
    public var onEvent: ((GameEvent) -> Void)?

    public init(quiz: Quiz, configuration: MatchConfiguration, profile: PlayerProfile) {
        self.quiz = quiz
        self.configuration = configuration
        self.playerID = profile.id
        self.timing = profile.preferences.timing
        self.inventory = profile.inventory
        self.session = GameSession(
            configuration: configuration,
            participants: [profile.id]
        )
    }

    /// La finestra di risposta personale: quella di riferimento della
    /// partita, scalata dai tempi estesi; `nil` con tempi illimitati.
    public var personalWindow: Duration? {
        guard let multiplier = timing.windowMultiplier else { return nil }
        return configuration.rules.referenceWindow.scaled(by: multiplier)
    }

    public var questionCount: Int { quiz.questions.count }

    public var currentQuestionIndex: Int? {
        switch phase {
        case .presenting(let index): index
        case .reviewing(let index, _): index
        case .idle, .finished: nil
        }
    }

    public var currentQuestion: Question? {
        guard let index = currentQuestionIndex,
              quiz.questions.indices.contains(index) else { return nil }
        return quiz.questions[index]
    }

    /// Le opzioni ancora visibili (i power-up nascondono, mai la domanda).
    public func visibleOptions(for question: Question) -> [AnswerOption] {
        question.options.filter { !hiddenOptionIDs.contains($0.id) }
    }

    // MARK: - Flusso

    public func start() {
        guard case .idle = phase else { return }
        session.startedAt = Date()
        onEvent?(.matchStarted)
        present(questionAt: 0)
    }

    public func submitAnswer(_ optionID: AnswerOption.ID?) {
        guard case .presenting(let index) = phase else { return }
        bonusScheduler.cancel()

        let question = quiz.questions[index]
        let elapsedFraction: Double? = {
            guard let window = personalWindow, let start = questionStart else { return nil }
            return start.duration(to: clock.now).seconds / window.seconds
        }()

        let isCorrect = optionID.map(question.isCorrect) ?? false
        let points = ScoreCalculator(rules: configuration.rules)
            .points(isCorrect: isCorrect, elapsedFraction: elapsedFraction)

        totalScore += points
        if isCorrect {
            correctCount += 1
            streak += 1
        } else {
            streak = 0
        }

        let answer = PlayerAnswer(
            playerID: playerID,
            selectedOptionID: optionID,
            elapsedFraction: elapsedFraction,
            powerUpsUsed: powerUpsUsedThisQuestion,
            awardedPoints: points
        )
        session.rounds.append(RoundRecord(questionID: question.id, answers: [answer]))

        onEvent?(isCorrect ? .circuitClosed : .circuitBroken)

        let merit = configuration.merit
        if isCorrect, merit.isEnabled, streak > 0, streak.isMultiple(of: merit.streakLength) {
            grant(merit.streakAward, reason: .correctStreak(length: streak))
        }

        phase = .reviewing(
            questionIndex: index,
            outcome: AnswerOutcome(
                selectedOptionID: optionID,
                isCorrect: isCorrect,
                awardedPoints: points,
                correctOptionID: question.correctOptionID,
                explanation: question.explanation
            )
        )
    }

    public func advance() {
        guard case .reviewing(let index, _) = phase else { return }
        present(questionAt: index + 1)
    }

    /// Interrompe la partita senza riversare nulla nel profilo.
    public func abort() {
        bonusScheduler.cancel()
        phase = .idle
    }

    // MARK: - Power-up

    /// Gioca un power-up "nascondi sbagliate" sulla domanda corrente.
    /// Regola: resta sempre visibile almeno una risposta sbagliata (il
    /// power-up aiuta, non rivela); se non c'è margine, non viene consumato.
    public func useHidePowerUp(_ kind: PowerUpKind) throws {
        guard case .presenting(let index) = phase,
              case .hideIncorrectAnswers(let count) = kind else {
            throw EngineError.powerUpNotApplicable
        }
        let question = quiz.questions[index]
        let candidates = question.incorrectOptionIDs.filter { !hiddenOptionIDs.contains($0) }
        let effective = min(count, candidates.count - 1)
        guard effective > 0 else {
            throw EngineError.powerUpNotApplicable
        }

        try inventory.use(kind)
        hiddenOptionIDs.formUnion(candidates.shuffled().prefix(effective))
        powerUpsUsedThisQuestion.append(kind)
        onEvent?(.powerUpUsed)
    }

    // MARK: - Interni

    private func present(questionAt index: Int) {
        guard quiz.questions.indices.contains(index) else {
            finish()
            return
        }
        hiddenOptionIDs = []
        powerUpsUsedThisQuestion = []
        session.status = .inProgress(currentQuestionIndex: index)
        phase = .presenting(questionIndex: index)
        questionStart = clock.now
        questionStartDate = Date()
        onEvent?(.questionPresented)
        scheduleBonusSignals(for: index)
    }

    /// Il momento-bonus: due segnali temporizzati sulla finestra personale.
    /// Chi li riceve (FeedbackCenter) li porta per contratto su tutti e tre
    /// i canali. Nessun segnale con bonus disattivato o tempi illimitati.
    private func scheduleBonusSignals(for index: Int) {
        guard case .curve(let curve, _) = configuration.rules.speedBonus,
              let window = personalWindow else {
            bonusScheduler.cancel()
            return
        }
        bonusScheduler.schedule(curve: curve, window: window) { [weak self] in
            guard let self, self.isPresenting(index) else { return }
            self.onEvent?(.bonusWindowOpened)
        } onPeak: { [weak self] in
            guard let self, self.isPresenting(index) else { return }
            self.onEvent?(.bonusPeak)
        }
    }

    private func isPresenting(_ index: Int) -> Bool {
        if case .presenting(index) = phase { return true }
        return false
    }

    private func grant(_ kind: PowerUpKind, reason: PowerUpAward.Reason) {
        inventory.add(kind)
        earnedAwards.append(PowerUpAward(kind: kind, reason: reason, date: Date()))
        onEvent?(.powerUpEarned)
    }

    private func finish() {
        bonusScheduler.cancel()
        session.status = .completed
        session.endedAt = Date()

        let merit = configuration.merit
        if merit.isEnabled,
           let perfectAward = merit.perfectQuizAward,
           !quiz.questions.isEmpty,
           correctCount == quiz.questions.count {
            grant(perfectAward, reason: .perfectQuiz(quizID: quiz.id))
        }

        onEvent?(.matchEnded)

        let summary = MatchSummary(
            sessionID: session.id,
            date: Date(),
            mode: configuration.mode,
            finalScore: totalScore
        )
        phase = .finished(
            MatchResult(
                session: session,
                summary: summary,
                totalScore: totalScore,
                correctCount: correctCount,
                questionCount: quiz.questions.count,
                earnedAwards: earnedAwards,
                remainingInventory: inventory
            )
        )
    }
}
