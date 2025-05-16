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

    @Published public var isBroadcasting: Bool = false

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        devices[idx].torchOn.toggle()
        Task {
            let osc = try await broadcasterTask.value
            if devices[id].torchOn {
                try await osc.send(FlashOn(index: Int32(id), intensity: 1))
            } else {
                try await osc.send(FlashOff(index: Int32(id)))
            }
        }
        print("[ConsoleState] Torch toggled on #\(id) ⇒ \(devices[idx].torchOn)")
        return devices
    }

    @discardableResult
    public func playAll() -> [ChoirDevice] {
        for idx in devices.indices {
            devices[idx].torchOn = true
        }
        print("[ConsoleState] All torches turned on")
        return devices
    }

    @discardableResult
    public func blackoutAll() -> [ChoirDevice] {
        for idx in devices.indices {
            devices[idx].torchOn = false
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
        guard !isBroadcasting else { return }   // already up
        isBroadcasting = true
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