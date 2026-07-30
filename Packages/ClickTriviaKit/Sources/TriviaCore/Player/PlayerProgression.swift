import Foundation

/// Avanzamento e storico del giocatore. Agganciato al `PlayerProfile.ID`
/// stabile: rinominare il profilo non tocca nulla di ciò che sta qui.
public struct PlayerProgression: Codable, Hashable, Sendable {
    public var totalAnswered: Int
    public var totalCorrect: Int
    public var totalPoints: Int
    /// Power-up guadagnati nel tempo, con la motivazione (per merito).
    public var awards: [PowerUpAward]
    public var matchHistory: [MatchSummary]

    public init(
        totalAnswered: Int = 0,
        totalCorrect: Int = 0,
        totalPoints: Int = 0,
        awards: [PowerUpAward] = [],
        matchHistory: [MatchSummary] = []
    ) {
        self.totalAnswered = totalAnswered
        self.totalCorrect = totalCorrect
        self.totalPoints = totalPoints
        self.awards = awards
        self.matchHistory = matchHistory
    }

    public static let empty = PlayerProgression()
}

/// Esito sintetico di una partita conclusa, per lo storico personale.
public struct MatchSummary: Codable, Hashable, Sendable {
    public var sessionID: GameSession.ID
    public var date: Date
    public var mode: GameMode
    public var finalScore: Int
    /// Posizione in classifica (1 = primo); `nil` in solitaria.
    public var ranking: Int?

    public init(
        sessionID: GameSession.ID,
        date: Date,
        mode: GameMode,
        finalScore: Int,
        ranking: Int? = nil
    ) {
        self.sessionID = sessionID
        self.date = date
        self.mode = mode
        self.finalScore = finalScore
        self.ranking = ranking
    }
}
