import Foundation

public struct ChoirDevice: Identifiable, Sendable {
    public var id: Int
    public var torchOn: Bool
    public var audioPlaying: Bool
    public var micActive: Bool
    /// Whether this slot represents a real device or a placeholder
    public var isPlaceholder: Bool
    /// The iOS device UDID used by `flutter run -d <UDID>`.
    public var udid: String
    /// Singer's name, from slot mapping JSON.
    public var name: String
    /// Device IP address, from slot mapping JSON.
    public var ip: String
    /// Current slot assignment the client should listen for (1-based).
    public var listeningSlot: Int
    /// MIDI channel this device responds to (1-16)
    public var midiChannel: Int

    public init(
        id: Int,
        udid: String,
        name: String = "",
        ip: String = "",
        torchOn: Bool = false,
        audioPlaying: Bool = false,
        micActive: Bool = false,
        listeningSlot: Int? = nil,
        midiChannel: Int = 1,
        isPlaceholder: Bool = false
    ) {
        self.id = id
        self.udid = udid
        self.name = name
        self.ip = ip
        self.torchOn = torchOn
        self.audioPlaying = audioPlaying
        self.micActive = micActive
        self.isPlaceholder = isPlaceholder
        // Default to own slot (1-based) if not provided
        self.listeningSlot = listeningSlot ?? (id + 1)
        self.midiChannel = midiChannel
    }
}

extension ChoirDevice {
    public static var demo: [ChoirDevice] {
        let realSlots: Set<Int> = [
            1, 3, 4, 5, 7, 9, 12,
            14, 15, 16, 18, 19, 20, 21, 23, 24, 25,
            27, 29, 34, 38, 40,
            41, 42, 44, 51, 53, 54
        ]
        return (1...54).map { i in
            ChoirDevice(
                id: i - 1,
                udid: "",
                name: "",
                midiChannel: 1,
                isPlaceholder: !realSlots.contains(i)
            )
        }
    }
}