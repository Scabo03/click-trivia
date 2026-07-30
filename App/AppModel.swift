import Foundation
import OSLog
import TriviaAccessibility
import TriviaCore
import TriviaImport
import TriviaNearby
import TriviaPersistence

/// Radice della composizione: qui si scelgono le implementazioni concrete
/// (store su file, canali di feedback) e vive il ciclo di vita della partita.
/// Il resto dell'app dipende solo da protocolli e tipi del dominio.
@MainActor
@Observable
final class AppModel {
    let systemAccessibility: SystemAccessibilitySettings
    let visualCues: VisualCueRelay
    let feedback: FeedbackCenter

    private(set) var activeProfile: PlayerProfile
    private(set) var currentMatch: SoloMatchEngine?
    private(set) var nearbyMatch: NearbyMatchController?

    /// I quiz giocabili: quello integrato più gli importati (persistiti).
    private(set) var quizzes: [Quiz] = [Quiz.sample]

    /// Regole della partita in solitaria: il giocatore le regola liberamente
    /// (in presenza e a distanza saranno invece quelle comuni della partita).
    var soloRules = ScoringRules.default

    private let profileStore: any PlayerProfileStore
    private let sessionStore: (any GameSessionStore)?
    private let quizStore: (any QuizStore)?
    private let importer = KahootTemplateImporter()
    private let logger = Logger(subsystem: "ClickTrivia", category: "app")

    init() {
        let system = SystemAccessibilitySettings()
        let visualCues = VisualCueRelay()
        self.systemAccessibility = system
        self.visualCues = visualCues

        // Se Application Support non fosse accessibile si degrada in memoria:
        // l'app deve restare giocabile in ogni circostanza.
        do {
            let directory = try PersistenceLocation.dataDirectory()
            self.profileStore = JSONPlayerProfileStore(directory: directory)
            self.sessionStore = JSONGameSessionStore(directory: directory)
            self.quizStore = JSONQuizStore(directory: directory)
        } catch {
            self.profileStore = InMemoryPlayerProfileStore()
            self.sessionStore = nil
            self.quizStore = nil
        }

        let profile = PlayerProfile(nickname: String(localized: "Giocatore 1"))
        self.activeProfile = profile

        self.feedback = FeedbackCenter(
            preferences: profile.preferences,
            system: system,
            audio: SynthesizedAudioChannel(),
            haptics: HapticChannelFactory.makeDefault(),
            visual: visualCues
        )
    }

    // MARK: - Profilo

    /// Carica il profilo salvato (o crea e salva quello iniziale) e i quiz.
    func loadOrCreateProfile() async {
        do {
            if let saved = try await profileStore.loadAll().first {
                activeProfile = saved
            } else {
                try await profileStore.save(activeProfile)
            }
            feedback.preferences = activeProfile.preferences
        } catch {
            logger.error("Caricamento profilo fallito: \(error.localizedDescription)")
        }
        await reloadQuizzes()
    }

    private func reloadQuizzes() async {
        let imported = (try? await quizStore?.loadAll()) ?? []
        quizzes = [Quiz.sample] + imported.sorted { $0.title < $1.title }
    }

    /// Aggiorna il profilo (nickname, preferenze, inventario) e lo salva.
    /// L'`id` è immutabile per costruzione: rinominare non perde nulla.
    func update(_ profile: PlayerProfile) async {
        activeProfile = profile
        feedback.preferences = profile.preferences
        do {
            try await profileStore.save(profile)
        } catch {
            logger.error("Salvataggio profilo fallito: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    /// Legge il file scelto e produce la bozza da rivedere. L'accesso è
    /// security-scoped: il file resta dell'utente, se ne legge una copia.
    func makeDraft(from url: URL) throws -> QuizDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try importer.draft(fromFileNamed: url.lastPathComponent, data: data)
    }

    /// Salva il quiz confermato dall'anteprima e aggiorna l'elenco.
    func saveImportedQuiz(_ quiz: Quiz) async {
        guard let quizStore else {
            quizzes.append(quiz)
            return
        }
        do {
            try await quizStore.save(quiz)
            await reloadQuizzes()
        } catch {
            logger.error("Salvataggio quiz importato fallito: \(error.localizedDescription)")
            quizzes.append(quiz)
        }
    }

    // MARK: - Partita

    func startSoloMatch(quiz: Quiz) {
        let configuration = MatchConfiguration(
            mode: .soloOffline,
            quizID: quiz.id,
            rules: soloRules
        )
        let engine = SoloMatchEngine(
            quiz: quiz,
            configuration: configuration,
            profile: activeProfile
        )
        engine.onEvent = { [weak self] event in
            self?.feedback.announce(event)
        }
        currentMatch = engine
        engine.start()
    }

    /// Chiusura regolare: riversa il risultato nel profilo e salva tutto.
    func finishMatch(_ result: SoloMatchEngine.MatchResult) async {
        var profile = activeProfile
        profile.inventory = result.remainingInventory
        profile.progression.totalAnswered += result.questionCount
        profile.progression.totalCorrect += result.correctCount
        profile.progression.totalPoints += result.totalScore
        profile.progression.awards.append(contentsOf: result.earnedAwards)
        profile.progression.matchHistory.append(result.summary)
        await update(profile)

        if let sessionStore {
            do {
                try await sessionStore.save(result.session)
            } catch {
                logger.error("Salvataggio sessione fallito: \(error.localizedDescription)")
            }
        }
        currentMatch = nil
    }

    /// Abbandono: nessun effetto sul profilo.
    func abandonMatch() {
        currentMatch?.abort()
        currentMatch = nil
    }

    // MARK: - In presenza

    /// Apre una sala: le regole comuni della partita sono quelle
    /// dell'organizzatore; power-up e merito arriveranno in presenza con un
    /// bilanciamento dedicato (per ora disattivati).
    func hostNearbyMatch(quiz: Quiz) {
        let configuration = MatchConfiguration(
            mode: .nearby,
            quizID: quiz.id,
            rules: soloRules,
            merit: .disabled
        )
        let controller = NearbyMatchController(
            hosting: quiz,
            configuration: configuration,
            profile: activeProfile
        )
        wire(controller)
        nearbyMatch = controller
    }

    func joinNearbyMatch() {
        let controller = NearbyMatchController(joining: activeProfile)
        wire(controller)
        nearbyMatch = controller
    }

    private func wire(_ controller: NearbyMatchController) {
        controller.onEvent = { [weak self] event, detail in
            self?.feedback.announce(event, voiceOverDetail: detail)
        }
        controller.onStatusAnnouncement = { [weak self] text in
            self?.feedback.announceStatus(text)
        }
    }

    /// Uscita dalla sala; a partita conclusa i propri risultati entrano
    /// nel profilo (posizione compresa).
    func leaveNearbyMatch() {
        guard let controller = nearbyMatch else { return }

        if let standing = controller.myStanding {
            var profile = activeProfile
            profile.progression.totalAnswered += controller.questionCount
            profile.progression.totalCorrect += controller.myCorrectCount
            profile.progression.totalPoints += controller.myTotalScore
            profile.progression.matchHistory.append(MatchSummary(
                sessionID: GameSession.ID(),
                date: Date(),
                mode: .nearby,
                finalScore: controller.myTotalScore,
                ranking: standing.rank
            ))
            Task {
                await self.update(profile)
            }
        }

        controller.leave()
        nearbyMatch = nil
    }
}
