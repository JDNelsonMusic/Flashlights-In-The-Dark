import Foundation

public struct ChoirDevice: Identifiable, Sendable {
    public let id: Int
    public var torchOn: Bool
    public var audioPlaying: Bool
    public var micActive: Bool

    public init(
        id: Int,
        torchOn: Bool = false,
        audioPlaying: Bool = false,
        micActive: Bool = false,
    ) {
        self.id = id
        self.torchOn = torchOn
        self.audioPlaying = audioPlaying
        self.micActive = micActive
    }
}

extension ChoirDevice {
    public static var demo: [ChoirDevice] {
        (0..<32).map { ChoirDevice(id: $0) }
    }
}