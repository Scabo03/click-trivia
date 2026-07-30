import SwiftUI

/// Token di movimento: ogni animazione dell'app passa da qui, così il
/// rispetto di Reduce Motion (di sistema o della preferenza interna
/// `reducesEffects`) è strutturale e non demandato alla singola vista.
///
/// Regola di tema: le luci salgono e scendono con rampe morbide; niente
/// pulsazioni, niente lampeggi, niente frequenze da fotosensibilità.
public enum MotionTokens {
    /// Rampa breve (comparsa di elementi).
    public static let quick: TimeInterval = 0.18
    /// Crescendo del circuito che si chiude.
    public static let crescendo: TimeInterval = 0.45
    /// Salita di luce del momento-bonus (una salita, non un lampeggio).
    public static let bonusRise: TimeInterval = 0.6

    /// L'animazione da usare, già risolta rispetto a Reduce Motion:
    /// con riduzione attiva restituisce `nil` (transizione istantanea,
    /// l'informazione resta veicolata da forma, testo, suono e aptica).
    public static func animation(
        duration: TimeInterval,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
