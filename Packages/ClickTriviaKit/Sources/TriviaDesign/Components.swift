import SwiftUI
import TriviaCore

/// Il badge dell'esito: la distinzione primaria è forma + simbolo + testo,
/// il colore è solo rinforzo (paletto non negoziabile del tema).
public struct OutcomeBadge: View {
    public let isCorrect: Bool
    public var palette: ColorPaletteOption
    public var increasedContrast: Bool

    public init(
        isCorrect: Bool,
        palette: ColorPaletteOption = .classicBlue,
        increasedContrast: Bool = false
    ) {
        self.isCorrect = isCorrect
        self.palette = palette
        self.increasedContrast = increasedContrast
    }

    public var body: some View {
        Label {
            Text(isCorrect ? OutcomeSymbol.circuitClosedLabel : OutcomeSymbol.circuitBrokenLabel)
                .font(.title2.weight(.semibold))
        } icon: {
            Image(
                systemName: isCorrect
                    ? OutcomeSymbol.circuitClosedSystemImage
                    : OutcomeSymbol.circuitBrokenSystemImage
            )
            .font(.title)
        }
        .foregroundStyle(
            TriviaTheme.color(
                isCorrect ? .circuitClosed : .circuitBroken,
                palette: palette,
                increasedContrast: increasedContrast
            )
        )
    }
}

/// Il misuratore del bonus velocità: una barra che si riempie seguendo la
/// curva. Niente lampeggi: il livello sale e scende con continuità (e chi
/// la aggiorna lo fa a bassa frequenza). Il canale visivo del momento-bonus
/// passa anche da qui; quello sonoro e aptico dal FeedbackCenter.
public struct BonusMeterView: View {
    public let curve: SpeedBonusCurve
    public let elapsedFraction: Double
    public var palette: ColorPaletteOption
    public var increasedContrast: Bool

    public init(
        curve: SpeedBonusCurve,
        elapsedFraction: Double,
        palette: ColorPaletteOption = .classicBlue,
        increasedContrast: Bool = false
    ) {
        self.curve = curve
        self.elapsedFraction = elapsedFraction
        self.palette = palette
        self.increasedContrast = increasedContrast
    }

    private var level: Double {
        curve.level(atFraction: elapsedFraction)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: "Bonus velocità")
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .font(.caption.weight(.medium))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TriviaTheme.color(.surface, palette: palette, increasedContrast: increasedContrast))
                    Capsule()
                        .fill(TriviaTheme.color(.accent, palette: palette, increasedContrast: increasedContrast))
                        .frame(width: max(0, proxy.size.width * level))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Bonus velocità"))
        .accessibilityValue(Text("\(Int((level * 100).rounded())) per cento"))
    }
}
