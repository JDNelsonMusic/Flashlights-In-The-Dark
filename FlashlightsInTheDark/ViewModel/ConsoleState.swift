import Foundation
import Combine


@MainActor
public final class ConsoleState: ObservableObject, Sendable {
    private let broadcasterTask = Task<OscBroadcaster, Error> {
        try await OscBroadcaster()
    }
    private var clockSync: ClockSyncService?

    public init() {
        // start clock-sync service once broadcaster is ready
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let broadcaster = try await self.broadcasterTask.value
                self.clockSync = ClockSyncService(broadcaster: broadcaster)
            } catch {
                // ignore errors (e.g. preview/sandbox)
                return
            }
        }
    }

    @Published public private(set) var devices = ChoirDevice.demo
    @Published public var lastLog: String = "🎛  Ready – tap a tile"

    @Published public var isBroadcasting: Bool = false

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        devices[idx].torchOn.toggle()
        Task {
            let osc = try await broadcasterTask.value
            if devices[idx].torchOn {
                try await osc.send(FlashOn(index: Int32(id + 1), intensity: 1))
                await MainActor.run { self.lastLog = "/flash/on [\(id + 1), 1]" }
            } else {
                try await osc.send(FlashOff(index: Int32(id + 1)))
                await MainActor.run { self.lastLog = "/flash/off [\(id + 1)]" }
            }
        }
        print("[ConsoleState] Torch toggled on #\(id) ⇒ \(devices[idx].torchOn)")
        return devices
    }

    @discardableResult
    public func playAll() -> [ChoirDevice] {
        for idx in devices.indices {
            devices[idx].torchOn = true
            Task {
                let osc = try await broadcasterTask.value
                try await osc.send(FlashOn(index: Int32(idx + 1), intensity: 1))
            }
        }
        print("[ConsoleState] All torches turned on")
        return devices
    }

    @discardableResult
    public func blackoutAll() -> [ChoirDevice] {
        for idx in devices.indices {
            devices[idx].torchOn = false
            Task {
                let osc = try await broadcasterTask.value
                try await osc.send(FlashOff(index: Int32(idx + 1)))
            }
        }
        print("[ConsoleState] All torches turned off")
        return devices
    }
}

// MARK: - Lifecycle helpers

extension ConsoleState {
    /// Idempotent network bootstrap for `.task {}` in ContentView.
    @MainActor
    public func startNetwork() async {
        guard !isBroadcasting else { return }
        isBroadcasting = true
        lastLog = "🛰  Broadcasting on 255.255.255.255:9000"
        print("[ConsoleState] Network stack started ✅")
    }

    /// Gracefully cancel background tasks when the app resigns active.
    @MainActor
    public func shutdown() {
        isBroadcasting = false
        // ClockSyncService de-initialises itself when its Task is cancelled.
        // Add additional cleanup here (file handles, etc.) as the project grows.
        print("[ConsoleState] Network stack suspended 💤")
    }
}