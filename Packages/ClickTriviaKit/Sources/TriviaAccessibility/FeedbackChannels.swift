import Foundation

/// I tre canali del feedback di gioco. Ogni canale è un protocollo: le
/// implementazioni concrete variano per piattaforma e degradano con grazia
/// (niente aptica sul Mac → il FeedbackCenter rinforza audio e visivo).

/// Cue sonori, astratti rispetto al file audio che li realizzerà.
public enum AudioCue: Hashable, Sendable {
    case matchStart
    case questionAppear
    /// Il "clack" caldo del circuito che si chiude, con crescendo.
    case circuitClose
    /// Il guizzo breve del circuito interrotto: informativo, mai aggressivo.
    case circuitBreak
    case bonusApproaching
    case bonusPeak
    case powerUpEarned
    case powerUpUsed
    case matchEnd
    /// Ingresso in sala: due note brevi in salita.
    case peerJoined
    /// Uscita dalla sala: due note brevi in discesa.
    case peerLeft
    /// Connessione persa: discesa bassa, morbida ma inequivocabile.
    case connectionLost
}

/// Pattern aptici, astratti rispetto al motore che li suonerà.
/// Nota di tema: il feedback dell'errore è morbido per contratto.
public enum HapticCue: Hashable, Sendable {
    case gentleTick
    case softSuccess
    /// Errore: singolo impulso attenuato, mai una scossa.
    case softBreak
    case bonusPeak
    case celebration
}

/// Cue visivi: token che le viste interpretano nel rispetto di Reduce Motion
/// (mai pulsazioni o lampeggi; con Reduce Motion attivo diventano variazioni
/// statiche di forma/luminosità).
public enum VisualCue: Hashable, Sendable {
    case questionAppear
    /// Il circuito si illumina, con crescendo misurato.
    case circuitGlow
    /// Il tratto di circuito interrotto resta visibile in forma.
    case circuitGap
    case bonusApproaching
    /// Evidenza del momento-bonus: una salita di luce, non un lampeggio.
    case bonusPeak
    case powerUpEarned
    case matchEnd
}

@MainActor
public protocol AudioFeedbackChannel: AnyObject {
    /// `volume` è già il valore effettivo (preferenze applicate), 0...1.
    func play(_ cue: AudioCue, volume: Double)
}

@MainActor
public protocol HapticFeedbackChannel: AnyObject {
    /// `false` dove l'hardware non c'è (Mac): il FeedbackCenter compensa.
    var isAvailable: Bool { get }
    /// `intensity` è già il valore effettivo (preferenze applicate), 0...1.
    func play(_ cue: HapticCue, intensity: Double)
}

@MainActor
public protocol VisualFeedbackChannel: AnyObject {
    func show(_ cue: VisualCue)
}
