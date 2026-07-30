import Foundation

#if os(iOS)
import CoreHaptics

/// Il canale aptico reale: pattern CoreHaptics dedicati per ogni cue.
/// Regola di tema incisa qui: l'errore (`softBreak`) è un impulso attenuato
/// e poco tagliente — un guizzo, mai una scossa. L'intensità che arriva è
/// già quella effettiva (preferenze del giocatore applicate dal
/// FeedbackCenter) e qui viene solo modulata per cue.
@MainActor
public final class CoreHapticsChannel: HapticFeedbackChannel {
    private let engine: CHHapticEngine

    /// `nil` dove l'hardware non supporta CoreHaptics (si ripiega sui
    /// feedback generator tramite `HapticChannelFactory`).
    public init?() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return nil }
        self.engine = engine
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in
            try? engine?.start()
        }
    }

    public var isAvailable: Bool { true }

    public func play(_ cue: HapticCue, intensity: Double) {
        let clamped = min(max(intensity, 0), 1)
        guard clamped > 0 else { return }
        let events = events(for: cue, intensity: clamped)
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func events(for cue: HapticCue, intensity i: Double) -> [CHHapticEvent] {
        func transient(at time: TimeInterval, _ strength: Double, sharpness: Double) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(strength)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
                ],
                relativeTime: time
            )
        }

        switch cue {
        case .gentleTick:
            return [transient(at: 0, 0.45 * i, sharpness: 0.3)]
        case .softSuccess:
            // Due battiti in crescendo: il circuito che si aggancia.
            return [
                transient(at: 0, 0.5 * i, sharpness: 0.4),
                transient(at: 0.12, 0.7 * i, sharpness: 0.5),
            ]
        case .softBreak:
            // Il guizzo morbido: singolo, attenuato, poco tagliente.
            return [transient(at: 0, 0.35 * i, sharpness: 0.15)]
        case .bonusPeak:
            // Una salita continua breve, coerente con la luce che sale.
            return [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.6 * i)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                    ],
                    relativeTime: 0,
                    duration: 0.25
                ),
            ]
        case .celebration:
            return [
                transient(at: 0, 0.5 * i, sharpness: 0.4),
                transient(at: 0.1, 0.6 * i, sharpness: 0.5),
                transient(at: 0.22, 0.75 * i, sharpness: 0.55),
            ]
        }
    }
}
#endif

/// Sceglie il miglior canale aptico per il dispositivo: CoreHaptics dove
/// c'è, feedback generator come ripiego su iOS, canale dichiaratamente
/// assente su macOS (il FeedbackCenter compensa sugli altri due canali).
@MainActor
public enum HapticChannelFactory {
    public static func makeDefault() -> any HapticFeedbackChannel {
        #if os(iOS)
        if let coreHaptics = CoreHapticsChannel() {
            return coreHaptics
        }
        #endif
        return SystemHapticsChannel()
    }
}
