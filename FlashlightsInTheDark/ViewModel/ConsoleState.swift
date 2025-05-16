import Foundation
import Combine


@MainActor
public final class ConsoleState: ObservableObject, Sendable {
    private let broadcasterTask = Task<OscBroadcaster, Error> {
        try await OscBroadcaster()
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