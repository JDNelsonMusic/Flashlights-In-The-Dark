import Foundation
import Combine
import SwiftUI

/// Possible device statuses for build/run lifecycle
public enum DeviceStatus: String, Sendable {
    case clean = "Clean"
    case buildReady = "Build Ready"
    case buildFailed = "Build Failed"
    case runFailed = "Run Failed"
    case live = "Live"
    case lostConnection = "Lost Connection"
}
extension DeviceStatus {
    var color: Color {
        switch self {
        case .clean: return .secondary
        case .buildReady: return .blue
        case .buildFailed, .runFailed: return .red
        case .live: return .mint
        case .lostConnection: return .orange
        }
    }
}

// Shared slot mapping data model for console
private struct ConsoleSlotInfo: Codable {
    let ip: String
    let udid: String
    let name: String
}


@MainActor
public final class ConsoleState: ObservableObject, Sendable {
    private let broadcasterTask = Task<OscBroadcaster, Error> {
        try await OscBroadcaster()
    }
    private var clockSync: ClockSyncService?
    // Track ongoing run processes to monitor connection/state
    private var runProcesses: [Int: Process] = [:]

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
        // Load device UDIDs, names, and initialize statuses
        if let url = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict: [String: ConsoleSlotInfo] = try? JSONDecoder().decode([String: ConsoleSlotInfo].self, from: data)
        {
            let mapped: [ChoirDevice] = dict.compactMap { (key, info) -> ChoirDevice? in
                guard let slot = Int(key) else { return nil }
                // slot is 1-based, convert to zero-based id
                return ChoirDevice(id: slot - 1, udid: info.udid, name: info.name)
            }
            // Sort by id
            self.devices = mapped.sorted(by: { $0.id < $1.id })
            // Initialize statuses to .clean
            self.statuses = Dictionary(uniqueKeysWithValues:
                self.devices.map { ($0.id, DeviceStatus.clean) }
            )
        }
    }

    @Published public private(set) var devices = ChoirDevice.demo
    @Published public var statuses: [Int: DeviceStatus] = [:]
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
    
    // MARK: – One-click build & run  🚀
    public func buildAndRun(device: ChoirDevice) {
        Task.detached {
            let slot  = device.id + 1          // 1-based in Flutter world
            let udid  = device.udid

            /// Construct: flutter run -d <UDID> --release --dart-define=SLOT=<N>
            let args  = ["run",
                         "-d", udid,
                         "--release",
                         "--dart-define=SLOT=\(slot)"]

            let proc = Process()
            proc.launchPath = "/usr/bin/env"
            proc.arguments  = ["flutter"] + args
            // run from flutter project directory
            proc.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = pipe
            try? proc.run()

            // Stream first few lines to console for feedback
            let handle = pipe.fileHandleForReading
            if let data = try? handle.readToEnd(),
               let out  = String(data: data, encoding: .utf8) {
                print("[Build&Run] \(out.prefix(300))…")      // truncate
            }
        }
    }
    
    /// Trigger playback of a preloaded audio file on a specific device
    public func triggerSound(device: ChoirDevice) {
        Task {
            let oscBroadcaster = try await broadcasterTask.value
            let slot = Int32(device.id + 1)
            let file = "sfx.ghost.mp3"
            let gain: Float32 = 1.0
            try await oscBroadcaster.send(AudioPlay(index: slot, file: file, gain: gain))
            await MainActor.run {
                self.lastLog = "/audio/play [\(device.id + 1), \(file), \(gain)]"
            }
        }
    }
    
    // MARK: – Build only  🔨
    /// Build the app for a single device slot.
    public func build(device: ChoirDevice) {
        statuses[device.id] = .clean
        Task.detached {
            let slot = device.id + 1
            let args = ["build", "ios", "--release", "--dart-define=SLOT=\(slot)"]
            let proc = Process()
            proc.launchPath = "/usr/bin/env"
            proc.arguments = ["flutter"] + args
            proc.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            do {
                try proc.run()
                proc.waitUntilExit()
                let success = proc.terminationStatus == 0
                await MainActor.run { self.statuses[device.id] = success ? .buildReady : .buildFailed }
            } catch {
                await MainActor.run { self.statuses[device.id] = .buildFailed }
            }
        }
    }

    /// Build all devices in parallel.
    public func buildAll() {
        for device in devices {
            build(device: device)
        }
    }

    // MARK: – Run only  ▶️
    /// Run the app on a single device slot (must be built).
    public func run(device: ChoirDevice) {
        guard statuses[device.id] == .buildReady else { return }
        // terminate any existing run process
        if let prev = runProcesses[device.id] {
            prev.terminate()
            runProcesses[device.id] = nil
        }
        let slot = device.id + 1
        let args = ["run", "-d", device.udid, "--release", "--dart-define=SLOT=\(slot)"]
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["flutter"] + args
        proc.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { p in
            Task { @MainActor in
                if p.terminationStatus == 0 {
                    // process exited (app disconnected)
                    self.statuses[device.id] = .lostConnection
                    self.run(device: device)
                } else {
                    self.statuses[device.id] = .runFailed
                }
            }
        }
        do {
            try proc.run()
            runProcesses[device.id] = proc
            statuses[device.id] = .live
        } catch {
            statuses[device.id] = .runFailed
        }
    }

    /// Run all devices that are build-ready.
    public func runAll() {
        for device in devices where statuses[device.id] == .buildReady {
            run(device: device)
        }
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