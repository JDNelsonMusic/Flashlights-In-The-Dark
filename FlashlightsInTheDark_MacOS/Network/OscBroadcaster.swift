//
//  OscBroadcaster.swift
//  FlashlightsInTheDark
//
//  Created by ChatGPT on 5/15/25.
//

import Foundation
import NIOCore
#if os(Linux) || os(Android)
import Glibc
#else
import Darwin
#endif
import NIOPosix
import OSCKit          // OSCMessage, OSCAddressPattern
import SystemConfiguration

/// Broadcasts OSC messages over UDP to all detected local-network broadcast
/// addresses. Designed for lightweight one-way cues.
// Slot mapping info for each device slot
struct SlotInfo: Codable {
    let ip: String
    let udid: String
    let name: String
}

public actor OscBroadcaster {
    // MARK: - Slot mapping (IP, UDID, singer name)  –––––––––––––––––––––––––––––
    let slotInfos: [Int: SlotInfo]

    // --------------------------------------------------------------------
    // MARK: - Stored properties
    // --------------------------------------------------------------------
    let channel: Channel
    let port: Int
    let broadcastAddrs: [SocketAddress]
    private var helloHandler: ((Int, String) -> Void)?
    /// Runtime IPs learned from /hello announcements (slot -> ip)
    var dynamicIPs: [Int: String] = [:]

    // --------------------------------------------------------------------
    // MARK: - Initialisation
    // --------------------------------------------------------------------
    public init(
        port: Int = 9000,
        routingFile: URL = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json")!,
        eventLoopGroup: MultiThreadedEventLoopGroup = .init(numberOfThreads: 1)
    ) async throws {
        self.port = port
        // load slot mapping once at launch
        if
            let data = try? Data(contentsOf: routingFile),
            let dict = try? JSONDecoder().decode([String: SlotInfo].self, from: data)
        {
            self.slotInfos = Dictionary(uniqueKeysWithValues:
                dict.compactMap { key, info in
                    guard let slot = Int(key) else { return nil }
                    return (slot, info)
                }
            )
        } else {
            self.slotInfos = [:]
            print("⚠️  No flash_ip+udid_map.json found – falling back to pure broadcast.")
        }

        // Datagram bootstrap with broadcast privileges.
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEPORT), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_broadcast), value: 1)

        // Bind to *all* interfaces on the chosen port.
        self.channel = try await bootstrap
            .bind(host: "0.0.0.0", port: port)
            .get()

        // Initialise **all** stored properties *before* we capture `self`
        // inside any pipeline handler, otherwise Swift’s definite-initialisation
        // rules complain that “self is used before all stored properties
        // are initialised”.
        self.broadcastAddrs = OscBroadcaster.gatherBroadcastAddrs(port: port)

        // Now that every property is set, it’s safe to reference `self`.
        try await self.channel.pipeline
            .addHandler(HelloDatagramHandler(owner: self))

        print("UDP broadcaster ready on 0.0.0.0:\(port) ✅")
    }

    // --------------------------------------------------------------------
    // MARK: - Public API
    // --------------------------------------------------------------------
    /// Announce self to the network upon startup
    public func start() async throws {
        try await announceSelf()
    }
    /// Broadcast a single OSC message to all detected broadcast addresses.
    public func send(_ osc: OSCMessage) async throws {
        let data = try osc.rawData()
        for addr in broadcastAddrs {
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            let env = AddressedEnvelope(remoteAddress: addr, data: buffer)
            try await channel.writeAndFlush(env)
        }
        print("→ \(osc.addressPattern.stringValue)")
    }
    
    /// Send an OSC message directly to a specific device slot (unicast) using its IP.
    /// - Parameters:
    ///   - osc: The OSC message to send
    ///   - slot: The 1-based slot number identifying the target device
    public func sendUnicast(_ osc: OSCMessage, toSlot slot: Int) async throws {
        let data = try osc.rawData()
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        if let ip = dynamicIPs[slot] ?? slotInfos[slot]?.ip {
            let addr = try SocketAddress(ipAddress: ip, port: port)
            let envelope = AddressedEnvelope(remoteAddress: addr, data: buffer)
            try await channel.writeAndFlush(envelope)
            print("→ \(osc.addressPattern.stringValue) to \(ip):\(port)")
        } else {
            // Fallback to broadcast if mapping not found
            try await send(osc)
        }
    }
    
    /// Send an OSC message directly to a specific IP address.
    /// - Parameters:
    ///   - osc: The OSC message to send
    ///   - ip: The target device's IP address
    public func sendUnicast(_ osc: OSCMessage, toIP ip: String) async throws {
        let data = try osc.rawData()
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let addr = try SocketAddress(ipAddress: ip, port: port)
        let envelope = AddressedEnvelope(remoteAddress: addr, data: buffer)
        try await channel.writeAndFlush(envelope)
        print("→ \(osc.addressPattern.stringValue) to \(ip):\(port)")
    }

    /// Register a callback for incoming /hello announcements
    public func registerHelloHandler(_ handler: @escaping (Int, String) -> Void) {
        helloHandler = handler
    }

    // --------------------------------------------------------------------
    // MARK: - De-initialisation
    // --------------------------------------------------------------------
    deinit {
        let ch = channel   // capture the channel (avoid capturing `self`)
        Task { try? await ch.close() }
    }

    func emitHello(slot: Int, ip: String) {
        dynamicIPs[slot] = ip
        helloHandler?(slot, ip)
    }
}

extension OscBroadcaster {
    private func announceSelf() async throws {
        let slotValue = Int32(UserDefaults.standard.integer(forKey: "slot"))
        let msg = OSCMessage(
            OSCAddressPattern("/hello"),
            values: [ProcessInfo.processInfo.hostName, slotValue]
        )
        try await send(msg)
    }
}

// MARK: - Incoming Hello Handling
extension OscBroadcaster {
    /// Basic OSC parser to detect `/hello` with a numeric slot argument.
    ///
    /// Earlier prototypes only sent an Int32, but some client libraries may
    /// emit Int64 values.  Accept either format for robustness.
    fileprivate func parseHelloSlot(_ bytes: [UInt8]) -> Int? {
        guard let addrEnd = bytes.firstIndex(of: 0),
              let addr = String(bytes: bytes[0..<addrEnd], encoding: .utf8),
              addr == "/hello" else { return nil }

        var index = (addrEnd + 4) & ~3
        guard index < bytes.count,
              bytes[index] == UInt8(ascii: ",") else { return nil }
        guard let tagEnd = bytes[index...].firstIndex(of: 0) else { return nil }
        let tags = String(bytes: bytes[index..<tagEnd], encoding: .utf8) ?? ""
        index = (tagEnd + 4) & ~3

        func readInt32(at idx: Int) -> Int? {
            guard idx + 3 < bytes.count else { return nil }
            var v: Int32 = 0
            for b in bytes[idx..<(idx+4)] { v = (v << 8) | Int32(b) }
            return Int(v)
        }

        func readInt64(at idx: Int) -> Int? {
            guard idx + 7 < bytes.count else { return nil }
            var v: Int64 = 0
            for b in bytes[idx..<(idx+8)] { v = (v << 8) | Int64(b) }
            return Int(v)
        }

        if tags.contains("i") {                // Int32
            return readInt32(at: index)
        } else if tags.contains("h") {         // Int64
            return readInt64(at: index)
        } else {
            return nil
        }
    }
}

final class HelloDatagramHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    unowned let owner: OscBroadcaster

    init(owner: OscBroadcaster) { self.owner = owner }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let env = self.unwrapInboundIn(data)
        var buffer = env.data
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            return
        }
        // Only emit if both an IP address and a valid slot are found
        guard let ip = env.remoteAddress.ipAddress else { return }

        Task {
            if let slot = await owner.parseHelloSlot(bytes) {
                await owner.emitHello(slot: slot, ip: ip)
            }
        }
    }
}

// MARK: - Broadcast Address Discovery
extension OscBroadcaster {
    /// Gather broadcast addresses for all active IPv4 interfaces.
    static func gatherBroadcastAddrs(port: Int) -> [SocketAddress] {
        var addrs: [SocketAddress] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return [try! SocketAddress(ipAddress: "255.255.255.255", port: port)]
        }
        defer { freeifaddrs(first) }

        var ptr = first
        while true {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            if flags & IFF_UP != 0 && flags & IFF_LOOPBACK == 0,
               let addr = ifa.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET),
               let netmask = ifa.ifa_netmask {
                var ip = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_in.self).pointee
                let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee
                let bcast = in_addr(s_addr: ip.sin_addr.s_addr | ~mask.sin_addr.s_addr)
                ip.sin_addr = bcast
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &ip.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                let ipStr = String(cString: buffer)
                if let sa = try? SocketAddress(ipAddress: ipStr, port: port) {
                    addrs.append(sa)
                }
            }
            if ptr.pointee.ifa_next == nil { break }
            ptr = ptr.pointee.ifa_next!
        }
        if addrs.isEmpty {
            addrs.append(try! SocketAddress(ipAddress: "255.255.255.255", port: port))
        }
        return addrs
    }
}
