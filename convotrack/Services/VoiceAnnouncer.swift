import Foundation
import AVFoundation

/// Speaks short spoken navigation announcements (e.g. "Ride updated, rerouting") via on-device
/// text-to-speech.
///
/// Uses the `.playback` session category with `.duckOthers` so the voice is heard over
/// music/podcasts and with the silent switch on during a ride, then releases the session when the
/// utterance finishes so other audio un-ducks. A leading earcon (chime) is typically played first
/// via `SirenPlayer`, so `announce(_:after:)` accepts a small delay to let that finish so the two
/// don't fight over the audio session.
final class VoiceAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceAnnouncer()

    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak `text`, optionally after `delay` seconds (to let a leading chime finish first).
    /// Cancels any in-flight utterance so a burst of updates doesn't queue up stale speech.
    func announce(_ text: String, after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.synth.isSpeaking {
                self.synth.stopSpeaking(at: .immediate)
            }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, options: [.duckOthers])
            try? session.setActive(true)

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate  = AVSpeechUtteranceDefaultSpeechRate
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.synth.speak(utterance)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivateSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
