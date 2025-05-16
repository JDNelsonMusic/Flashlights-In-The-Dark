import Foundation
import OSCKit

public enum OscAddress: String {
    case flashOn   = "/flash/on"
    case flashOff  = "/flash/off"
    case audioPlay = "/audio/play"
    case audioStop = "/audio/stop"
    case micRecord = "/mic/record"
    case sync      = "/sync"
}

public protocol OscCodable {
    static var address: OscAddress { get }
    init?(from message: OSCMessage)
    func encode() -> OSCMessage
}

// MARK: – FlashOn -------------------------------------------------------------

public struct FlashOn: OscCodable {
    public static let address: OscAddress = .flashOn
    public let index: Int32
    public let intensity: Float32

    public init(index: Int32, intensity: Float32) {
        self.index = index
        self.intensity = intensity
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx   = message.values.int32(at: 0),
              let inten = message.values.float32(at: 1)
        else { return nil }

        self.init(index: idx, intensity: inten)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ index, intensity ]
        )
    }
}

// MARK: – FlashOff ------------------------------------------------------------

public struct FlashOff: OscCodable {
    public static let address: OscAddress = .flashOff
    public let index: Int32

    public init(index: Int32) { self.index = index }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx = message.values.int32(at: 0)
        else { return nil }
        self.init(index: idx)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ index ]
        )
    }
}

// MARK: – AudioPlay -----------------------------------------------------------

public struct AudioPlay: OscCodable {
    public static let address: OscAddress = .audioPlay
    public let index: Int32
    public let file: String
    public let gain: Float32

    public init(index: Int32, file: String, gain: Float32) {
        self.index = index; self.file = file; self.gain = gain
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx  = message.values.int32(at: 0),
              let name = message.values.string(at: 1),
              let g    = message.values.float32(at: 2)
        else { return nil }
        self.init(index: idx, file: name, gain: g)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ index, file, gain ]
        )
    }
}

// MARK: – AudioStop -----------------------------------------------------------

public struct AudioStop: OscCodable {
    public static let address: OscAddress = .audioStop
    public let index: Int32

    public init(index: Int32) { self.index = index }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx = message.values.int32(at: 0)
        else { return nil }
        self.init(index: idx)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ index ]
        )
    }
}

// MARK: – MicRecord -----------------------------------------------------------

public struct MicRecord: OscCodable {
    public static let address: OscAddress = .micRecord
    public let index: Int32
    public let maxDuration: Float32

    public init(index: Int32, maxDuration: Float32) {
        self.index = index; self.maxDuration = maxDuration
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx = message.values.int32(at: 0),
              let dur = message.values.float32(at: 1)
        else { return nil }
        self.init(index: idx, maxDuration: dur)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ index, maxDuration ]
        )
    }
}

// MARK: – SyncMessage ---------------------------------------------------------

public struct SyncMessage: OscCodable {
    public static let address: OscAddress = .sync
    public let timestamp: OSCTimeTag

    public init(timestamp: OSCTimeTag) { self.timestamp = timestamp }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let ts = message.values.timetag(at: 0)
        else { return nil }
        self.init(timestamp: ts)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ timestamp ]
        )
    }
}

// TODO: wire these messages into the SwiftNIO broadcaster.