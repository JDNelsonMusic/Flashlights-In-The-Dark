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
    /// MIDI channels this device responds to (1-16)
    public var midiChannels: Set<Int>

    public init(
        id: Int,
        udid: String,
        name: String = "",
        ip: String = "",
        torchOn: Bool = false,
        audioPlaying: Bool = false,
        micActive: Bool = false,
        listeningSlot: Int? = nil,
        midiChannels: Set<Int> = [10],
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
        self.midiChannels = midiChannels
    }
}

extension ChoirDevice {
    /// Default mapping of real slot numbers to their listening MIDI channels.
    public static let defaultChannelMap: [Int: Set<Int>] = [
        27: [10, 1, 11, 12], 41: [10, 1, 11, 12], 42: [10, 1, 11, 12],
        1: [10, 2, 11, 12], 14: [10, 2, 11, 12], 15: [10, 2, 11, 12],
        16: [10, 3, 11, 12], 29: [10, 3, 11, 12], 44: [10, 3, 11, 12],
        3: [10, 4, 13, 14], 4: [10, 4, 13, 14], 18: [10, 4, 13, 14],
        7: [10, 5, 13, 14], 19: [10, 5, 13, 14], 34: [10, 5, 13, 14],
        9: [10, 6, 13, 14], 20: [10, 6, 13, 14], 21: [10, 6, 13, 14],
        23: [10, 7, 15, 16], 38: [10, 7, 15, 16], 51: [10, 7, 15, 16],
        12: [10, 8, 15, 16], 24: [10, 8, 15, 16], 25: [10, 8, 15, 16],
        40: [10, 9, 15, 16], 53: [10, 9, 15, 16], 54: [10, 9, 15, 16]
    ]

    public static var demo: [ChoirDevice] {
        let realSlots = Set(defaultChannelMap.keys)
        return (1...54).map { i in
            ChoirDevice(
                id: i - 1,
                udid: "",
                name: "",
                midiChannels: defaultChannelMap[i] ?? [10],
                isPlaceholder: !realSlots.contains(i)
            )
        }
    }
}