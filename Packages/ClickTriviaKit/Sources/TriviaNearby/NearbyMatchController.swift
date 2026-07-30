import Foundation
import Observation
import TriviaCore

/// La partita in presenza, per entrambi i ruoli. Macchina a stati
/// osservabile: ogni transizione ha un riscontro sui canali accessibili
/// (via `onEvent` → FeedbackCenter) e uno stato testuale leggibile nelle
/// viste — mai segnali solo visivi.
///
/// L'organizzatore è l'autorità: accetta gli ingressi, avvia, calcola i
/// punteggi con le regole comuni (NearbyScorekeeper) e detta l'avanzamento.
@MainActor
@Observable
public final class NearbyMatchController {

    public enum Role: Sendable {
        case host
        case guest
    }

    public enum EndReason: Hashable, Sendable {
        /// L'organizzatore ha chiuso la sala.
        case hostLeft
        /// Connessione persa.
        case connectionLost
        /// Richiesta non accettata, oppure sala piena (massimo 8).
        case declinedOrFull
    }

    public enum Stage: Hashable, Sendable {
        /// Ospite: ricerca delle sale vicine.
        case browsing
        /// Ospite: richiesta inviata, in attesa dell'organizzatore.
        case requesting(hostName: String)
        /// In sala, prima dell'avvio.
        case lobby
        /// Domanda sullo schermo, in attesa della mia risposta.
        case question(index: Int)
        /// Ho risposto: attendo gli altri.
        case awaitingOthers(index: Int)
        /// Esiti del turno.
        case review(RoundResultsPayload)
        /// Classifica finale.
        case finished(FinalResultsPayload)
        /// Sala chiusa, con il motivo (da spiegare, mai solo sparire).
        case ended(EndReason)
    }

    public let role: Role
    public private(set) var stage: Stage
    public private(set) var room: RoomState
    public private(set) var rooms: [MultipeerTransport.DiscoveredRoom] = []
    public private(set) var pendingRequests: [MultipeerTransport.PendingJoinRequest] = []
    public private(set) var quiz: Quiz?
    public private(set) var configuration: MatchConfiguration?
    public private(set) var answeredCount = 0
    public private(set) var expectedAnswers = 0
    public private(set) var myTotalScore = 0
    public private(set) var myCorrectCount = 0
    /// Inizio della domanda corrente, per il misuratore del bonus.
    public private(set) var questionStartDate: Date?

    /// Eventi di dominio + dettaglio vocale specifico ("Sara è entrata").
    public var onEvent: ((GameEvent, String?) -> Void)?
    /// Annunci di stato multi-canale (richieste in arrivo, sala piena...).
    public var onStatusAnnouncement: ((String) -> Void)?

    private let transport: MultipeerTransport
    private let profile: PlayerProfile
    private var scorekeeper: NearbyScorekeeper?
    private var pendingAnswers: [PlayerProfile.ID: AnswerPayload] = [:]
    private let bonusScheduler = BonusSignalScheduler()
    private var questionStart: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    // MARK: - Avvio

    /// Organizzatore: apre la sala con quiz e regole comuni già decisi.
    public init(hosting quiz: Quiz, configuration: MatchConfiguration, profile: PlayerProfile) {
        self.role = .host
        self.profile = profile
        self.quiz = quiz
        self.configuration = configuration
        self.transport = MultipeerTransport()
        self.stage = .lobby
        self.room = RoomState(
            hostName: profile.nickname,
            quizTitle: quiz.title,
            participants: [
                NearbyParticipant(id: profile.id, nickname: profile.nickname, isHost: true),
            ]
        )
        wireTransport()
        transport.startHosting(as: JoinRequestPayload(playerID: profile.id, nickname: profile.nickname))
    }

    /// Ospite: cerca le sale vicine.
    public init(joining profile: PlayerProfile) {
        self.role = .guest
        self.profile = profile
        self.transport = MultipeerTransport()
        self.stage = .browsing
        self.room = RoomState(hostName: "", quizTitle: "", participants: [])
        wireTransport()
        transport.startBrowsing(as: JoinRequestPayload(playerID: profile.id, nickname: profile.nickname))
    }

    /// Uscita volontaria: l'host chiude la sala per tutti.
    public func leave() {
        if role == .host {
            transport.send(.hostLeft)
        }
        bonusScheduler.cancel()
        transport.stop()
    }

    // MARK: - Azioni ospite

    public func requestJoin(_ discovered: MultipeerTransport.DiscoveredRoom) {
        guard role == .guest, case .browsing = stage else { return }
        stage = .requesting(hostName: discovered.hostName)
        onStatusAnnouncement?(String(localized: "Richiesta inviata a \(discovered.hostName). In attesa dell'organizzatore."))
        transport.requestJoin(discovered)
    }

    // MARK: - Azioni organizzatore

    public func respond(to request: MultipeerTransport.PendingJoinRequest, accept: Bool) {
        guard role == .host else { return }
        transport.respond(to: request, accept: accept)
        if !accept {
            onStatusAnnouncement?(String(localized: "Richiesta di \(request.payload.nickname) rifiutata."))
        }
    }

    public var canStartMatch: Bool {
        role == .host && stage == .lobby && room.participants.count >= 2
    }

    public func startMatch() {
        guard canStartMatch, let quiz, let configuration else { return }
        scorekeeper = NearbyScorekeeper(rules: configuration.rules)
        transport.send(.matchBegan(quiz: quiz, configuration: configuration))
        onEvent?(.matchStarted, nil)
        beginQuestion(0)
        transport.send(.questionBegan(index: 0))
    }

    /// L'host avanza quando il gruppo è pronto (anche se qualcuno non ha
    /// ancora risposto: la risposta mancata vale zero, mai penalità).
    public func advance() {
        guard role == .host, let quiz else { return }
        let currentIndex: Int
        switch stage {
        case .review(let results):
            currentIndex = results.questionIndex
        case .question(let index), .awaitingOthers(let index):
            // Avanzamento forzato a turno ancora aperto: si chiude il turno.
            completeRound(questionIndex: index)
            return
        default:
            return
        }

        let next = currentIndex + 1
        if next < quiz.questions.count {
            beginQuestion(next)
            transport.send(.questionBegan(index: next))
        } else {
            finishMatch()
        }
    }

    // MARK: - Gioco (entrambi i ruoli)

    public var currentQuestion: Question? {
        let index: Int
        switch stage {
        case .question(let i), .awaitingOthers(let i): index = i
        case .review(let results): index = results.questionIndex
        default: return nil
        }
        guard let quiz, quiz.questions.indices.contains(index) else { return nil }
        return quiz.questions[index]
    }

    /// La finestra personale: regole comuni, tempi propri.
    public var personalWindow: Duration? {
        guard let configuration,
              let multiplier = profile.preferences.timing.windowMultiplier else { return nil }
        return configuration.rules.referenceWindow.scaled(by: multiplier)
    }

    public func submitAnswer(_ optionID: AnswerOption.ID?) {
        guard case .question(let index) = stage else { return }
        bonusScheduler.cancel()

        let elapsedFraction: Double? = {
            guard let window = personalWindow, let start = questionStart else { return nil }
            return start.duration(to: clock.now).seconds / window.seconds
        }()

        let payload = AnswerPayload(
            playerID: profile.id,
            questionIndex: index,
            selectedOptionID: optionID,
            elapsedFraction: elapsedFraction
        )

        stage = .awaitingOthers(index: index)
        onStatusAnnouncement?(String(localized: "Risposta inviata. In attesa degli altri."))

        if role == .host {
            handleAnswer(payload)
        } else {
            transport.send(.answerSubmitted(payload))
        }
    }

    // MARK: - Interni: flusso domande

    private func beginQuestion(_ index: Int) {
        pendingAnswers = [:]
        answeredCount = 0
        expectedAnswers = room.participants.count
        stage = .question(index: index)
        questionStart = clock.now
        questionStartDate = Date()
        onEvent?(.questionPresented, nil)
        scheduleBonusSignals(for: index)
    }

    private func scheduleBonusSignals(for index: Int) {
        guard let configuration,
              case .curve(let curve, _) = configuration.rules.speedBonus,
              let window = personalWindow else {
            bonusScheduler.cancel()
            return
        }
        bonusScheduler.schedule(curve: curve, window: window) { [weak self] in
            guard let self, case .question(index) = self.stage else { return }
            self.onEvent?(.bonusWindowOpened, nil)
        } onPeak: { [weak self] in
            guard let self, case .question(index) = self.stage else { return }
            self.onEvent?(.bonusPeak, nil)
        }
    }

    private func handleAnswer(_ payload: AnswerPayload) {
        guard role == .host else { return }
        let activeIndex: Int
        switch stage {
        case .question(let i), .awaitingOthers(let i): activeIndex = i
        default: return
        }
        guard payload.questionIndex == activeIndex,
              pendingAnswers[payload.playerID] == nil,
              room.participants.contains(where: { $0.id == payload.playerID }) else { return }

        pendingAnswers[payload.playerID] = payload
        answeredCount = pendingAnswers.count
        expectedAnswers = room.participants.count
        transport.send(.answerProgress(answered: answeredCount, total: expectedAnswers))

        if answeredCount >= expectedAnswers {
            completeRound(questionIndex: activeIndex)
        }
    }

    private func completeRound(questionIndex: Int) {
        guard role == .host, let quiz,
              quiz.questions.indices.contains(questionIndex),
              scorekeeper != nil else { return }
        let results = scorekeeper!.score(
            question: quiz.questions[questionIndex],
            questionIndex: questionIndex,
            answers: Array(pendingAnswers.values),
            roster: room.participants
        )
        transport.send(.roundResults(results))
        applyRoundResults(results)
    }

    private func applyRoundResults(_ results: RoundResultsPayload) {
        bonusScheduler.cancel()
        stage = .review(results)
        if let mine = results.entries.first(where: { $0.playerID == profile.id }) {
            myTotalScore = mine.totalScore
            if mine.isCorrect { myCorrectCount += 1 }
            onEvent?(mine.isCorrect ? .circuitClosed : .circuitBroken, nil)
        }
    }

    private func finishMatch() {
        guard role == .host, let scorekeeper else { return }
        let final = scorekeeper.finalStandings(roster: room.participants)
        transport.send(.matchEnded(final))
        applyFinal(final)
    }

    private func applyFinal(_ final: FinalResultsPayload) {
        bonusScheduler.cancel()
        stage = .finished(final)
        onEvent?(.matchEnded, nil)
    }

    public var myStanding: FinalStanding? {
        guard case .finished(let final) = stage else { return nil }
        return final.standings.first { $0.playerID == profile.id }
    }

    public var questionCount: Int { quiz?.questions.count ?? 0 }

    // MARK: - Interni: trasporto

    private func wireTransport() {
        transport.onRoomsChanged = { [weak self] rooms in
            self?.rooms = rooms
        }
        transport.onPendingRequestsChanged = { [weak self] requests in
            guard let self else { return }
            let previous = Set(self.pendingRequests.map(\.id))
            self.pendingRequests = requests
            for request in requests where !previous.contains(request.id) {
                self.onStatusAnnouncement?(String(localized: "\(request.payload.nickname) chiede di entrare nella sala."))
            }
        }
        transport.onRoomFullAutoDecline = { [weak self] nickname in
            guard let self else { return }
            self.onStatusAnnouncement?(String(localized: "Sala piena: \(self.room.capacity) dispositivi su \(self.room.capacity). La richiesta di \(nickname) è stata rifiutata automaticamente."))
        }
        transport.onGuestConnected = { [weak self] payload in
            guard let self else { return }
            self.room.participants.append(NearbyParticipant(
                id: payload.playerID,
                nickname: payload.nickname,
                isHost: false
            ))
            self.transport.send(.roomUpdated(self.room))
            self.onEvent?(.peerJoined, String(localized: "\(payload.nickname) è entrato nella sala. Siete \(self.room.participants.count) su \(self.room.capacity)."))
        }
        transport.onGuestDisconnected = { [weak self] payload in
            guard let self else { return }
            self.room.participants.removeAll { $0.id == payload.playerID }
            self.transport.send(.roomUpdated(self.room))
            self.onEvent?(.peerLeft, String(localized: "\(payload.nickname) ha lasciato la sala."))
            // A turno aperto, l'attesa si accorcia: si ricontrolla il quorum.
            if case .question(let index) = self.stage {
                self.expectedAnswers = self.room.participants.count
                if self.answeredCount >= self.expectedAnswers {
                    self.completeRound(questionIndex: index)
                }
            } else if case .awaitingOthers(let index) = self.stage {
                self.expectedAnswers = self.room.participants.count
                if self.answeredCount >= self.expectedAnswers {
                    self.completeRound(questionIndex: index)
                }
            }
        }
        transport.onConnectedToHost = { [weak self] in
            guard let self else { return }
            self.stage = .lobby
            self.onEvent?(.peerJoined, String(localized: "Sei nella sala. In attesa dell'organizzatore."))
        }
        transport.onDisconnectedFromHost = { [weak self] in
            guard let self else { return }
            switch self.stage {
            case .requesting:
                self.stage = .ended(.declinedOrFull)
                self.onStatusAnnouncement?(String(localized: "La richiesta non è stata accettata, oppure la sala è piena (massimo \(NearbyConstants.maxPeersPerSession) dispositivi)."))
            case .finished, .ended:
                break
            default:
                self.stage = .ended(.connectionLost)
                self.onEvent?(.connectionLost, nil)
            }
        }
        transport.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    private func handleMessage(_ message: NearbyMessage) {
        switch message {
        case .roomUpdated(let newRoom):
            guard role == .guest else { return }
            announceRoomDiff(old: room, new: newRoom)
            room = newRoom
        case .matchBegan(let quiz, let configuration):
            guard role == .guest else { return }
            self.quiz = quiz
            self.configuration = configuration
            onEvent?(.matchStarted, nil)
        case .questionBegan(let index):
            guard role == .guest else { return }
            beginQuestion(index)
        case .answerSubmitted(let payload):
            handleAnswer(payload)
        case .answerProgress(let answered, let total):
            guard role == .guest else { return }
            answeredCount = answered
            expectedAnswers = total
        case .roundResults(let results):
            guard role == .guest else { return }
            applyRoundResults(results)
        case .matchEnded(let final):
            guard role == .guest else { return }
            applyFinal(final)
        case .hostLeft:
            guard role == .guest else { return }
            transport.stop()
            stage = .ended(.hostLeft)
            onEvent?(.connectionLost, String(localized: "L'organizzatore ha chiuso la sala."))
        }
    }

    private func announceRoomDiff(old: RoomState, new: RoomState) {
        let oldIDs = Set(old.participants.map(\.id))
        let newIDs = Set(new.participants.map(\.id))
        for participant in new.participants where !oldIDs.contains(participant.id) {
            if participant.id != profile.id {
                onEvent?(.peerJoined, String(localized: "\(participant.nickname) è entrato nella sala. Siete \(new.participants.count) su \(new.capacity)."))
            }
        }
        for participant in old.participants where !newIDs.contains(participant.id) {
            onEvent?(.peerLeft, String(localized: "\(participant.nickname) ha lasciato la sala."))
        }
    }
}
