//
//  OscBroadcaster.swift
//  FlashlightsInTheDark
//
//  Created by OpenAI ChatGPT on 5/15/25.
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
#if canImport(Network)
import Network
#endif

/// Broadcasts OSC messages over UDP to all detected local-network broadcast
/// addresses. Designed for lightweight one-way cues.
// Slot mapping info for each device slot
struct SlotInfo: Codable {
    let ip: String
    let udid: String
    let name: String
}

#if canImport(Network)
/// Lightweight wrapper around NWPathMonitor so we can observe interface changes.
final class InterfaceChangeMonitor {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init(onChange: @escaping (NWPath) -> Void) {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "ai.keex.flashlights.osc.interface-monitor")
        monitor.pathUpdateHandler = onChange
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
extension InterfaceChangeMonitor: @unchecked Sendable {}
#endif

public actor OscBroadcaster {
    // MARK: - Slot mapping (IP, UDID, singer name)  –––––––––––––––––––––––––––––
    let slotInfos: [Int: SlotInfo]

    // --------------------------------------------------------------------
    // MARK: - Stored properties
    // --------------------------------------------------------------------
    private(set) var channel: Channel
    let port: Int
    private(set) var broadcastAddrs: [SocketAddress]
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let ownsEventLoopGroup: Bool
    private var helloHandler: ((Int, String, String?) -> Void)?
    private var ackHandler: ((Int) -> Void)?
    private var tapHandler: (() -> Void)?
    /// Runtime IPs learned from /hello announcements (slot -> ip)
    var dynamicIPs: [Int: String] = [:]
#if canImport(Network)
    private var interfaceMonitor: InterfaceChangeMonitor?
    private var lastPathSignature: String?
#endif

    // --------------------------------------------------------------------
    // MARK: - Initialisation
    // --------------------------------------------------------------------
    public init(
        port: Int = 9000,
        routingFile: URL = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json")!,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws {
        let resolvedGroup: MultiThreadedEventLoopGroup
        if let eventLoopGroup {
            resolvedGroup = eventLoopGroup
            self.ownsEventLoopGroup = false
        } else {
            resolvedGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.ownsEventLoopGroup = true
        }
        self.port = port
        self.eventLoopGroup = resolvedGroup
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

        let boundChannel = try await OscBroadcaster.makeChannel(on: port, group: resolvedGroup)
        self.channel = boundChannel
        self.broadcastAddrs = OscBroadcaster.gatherBroadcastAddrs(port: port)

        try await self.channel.pipeline
            .addHandler(HelloDatagramHandler(owner: self))

#if canImport(Network)
        self.interfaceMonitor = InterfaceChangeMonitor { [weak actor = self] path in
            Task {
                await actor?.handleNetworkPathUpdate(path)
            }
        }
#endif

        print("UDP broadcaster ready on 0.0.0.0:\(port) ✅ – broadcast targets: \(describeBroadcastTargets(broadcastAddrs))")
    }

    // --------------------------------------------------------------------
    // MARK: - Public API
    // --------------------------------------------------------------------
    /// Announce self to the network upon startup
    public func start() async throws {
        try await announceSelf()
        try await discoverKnownDevices()
    }
    /// Broadcast a single OSC message to all detected broadcast addresses.
    public func send(_ osc: OSCMessage) async throws {
        let data = try osc.rawData()
        for addr in broadcastAddrs {
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            let env = AddressedEnvelope(remoteAddress: addr, data: buffer)
            do {
                try await channel.writeAndFlush(env)
            } catch let error as IOError {
                // Ignore "Host is down" errors so the network stack can start
                // even if no interface is currently active.
                if error.errnoCode == EHOSTDOWN {
                    print("⚠️ sendmsg to \(addr) failed: Host is down")
                    continue
                }
                throw error
            }
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

    /// Attempt to send an OSC message directly to the slot's last-known IP,
    /// falling back to broadcast if no address is available.
    public func send(_ osc: OSCMessage, toSlot slot: Int) async throws {
        var delivered = false

        if let ip = dynamicIPs[slot], !ip.isEmpty {
            do {
                try await sendUnicast(osc, toIP: ip)
                delivered = true
            } catch {
                print("⚠️ Unicast to slot \(slot) via dynamic IP \(ip) failed: \(error.localizedDescription)")
            }
        }

        if !delivered, let info = slotInfos[slot], !info.ip.isEmpty {
            do {
                try await sendUnicast(osc, toIP: info.ip)
                delivered = true
            } catch {
                print("⚠️ Unicast to slot \(slot) via mapped IP \(info.ip) failed: \(error.localizedDescription)")
            }
        }

        // Always broadcast as a safety net so devices still hear the cue if
        // their current IP isn't known. Clients filter by index, so duplicates are fine.
        try await send(osc)
    }

    /// Register a callback for incoming /hello announcements
    public func registerHelloHandler(_ handler: @escaping (Int, String, String?) -> Void) {
        helloHandler = handler
    }

    /// Register a callback for incoming /ack messages
    public func registerAckHandler(_ handler: @escaping (Int) -> Void) {
        ackHandler = handler
    }

    /// Register a callback for /tap messages
    public func registerTapHandler(_ handler: @escaping () -> Void) {
        tapHandler = handler
    }

    /// Prompt every known device slot to announce itself by unicasting a
    /// `/discover` message to any saved IP address. This supplements the
    /// broadcast so environments that block 255.255.255.255 still reconnect.
    public func discoverKnownDevices() async throws {
        let osc = OSCMessage(
            OSCAddressPattern("/discover"),
            values: [Int32(0)]
        )

        // Start with a broadcast in case IP assignments have changed. Errors
        // are already handled inside `send` so this call is best-effort.
        try await send(osc)

        var targets = Set<String>()
        for (_, info) in slotInfos where !info.ip.isEmpty {
            targets.insert(info.ip)
        }
        for (_, ip) in dynamicIPs where !ip.isEmpty {
            targets.insert(ip)
        }

        for ip in targets {
            do {
                try await sendUnicast(osc, toIP: ip)
            } catch {
                print("⚠️ Unable to deliver /discover to \(ip): \(error)")
            }
        }
    }

    /// Request a specific slot to announce itself again. Falls back to
    /// broadcast if we don't currently have an IP on record.
    public func requestHello(forSlot slot: Int) async {
        let osc = OSCMessage(
            OSCAddressPattern("/discover"),
            values: [Int32(slot)]
        )

        if let ip = dynamicIPs[slot] ?? slotInfos[slot]?.ip, !ip.isEmpty {
            do {
                try await sendUnicast(osc, toIP: ip)
                return
            } catch {
                print("⚠️ requestHello unicast failed for slot \(slot): \(error)")
            }
        }

        do {
            try await send(osc)
        } catch {
            print("⚠️ requestHello broadcast failed for slot \(slot): \(error)")
        }
    }

    /// Force the broadcaster to rebind its UDP socket and recalculate broadcast targets.
    public func refreshNetworkInterfaces(reason: String = "manual request") async {
        await refreshBindings(reason: reason)
    }

    private static func makeChannel(on port: Int, group: MultiThreadedEventLoopGroup) async throws -> Channel {
        try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEPORT), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_broadcast), value: 1)
            .bind(host: "0.0.0.0", port: port)
            .get()
    }

    private func refreshBindings(reason: String) async {
        var candidate: Channel?
        do {
            candidate = try await OscBroadcaster.makeChannel(on: port, group: eventLoopGroup)
            guard let newChannel = candidate else { return }
            try await newChannel.pipeline.addHandler(HelloDatagramHandler(owner: self))

            let previousAddrs = broadcastAddrs
            let previousDesc = describeBroadcastTargets(previousAddrs)

            let newAddrs = OscBroadcaster.gatherBroadcastAddrs(port: port)
            let oldChannel = channel
            channel = newChannel
            broadcastAddrs = newAddrs

            do {
                try await oldChannel.close()
            } catch {
                print("⚠️ Failed to close old UDP channel during refresh: \(error)")
            }

            do {
                try await announceSelf()
            } catch {
                print("⚠️ announceSelf after refresh failed: \(error)")
            }

            do {
                try await discoverKnownDevices()
            } catch {
                print("⚠️ discoverKnownDevices after refresh failed: \(error)")
            }

            let updatedDesc = describeBroadcastTargets(newAddrs)
            if previousDesc != updatedDesc {
                print("[OscBroadcaster] Broadcast targets updated: \(previousDesc) → \(updatedDesc)")
            } else {
                print("[OscBroadcaster] Broadcast targets unchanged (\(updatedDesc))")
            }
            print("[OscBroadcaster] Refreshed UDP socket (\(reason)).")
        } catch {
            if let candidate {
                Task { try? await candidate.close() }
            }
            print("⚠️ OscBroadcaster refresh failed (\(reason)): \(error)")
        }
    }

    private func describeBroadcastTargets(_ addrs: [SocketAddress]) -> String {
        guard !addrs.isEmpty else { return "none" }
        return addrs.map { address in
            if let ip = address.ipAddress {
                return ip
            }
            return address.description
        }.joined(separator: ", ")
    }
#if canImport(Network)
    private func handleNetworkPathUpdate(_ path: NWPath) async {
        let interfaceSummary = path.availableInterfaces
            .map { describe(interface: $0) }
            .sorted()
            .joined(separator: ", ")
        let statusDescription = describe(pathStatus: path.status)
        let signature = "\(statusDescription)|\(interfaceSummary)"

        if lastPathSignature == signature {
            return
        }
        lastPathSignature = signature

        let reason: String
        if interfaceSummary.isEmpty {
            reason = "network path \(statusDescription)"
        } else {
            reason = "network path \(statusDescription) [\(interfaceSummary)]"
        }
        await refreshBindings(reason: reason)
    }

    private func describe(pathStatus: NWPath.Status) -> String {
        switch pathStatus {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown"
        }
    }

    private func describe(interface: NWInterface) -> String {
        let typeDescription: String
        switch interface.type {
        case .wifi: typeDescription = "wifi"
        case .wiredEthernet: typeDescription = "ethernet"
        case .cellular: typeDescription = "cellular"
        case .loopback: typeDescription = "loopback"
        case .other: typeDescription = "other"
        @unknown default: typeDescription = "unknown"
        }
        return "\(typeDescription):\(interface.name)"
    }
#endif

    // --------------------------------------------------------------------
    // MARK: - De-initialisation
    // --------------------------------------------------------------------
    deinit {
#if canImport(Network)
        interfaceMonitor?.cancel()
#endif
        let ch = channel   // capture the channel (avoid capturing `self`)
        let ownsGroup = ownsEventLoopGroup
        let group = eventLoopGroup
        Task {
            try? await ch.close()
            if ownsGroup {
                group.shutdownGracefully { error in
                    if let error {
                        print("⚠️ Failed to shutdown eventLoopGroup: \(error)")
                    }
                }
            }
        }
    }

    func emitHello(slot: Int, ip: String, udid: String?) {
        dynamicIPs[slot] = ip
        // Check UDID mapping and correct slot if needed
        if let u = udid,
           let expected = slotInfos.first(where: { $0.value.udid == u })?.key,
           expected != slot {
            Task {
                let msg = SetSlot(slot: Int32(expected)).encode()
                try? await sendUnicast(msg, toIP: ip)
            }
        }
        helloHandler?(slot, ip, udid)
    }

    func emitAck(slot: Int) {
        ackHandler?(slot)
    }

    func emitTap() {
        tapHandler?()
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
    /// Parse `/hello` datagram extracting slot and optional UDID.
    fileprivate func parseHello(_ bytes: [UInt8]) -> (Int, String?)? {
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

        func readString(at idx: Int) -> (String, Int)? {
            guard idx < bytes.count else { return nil }
            guard let end = bytes[idx...].firstIndex(of: 0) else { return nil }
            let str = String(bytes: bytes[idx..<end], encoding: .utf8) ?? ""
            let next = (end + 4) & ~3
            return (str, next)
        }

        var slot: Int?
        var udid: String?
        var pos = index
        for t in tags.dropFirst() {
            switch t {
            case "i":
                slot = readInt32(at: pos); pos += 4
            case "h":
                slot = readInt64(at: pos); pos += 8
            case "s":
                if let (s, next) = readString(at: pos) {
                    udid = s; pos = next
                }
            default:
                break
            }
        }
        if let s = slot { return (s, udid) } else { return nil }
    }

    /// Parse `/ack` datagram extracting slot.
    fileprivate func parseAck(_ bytes: [UInt8]) -> Int? {
        guard let addrEnd = bytes.firstIndex(of: 0),
              let addr = String(bytes: bytes[0..<addrEnd], encoding: .utf8),
              addr == "/ack" else { return nil }

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

        if tags.contains("i") {
            return readInt32(at: index)
        }
        return nil
    }

    /// Parse `/tap` datagram
    fileprivate func parseTap(_ bytes: [UInt8]) -> Bool {
        guard let addrEnd = bytes.firstIndex(of: 0),
              let addr = String(bytes: bytes[0..<addrEnd], encoding: .utf8) else { return false }
        return addr == "/tap"
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
            if let (slot, udid) = await owner.parseHello(bytes) {
                await owner.emitHello(slot: slot, ip: ip, udid: udid)
            } else if let slot = await owner.parseAck(bytes) {
                await owner.emitAck(slot: slot)
            } else if await owner.parseTap(bytes) {
                await owner.emitTap()
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
