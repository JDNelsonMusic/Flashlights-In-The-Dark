import OSCKit

public extension OscBroadcaster {
    @inline(__always)
    func send<T: OscCodable>(
        _ model: T,
        allowWhenDisarmed: Bool = false
    ) async throws {
        switch model {
        case let m as FlashOn:
            try await sendCue(
                address: .flashOn,
                slot: m.index,
                payload: [m.intensity],
                allowWhenDisarmed: allowWhenDisarmed
            )

        case let m as FlashOff:
            try await sendCue(
                address: .flashOff,
                slot: m.index,
                payload: [],
                allowWhenDisarmed: allowWhenDisarmed
            )

        case let m as AudioPlay:
            var payload: [any OSCValue] = [m.file, m.gain]
            if let startAtMs = m.startAtMs {
                payload.append(Float64(startAtMs))
            }
            try await sendCue(
                address: .audioPlay,
                slot: m.index,
                payload: payload,
                allowWhenDisarmed: allowWhenDisarmed
            )

        case let m as AudioStop:
            try await sendCue(
                address: .audioStop,
                slot: m.index,
                payload: [],
                allowWhenDisarmed: allowWhenDisarmed
            )

        case let m as EventTrigger:
            var payload: [any OSCValue] = [m.eventId]
            if let startAtMs = m.startAtMs {
                payload.append(Float64(startAtMs))
            }
            if let componentMode = m.componentMode {
                payload.append(componentMode.rawValue)
            }
            try await sendCue(
                address: .eventTrigger,
                slot: m.index,
                payload: payload,
                allowWhenDisarmed: allowWhenDisarmed
            )

        case let m as MicRecord:
            try await sendCue(
                address: .micRecord,
                slot: m.index,
                payload: [m.maxDuration],
                allowWhenDisarmed: allowWhenDisarmed
            )

        case _ as PanicAllStop:
            try await broadcastPanicAllStop()

        case _ as Tap:
            try await send(model.encode())

        default:
            try await send(model.encode())
        }
    }
}
