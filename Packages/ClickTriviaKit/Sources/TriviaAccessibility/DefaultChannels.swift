import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Implementazioni di base dei tre canali. Sono il punto di estensione per
/// le fasi successive: il canale audio diventerà un player di campionamenti
/// a tema (AVFoundation), quello aptico un motore CoreHaptics con pattern
/// dedicati. Le firme non cambieranno: le schermate parlano solo con il
/// FeedbackCenter.

/// Canale audio segnaposto: per ora registra i cue nel log.
/// Fase 1: sostituire con un player AVFoundation dei suoni a tema
/// (clack meccanici, crescendo della dinamo).
@MainActor
public final class PlaceholderAudioChannel: AudioFeedbackChannel {
    private let logger = Logger(subsystem: "ClickTrivia", category: "audio")

    public init() {}

    public func play(_ cue: AudioCue, volume: Double) {
        logger.debug("Audio cue \(String(describing: cue)) volume \(volume)")
    }
}

#if canImport(UIKit)
/// Aptica su iPhone tramite i feedback generator di sistema: semplice,
/// rispettosa delle impostazioni di sistema, già modulabile in intensità.
/// Fase 1: pattern CoreHaptics dedicati (crescendo del circuito, picco bonus).
@MainActor
public final class SystemHapticsChannel: HapticFeedbackChannel {
    public init() {}

    // Su iPad l'aptica può mancare: i generator degradano da soli in no-op,
    // quindi il canale resta "disponibile" e il costo è nullo.
    public var isAvailable: Bool { true }

    public func play(_ cue: HapticCue, intensity: Double) {
        let clamped = min(max(intensity, 0), 1)
        switch cue {
        case .gentleTick:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: clamped)
        case .softSuccess:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .softBreak:
            // L'errore è un guizzo morbido: impulso leggero e attenuato,
            // mai la scossa di un ".error" pieno.
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: clamped * 0.6)
        case .bonusPeak:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: clamped)
        case .celebration:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
#else
/// Sul Mac l'aptica di sistema non è disponibile per l'app: il canale si
/// dichiara assente e il FeedbackCenter veicola l'informazione sugli altri
/// due canali (che per contratto la portano già entrambi).
@MainActor
public final class SystemHapticsChannel: HapticFeedbackChannel {
    public init() {}

    public var isAvailable: Bool { false }

    public func play(_ cue: HapticCue, intensity: Double) {}
}
#endif

/// Canale visivo: pubblica l'ultimo cue come stato osservabile; le viste lo
/// interpretano con il design system, nel rispetto di Reduce Motion.
@MainActor
@Observable
public final class VisualCueRelay: VisualFeedbackChannel {
    /// L'ultimo cue emesso, con un contatore che permette alle viste di
    /// reagire anche a due cue uguali consecutivi.
    public private(set) var latestCue: VisualCue?
    public private(set) var cueCount = 0

    public init() {}

    public func show(_ cue: VisualCue) {
        latestCue = cue
        cueCount += 1
    }
}
