import Foundation

public struct ChoirDevice: Identifiable, Sendable {
    public var id: Int
    public var torchOn: Bool
    public var audioPlaying: Bool
    public var micActive: Bool
    /// The iOS device UDID used by `flutter run -d <UDID>`.
    public var udid: String
    /// Singer's name, from slot mapping JSON.
    public var name: String
    /// Device IP address, from slot mapping JSON.
    public var ip: String
    /// Current slot assignment the client should listen for (1-based).
    public var listeningSlot: Int

    public init(
        id: Int,
        udid: String,
        name: String = "",
        ip: String = "",
        torchOn: Bool = false,
        audioPlaying: Bool = false,
        micActive: Bool = false,
        listeningSlot: Int? = nil
    ) {
        self.id = id
        self.udid = udid
        self.name = name
        self.ip = ip
        self.torchOn = torchOn
        self.audioPlaying = audioPlaying
        self.micActive = micActive
        // Default to own slot (1-based) if not provided
        self.listeningSlot = listeningSlot ?? (id + 1)
    }
}

extension ChoirDevice {
    public static var demo: [ChoirDevice] {
        (0..<32).map { ChoirDevice(id: $0, udid: "", name: "") }
    }
}