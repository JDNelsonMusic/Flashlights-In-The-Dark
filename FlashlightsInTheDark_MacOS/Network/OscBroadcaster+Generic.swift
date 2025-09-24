import OSCKit
import NIOCore

public extension OscBroadcaster {
    @inline(__always)
    func send<T: OscCodable>(_ model: T) async throws {
        switch model {
        case let m as FlashOn:
            try await directedOrBroadcast(slot: m.index, osc: m.encode())
        case let m as FlashOff:
            try await directedOrBroadcast(slot: m.index, osc: m.encode())
        case let m as AudioPlay:
            try await directedOrBroadcast(slot: m.index, osc: m.encode())
        case let m as AudioStop:
            try await directedOrBroadcast(slot: m.index, osc: m.encode())
        case let m as MicRecord:
            try await directedOrBroadcast(slot: m.index, osc: m.encode())
        case _ as Tap:
            try await send(model.encode())
        default:
            try await send(model.encode())
        }
    }
    private func directedOrBroadcast(slot: Int32, osc: OSCMessage) async throws {
        let s = Int(slot)
        try await send(osc, toSlot: s)
    }
}
