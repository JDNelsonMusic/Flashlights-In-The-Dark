import Foundation

public struct ChoirDevice: Codable, Identifiable, Sendable {
    public var id: Int
    public var torchOn: Bool
    public var audioPlaying: Bool
    public var micActive: Bool
    /// Whether this slot represents a real device or a placeholder
    public var isPlaceholder: Bool
    /// Persistent app-generated device identifier reported in /hello.
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
        1: [10, 3, 11, 12], 2: [10, 3, 11, 12], 3: [10, 3, 11, 12], 4: [10, 3, 11, 12],
        5: [10, 7, 15, 16], 6: [10, 7, 15, 16], 7: [10, 8, 15, 16], 8: [10, 8, 15, 16],
        9: [10, 8, 15, 16], 10: [10, 8, 15, 16], 11: [10, 7, 15, 16], 12: [10, 7, 15, 16],
        13: [10, 5, 13, 14], 14: [10, 5, 13, 14], 15: [10, 5, 13, 14], 16: [10, 5, 13, 14],
        17: [10, 6, 13, 14], 18: [10, 6, 13, 14], 19: [10, 4, 13, 14], 20: [10, 4, 13, 14],
        21: [10, 4, 13, 14], 22: [10, 4, 13, 14], 23: [10, 6, 13, 14], 24: [10, 6, 13, 14],
        25: [10, 2, 11, 12], 26: [10, 2, 11, 12], 27: [10, 2, 11, 12], 28: [10, 2, 11, 12],
        29: [10, 9, 15, 16], 30: [10, 9, 15, 16], 31: [10, 1, 11, 12], 32: [10, 1, 11, 12],
        33: [10, 1, 11, 12], 34: [10, 1, 11, 12], 35: [10, 9, 15, 16], 36: [10, 9, 15, 16]
    ]

    /// Attempt to load a channel map from a JSON file. The JSON should be a
    /// dictionary where keys are slot numbers as strings and values are arrays
    /// of MIDI channel integers. Returns nil if the file cannot be parsed.
    public static func loadChannelMap(from url: URL) -> [Int: Set<Int>]? {
        do {
            let data = try Data(contentsOf: url)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: [Int]] {
                var result: [Int: Set<Int>] = [:]
                for (slotStr, channels) in dict {
                    if let slot = Int(slotStr) {
                        result[slot] = Set(channels)
                    }
                }
                return result
            }
        } catch {
            print("Error loading channel map: \(error)")
        }
        return nil
    }

    public static var demo: [ChoirDevice] {
        return (1...36).map { i in
            ChoirDevice(
                id: i - 1,
                udid: "",
                name: "",
                midiChannels: defaultChannelMap[i] ?? [10],
                isPlaceholder: false
            )
        }
    }
}
