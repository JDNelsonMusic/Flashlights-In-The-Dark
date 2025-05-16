import Foundation
import Combine

@MainActor
public final class ConsoleState: ObservableObject, Sendable {
    @Published public private(set) var devices = ChoirDevice.demo

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        devices[idx].torchOn.toggle()
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