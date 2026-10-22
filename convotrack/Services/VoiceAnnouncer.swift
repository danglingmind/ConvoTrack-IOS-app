import Foundation
import AVFoundation

/// How urgent an utterance is. A higher priority interrupts a lower one; a lower one waits its
/// turn behind a higher one instead of cutting it off.
enum VoicePriority: Int, Comparable {
    /// Turn-by-turn prompts. Replaced by the next prompt, since only the newest is worth hearing.
    case turn = 0
    /// Regroup, split and reroute announcements.
    case alert = 1
    /// Emergencies. The only speech that ignores the mute switch.
    case emergency = 2

    static func < (a: VoicePriority, b: VoicePriority) -> Bool { a.rawValue < b.rawValue }
}

/// Speaks short spoken navigation announcements via on-device text-to-speech.
///
/// Uses `.playback` with the `.voicePrompt` mode and `.duckOthers`, so the voice is heard over
/// music and podcasts and with the silent switch on, then releases the session when the utterance
/// finishes so other audio un-ducks. A leading earcon (chime) is typically played first via
/// `SirenPlayer`, so `announce` accepts a small delay to let that finish so the two don't fight
/// over the audio session.
///
/// Muting (`navVoiceMuted`) silences everything except emergencies.
final class VoiceAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceAnnouncer()
    static let mutedKey = "navVoiceMuted"

    private let synth = AVSpeechSynthesizer()
    private var priorities: [ObjectIdentifier: VoicePriority] = [:]
    private var speakingPriority: VoicePriority?

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// The prompts are English, so the voice is too. `AVSpeechSynthesisVoice(language:)` hands back
    /// the low-quality compact voice, which is what sounded robotic, so pick the best installed
    /// English voice instead (premium > enhanced > default), preferring the rider's own accent
    /// (en-IN, en-GB, ...) among equals. Novelty and Eloquence voices are skipped: both are robotic.
    private static let englishVoice: AVSpeechSynthesisVoice? = {
        let region = Locale.current.region?.identifier
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en-")
                && !$0.identifier.contains("eloquence")
                && !$0.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
        }
        let best = candidates.max { a, b in
            func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int) {
                (v.quality.rawValue, v.language == "en-\(region ?? "US")" ? 1 : 0)
            }
            return rank(a) < rank(b)
        }
        return best ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    var isMuted: Bool { UserDefaults.standard.bool(forKey: Self.mutedKey) }

    /// Speak `text`, optionally after `delay` seconds (to let a leading chime finish first).
    func announce(_ text: String, after delay: TimeInterval = 0, priority: VoicePriority = .alert) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.isMuted && priority != .emergency { return }

            // Equal or lower priority than what is speaking: a newer prompt replaces a stale one;
            // a lower one never cuts off a higher one, it queues behind it.
            if self.synth.isSpeaking, (self.speakingPriority ?? .turn) <= priority {
                self.synth.stopSpeaking(at: .immediate)
            }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt,
                                     options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try? session.setActive(true)

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate  = AVSpeechUtteranceDefaultSpeechRate * 1.02
            utterance.pitchMultiplier = 1.05
            utterance.preUtteranceDelay = 0.1
            utterance.voice = Self.englishVoice
            self.priorities[ObjectIdentifier(utterance)] = priority
            self.synth.speak(utterance)
        }
    }

    /// Cuts off whatever is being said, e.g. when voice is muted or navigation ends.
    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.synth.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        speakingPriority = priorities[ObjectIdentifier(utterance)]
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        priorities.removeValue(forKey: ObjectIdentifier(utterance))
        speakingPriority = nil
        // A cancelled prompt is usually replaced at once; releasing the session under the
        // replacement would cut it off.
        if !synth.isSpeaking { deactivateSession() }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
