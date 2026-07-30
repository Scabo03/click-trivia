import Foundation

/// La curva del bonus velocità, definita su frazioni (0...1) della finestra
/// di riferimento. Concettualmente:
///
/// ```
/// livello
///  1.0 ┤              ●  picco (di norma a metà finestra)
///      │            ／  ＼
///  0.35┤        ●／       ＼
///      │      ／             ＼
///  0.0 ┤●——●／                  ＼—●
///      └┴────┴────┴─────────────┴──→ frazione del tempo
///       0  quietLeadIn   0.5       1
/// ```
///
/// Nessun bonus nella parte iniziale (niente premio al riflesso puro),
/// un livello intermedio in salita, il picco, poi decadimento dolce.
/// Il momento del picco è l'evento segnalato sui tre canali insieme
/// (sonoro, aptico, visivo) da TriviaAccessibility.
///
/// Implementata come spezzata su punti di controllo: banale da testare e
/// deterministica su ogni dispositivo.
public struct SpeedBonusCurve: Codable, Hashable, Sendable {
    /// Frazione iniziale senza alcun bonus.
    public var quietLeadIn: Double
    /// Livello (0...1) del gradino intermedio, a metà strada tra
    /// `quietLeadIn` e `peakPosition`.
    public var warmupLevel: Double
    /// Posizione del picco (di norma 0.5: metà finestra).
    public var peakPosition: Double
    /// Livello residuo a fine finestra (di norma 0: bonus esaurito).
    public var tailLevel: Double

    public init(
        quietLeadIn: Double = 0.15,
        warmupLevel: Double = 0.35,
        peakPosition: Double = 0.5,
        tailLevel: Double = 0.0
    ) {
        self.quietLeadIn = quietLeadIn.clamped(to: 0...1)
        self.warmupLevel = warmupLevel.clamped(to: 0...1)
        self.peakPosition = peakPosition.clamped(to: 0...1)
        self.tailLevel = tailLevel.clamped(to: 0...1)
    }

    public static let `default` = SpeedBonusCurve()

    /// Il momento del picco, come frazione della finestra: è l'istante da
    /// segnalare al giocatore su tutti e tre i canali.
    public var peakMoment: Double { peakPosition }

    /// Livello del bonus (0...1) al momento `t` (frazione della finestra).
    /// Fuori dalla finestra (t > 1) il livello resta `tailLevel`.
    public func level(atFraction t: Double) -> Double {
        let lead = min(quietLeadIn, peakPosition)
        let warmupPoint = (lead + peakPosition) / 2

        var points: [(t: Double, level: Double)] = [
            (0, 0),
            (lead, 0),
        ]
        if warmupPoint > lead && warmupPoint < peakPosition {
            points.append((warmupPoint, warmupLevel))
        }
        points.append((peakPosition, 1.0))
        if peakPosition < 1 {
            points.append((1, tailLevel))
        }

        let clamped = t.clamped(to: 0...1)
        guard t <= 1 else { return tailLevel }

        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            if clamped >= a.t && clamped <= b.t {
                guard b.t > a.t else { return b.level }
                let progress = (clamped - a.t) / (b.t - a.t)
                return a.level + (b.level - a.level) * progress
            }
        }
        return tailLevel
    }
}
