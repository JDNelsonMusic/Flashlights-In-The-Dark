//
//  OscBroadcaster.swift
//  FlashlightsInTheDark
//

import Foundation
import NIOCore
#if os(Linux) || os(Android)
import Glibc
#else
import Darwin
#endif
import NIOPosix
import OSCKit
import SystemConfiguration
#if canImport(Network)
import Network
#endif

struct SlotInfo: Codable {
    let ip: String
    let udid: String
    let name: String
}

public struct CueSendMetricsSnapshot: Sendable {
    public struct InterfaceHealth: Sendable {
        public let interfaceName: String
        public let successCount: Int
        public let failureCount: Int
    }

    public let totalPacketsSent: Int
    public let totalPacketsFailed: Int
    public let packetsPerSecond: Double
    public let packetsPerCue: [String: Int]
    public let interfaceHealth: [InterfaceHealth]
}

public struct ConcertHelloSnapshot: Sendable {
    public let showSessionId: String
    public let protocolVersion: Int32
    public let expectedDeviceCount: Int
    public let isArmed: Bool
}

private struct BroadcastTarget: Sendable {
    let interfaceName: String
    let address: SocketAddress
    let ipAddress: String
}

private struct InterfaceCounters: Sendable {
    var success: Int = 0
    var failure: Int = 0
}

private struct ClientHello {
    let slot: Int
    let deviceId: String?
    let protocolVersion: Int?
    let showSessionId: String?
}

#if canImport(Network)
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
    let slotInfos: [Int: SlotInfo]

    private(set) var channel: Channel
    let port: Int
    private var broadcastTargets: [BroadcastTarget]
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let ownsEventLoopGroup: Bool
    fileprivate let diagnostics: NetworkDiagnostics?

    private var helloHandler: ((Int, String, String?) -> Void)?
    private var ackHandler: ((Int) -> Void)?
    private var tapHandler: (() -> Void)?

    private var dynamicIPs: [Int: String] = [:]
    private var dynamicDeviceIds: [Int: String] = [:]

    private var showSessionId: String = UUID().uuidString
    private var protocolVersion: Int32 = ConcertProtocol.version
    private var expectedDeviceCount: Int = ConcertProtocol.expectedDeviceCount
    private var nextSequence: Int64 = 1
    private var isArmed: Bool = false

    private let resendAttempts: Int = 3
    private let resendIntervalNs: UInt64 = 30_000_000

    private var packetTimestamps: [Date] = []
    private var packetsPerCue: [String: Int] = [:]
    private var totalPacketsSent: Int = 0
    private var totalPacketsFailed: Int = 0
    private var interfaceCounters: [String: InterfaceCounters] = [:]

#if canImport(Network)
    private var interfaceMonitor: InterfaceChangeMonitor?
    private var lastPathSignature: String?
#endif

    public init(
        port: Int = 9000,
        routingFile: URL = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json")!,
        diagnostics: NetworkDiagnostics? = nil,
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
        self.diagnostics = diagnostics

        if
            let data = try? Data(contentsOf: routingFile),
            let dict = try? JSONDecoder().decode([String: SlotInfo].self, from: data)
        {
            self.slotInfos = Dictionary(uniqueKeysWithValues: dict.compactMap { key, info in
                guard let slot = Int(key) else { return nil }
                return (slot, info)
            })
        } else {
            self.slotInfos = [:]
        }

        let boundChannel = try await OscBroadcaster.makeChannel(on: port, group: resolvedGroup)
        self.channel = boundChannel
        self.broadcastTargets = OscBroadcaster.gatherBroadcastTargets(port: port)

        try await self.channel.pipeline.addHandler(HelloDatagramHandler(owner: self))

        await diagnostics?.record(
            .broadcasterStarted,
            message: "Bound UDP broadcaster on 0.0.0.0:\(port)"
        )
        await diagnostics?.record(
            .broadcasterInterfaceRefresh,
            message: "Initial broadcast targets: \(describeBroadcastTargets(self.broadcastTargets))"
        )

#if canImport(Network)
        self.interfaceMonitor = InterfaceChangeMonitor { [weak actor = self] path in
            Task {
                await actor?.handleNetworkPathUpdate(path)
            }
        }
#endif
    }

    // MARK: - Concert state

    public func configureConcert(
        showSessionId: String,
        protocolVersion: Int32 = ConcertProtocol.version,
        expectedDeviceCount: Int = ConcertProtocol.expectedDeviceCount
    ) {
        self.showSessionId = showSessionId
        self.protocolVersion = protocolVersion
        self.expectedDeviceCount = expectedDeviceCount
        self.nextSequence = 1
        self.packetsPerCue.removeAll()
        self.packetTimestamps.removeAll()
        self.totalPacketsSent = 0
        self.totalPacketsFailed = 0
    }

    public func setArmed(_ armed: Bool) {
        isArmed = armed
    }

    public func concertSnapshot() -> ConcertHelloSnapshot {
        ConcertHelloSnapshot(
            showSessionId: showSessionId,
            protocolVersion: protocolVersion,
            expectedDeviceCount: expectedDeviceCount,
            isArmed: isArmed
        )
    }

    public func metricsSnapshot() -> CueSendMetricsSnapshot {
        let now = Date()
        packetTimestamps.removeAll { now.timeIntervalSince($0) > 1 }
        let pps = Double(packetTimestamps.count)

        let interfaceHealth = interfaceCounters
            .map { name, counters in
                CueSendMetricsSnapshot.InterfaceHealth(
                    interfaceName: name,
                    successCount: counters.success,
                    failureCount: counters.failure
                )
            }
            .sorted { $0.interfaceName < $1.interfaceName }

        return CueSendMetricsSnapshot(
            totalPacketsSent: totalPacketsSent,
            totalPacketsFailed: totalPacketsFailed,
            packetsPerSecond: pps,
            packetsPerCue: packetsPerCue,
            interfaceHealth: interfaceHealth
        )
    }

    // MARK: - Lifecycle

    public func start() async throws {
        await diagnostics?.record(.broadcasterAnnounced, message: "Starting network stack")
        try await broadcastConductorHello()
        await diagnostics?.record(.broadcasterDiscover, message: "Initial discover sweep")
        try await discoverKnownDevices()
    }

    public func refreshNetworkInterfaces(reason: String = "manual request") async {
        await refreshBindings(reason: reason)
    }

    // MARK: - Public sending API

    /// Explicit broadcast path for discovery and panic-only traffic.
    public func send(_ osc: OSCMessage) async throws {
        try await sendBroadcast(osc, cueId: nil, routeLabel: "broadcast")
    }

    public func sendUnicast(_ osc: OSCMessage, toSlot slot: Int) async throws {
        guard let ip = resolveIP(forSlot: slot) else {
            throw NSError(
                domain: "OscBroadcaster",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No known endpoint for slot \(slot)"]
            )
        }
        try await sendUnicast(osc, toIP: ip, slot: slot, cueId: nil, routeLabel: "unicast")
    }

    public func sendUnicast(_ osc: OSCMessage, toIP ip: String) async throws {
        try await sendUnicast(osc, toIP: ip, slot: nil, cueId: nil, routeLabel: "direct")
    }

    /// Authoritative routing path for sloted cues: unicast only.
    public func send(_ osc: OSCMessage, toSlot slot: Int) async throws {
        try await sendUnicast(osc, toSlot: slot)
    }

    public func sendCue(
        address: OscAddress,
        slot: Int32,
        payload: [any OSCValue],
        allowWhenDisarmed: Bool = false
    ) async throws {
        guard isArmed || allowWhenDisarmed else {
            throw NSError(
                domain: "OscBroadcaster",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Concert mode is not armed"]
            )
        }

        let meta = nextCueMeta()
        var values: [any OSCValue] = [
            slot,
            protocolVersion,
            showSessionId,
            Int64(meta.seq),
            meta.cueId,
            Int64(meta.sentAtMs)
        ]
        values.append(contentsOf: payload)

        let message = OSCMessage(OSCAddressPattern(address.rawValue), values: values)
        let slotNumber = Int(slot)

        await diagnostics?.record(
            .cueRouteSelected,
            slot: slotNumber,
            message: "Cue \(address.rawValue) via unicast",
            route: "unicast",
            cueId: meta.cueId
        )

        guard let ip = resolveIP(forSlot: slotNumber) else {
            await diagnostics?.record(
                .sendFailed,
                slot: slotNumber,
                message: "No endpoint known for slot \(slotNumber)",
                cueId: meta.cueId
            )
            throw NSError(
                domain: "OscBroadcaster",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No known endpoint for slot \(slotNumber)"]
            )
        }

        for attempt in 1...resendAttempts {
            do {
                try await sendUnicast(
                    message,
                    toIP: ip,
                    slot: slotNumber,
                    cueId: meta.cueId,
                    routeLabel: "unicast"
                )
            } catch {
                if attempt == resendAttempts {
                    throw error
                }
            }
            if attempt < resendAttempts {
                try? await Task.sleep(nanoseconds: resendIntervalNs)
            }
        }
    }

    public func broadcastConductorHello() async throws {
        let message = OSCMessage(
            OSCAddressPattern("/hello"),
            values: [
                "conductor",
                protocolVersion,
                showSessionId,
                Int32(expectedDeviceCount),
                Int64(Date().timeIntervalSince1970 * 1000)
            ]
        )
        try await sendBroadcast(message, cueId: nil, routeLabel: "broadcast")
        await diagnostics?.record(
            .broadcasterAnnounced,
            message: "Broadcast conductor /hello"
        )
    }

    public func broadcastPanicAllStop() async throws {
        let meta = nextCueMeta()
        let message = OSCMessage(
            OSCAddressPattern(OscAddress.panicAllStop.rawValue),
            values: [
                Int32(0),
                protocolVersion,
                showSessionId,
                Int64(meta.seq),
                meta.cueId,
                Int64(meta.sentAtMs)
            ]
        )

        await diagnostics?.record(
            .cueRouteSelected,
            message: "Panic all-stop via broadcast",
            route: "broadcast",
            cueId: meta.cueId
        )

        try await sendBroadcast(message, cueId: meta.cueId, routeLabel: "broadcast")
    }

    public func discoverKnownDevices() async throws {
        let discover = OSCMessage(
            OSCAddressPattern("/discover"),
            values: [Int32(0)]
        )

        try await sendBroadcast(discover, cueId: nil, routeLabel: "broadcast")

        var targets = Set<String>()
        for (_, info) in slotInfos where !info.ip.isEmpty {
            targets.insert(info.ip)
        }
        for (_, ip) in dynamicIPs where !ip.isEmpty {
            targets.insert(ip)
        }

        for ip in targets {
            do {
                try await sendUnicast(discover, toIP: ip, slot: nil, cueId: nil, routeLabel: "direct")
            } catch {
                await diagnostics?.record(
                    .sendFailed,
                    ipAddress: ip,
                    message: "/discover unicast failed: \(error.localizedDescription)"
                )
            }
        }
    }

    public func requestHello(forSlot slot: Int) async {
        let discover = OSCMessage(
            OSCAddressPattern("/discover"),
            values: [Int32(slot)]
        )

        await diagnostics?.record(
            .slotAssignmentRequested,
            slot: slot,
            message: "Requested /hello refresh"
        )

        if let ip = resolveIP(forSlot: slot) {
            do {
                try await sendUnicast(discover, toIP: ip, slot: slot, cueId: nil, routeLabel: "unicast")
                return
            } catch {
                await diagnostics?.record(
                    .sendFailed,
                    slot: slot,
                    ipAddress: ip,
                    message: "/discover unicast failed: \(error.localizedDescription)"
                )
            }
        }

        do {
            try await sendBroadcast(discover, cueId: nil, routeLabel: "broadcast")
        } catch {
            await diagnostics?.record(
                .sendFailed,
                slot: slot,
                message: "/discover broadcast failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Handlers

    public func registerHelloHandler(_ handler: @escaping (Int, String, String?) -> Void) {
        helloHandler = handler
    }

    public func registerAckHandler(_ handler: @escaping (Int) -> Void) {
        ackHandler = handler
    }

    public func registerTapHandler(_ handler: @escaping () -> Void) {
        tapHandler = handler
    }

    // MARK: - Private send internals

    private func resolveIP(forSlot slot: Int) -> String? {
        if let dynamic = dynamicIPs[slot], !dynamic.isEmpty {
            return dynamic
        }
        if let mapped = slotInfos[slot]?.ip, !mapped.isEmpty {
            return mapped
        }
        return nil
    }

    private func nextCueMeta() -> (cueId: String, seq: Int64, sentAtMs: Int64) {
        let seq = nextSequence
        nextSequence += 1
        let cueId = UUID().uuidString
        let sentAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        return (cueId, seq, sentAtMs)
    }

    private func recordPacketSuccess(cueId: String?, interfaceName: String?) {
        totalPacketsSent += 1
        packetTimestamps.append(Date())
        packetTimestamps.removeAll { Date().timeIntervalSince($0) > 1 }

        if let cueId {
            packetsPerCue[cueId, default: 0] += 1
        }
        if let interfaceName {
            var counters = interfaceCounters[interfaceName, default: InterfaceCounters()]
            counters.success += 1
            interfaceCounters[interfaceName] = counters
        }
    }

    private func recordPacketFailure(interfaceName: String?) {
        totalPacketsFailed += 1
        if let interfaceName {
            var counters = interfaceCounters[interfaceName, default: InterfaceCounters()]
            counters.failure += 1
            interfaceCounters[interfaceName] = counters
        }
    }

    private func sendBroadcast(
        _ osc: OSCMessage,
        cueId: String?,
        routeLabel: String
    ) async throws {
        let data = try osc.rawData()
        var atLeastOneSuccess = false
        var lastError: Error?

        await diagnostics?.record(
            .sendQueued,
            message: "Broadcast \(osc.addressPattern.stringValue) -> \(broadcastTargets.count) interfaces",
            route: routeLabel,
            cueId: cueId
        )

        for target in broadcastTargets {
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            let envelope = AddressedEnvelope(remoteAddress: target.address, data: buffer)

            do {
                try await channel.writeAndFlush(envelope)
                atLeastOneSuccess = true
                recordPacketSuccess(cueId: cueId, interfaceName: target.interfaceName)
                await diagnostics?.record(
                    .sendSucceeded,
                    ipAddress: target.ipAddress,
                    message: "Broadcast \(osc.addressPattern.stringValue) delivered",
                    route: routeLabel,
                    cueId: cueId,
                    interfaceName: target.interfaceName
                )
            } catch {
                lastError = error
                recordPacketFailure(interfaceName: target.interfaceName)
                await diagnostics?.record(
                    .sendFailed,
                    ipAddress: target.ipAddress,
                    message: "Broadcast \(osc.addressPattern.stringValue) failed: \(error.localizedDescription)",
                    route: routeLabel,
                    cueId: cueId,
                    interfaceName: target.interfaceName
                )
                // Continue best-effort: one interface failure must not abort others.
                continue
            }
        }

        if !atLeastOneSuccess, let lastError {
            throw lastError
        }
    }

    private func sendUnicast(
        _ osc: OSCMessage,
        toIP ip: String,
        slot: Int?,
        cueId: String?,
        routeLabel: String
    ) async throws {
        let data = try osc.rawData()
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        let target = try SocketAddress(ipAddress: ip, port: port)
        let envelope = AddressedEnvelope(remoteAddress: target, data: buffer)

        await diagnostics?.record(
            .sendQueued,
            slot: slot,
            ipAddress: ip,
            message: "Unicast \(osc.addressPattern.stringValue)",
            route: routeLabel,
            cueId: cueId
        )

        do {
            try await channel.writeAndFlush(envelope)
            recordPacketSuccess(cueId: cueId, interfaceName: nil)
            await diagnostics?.record(
                .sendSucceeded,
                slot: slot,
                ipAddress: ip,
                message: "Unicast \(osc.addressPattern.stringValue) delivered",
                route: routeLabel,
                cueId: cueId
            )
        } catch {
            recordPacketFailure(interfaceName: nil)
            await diagnostics?.record(
                .sendFailed,
                slot: slot,
                ipAddress: ip,
                message: "Unicast \(osc.addressPattern.stringValue) failed: \(error.localizedDescription)",
                route: routeLabel,
                cueId: cueId
            )
            throw error
        }
    }

    // MARK: - Rebinding

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
            await diagnostics?.record(
                .broadcasterInterfaceRefresh,
                message: "Refreshing UDP socket (\(reason))"
            )

            candidate = try await OscBroadcaster.makeChannel(on: port, group: eventLoopGroup)
            guard let newChannel = candidate else { return }
            try await newChannel.pipeline.addHandler(HelloDatagramHandler(owner: self))

            let oldChannel = channel
            channel = newChannel
            let previous = broadcastTargets
            broadcastTargets = OscBroadcaster.gatherBroadcastTargets(port: port)

            do {
                try await oldChannel.close()
            } catch {
                await diagnostics?.record(
                    .broadcasterInterfaceFailed,
                    message: "Failed to close old channel during refresh: \(error.localizedDescription)"
                )
            }

            let oldDescription = describeBroadcastTargets(previous)
            let newDescription = describeBroadcastTargets(broadcastTargets)

            if oldDescription == newDescription {
                await diagnostics?.record(
                    .broadcasterInterfaceUnchanged,
                    message: "Broadcast targets unchanged: \(newDescription)"
                )
            } else {
                await diagnostics?.record(
                    .broadcasterInterfaceRefresh,
                    message: "Broadcast targets updated: \(oldDescription) -> \(newDescription)"
                )
            }

            do {
                try await broadcastConductorHello()
            } catch {
                await diagnostics?.record(
                    .sendFailed,
                    message: "Conductor hello after refresh failed: \(error.localizedDescription)"
                )
            }
        } catch {
            if let candidate {
                Task { try? await candidate.close() }
            }
            await diagnostics?.record(
                .broadcasterInterfaceFailed,
                message: "Refresh failed (\(reason)): \(error.localizedDescription)"
            )
        }
    }

    private func describeBroadcastTargets(_ targets: [BroadcastTarget]) -> String {
        guard !targets.isEmpty else { return "none" }
        return targets.map { "\($0.interfaceName):\($0.ipAddress)" }.joined(separator: ", ")
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

        await diagnostics?.record(
            .broadcasterInterfaceMonitorUpdate,
            message: "network path \(statusDescription) [\(interfaceSummary)]"
        )
        await refreshBindings(reason: "network path \(statusDescription)")
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

    // MARK: - Deinit

    deinit {
#if canImport(Network)
        interfaceMonitor?.cancel()
#endif
        let ch = channel
        let ownsGroup = ownsEventLoopGroup
        let group = eventLoopGroup
        Task {
            try? await ch.close()
            if ownsGroup {
                group.shutdownGracefully { _ in }
            }
        }
    }

    // MARK: - Incoming emitters

    fileprivate func emitHello(_ hello: ClientHello, ip: String) async {
        if let announcedVersion = hello.protocolVersion,
           announcedVersion != Int(protocolVersion)
        {
            await diagnostics?.record(
                .protocolMismatch,
                slot: hello.slot,
                ipAddress: ip,
                message: "Client protocol mismatch: \(announcedVersion)"
            )
            return
        }

        if let session = hello.showSessionId,
           !session.isEmpty,
           session != showSessionId
        {
            await diagnostics?.record(
                .protocolMismatch,
                slot: hello.slot,
                ipAddress: ip,
                message: "Client session mismatch: \(session)"
            )
            return
        }

        dynamicIPs[hello.slot] = ip
        if let deviceId = hello.deviceId, !deviceId.isEmpty {
            dynamicDeviceIds[hello.slot] = deviceId
        }

        await diagnostics?.record(
            .helloReceived,
            slot: hello.slot,
            ipAddress: ip,
            message: hello.deviceId
        )

        helloHandler?(hello.slot, ip, hello.deviceId)
    }

    func emitAck(slot: Int) async {
        await diagnostics?.record(
            .ackReceived,
            slot: slot,
            message: "Ack received"
        )
        ackHandler?(slot)
    }

    func emitTap() async {
        await diagnostics?.record(.tapReceived, message: "/tap received")
        tapHandler?()
    }
}

// MARK: - Datagram parsing

extension OscBroadcaster {
    fileprivate func parseHello(_ bytes: [UInt8]) -> ClientHello? {
        guard let (address, values) = parseAddressAndValues(bytes), address == "/hello" else {
            return nil
        }
        guard let first = values.first as? Int else {
            // Conductor hello from another source or unknown payload.
            return nil
        }

        let deviceId = values.count > 1 ? values[1] as? String : nil
        let protocolVersion: Int?
        if values.count > 2 {
            protocolVersion = values[2] as? Int
        } else {
            protocolVersion = nil
        }
        let showSessionId = values.count > 3 ? values[3] as? String : nil

        return ClientHello(
            slot: first,
            deviceId: deviceId,
            protocolVersion: protocolVersion,
            showSessionId: showSessionId
        )
    }

    fileprivate func parseAck(_ bytes: [UInt8]) -> Int? {
        guard let (address, values) = parseAddressAndValues(bytes), address == "/ack" else {
            return nil
        }
        return values.first as? Int
    }

    fileprivate func parseTap(_ bytes: [UInt8]) -> Bool {
        guard let (address, _) = parseAddressAndValues(bytes) else { return false }
        return address == "/tap"
    }

    private func parseAddressAndValues(_ bytes: [UInt8]) -> (String, [Any])? {
        guard let addrEnd = bytes.firstIndex(of: 0),
              let address = String(bytes: bytes[0..<addrEnd], encoding: .utf8)
        else {
            return nil
        }

        var index = (addrEnd + 4) & ~3
        guard index < bytes.count, bytes[index] == UInt8(ascii: ",") else {
            return (address, [])
        }
        guard let tagEnd = bytes[index...].firstIndex(of: 0),
              let tags = String(bytes: bytes[index..<tagEnd], encoding: .utf8)
        else {
            return nil
        }

        index = (tagEnd + 4) & ~3
        var values: [Any] = []

        func readInt32(at idx: Int) -> Int? {
            guard idx + 3 < bytes.count else { return nil }
            var value: Int32 = 0
            for b in bytes[idx..<(idx + 4)] {
                value = (value << 8) | Int32(b)
            }
            return Int(value)
        }

        func readInt64(at idx: Int) -> Int? {
            guard idx + 7 < bytes.count else { return nil }
            var value: Int64 = 0
            for b in bytes[idx..<(idx + 8)] {
                value = (value << 8) | Int64(b)
            }
            return Int(value)
        }

        func readString(at idx: Int) -> (String, Int)? {
            guard idx < bytes.count,
                  let end = bytes[idx...].firstIndex(of: 0),
                  let string = String(bytes: bytes[idx..<end], encoding: .utf8)
            else { return nil }
            let next = (end + 4) & ~3
            return (string, next)
        }

        var position = index
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard let v = readInt32(at: position) else { return nil }
                values.append(v)
                position += 4
            case "h":
                guard let v = readInt64(at: position) else { return nil }
                values.append(v)
                position += 8
            case "s":
                guard let (s, next) = readString(at: position) else { return nil }
                values.append(s)
                position = next
            default:
                return nil
            }
        }

        return (address, values)
    }
}

final class HelloDatagramHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    unowned let owner: OscBroadcaster

    init(owner: OscBroadcaster) {
        self.owner = owner
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data

        guard let bytes = buffer.readBytes(length: buffer.readableBytes),
              let ip = envelope.remoteAddress.ipAddress
        else {
            return
        }

        Task {
            if let hello = await owner.parseHello(bytes) {
                await owner.emitHello(hello, ip: ip)
                return
            }
            if let slot = await owner.parseAck(bytes) {
                await owner.emitAck(slot: slot)
                return
            }
            if await owner.parseTap(bytes) {
                await owner.emitTap()
                return
            }
            await owner.diagnostics?.record(
                .unknownSender,
                ipAddress: ip,
                message: "Unknown inbound OSC datagram"
            )
        }
    }
}

// MARK: - Broadcast target discovery

extension OscBroadcaster {
    private static func gatherBroadcastTargets(port: Int) -> [BroadcastTarget] {
        var targets: [BroadcastTarget] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            if let fallback = try? SocketAddress(ipAddress: "255.255.255.255", port: port) {
                return [BroadcastTarget(interfaceName: "global", address: fallback, ipAddress: "255.255.255.255")]
            }
            return []
        }
        defer { freeifaddrs(first) }

        var pointer = first
        var seen = Set<String>()

        while true {
            let ifa = pointer.pointee
            let flags = Int32(ifa.ifa_flags)

            let isUp = flags & IFF_UP != 0
            let isLoopback = flags & IFF_LOOPBACK != 0
            let hasBroadcast = flags & IFF_BROADCAST != 0

            if isUp,
               !isLoopback,
               hasBroadcast,
               let addr = ifa.ifa_addr,
               let netmask = ifa.ifa_netmask,
               addr.pointee.sa_family == sa_family_t(AF_INET)
            {
                var ip = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_in.self).pointee
                let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee
                let broadcast = in_addr(s_addr: ip.sin_addr.s_addr | ~mask.sin_addr.s_addr)
                ip.sin_addr = broadcast

                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &ip.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                let ipString = String(cString: buffer)

                if !ipString.isEmpty,
                   let socketAddress = try? SocketAddress(ipAddress: ipString, port: port)
                {
                    let interfaceName = String(cString: ifa.ifa_name)
                    let key = "\(interfaceName)|\(ipString)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        targets.append(
                            BroadcastTarget(
                                interfaceName: interfaceName,
                                address: socketAddress,
                                ipAddress: ipString
                            )
                        )
                    }
                }
            }

            guard let next = pointer.pointee.ifa_next else { break }
            pointer = next
        }

        if targets.isEmpty,
           let fallback = try? SocketAddress(ipAddress: "255.255.255.255", port: port)
        {
            targets.append(BroadcastTarget(interfaceName: "global", address: fallback, ipAddress: "255.255.255.255"))
        }

        return targets
    }
}
