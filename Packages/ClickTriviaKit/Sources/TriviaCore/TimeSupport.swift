import Foundation

extension Duration {
    /// La durata in secondi, come `Double` (comodo per frazioni di finestra).
    public var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// Durata scalata di un fattore (es. la finestra personale con tempi
    /// estesi, o la posizione del picco come frazione della finestra).
    public func scaled(by factor: Double) -> Duration {
        .seconds(seconds * factor)
    }
}
