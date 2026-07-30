import Foundation

/// Preferenze personali: regolano **come il giocatore percepisce il gioco**
/// (suoni, aptica, contrasto, palette, tempi). Viaggiano con il profilo e non
/// influenzano il punteggio degli altri — a differenza delle `ScoringRules`,
/// che appartengono alla partita e valgono per tutti i partecipanti.
///
/// Questo è puro dato: l'interpretazione a runtime (mescolarle con le
/// impostazioni di accessibilità di sistema) vive in TriviaAccessibility.
public struct PlayerPreferences: Codable, Hashable, Sendable {
    public var audio: AudioPreferences
    public var haptics: HapticPreferences
    public var visual: VisualPreferences
    public var timing: TimingPreference
    public var speech: SpeechPreferences

    public init(
        audio: AudioPreferences = AudioPreferences(),
        haptics: HapticPreferences = HapticPreferences(),
        visual: VisualPreferences = VisualPreferences(),
        timing: TimingPreference = .standard,
        speech: SpeechPreferences = SpeechPreferences()
    ) {
        self.audio = audio
        self.haptics = haptics
        self.visual = visual
        self.timing = timing
        self.speech = speech
    }

    public static let `default` = PlayerPreferences()
}

public struct AudioPreferences: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Volume degli effetti di gioco, 0...1.
    public var effectsVolume: Double

    public init(isEnabled: Bool = true, effectsVolume: Double = 0.8) {
        self.isEnabled = isEnabled
        self.effectsVolume = effectsVolume.clamped(to: 0...1)
    }
}

public struct HapticPreferences: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Intensità globale dell'aptica, 0...1. Il feedback d'errore resta in
    /// ogni caso morbido: questa è un'attenuazione ulteriore, mai un rinforzo
    /// oltre il massimo previsto dal tema.
    public var intensity: Double

    public init(isEnabled: Bool = true, intensity: Double = 0.7) {
        self.isEnabled = isEnabled
        self.intensity = intensity.clamped(to: 0...1)
    }
}

public struct VisualPreferences: Codable, Hashable, Sendable {
    /// Alto contrasto interno all'app, in aggiunta a quello di sistema.
    public var prefersHighContrast: Bool
    /// Palette scelta dal giocatore (la palette blu di base è insidiosa per
    /// daltonismo e contrasto: le varianti sono un'opzione di prima classe).
    public var palette: ColorPaletteOption
    /// Riduzione degli effetti luminosi interna all'app, in aggiunta al
    /// Reduce Motion di sistema (che va comunque sempre rispettato).
    public var reducesEffects: Bool

    public init(
        prefersHighContrast: Bool = false,
        palette: ColorPaletteOption = .classicBlue,
        reducesEffects: Bool = false
    ) {
        self.prefersHighContrast = prefersHighContrast
        self.palette = palette
        self.reducesEffects = reducesEffects
    }
}

public enum ColorPaletteOption: String, Codable, CaseIterable, Sendable {
    case classicBlue
    case highContrast
    case deuteranopiaFriendly
    case tritanopiaFriendly
    case monochrome
}

/// Tempi di risposta: preferenza personale di accessibilità. La finestra di
/// riferimento della partita viene scalata (o disattivata) per il singolo
/// giocatore senza cambiare le regole comuni: con `unlimited` il giocatore
/// rientra di fatto nella modalità "conta solo la correttezza".
public enum TimingPreference: Codable, Hashable, Sendable {
    case standard
    case extended(multiplier: Double)
    case unlimited

    /// Fattore da applicare alla finestra di riferimento; `nil` = senza limite.
    public var windowMultiplier: Double? {
        switch self {
        case .standard: 1.0
        case .extended(let multiplier): max(1.0, multiplier)
        case .unlimited: nil
        }
    }
}

public struct SpeechPreferences: Codable, Hashable, Sendable {
    /// Lettura automatica della domanda alla presentazione (oltre a VoiceOver).
    public var autoReadsQuestions: Bool

    public init(autoReadsQuestions: Bool = false) {
        self.autoReadsQuestions = autoReadsQuestions
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
