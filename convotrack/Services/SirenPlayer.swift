import Foundation
import AVFoundation

/// Synthesizes and plays short alert tones — no bundled audio asset required.
///
/// Two distinct sounds are generated on demand:
///  - `.emergency` — an urgent two-tone siren wail (repeated), for `ride:emergency`.
///  - `.regroup`   — a gentle ascending chime (a major arpeggio), for `ride:regroup`.
///    Deliberately melodic and discrete so it can never be mistaken for the siren.
///
/// Uses the `.playback` session category with `.duckOthers` so the alert is heard
/// even when the ringer/silent switch is on, which is appropriate for a ride
/// coordination event. The session is deactivated (un-ducking other audio) once the
/// last tone finishes.
final class SirenPlayer {
    static let shared = SirenPlayer()

    enum Sound {
        case emergency   // urgent two-tone siren wail
        case regroup     // gentle ascending chime — distinct from the emergency siren

        /// Natural number of back-to-back repeats when the caller doesn't override it.
        var defaultRepeats: Int {
            switch self {
            case .emergency: return 3
            case .regroup:   return 1
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var isConfigured = false
    // Bumped on every play(); scheduled-buffer completions from an earlier call carry a stale
    // generation and are ignored, so a rapid second alert isn't silenced by the first's
    // teardown (player.stop() flushes and fires the prior buffers' completion handlers).
    private var generation = 0

    private init() {}

    /// Plays `sound` back-to-back `times` times. Passing `nil` uses the sound's natural
    /// repeat count (siren ×3, chime ×1). Defaults keep existing emergency call sites working.
    func play(_ sound: Sound = .emergency, times: Int? = nil) {
        configureIfNeeded()
        guard let buffer = buffers[sound] else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }

        generation &+= 1
        let currentGeneration = generation
        player.stop()  // flushes any prior schedule — its completions carry an older generation
        let count = max(1, times ?? sound.defaultRepeats)
        for i in 0..<count {
            let isLast = (i == count - 1)
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                guard isLast else { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == currentGeneration else { return }
                    self.finish()
                }
            }
        }
        player.play()
    }

    private func finish() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers[.emergency] = makeSirenBuffer(format: format)
        buffers[.regroup]   = makeChimeBuffer(format: format)
        engine.prepare()
        isConfigured = true
    }

    /// One siren "wail": the pitch sweeps up from `lowFreq` to `highFreq` and back,
    /// with short fades at each end to keep repeats click-free.
    private func makeSirenBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let wailDuration = 0.9                       // seconds per wail
        let frameCount = AVAudioFrameCount(sampleRate * wailDuration)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount
        guard let channel = buf.floatChannelData?[0] else { return nil }

        let lowFreq = 600.0
        let highFreq = 1_200.0
        let fade = 0.02                              // 20 ms fade in/out
        var phase = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Sweep 0→1→0 across the wail so the pitch rises then falls.
            let sweep = (sin(2 * .pi * (1.0 / wailDuration) * t - .pi / 2) + 1) / 2
            let freq = lowFreq + (highFreq - lowFreq) * sweep
            phase += 2 * .pi * freq / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
            let env = min(1.0, min(t, wailDuration - t) / fade)
            channel[frame] = Float(sin(phase) * 0.5 * env)
        }
        return buf
    }

    /// A "gather up" chime: three ascending notes (C5–E5–G5, a major arpeggio), each with a
    /// soft attack and a bell-like decay tapered to silence at the note boundary. Discrete,
    /// melodic and friendly — nothing like the continuous emergency siren sweep.
    private func makeChimeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes: [Double] = [523.25, 659.25, 783.99]   // C5, E5, G5
        let noteDuration = 0.2                            // seconds per note
        let frameCount = AVAudioFrameCount(sampleRate * noteDuration * Double(notes.count))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount
        guard let channel = buf.floatChannelData?[0] else { return nil }

        let framesPerNote = Int(sampleRate * noteDuration)
        for frame in 0..<Int(frameCount) {
            let noteIndex = min(notes.count - 1, frame / framesPerNote)
            let freq = notes[noteIndex]
            let localT = Double(frame % framesPerNote) / sampleRate
            let attack  = min(1.0, localT / 0.006)                          // 6 ms attack
            let decay   = exp(-localT * 5.0)                               // bell-like ring-down
            let release = min(1.0, (noteDuration - localT) / 0.03)         // last 30 ms → silence
            let env = attack * decay * max(0, release)
            channel[frame] = Float(sin(2 * .pi * freq * localT) * 0.4 * env)
        }
        return buf
    }
}
