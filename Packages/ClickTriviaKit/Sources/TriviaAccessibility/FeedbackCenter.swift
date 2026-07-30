import Foundation
import SwiftUI
import TriviaCore

/// Il punto unico da cui il gioco annuncia gli eventi. Traduce ogni
/// `GameEvent` sui tre canali (audio, aptico, visivo) più l'annuncio
/// VoiceOver, applicando insieme:
///  - le preferenze personali del giocatore (volumi, intensità, riduzioni);
///  - le impostazioni di accessibilità di sistema (`SystemAccessibilitySettings`).
///
/// Le schermate di gioco non parlano mai direttamente con suoni o aptica:
/// passano da qui, così nessun evento può "dimenticarsi" un canale.
@MainActor
@Observable
public final class FeedbackCenter {
    /// Preferenze del giocatore attivo; aggiornarle ha effetto immediato.
    public var preferences: PlayerPreferences

    public let system: SystemAccessibilitySettings

    private let audio: any AudioFeedbackChannel
    private let haptics: any HapticFeedbackChannel
    private let visual: any VisualFeedbackChannel

    public init(
        preferences: PlayerPreferences = .default,
        system: SystemAccessibilitySettings,
        audio: any AudioFeedbackChannel,
        haptics: any HapticFeedbackChannel,
        visual: any VisualFeedbackChannel
    ) {
        self.preferences = preferences
        self.system = system
        self.audio = audio
        self.haptics = haptics
        self.visual = visual
    }

    /// Annuncia un evento su tutti i canali pertinenti.
    /// `voiceOverDetail` sostituisce la frase generica dell'annuncio con una
    /// specifica ("Sara è entrata" invece di "Un giocatore è entrato").
    public func announce(_ event: GameEvent, voiceOverDetail: String? = nil) {
        let script = FeedbackScript.script(for: event)

        if let cue = script.audio, preferences.audio.isEnabled {
            let volume = preferences.audio.effectsVolume
            if volume > 0 {
                audio.play(cue, volume: volume)
            }
        }

        if let cue = script.haptic, preferences.haptics.isEnabled, haptics.isAvailable {
            let intensity = preferences.haptics.intensity
            if intensity > 0 {
                haptics.play(cue, intensity: intensity)
            }
        }

        if let cue = script.visual {
            visual.show(cue)
        }

        if system.isVoiceOverRunning,
           let phrase = voiceOverDetail ?? script.voiceOverAnnouncement {
            AccessibilityNotification.Announcement(phrase).post()
        }
    }

    /// Annuncio di stato: per le transizioni che non sono eventi di gioco
    /// (richiesta di ingresso, sala piena, attese). Anche qui più canali:
    /// un tocco sonoro e aptico leggero + l'annuncio VoiceOver del testo,
    /// che le viste mostrano comunque per iscritto.
    public func announceStatus(_ text: String) {
        if preferences.audio.isEnabled, preferences.audio.effectsVolume > 0 {
            audio.play(.questionAppear, volume: preferences.audio.effectsVolume)
        }
        if preferences.haptics.isEnabled, haptics.isAvailable, preferences.haptics.intensity > 0 {
            haptics.play(.gentleTick, intensity: preferences.haptics.intensity)
        }
        if system.isVoiceOverRunning {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// La partitura di un evento: quale cue su ciascun canale, più l'eventuale
/// annuncio vocale. Tenerla in un unico posto rende verificabile a colpo
/// d'occhio che ogni evento importante copra più canali.
struct FeedbackScript {
    var audio: AudioCue?
    var haptic: HapticCue?
    var visual: VisualCue?
    /// Annuncio VoiceOver per gli eventi che non producono già un cambio di
    /// focus o di contenuto letto. Localizzazione vera in arrivo con la UI.
    var voiceOverAnnouncement: String?

    static func script(for event: GameEvent) -> FeedbackScript {
        switch event {
        case .matchStarted:
            FeedbackScript(
                audio: .matchStart,
                haptic: .gentleTick,
                visual: nil
            )
        case .questionPresented:
            FeedbackScript(
                audio: .questionAppear,
                haptic: nil,
                visual: .questionAppear
            )
        case .circuitClosed:
            FeedbackScript(
                audio: .circuitClose,
                haptic: .softSuccess,
                visual: .circuitGlow,
                voiceOverAnnouncement: String(localized: "Risposta esatta. Circuito chiuso.")
            )
        case .circuitBroken:
            FeedbackScript(
                audio: .circuitBreak,
                haptic: .softBreak,
                visual: .circuitGap,
                voiceOverAnnouncement: String(localized: "Risposta sbagliata. Circuito interrotto.")
            )
        case .bonusWindowOpened:
            FeedbackScript(
                audio: .bonusApproaching,
                haptic: nil,
                visual: .bonusApproaching
            )
        case .bonusPeak:
            // Il momento-bonus per contratto viaggia su tutti e tre i canali.
            FeedbackScript(
                audio: .bonusPeak,
                haptic: .bonusPeak,
                visual: .bonusPeak,
                voiceOverAnnouncement: String(localized: "Momento bonus.")
            )
        case .powerUpEarned:
            FeedbackScript(
                audio: .powerUpEarned,
                haptic: .celebration,
                visual: .powerUpEarned,
                voiceOverAnnouncement: String(localized: "Hai guadagnato un power-up.")
            )
        case .powerUpUsed:
            FeedbackScript(
                audio: .powerUpUsed,
                haptic: .gentleTick,
                visual: nil
            )
        case .matchEnded:
            FeedbackScript(
                audio: .matchEnd,
                haptic: .celebration,
                visual: .matchEnd
            )
        case .peerJoined:
            FeedbackScript(
                audio: .peerJoined,
                haptic: .gentleTick,
                visual: nil,
                voiceOverAnnouncement: String(localized: "Un giocatore è entrato.")
            )
        case .peerLeft:
            FeedbackScript(
                audio: .peerLeft,
                haptic: .gentleTick,
                visual: nil,
                voiceOverAnnouncement: String(localized: "Un giocatore è uscito.")
            )
        case .connectionLost:
            FeedbackScript(
                audio: .connectionLost,
                haptic: .softBreak,
                visual: .circuitGap,
                voiceOverAnnouncement: String(localized: "Connessione con la sala persa.")
            )
        }
    }
}
