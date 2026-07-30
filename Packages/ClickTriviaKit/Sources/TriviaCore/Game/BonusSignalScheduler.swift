import Foundation

/// Temporizza i segnali del momento-bonus sulla finestra personale del
/// giocatore: uno all'apertura della salita, uno al picco. Estratto dal
/// motore solo perché il contratto è identico in ogni modalità: chi riceve
/// i callback (il FeedbackCenter, via engine/controller) porta il picco su
/// tutti e tre i canali.
@MainActor
public final class BonusSignalScheduler {
    private var task: Task<Void, Never>?
    private let clock = ContinuousClock()

    public init() {}

    /// Nessun segnale con bonus disattivato o finestra assente (tempi
    /// illimitati): in quel caso semplicemente non chiamare `schedule`.
    public func schedule(
        curve: SpeedBonusCurve,
        window: Duration,
        onOpen: @escaping @MainActor () -> Void,
        onPeak: @escaping @MainActor () -> Void
    ) {
        cancel()
        let openDelay = window.scaled(by: min(curve.quietLeadIn, curve.peakMoment))
        let peakDelay = window.scaled(by: curve.peakMoment)

        task = Task {
            try? await clock.sleep(for: openDelay)
            guard !Task.isCancelled else { return }
            onOpen()

            try? await clock.sleep(for: peakDelay - openDelay)
            guard !Task.isCancelled else { return }
            onPeak()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
