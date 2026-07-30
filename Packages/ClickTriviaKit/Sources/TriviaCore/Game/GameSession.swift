import Foundation

/// Le modalità di gioco previste dal perimetro tecnico.
public enum GameMode: String, Codable, CaseIterable, Sendable {
    /// Solitaria offline: sempre disponibile, regole liberamente regolabili.
    case soloOffline
    /// In presenza tra dispositivi vicini (Fase 3, Multipeer Connectivity).
    case nearby
    /// A distanza, asincrono (Fase 4, CloudKit).
    case remote
}

/// Configurazione di una partita: le regole sono condivise da tutti i
/// partecipanti (eccetto la solitaria, dove il giocatore le regola a piacere).
public struct MatchConfiguration: Codable, Hashable, Sendable {
    public var mode: GameMode
    public var quizID: Quiz.ID
    public var rules: ScoringRules
    public var merit: MeritRules

    public init(
        mode: GameMode,
        quizID: Quiz.ID,
        rules: ScoringRules = .default,
        merit: MeritRules = .default
    ) {
        self.mode = mode
        self.quizID = quizID
        self.rules = rules
        self.merit = merit
    }
}

/// Una partita: chi gioca, con quali regole, e cosa è successo turno per
/// turno. In Fase 0 è solo stato ben tipizzato; il motore che la fa avanzare
/// arriverà con il single-player (Fase 1).
public struct GameSession: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = EntityID<GameSession>

    public enum Status: Codable, Hashable, Sendable {
        case notStarted
        case inProgress(currentQuestionIndex: Int)
        case completed
    }

    public let id: ID
    public var configuration: MatchConfiguration
    public var participants: [PlayerProfile.ID]
    public var rounds: [RoundRecord]
    public var status: Status
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        id: ID = ID(),
        configuration: MatchConfiguration,
        participants: [PlayerProfile.ID],
        rounds: [RoundRecord] = [],
        status: Status = .notStarted,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.configuration = configuration
        self.participants = participants
        self.rounds = rounds
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// Punteggio totale di un partecipante, somma dei punti assegnati.
    public func totalScore(for playerID: PlayerProfile.ID) -> Int {
        rounds
            .flatMap(\.answers)
            .filter { $0.playerID == playerID }
            .reduce(0) { $0 + $1.awardedPoints }
    }
}

/// Cosa è successo su una singola domanda.
public struct RoundRecord: Codable, Hashable, Sendable {
    public var questionID: Question.ID
    public var answers: [PlayerAnswer]

    public init(questionID: Question.ID, answers: [PlayerAnswer] = []) {
        self.questionID = questionID
        self.answers = answers
    }
}

/// La risposta di un giocatore a una domanda.
public struct PlayerAnswer: Codable, Hashable, Sendable {
    public var playerID: PlayerProfile.ID
    /// `nil` = nessuna risposta data.
    public var selectedOptionID: AnswerOption.ID?
    /// Momento della risposta come frazione (0...1) della finestra personale;
    /// `nil` quando il tempo non è misurato (preferenza `unlimited`).
    public var elapsedFraction: Double?
    /// Power-up giocati su questa domanda (meccanica di partita: la domanda
    /// non ne sa nulla).
    public var powerUpsUsed: [PowerUpKind]
    public var awardedPoints: Int

    public init(
        playerID: PlayerProfile.ID,
        selectedOptionID: AnswerOption.ID?,
        elapsedFraction: Double? = nil,
        powerUpsUsed: [PowerUpKind] = [],
        awardedPoints: Int = 0
    ) {
        self.playerID = playerID
        self.selectedOptionID = selectedOptionID
        self.elapsedFraction = elapsedFraction
        self.powerUpsUsed = powerUpsUsed
        self.awardedPoints = awardedPoints
    }
}
