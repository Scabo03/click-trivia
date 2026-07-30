import AVFAudio
import Foundation
import OSLog

/// Il canale audio reale: suoni a tema sintetizzati in codice (nessun asset,
/// nessun servizio esterno) — click meccanici, il crescendo del circuito che
/// si chiude, il guizzo morbido di quello interrotto.
///
/// Su iOS la sessione è `.ambient`: rispetta l'interruttore silenzioso e non
/// zittisce musica o VoiceOver. I buffer sono generati una volta e riusati.
@MainActor
public final class SynthesizedAudioChannel: AudioFeedbackChannel {

    /// Una nota: frequenza, quando parte, quanto dura, quanto forte.
    private struct Tone {
        var frequency: Double
        var start: TimeInterval
        var duration: TimeInterval
        var amplitude: Double
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var buffers: [AudioCue: AVAudioPCMBuffer] = [:]
    private var isConfigured = false
    private let logger = Logger(subsystem: "ClickTrivia", category: "audio")

    public init() {}

    public func play(_ cue: AudioCue, volume: Double) {
        guard ensureEngineRunning() else { return }
        guard let buffer = buffer(for: cue) else { return }
        player.volume = Float(min(max(volume, 0), 1))
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
    }

    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        if !isConfigured {
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate, channels: 1
            ) else { return false }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConfigured = true
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Avvio motore audio fallito: \(error.localizedDescription)")
            return false
        }
    }

    private func buffer(for cue: AudioCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] { return cached }
        let made = render(tones(for: cue))
        buffers[cue] = made
        return made
    }

    /// La "partitura" sonora di ogni cue. Frequenze e durate sono la
    /// taratura di riferimento; potranno diventare campioni registrati
    /// senza toccare nulla fuori da questo file.
    private func tones(for cue: AudioCue) -> [Tone] {
        switch cue {
        case .matchStart:
            [
                Tone(frequency: 392.00, start: 0, duration: 0.12, amplitude: 0.35),
                Tone(frequency: 523.25, start: 0.10, duration: 0.18, amplitude: 0.4),
            ]
        case .questionAppear:
            [Tone(frequency: 660, start: 0, duration: 0.07, amplitude: 0.3)]
        case .circuitClose:
            // Il crescendo del circuito che si chiude.
            [
                Tone(frequency: 523.25, start: 0, duration: 0.12, amplitude: 0.3),
                Tone(frequency: 659.25, start: 0.09, duration: 0.12, amplitude: 0.35),
                Tone(frequency: 783.99, start: 0.18, duration: 0.24, amplitude: 0.4),
            ]
        case .circuitBreak:
            // Discesa breve e morbida: informa, non punisce.
            [
                Tone(frequency: 196.00, start: 0, duration: 0.16, amplitude: 0.28),
                Tone(frequency: 174.61, start: 0.11, duration: 0.20, amplitude: 0.22),
            ]
        case .bonusApproaching:
            [Tone(frequency: 880, start: 0, duration: 0.05, amplitude: 0.22)]
        case .bonusPeak:
            [
                Tone(frequency: 987.77, start: 0, duration: 0.10, amplitude: 0.35),
                Tone(frequency: 1318.51, start: 0.08, duration: 0.18, amplitude: 0.38),
            ]
        case .powerUpEarned:
            [
                Tone(frequency: 523.25, start: 0, duration: 0.09, amplitude: 0.32),
                Tone(frequency: 659.25, start: 0.07, duration: 0.09, amplitude: 0.32),
                Tone(frequency: 783.99, start: 0.14, duration: 0.09, amplitude: 0.34),
                Tone(frequency: 1046.50, start: 0.21, duration: 0.20, amplitude: 0.38),
            ]
        case .powerUpUsed:
            [Tone(frequency: 740, start: 0, duration: 0.08, amplitude: 0.3)]
        case .matchEnd:
            [
                Tone(frequency: 523.25, start: 0, duration: 0.15, amplitude: 0.33),
                Tone(frequency: 392.00, start: 0.12, duration: 0.15, amplitude: 0.3),
                Tone(frequency: 523.25, start: 0.24, duration: 0.32, amplitude: 0.38),
            ]
        case .peerJoined:
            [
                Tone(frequency: 587.33, start: 0, duration: 0.08, amplitude: 0.28),
                Tone(frequency: 783.99, start: 0.07, duration: 0.12, amplitude: 0.3),
            ]
        case .peerLeft:
            [
                Tone(frequency: 783.99, start: 0, duration: 0.08, amplitude: 0.26),
                Tone(frequency: 587.33, start: 0.07, duration: 0.12, amplitude: 0.24),
            ]
        case .connectionLost:
            [
                Tone(frequency: 246.94, start: 0, duration: 0.2, amplitude: 0.3),
                Tone(frequency: 196.00, start: 0.15, duration: 0.28, amplitude: 0.26),
            ]
        }
    }

    /// Rende le note in un buffer PCM: sinusoidi con inviluppo a campana
    /// (attacco e rilascio morbidi, nessun click di troncamento).
    private func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        ) else { return nil }
        let totalDuration = tones.map { $0.start + $0.duration }.max() ?? 0
        let frameCount = AVAudioFrameCount((totalDuration + 0.02) * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var value = 0.0
            for tone in tones where t >= tone.start && t < tone.start + tone.duration {
                let progress = (t - tone.start) / tone.duration
                let envelope = sin(.pi * progress)
                value += tone.amplitude * envelope * sin(2 * .pi * tone.frequency * (t - tone.start))
            }
            samples[frame] = Float(max(-1, min(1, value)))
        }
        buffer.frameLength = frameCount
        return buffer
    }
}
