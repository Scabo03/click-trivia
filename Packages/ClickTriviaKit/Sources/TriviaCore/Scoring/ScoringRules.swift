import Foundation

/// Regole di punteggio: **come si calcola il punteggio**. Appartengono alla
/// partita (o alla lega) e valgono identiche per tutti i partecipanti.
/// Eccezione: in solitaria offline il giocatore le regola liberamente.
/// Mai valori incollati nel codice: tutto ciò che è regolabile sta qui.
public struct ScoringRules: Codable, Hashable, Sendable {
    /// Punti per una risposta corretta, indipendenti dalla velocità.
    public var basePointsPerCorrectAnswer: Int

    /// Politica del bonus velocità. `.none` è la modalità in cui conta solo
    /// la correttezza (nessun vantaggio a chi risponde in fretta).
    public var speedBonus: SpeedBonusPolicy

    /// Finestra di risposta di riferimento su cui è definita la curva del
    /// bonus. Non è un timer rigido: allo scadere non succede nulla di
    /// punitivo, semplicemente il bonus si esaurisce. La `TimingPreference`
    /// personale può dilatarla o renderla irrilevante.
    public var referenceWindow: Duration

    public init(
        basePointsPerCorrectAnswer: Int = 100,
        speedBonus: SpeedBonusPolicy = .curve(.default, maxBonusPoints: 50),
        referenceWindow: Duration = .seconds(30)
    ) {
        self.basePointsPerCorrectAnswer = basePointsPerCorrectAnswer
        self.speedBonus = speedBonus
        self.referenceWindow = referenceWindow
    }

    public static let `default` = ScoringRules()

    /// Preset "conta solo la correttezza".
    public static let accuracyOnly = ScoringRules(speedBonus: .none)
}

public enum SpeedBonusPolicy: Codable, Hashable, Sendable {
    /// Nessun bonus velocità.
    case none
    /// Bonus modulato dalla curva, fino a `maxBonusPoints` al picco.
    case curve(SpeedBonusCurve, maxBonusPoints: Int)
}

/// Calcolo puro del punteggio di una risposta: nessuno stato, facilmente
/// testabile, identico su tutti i dispositivi di una stessa partita.
public struct ScoreCalculator: Sendable {
    public let rules: ScoringRules

    public init(rules: ScoringRules) {
        self.rules = rules
    }

    /// - Parameters:
    ///   - isCorrect: se la risposta scelta è quella giusta.
    ///   - elapsedFraction: momento della risposta come frazione (0...1)
    ///     della finestra di riferimento *personale* del giocatore;
    ///     `nil` quando il tempo non è misurato (preferenza `unlimited`).
    /// - Returns: punti assegnati; una risposta errata vale sempre 0,
    ///   mai punti negativi (l'errore non è una punizione).
    public func points(isCorrect: Bool, elapsedFraction: Double?) -> Int {
        guard isCorrect else { return 0 }
        let base = rules.basePointsPerCorrectAnswer
        switch rules.speedBonus {
        case .none:
            return base
        case .curve(let curve, let maxBonusPoints):
            guard let elapsedFraction else { return base }
            let level = curve.level(atFraction: elapsedFraction)
            return base + Int((Double(maxBonusPoints) * level).rounded())
        }
    }
}
