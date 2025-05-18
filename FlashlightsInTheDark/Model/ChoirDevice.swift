import Foundation

public struct ChoirDevice: Identifiable, Sendable {
    public let id: Int
    public var torchOn: Bool
    public var audioPlaying: Bool
    public var micActive: Bool
    /// The iOS device UDID used by `flutter run -d <UDID>`.
    public let udid: String
    /// Singer's name, from slot mapping JSON.
    public let name: String

    public init(
        id: Int,
        udid: String,
        name: String = "",
        torchOn: Bool = false,
        audioPlaying: Bool = false,
        micActive: Bool = false
    ) {
        self.id = id
        self.udid = udid
        self.name = name
        self.torchOn = torchOn
        self.audioPlaying = audioPlaying
        self.micActive = micActive
    }
}

extension ChoirDevice {
    public static var demo: [ChoirDevice] {
        (0..<32).map { ChoirDevice(id: $0, udid: "", name: "") }
    }
}