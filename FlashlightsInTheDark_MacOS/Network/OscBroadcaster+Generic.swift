import OSCKit
import NIOCore

public extension OscBroadcaster {
    @inline(__always)
    func send<T: OscCodable>(_ model: T) async throws {
        try await send(model.encode())
        // For per-slot messages also send a directed copy  –––––––––
        switch model {
        case let m as FlashOn:  try await directed(m.index, osc: m.encode())
        case let m as FlashOff: try await directed(m.index, osc: m.encode())
        case let m as AudioPlay:try await directed(m.index, osc: m.encode())
        case let m as AudioStop:try await directed(m.index, osc: m.encode())
        case let m as MicRecord:try await directed(m.index, osc: m.encode())
        default: break          // /sync etc. stay broadcast-only
        }
    }
    // Helper – send to a single phone if we have its IP
    private func directed(_ slot: Int32, osc: OSCMessage) async throws {
        let s = Int(slot)
        guard let ip = dynamicIPs[s] ?? slotInfos[s]?.ip else { return }
        var buf = channel.allocator.buffer(capacity: try osc.rawData().count)
        buf.writeBytes(try osc.rawData())
        let addr = try SocketAddress(ipAddress: ip, port: port)
        try await channel.writeAndFlush(AddressedEnvelope(remoteAddress: addr, data: buf))
        print("→ directed \(slot) @ \(ip)")
    }
}
