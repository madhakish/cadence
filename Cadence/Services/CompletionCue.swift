import AudioToolbox
import AVFoundation
import UIKit
import UserNotifications

/// The one "it's done" cue on this client — rest over, hold complete. One
/// bundled tone (the same 880 Hz half-second the web client synthesizes in
/// `beep()`), played through an ambient audio session so it follows the
/// active route (headphones, speaker), mixes with music instead of stopping
/// it, and honours the Ring/Silent switch; the same file is attached to the
/// background notification so the phone says exactly one thing whether it
/// is in hand or face-down. Callers decide *whether* to cue (foreground only,
/// never after a background alert already fired); this decides *how*.
///
/// Main thread only: the feedback generator and the accessibility post are
/// UI-bound, and every caller already runs there.
enum CompletionCue {
    /// The bundled tone. The Live Activity controller names the same file for
    /// the rest notification so both paths share one identity.
    static let soundFile = WorkoutActivityController.completionSoundFile

    private static var player: AVAudioPlayer?

    /// The tone plays only while the device-local sound preference is on;
    /// haptics and the announcement are independent of it.
    static var soundEnabled: Bool { WorkoutActivityController.completionSoundEnabled }

    /// Foreground cue: tone, haptic when the athlete allows it, and a
    /// VoiceOver announcement that says the same thing the screen does.
    static func play(haptics: Bool, announcement: String) {
        if soundEnabled { playTone() }
        if haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    /// The same tone on a delivered notification, or silence when the sound
    /// preference is off.
    static var notificationSound: UNNotificationSound? {
        soundEnabled ? UNNotificationSound(named: UNNotificationSoundName(rawValue: soundFile)) : nil
    }

    /// Releases the player and hands the audio session back once the half
    /// second is over, so a cue never leaves an active session behind.
    private final class Releaser: NSObject, AVAudioPlayerDelegate {
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            CompletionCue.release()
        }
    }
    private static let releaser = Releaser()

    private static func release() {
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func playTone() {
        let name = (soundFile as NSString).deletingPathExtension
        let ext = (soundFile as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            AudioServicesPlaySystemSound(1005) // the tone is missing from the bundle; still say something
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            let tone = try AVAudioPlayer(contentsOf: url)
            tone.delegate = releaser
            tone.prepareToPlay()
            tone.play()
            player = tone
        } catch {
            AudioServicesPlaySystemSound(1005)
        }
    }
}
