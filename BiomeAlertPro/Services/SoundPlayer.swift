import AppKit

/// Plays the configurable alert sound using the system sound library.
@MainActor
final class SoundPlayer {
    /// Standard macOS system sounds available for alerts.
    static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private var currentSound: NSSound?

    func play(named name: String) {
        currentSound?.stop()
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        currentSound = sound
        sound.play()
    }
}
