import Foundation

/// Come si **guadagnano** i power-up: per merito, mai per acquisto.
/// Come le `ScoringRules`, appartengono alla partita/lega e valgono per
/// tutti; in solitaria il giocatore le regola liberamente.
public struct MeritRules: Codable, Hashable, Sendable {
    public var isEnabled: Bool

    /// Ogni serie di `streakLength` risposte corrette consecutive frutta
    /// `streakAward` (il Fusibile, comune, nella taratura di riferimento).
    public var streakLength: Int
    public var streakAward: PowerUpKind

    /// Quiz completato senza errori: premio raro (il Corto circuito).
    /// `nil` per disattivare.
    public var perfectQuizAward: PowerUpKind?

    public init(
        isEnabled: Bool = true,
        streakLength: Int = 3,
        streakAward: PowerUpKind = .lightHideOne,
        perfectQuizAward: PowerUpKind? = .classicHideTwo
    ) {
        self.isEnabled = isEnabled
        self.streakLength = max(1, streakLength)
        self.streakAward = streakAward
        self.perfectQuizAward = perfectQuizAward
    }

    public static let `default` = MeritRules()
    public static let disabled = MeritRules(isEnabled: false)
}
