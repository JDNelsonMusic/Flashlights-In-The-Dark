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
}

/// A single network event captured during a rehearsal session.
public struct NetworkLogEvent: Codable, Sendable {
    public let timestamp: Date
    public let kind: NetworkEventKind
    public let slot: Int?
    public let ipAddress: String?
    public let message: String?

    public init(
        timestamp: Date = Date(),
        kind: NetworkEventKind,
        slot: Int? = nil,
        ipAddress: String? = nil,
        message: String? = nil
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.slot = slot
        self.ipAddress = ipAddress
        self.message = message
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

    public let generatedAt: Date
    public let events: [NetworkLogEvent]
    public let slotSummaries: [SlotSummary]
    public let totalEvents: Int
    public let uniqueSlots: [Int]
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

    public init(maxEvents: Int = 4000) {
        self.maxEvents = maxEvents
    }

    public func record(
        _ kind: NetworkEventKind,
        slot: Int? = nil,
        ipAddress: String? = nil,
        message: String? = nil
    ) {
        let event = NetworkLogEvent(
            timestamp: Date(),
            kind: kind,
            slot: slot,
            ipAddress: ipAddress,
            message: message
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

        return NetworkDiagnosticsSnapshot(
            generatedAt: Date(),
            events: events,
            slotSummaries: summaries,
            totalEvents: events.count,
            uniqueSlots: summaries.map(\.slot)
        )
    }

    public func export(to directory: URL? = nil) throws -> URL {
        let snapshot = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = snapshot
        let data = try encoder.encode(payload)

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
