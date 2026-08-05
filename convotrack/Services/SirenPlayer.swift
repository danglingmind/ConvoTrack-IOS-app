import Foundation
import AVFoundation

/// Synthesizes and plays a two-tone emergency siren — no bundled audio asset required.
///
/// Uses the `.playback` session category with `.duckOthers` so the alert is heard
/// even when the ringer/silent switch is on, which is appropriate for a
/// safety-critical event. The session is deactivated (un-ducking other audio)
/// once the last wail finishes.
final class SirenPlayer {
    static let shared = SirenPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var buffer: AVAudioPCMBuffer?
    private var isConfigured = false
    // Bumped on every play(); scheduled-buffer completions from an earlier call carry a stale
    // generation and are ignored, so a rapid second emergency isn't silenced by the first's
    // teardown (player.stop() flushes and fires the prior buffers' completion handlers).
    private var generation = 0

    private init() {}

    /// Plays the siren `times` times back-to-back (default 3).
    func play(times: Int = 3) {
        configureIfNeeded()
        guard let buffer else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }

        generation &+= 1
        let currentGeneration = generation
        player.stop()  // flushes any prior schedule — its completions carry an older generation
        let count = max(1, times)
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
        buffer = makeSirenBuffer(format: format)
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
}
