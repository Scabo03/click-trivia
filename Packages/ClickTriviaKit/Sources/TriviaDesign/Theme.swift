import SwiftUI
import TriviaCore

/// Il tema visivo: mondo meccanico-analogico retrò alimentato dall'elettricità,
/// palette sui blu, firma a zig-zag. Tre paletti non negoziabili:
///  1. giusto/sbagliato mai per solo colore: sempre anche forma e simbolo;
///  2. l'errore è un guizzo informativo, mai una punizione;
///  3. niente effetti pulsanti o lampeggianti; Reduce Motion sempre rispettato.
///
/// I colori sono esposti come ruoli semantici risolti in base alla palette
/// scelta e all'alto contrasto: le viste non toccano mai valori RGB.
public enum TriviaTheme {

    /// Ruoli semantici di colore usati dalle viste.
    public enum ColorRole: Sendable {
        case background
        case surface
        case primaryText
        case accent          // l'elettricità: il blu "acceso"
        case circuitClosed   // esito corretto (sempre accompagnato dal simbolo)
        case circuitBroken   // esito errato (sempre accompagnato dal simbolo)
    }

    /// Risolve un ruolo nel colore concreto per la palette e il contrasto
    /// richiesti. La palette blu di base è insidiosa per daltonismo e
    /// contrasto: le varianti non sono decorazione, sono requisito.
    /// I valori andranno verificati strumentalmente (rapporto ≥ 4.5:1)
    /// quando nasceranno le schermate vere.
    public static func color(
        _ role: ColorRole,
        palette: ColorPaletteOption = .classicBlue,
        increasedContrast: Bool = false
    ) -> Color {
        switch (role, increasedContrast) {
        case (.background, false): base(palette).background
        case (.background, true): base(palette).background
        case (.surface, _): base(palette).surface
        case (.primaryText, false): base(palette).primaryText
        case (.primaryText, true): Color.white
        case (.accent, _): base(palette).accent
        case (.circuitClosed, false): base(palette).circuitClosed
        case (.circuitClosed, true): base(palette).circuitClosed
        case (.circuitBroken, false): base(palette).circuitBroken
        case (.circuitBroken, true): base(palette).circuitBroken
        }
    }

    private struct PaletteColors {
        var background: Color
        var surface: Color
        var primaryText: Color
        var accent: Color
        var circuitClosed: Color
        var circuitBroken: Color
    }

    private static func base(_ palette: ColorPaletteOption) -> PaletteColors {
        switch palette {
        case .classicBlue:
            PaletteColors(
                background: Color(red: 0.04, green: 0.08, blue: 0.16),
                surface: Color(red: 0.09, green: 0.15, blue: 0.27),
                primaryText: Color(red: 0.92, green: 0.95, blue: 1.0),
                accent: Color(red: 0.16, green: 0.48, blue: 0.92),
                circuitClosed: Color(red: 0.42, green: 0.78, blue: 1.0),
                circuitBroken: Color(red: 0.72, green: 0.62, blue: 0.36)
            )
        case .highContrast:
            PaletteColors(
                background: .black,
                surface: Color(red: 0.06, green: 0.06, blue: 0.12),
                primaryText: .white,
                accent: Color(red: 0.35, green: 0.65, blue: 1.0),
                circuitClosed: .white,
                circuitBroken: Color(red: 1.0, green: 0.85, blue: 0.3)
            )
        case .deuteranopiaFriendly, .tritanopiaFriendly:
            // Prima taratura: coppie blu/giallo-arancio, distinguibili nelle
            // forme più comuni di daltonismo. Da raffinare con verifica
            // strumentale in Fase 1.
            PaletteColors(
                background: Color(red: 0.05, green: 0.08, blue: 0.14),
                surface: Color(red: 0.10, green: 0.14, blue: 0.24),
                primaryText: Color(red: 0.94, green: 0.95, blue: 0.98),
                accent: Color(red: 0.25, green: 0.55, blue: 0.95),
                circuitClosed: Color(red: 0.55, green: 0.75, blue: 1.0),
                circuitBroken: Color(red: 0.95, green: 0.72, blue: 0.25)
            )
        case .monochrome:
            PaletteColors(
                background: .black,
                surface: Color(white: 0.12),
                primaryText: .white,
                accent: Color(white: 0.85),
                circuitClosed: .white,
                circuitBroken: Color(white: 0.6)
            )
        }
    }
}

/// Simboli degli esiti: la distinzione primaria è la **forma**, il colore è
/// solo rinforzo. Circuito chiuso = fulmine pieno nel cerchio; circuito
/// interrotto = fulmine barrato. Le etichette accessibili viaggiano insieme.
public enum OutcomeSymbol {
    public static let circuitClosedSystemImage = "bolt.circle.fill"
    public static let circuitBrokenSystemImage = "bolt.slash.circle"

    public static var circuitClosedLabel: String {
        String(localized: "Risposta esatta")
    }
    public static var circuitBrokenLabel: String {
        String(localized: "Risposta sbagliata")
    }
}
