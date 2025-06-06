import Foundation
import Combine
import SwiftUI
//import Network   // auto-discovery removed

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
        // Initialize with all 32 slots (demo placeholders)
        self.devices = ChoirDevice.demo
        self.statuses = Dictionary(uniqueKeysWithValues:
            devices.map { ($0.id, DeviceStatus.clean) }
        )
    }

    @Published public private(set) var devices: [ChoirDevice] = []
    @Published public var statuses: [Int: DeviceStatus] = [:]
    @Published public var lastLog: String = "🎛  Ready – tap a tile"

    @Published public var isBroadcasting: Bool = false
    /// Active audio tone sets ("A","B","C","D").
    @Published public var activeToneSets: Set<String> = []
    // Envelope parameters (ms, %)
    @Published public var attackMs: Int = 200
    @Published public var decayMs: Int = 200
    @Published public var sustainPct: Int = 50
    @Published public var releaseMs: Int = 200
    /// How typing keyboard triggers devices: torch only, sound only, or both
    public enum KeyboardTriggerMode: String, CaseIterable {
        case torch = "Torch"
        case sound = "Sound"
        case both  = "Torch+Sound"
    }
    /// Current typing keyboard trigger mode
    @Published public var keyboardTriggerMode: KeyboardTriggerMode = .torch
    // Envelope task to allow cancellation
    private var envelopeTask: Task<Void, Never>?
    

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        objectWillChange.send()
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
    
    /// Directly flash on a specific lamp slot (no toggle) and update state.
    public func flashOn(id: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        devices[idx].torchOn = true
        Task {
            let osc = try await broadcasterTask.value
            try await osc.send(FlashOn(index: Int32(id + 1), intensity: 1))
            await MainActor.run { lastLog = "/flash/on [\(id + 1), 1]" }
        }
    }
    /// Directly flash off a specific lamp slot and update state.
    public func flashOff(id: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        devices[idx].torchOn = false
        Task {
            let osc = try await broadcasterTask.value
            try await osc.send(FlashOff(index: Int32(id + 1)))
            await MainActor.run { lastLog = "/flash/off [\(id + 1)]" }
        }
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
            let gain: Float32 = 1.0
            // Determine tone sets to send: default to ["A"] if none selected
            let sets = activeToneSets.isEmpty ? ["A"] : activeToneSets.sorted()
            for set in sets {
                let prefix = set.lowercased()
                let file = "\(prefix)\(slot).mp3"
                try await oscBroadcaster.send(AudioPlay(index: slot, file: file, gain: gain))
                await MainActor.run { self.lastLog = "/audio/play [\(slot), \(file), \(gain)]" }
            }
        }
    }
    /// Play audio on all devices slots based on current activeToneSets
    public func playAllTones() {
        for device in devices {
            triggerSound(device: device)
        }
    }
    /// Refresh device information from the slot mapping JSON resource
    public func refreshDevices() {
        Task { @MainActor in
            guard let url = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json") else { return }
            do {
                let data = try Data(contentsOf: url)
                let dict = try JSONDecoder().decode([String: ConsoleSlotInfo].self, from: data)
                // Update devices by slot index (1-based keys)
                for (key, info) in dict {
                    if let slot = Int(key), slot > 0, slot <= devices.count {
                        let idx = slot - 1
                        devices[idx].ip = info.ip
                        devices[idx].udid = info.udid
                        devices[idx].name = info.name
                    }
                }
                lastLog = "🔄 Refreshed device list"
                // Re-broadcast hello so clients can reconnect
                if let osc = try? await broadcasterTask.value {
                    try? await osc.start()
                }
            } catch {
                lastLog = "⚠️ Refresh failed: \(error)"
            }
        }
    }
    /// Stop playback of sound on a specific device slot (send audio/stop)
    public func stopSound(device: ChoirDevice) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        Task {
            let osc = try await broadcasterTask.value
            let slot = Int32(device.id + 1)
            try await osc.send(AudioStop(index: slot))
            await MainActor.run { self.lastLog = "/audio/stop [\(slot)]" }
        }
    }
    
    /// Start a global ADSR envelope across all lamps
    public func startEnvelopeAll() {
        envelopeTask?.cancel()
        envelopeTask = Task {
            do {
                let osc = try await broadcasterTask.value
                let steps = 10
                // Attack phase
                for i in 0...steps {
                    let intensity = Float32(i) / Float32(steps)
                    for d in devices {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(attackMs) * 1_000_000 / UInt64(steps))
                }
                // Decay to sustain
                let sustainLevel = Float32(sustainPct) / 100
                for i in 0...steps {
                    let t = Float32(i) / Float32(steps)
                    let intensity = (1 - t) + t * sustainLevel
                    for d in devices {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(decayMs) * 1_000_000 / UInt64(steps))
                }
                // Hold sustain until release called
            } catch {
                print("⚠️ startEnvelopeAll error: \(error)")
            }
        }
    }
    
    /// Release the envelope: fade out and send flash-off
    public func releaseEnvelopeAll() {
        envelopeTask?.cancel()
        envelopeTask = Task {
            do {
                let osc = try await broadcasterTask.value
                let steps = 10
                let sustainLevel = Float32(sustainPct) / 100
                for i in 0...steps {
                    let intensity = sustainLevel * (1 - Float32(i) / Float32(steps))
                    for d in devices {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(releaseMs) * 1_000_000 / UInt64(steps))
                }
                for d in devices {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
                await MainActor.run { lastLog = "/envelope release" }
            } catch {
                print("⚠️ releaseEnvelopeAll error: \(error)")
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
    
    // MARK: – Dynamic device management  📱
    /// Add a new device at runtime. Assigns next available zero-based id and initializes status.
    public func addDevice(name: String, ip: String, udid: String) {
        let newId = devices.count
        let device = ChoirDevice(id: newId,
                                 udid: udid,
                                 name: name,
                                 ip: ip,
                                 listeningSlot: newId + 1)
        devices.append(device)
        statuses[newId] = .clean
    }
    
    /// Remove a device by its id, reindexes remaining devices.
    public func removeDevice(id: Int) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices.remove(at: index)
        statuses.removeValue(forKey: id)
        // Reassign ids and statuses for subsequent devices
        for idx in index..<devices.count {
            devices[idx].listeningSlot = idx + 1
            let oldId = devices[idx].id
            devices[idx].id = idx
            if let status = statuses[oldId] {
                statuses[idx] = status
                statuses.removeValue(forKey: oldId)
            }
        }
    }
    
    /// Assign a new listening slot to a specific device at runtime.
    /// Updates the local model and sends a unicast OSC message to notify the client.
    public func assignSlot(device: ChoirDevice, slot: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[idx].listeningSlot = slot
        Task {
            let osc = try await broadcasterTask.value
            let msg = SetSlot(slot: Int32(slot))
            do {
                try await osc.sendUnicast(msg.encode(), toIP: device.ip)
                await MainActor.run { self.lastLog = "/set-slot [\(device.ip), \(slot)]" }
            } catch {
                await MainActor.run { self.lastLog = "⚠️ Failed to send set-slot to device at \(device.ip)" }
            }
        }
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
        do {
            let broadcaster = try await broadcasterTask.value
            try await broadcaster.start()
            print("[ConsoleState] Network stack started ✅")
        } catch {
            lastLog = "⚠️ Network start failed: \(error)"
            print("⚠️ startNetwork error: \(error)")
        }
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