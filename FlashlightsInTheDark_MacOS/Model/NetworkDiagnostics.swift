import Foundation

/// Categorises key networking events for post-rehearsal diagnostics.
public enum NetworkEventKind: String, Codable, Sendable {
    case broadcasterStarted
    case broadcasterAnnounced
    case broadcasterDiscover
    case broadcasterInterfaceRefresh
    case broadcasterInterfaceUnchanged
    case broadcasterInterfaceFailed
    case broadcasterInterfaceMonitorUpdate
    case sendQueued
    case sendSucceeded
    case sendFailed
    case helloReceived
    case ackReceived
    case tapReceived
    case heartbeatLost
    case heartbeatRecovered
    case manualRefresh
    case manualExport
    case slotAssignmentAdjusted
    case slotAssignmentRequested
    case unknownSender
    case protocolMismatch
    case cueDroppedDuplicate
    case cueDroppedOutOfOrder
    case cueRouteSelected
}

/// A single network event captured during a rehearsal session.
public struct NetworkLogEvent: Codable, Sendable {
    public let timestamp: Date
    public let kind: NetworkEventKind
    public let slot: Int?
    public let ipAddress: String?
    public let message: String?
    public let route: String?
    public let cueId: String?
    public let interfaceName: String?

    public init(
        timestamp: Date = Date(),
        kind: NetworkEventKind,
        slot: Int? = nil,
        ipAddress: String? = nil,
        message: String? = nil,
        route: String? = nil,
        cueId: String? = nil,
        interfaceName: String? = nil
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.slot = slot
        self.ipAddress = ipAddress
        self.message = message
        self.route = route
        self.cueId = cueId
        self.interfaceName = interfaceName
    }
}

/// Aggregated snapshot of all recorded diagnostics.
public struct NetworkDiagnosticsSnapshot: Codable, Sendable {
    public struct SlotSummary: Codable, Sendable {
        public let slot: Int
        public let helloCount: Int
        public let ackCount: Int
        public let sendFailureCount: Int
        public let lastHello: Date?
        public let lastAck: Date?
    }

    public struct InterfaceSummary: Codable, Sendable {
        public let name: String
        public let sendSuccessCount: Int
        public let sendFailureCount: Int
    }

    public let generatedAt: Date
    public let events: [NetworkLogEvent]
    public let slotSummaries: [SlotSummary]
    public let interfaceSummaries: [InterfaceSummary]
    public let totalEvents: Int
    public let uniqueSlots: [Int]
    public let totalSendQueued: Int
    public let totalSendSucceeded: Int
    public let totalSendFailed: Int
    public let unknownSenderCount: Int
    public let cueDroppedDuplicateCount: Int
    public let cueDroppedOutOfOrderCount: Int
    public let protocolMismatchCount: Int
    public let packetsPerSecond: Double
}

/// Actor that captures networking diagnostics and can export the session.
public actor NetworkDiagnostics {
    private let maxEvents: Int
    private var events: [NetworkLogEvent] = []
    private var helloCount: [Int: Int] = [:]
    private var ackCount: [Int: Int] = [:]
    private var sendFailureCount: [Int: Int] = [:]
    private var lastHello: [Int: Date] = [:]
    private var lastAck: [Int: Date] = [:]
    private var interfaceSendSuccess: [String: Int] = [:]
    private var interfaceSendFailure: [String: Int] = [:]

    public init(maxEvents: Int = 4000) {
        self.maxEvents = maxEvents
    }

    public func record(
        _ kind: NetworkEventKind,
        slot: Int? = nil,
        ipAddress: String? = nil,
        message: String? = nil,
        route: String? = nil,
        cueId: String? = nil,
        interfaceName: String? = nil
    ) {
        let event = NetworkLogEvent(
            timestamp: Date(),
            kind: kind,
            slot: slot,
            ipAddress: ipAddress,
            message: message,
            route: route,
            cueId: cueId,
            interfaceName: interfaceName
        )

        if events.count >= maxEvents {
            events.removeFirst(events.count - maxEvents + 1)
        }
        events.append(event)

        if let slot {
            switch kind {
            case .helloReceived:
                helloCount[slot, default: 0] += 1
                lastHello[slot] = event.timestamp
            case .ackReceived:
                ackCount[slot, default: 0] += 1
                lastAck[slot] = event.timestamp
            case .sendFailed:
                sendFailureCount[slot, default: 0] += 1
            default:
                break
            }
        }

        if let interfaceName {
            switch kind {
            case .sendSucceeded:
                interfaceSendSuccess[interfaceName, default: 0] += 1
            case .sendFailed:
                interfaceSendFailure[interfaceName, default: 0] += 1
            default:
                break
            }
        }
    }

    public func snapshot() -> NetworkDiagnosticsSnapshot {
        let slots = Set(helloCount.keys)
            .union(ackCount.keys)
            .union(sendFailureCount.keys)
            .sorted()

        let summaries = slots.map { slot -> NetworkDiagnosticsSnapshot.SlotSummary in
            NetworkDiagnosticsSnapshot.SlotSummary(
                slot: slot,
                helloCount: helloCount[slot, default: 0],
                ackCount: ackCount[slot, default: 0],
                sendFailureCount: sendFailureCount[slot, default: 0],
                lastHello: lastHello[slot],
                lastAck: lastAck[slot]
            )
        }

        let interfaceNames = Set(interfaceSendSuccess.keys).union(interfaceSendFailure.keys).sorted()
        let interfaces = interfaceNames.map { name in
            NetworkDiagnosticsSnapshot.InterfaceSummary(
                name: name,
                sendSuccessCount: interfaceSendSuccess[name, default: 0],
                sendFailureCount: interfaceSendFailure[name, default: 0]
            )
        }

        let totalQueued = events.reduce(into: 0) { count, event in
            if event.kind == .sendQueued { count += 1 }
        }
        let totalSucceeded = events.reduce(into: 0) { count, event in
            if event.kind == .sendSucceeded { count += 1 }
        }
        let totalFailed = events.reduce(into: 0) { count, event in
            if event.kind == .sendFailed { count += 1 }
        }
        let unknownSenderCount = events.reduce(into: 0) { count, event in
            if event.kind == .unknownSender { count += 1 }
        }
        let duplicateDrops = events.reduce(into: 0) { count, event in
            if event.kind == .cueDroppedDuplicate { count += 1 }
        }
        let outOfOrderDrops = events.reduce(into: 0) { count, event in
            if event.kind == .cueDroppedOutOfOrder { count += 1 }
        }
        let protocolMismatches = events.reduce(into: 0) { count, event in
            if event.kind == .protocolMismatch { count += 1 }
        }

        let now = Date()
        let packetsThisSecond = events.reduce(into: 0) { count, event in
            if (event.kind == .sendSucceeded || event.kind == .sendFailed),
               now.timeIntervalSince(event.timestamp) <= 1 {
                count += 1
            }
        }

        return NetworkDiagnosticsSnapshot(
            generatedAt: now,
            events: events,
            slotSummaries: summaries,
            interfaceSummaries: interfaces,
            totalEvents: events.count,
            uniqueSlots: summaries.map(\.slot),
            totalSendQueued: totalQueued,
            totalSendSucceeded: totalSucceeded,
            totalSendFailed: totalFailed,
            unknownSenderCount: unknownSenderCount,
            cueDroppedDuplicateCount: duplicateDrops,
            cueDroppedOutOfOrderCount: outOfOrderDrops,
            protocolMismatchCount: protocolMismatches,
            packetsPerSecond: Double(packetsThisSecond)
        )
    }

    public func export(to directory: URL? = nil) throws -> URL {
        let snapshot = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        let rootDir: URL
        if let directory {
            rootDir = directory
        } else {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "NetworkDiagnostics", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate Documents directory"])
            }
            rootDir = docs.appendingPathComponent("FlashlightsLogs", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = "network-log-\(formatter.string(from: snapshot.generatedAt)).json"
        let destination = rootDir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
