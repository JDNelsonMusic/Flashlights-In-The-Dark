import Foundation
import OSCKit

public enum OscAddress: String {
    case flashOn   = "/flash/on"
    case flashOff  = "/flash/off"
    case audioPlay = "/audio/play"
    case audioStop = "/audio/stop"
    case eventTrigger = "/event/trigger"
    case micRecord = "/mic/record"
    case sync      = "/sync"
    case tap       = "/tap"
    /// Dynamically assign the listening slot on a client
    case setSlot   = "/set-slot"
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
    public let startAtMs: Double?

    public init(index: Int32, file: String, gain: Float32, startAtMs: Double? = nil) {
        self.index = index
        self.file = file
        self.gain = gain
        self.startAtMs = startAtMs
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx  = message.values.int32(at: 0),
              let name = message.values.string(at: 1),
              let g    = message.values.float32(at: 2)
        else { return nil }

        let start: Double?
        if message.values.count >= 4 {
            if let raw64 = message.values.float64(at: 3) {
                start = Double(raw64)
            } else if let raw32 = message.values.float32(at: 3) {
                start = Double(raw32)
            } else {
                start = nil
            }
        } else {
            start = nil
        }

        self.init(index: idx, file: name, gain: g, startAtMs: start)
    }

    public func encode() -> OSCMessage {
        var values: [any OSCValue] = [index, file, gain]
        if let startAtMs {
            values.append(Float64(startAtMs))
        }
        return OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: values
        )
    }
}

// MARK: – EventTrigger -------------------------------------------------------

public struct EventTrigger: OscCodable {
    public static let address: OscAddress = .eventTrigger
    public let index: Int32
    public let eventId: Int32
    public let startAtMs: Double?

    public init(index: Int32, eventId: Int32, startAtMs: Double? = nil) {
        self.index = index
        self.eventId = eventId
        self.startAtMs = startAtMs
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let idx = message.values.int32(at: 0),
              let evt = message.values.int32(at: 1)
        else { return nil }
        let start: Double?
        if message.values.count >= 3 {
            if let raw64 = message.values.float64(at: 2) {
                start = Double(raw64)
            } else if let raw32 = message.values.float32(at: 2) {
                start = Double(raw32)
            } else {
                start = nil
            }
        } else {
            start = nil
        }
        self.init(index: idx, eventId: evt, startAtMs: start)
    }

    public func encode() -> OSCMessage {
        var vals: [any OSCValue] = [index, eventId]
        if let s = startAtMs {
            vals.append(Float64(s))
        }
        return OSCMessage(OSCAddressPattern(Self.address.rawValue), values: vals)
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
// MARK: – SetSlot ------------------------------------------------------------
/// Instruct a client to change its listening slot at runtime
public struct SetSlot: OscCodable {
    public static let address: OscAddress = .setSlot
    /// The new slot index (1-based) the client should listen for
    public let slot: Int32

    public init(slot: Int32) {
        self.slot = slot
    }

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue),
              let s = message.values.int32(at: 0)
        else { return nil }
        self.init(slot: s)
    }

    public func encode() -> OSCMessage {
        OSCMessage(
            OSCAddressPattern(Self.address.rawValue),
            values: [ slot ]
        )
    }
}

// MARK: – Tap ---------------------------------------------------------------
/// Simple tap/cue message from a proxy device
public struct Tap: OscCodable {
    public static let address: OscAddress = .tap

    public init() {}

    public init?(from message: OSCMessage) {
        guard message.addressPattern == OSCAddressPattern(Self.address.rawValue) else { return nil }
        self.init()
    }

    public func encode() -> OSCMessage {
        OSCMessage(OSCAddressPattern(Self.address.rawValue), values: [])
    }
}
