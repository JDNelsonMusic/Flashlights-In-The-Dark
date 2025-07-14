import Foundation
import Combine
import SwiftUI
import NIOPosix
//import Network   // auto-discovery removed
import Darwin           // for POSIXError & EHOSTDOWN

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
    private let midi = MIDIManager()
    /// Base offset so MIDI note 1 corresponds to device 1
    private let midiNoteOffset = 0
    private let allInputsLabel = "All MIDI Inputs"

    // MIDI device lists and selections
    @Published public var midiInputNames: [String] = []
    @Published public var midiOutputNames: [String] = []
    @Published public var selectedMidiInput: String = "" {
        didSet {
            if selectedMidiInput == allInputsLabel {
                midi.connectAllInputs()
            } else {
                midi.connectInput(named: selectedMidiInput)
            }
        }
    }
    @Published public var selectedMidiOutput: String = "" {
        didSet { midi.connectOutput(named: selectedMidiOutput) }
    }
    @Published public var outputChannel: Int = 1 {
        didSet { midi.setChannel(outputChannel) }
    }
    /// Recent MIDI messages for debugging
    @Published public var midiLog: [String] = []

    // Slots currently glowing for UI feedback
    @Published public var glowingSlots: Set<Int> = []
    /// Slots currently triggered via typing keyboard
    @Published public var triggeredSlots: Set<Int> = []

    /// Members for dynamic groups 1-9
    @Published public var groupMembers: [Int: [Int]] = [:]

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
        // Initialize with all 54 slots (real + placeholder)
        self.devices = ChoirDevice.demo
        self.statuses = Dictionary(uniqueKeysWithValues:
            devices.map { ($0.id, DeviceStatus.clean) }
        )
        // MIDI callbacks for incoming messages
        midi.noteOnHandler = { [weak self] note, vel, chan in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleNoteOn(note: note, velocity: vel, channel: chan)
            }
        }
        midi.noteOffHandler = { [weak self] note, chan in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleNoteOff(note: note, channel: chan)
            }
        }
        midi.controlChangeHandler = { [weak self] cc, value, chan in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleControlChange(cc: cc, value: value, channel: chan)
            }
        }

        midi.setChannel(outputChannel)

        refreshMidiDevices()
    }

    @Published public private(set) var devices: [ChoirDevice] = []
    @Published public var statuses: [Int: DeviceStatus] = [:]
    @Published public var lastLog: String = "🎛  Ready – tap a tile"

    @Published public var isBroadcasting: Bool = false
    /// True whenever any connected device currently has its torch on.
    @Published public var isAnyTorchOn: Bool = false
    /// Whether the strobe effect is active.
    @Published public var strobeActive: Bool = false {
        didSet {
            if strobeActive {
                slowStrobeActive = false
                startStrobe()
            } else {
                stopStrobe()
            }
        }
    }
    /// Whether the slow strobe effect is active.
    @Published public var slowStrobeActive: Bool = false {
        didSet {
            if slowStrobeActive {
                strobeActive = false
                glowRampActive = false
                startSlowStrobe()
            } else {
                stopSlowStrobe()
            }
        }
    }
    /// Whether the glow ramp effect is active.
    @Published public var glowRampActive: Bool = false {
        didSet {
            if glowRampActive {
                strobeActive = false
                slowStrobeActive = false
                startGlowRamp()
            } else {
                stopGlowRamp()
            }
        }
    }
    /// Whether the slow glow ramp effect is active.
    @Published public var slowGlowRampActive: Bool = false {
        didSet {
            if slowGlowRampActive {
                strobeActive = false
                slowStrobeActive = false
                glowRampActive = false
                startSlowGlowRamp()
            } else {
                stopSlowGlowRamp()
            }
        }
    }
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
    // Strobe oscillation task
    private var strobeTask: Task<Void, Never>?
    // Slow strobe oscillation task
    private var slowStrobeTask: Task<Void, Never>?
    // Glow ramp oscillation task
    private var glowRampTask: Task<Void, Never>?
    // Slow glow ramp oscillation task
    private var slowGlowRampTask: Task<Void, Never>?

    /// Recalculate `isAnyTorchOn` based on current device states.
    private func updateAnyTorchOn() {
        isAnyTorchOn = devices.contains { $0.torchOn }
    }

    /// Make a slot glow in the UI for a short duration
    public func glow(slot: Int, duration: Double = 0.3) {
        Task { @MainActor in
            glowingSlots.insert(slot)
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            glowingSlots.remove(slot)
        }
    }

    /// Track pressed typing slots for UI feedback
    public func addTriggeredSlot(_ slot: Int) {
        triggeredSlots.insert(slot)
    }

    public func removeTriggeredSlot(_ slot: Int) {
        triggeredSlots.remove(slot)
    }

    /// Append a MIDI message string to the log, trimming to last 20 entries.
    public func logMidi(_ message: String) {
        midiLog.append(message)
        if midiLog.count > 20 {
            midiLog.removeFirst(midiLog.count - 20)
        }
    }
    

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        guard !devices[idx].isPlaceholder else { return devices }
        objectWillChange.send()
        devices[idx].torchOn.toggle()
        let isOn = devices[idx].torchOn
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                if isOn {
                    try await osc.send(FlashOn(index: Int32(id + 1), intensity: 1))
                    await MainActor.run { self.lastLog = "/flash/on [\(id + 1), 1]" }
                    await self.midi.sendControlChange(UInt8(id + 1), value: 127)
                    await MainActor.run { self.glow(slot: id + 1) }
                } else {
                    try await osc.send(FlashOff(index: Int32(id + 1)))
                    await MainActor.run { self.lastLog = "/flash/off [\(id + 1)]" }
                    await self.midi.sendControlChange(UInt8(id + 1), value: 0)
                }
            } catch {
                print("Error toggling torch for slot \(id + 1): \(error)")
            }
        }
        print("[ConsoleState] Torch toggled on #\(id) ⇒ \(devices[idx].torchOn)")
        updateAnyTorchOn()
        return devices
    }
    
    /// Directly flash on a specific lamp slot (no toggle) and update state.
    public func flashOn(id: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        objectWillChange.send()
        devices[idx].torchOn = true
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                try await osc.send(FlashOn(index: Int32(id + 1), intensity: 1))
                await MainActor.run { self.lastLog = "/flash/on [\(id + 1), 1]" }
                await self.midi.sendControlChange(UInt8(id + 1), value: 127)
                await MainActor.run { self.glow(slot: id + 1) }
            } catch {
                print("Error sending FlashOn for slot \(id + 1): \(error)")
            }
        }
        updateAnyTorchOn()
    }
    /// Directly flash off a specific lamp slot and update state.
    public func flashOff(id: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        objectWillChange.send()
        devices[idx].torchOn = false
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                try await osc.send(FlashOff(index: Int32(id + 1)))
                await MainActor.run { self.lastLog = "/flash/off [\(id + 1)]" }
                await self.midi.sendControlChange(UInt8(id + 1), value: 0)
            } catch {
                print("Error sending FlashOff for slot \(id + 1): \(error)")
            }
        }
        updateAnyTorchOn()
    }

    /// Trigger a list of real slots according to the current keyboardTriggerMode.
    public func triggerSlots(realSlots: [Int]) {
        for real in realSlots {
            let idx = real - 1
            switch keyboardTriggerMode {
            case .torch:
                _ = toggleTorch(id: idx)
            case .sound:
                guard idx < devices.count else { continue }
                let device = devices[idx]
                triggerSound(device: device)
            case .both:
                _ = toggleTorch(id: idx)
                guard idx < devices.count else { continue }
                let device = devices[idx]
                triggerSound(device: device)
            }
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
        guard !device.isPlaceholder else { return }

        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                // --- Cross-actor property: broadcasterTask ---
                let oscBroadcaster = try await self.broadcasterTask.value

                let slot = Int32(device.id + 1)
                let gain: Float32 = 1.0

                // --- Collect main-actor data once, then use it ---
                let toneSets: [String] = await MainActor.run {
                    let raw = self.activeToneSets
                    return raw.isEmpty ? ["A"] : raw.sorted()
                }

                for set in toneSets {
                    let prefix = set.lowercased()
                    let file = "\(prefix)\(slot).mp3"

                    try await oscBroadcaster.send(AudioPlay(index: slot,
                                                            file: file,
                                                            gain: gain))

                    await MainActor.run {
                        self.lastLog = "/audio/play \(slot) \(file)"
                    }

                    // --- Cross-actor property: midi ---
                    let noteBase = device.id * 4
                    let noteOffset: Int = switch set.lowercased() {
                        case "a": 0
                        case "b": 1
                        case "c": 2
                        default:  3
                    }
                    await self.midi.sendNoteOn(UInt8(noteBase + noteOffset), velocity: 127)
                }

                // --- Cross-actor call: glow ---
                await self.glow(slot: device.id + 1)
            } catch {
                print("Error triggering sound for slot \(device.id + 1): \(error)")
            }
        }
    }
    /// Play audio on all devices slots based on current activeToneSets
    public func playAllTones() {
        for device in devices where !device.isPlaceholder {
            triggerSound(device: device)
        }
    }

    /// Refresh available MIDI devices and reconnect selections
    public func refreshMidiDevices() {
        midiInputNames = [allInputsLabel] + midi.inputNames
        midiOutputNames = midi.outputNames
        if let scarlett = midiInputNames.first(where: { $0.contains("Scarlett 18i20 USB") }) {
            selectedMidiInput = scarlett
        } else if selectedMidiInput.isEmpty, let first = midiInputNames.first {
            selectedMidiInput = first
        } else if !midiInputNames.contains(selectedMidiInput) {
            selectedMidiInput = midiInputNames.first ?? ""
        }
        if selectedMidiOutput.isEmpty, let firstOut = midiOutputNames.first {
            selectedMidiOutput = firstOut
        } else if !midiOutputNames.contains(selectedMidiOutput) {
            selectedMidiOutput = midiOutputNames.first ?? ""
        }
    }
    /// Refresh device information from the slot mapping JSON resource
    public func refreshDevices() {
        Task { @MainActor in
            guard let url = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json") else { return }
            do {
                let data = try Data(contentsOf: url)
                do {
                    // Preferred format is keyed by slot numbers
                    let dict = try JSONDecoder().decode([String: ConsoleSlotInfo].self, from: data)
                    updateDevices(from: dict)
                } catch {
                    // Fallback: attempt to parse and log helpful error
                    print("[ConsoleState] mapping decode failed: \(error). Attempting fallback…")
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var parsed: [String: ConsoleSlotInfo] = [:]
                        for (key, value) in json {
                            if let slot = Int(key),
                               let info = value as? [String: Any],
                               let ip = info["ip"] as? String,
                               let udid = info["udid"] as? String,
                               let name = info["name"] as? String {
                                parsed[String(slot)] = ConsoleSlotInfo(ip: ip, udid: udid, name: name)
                            }
                        }
                        if !parsed.isEmpty {
                            updateDevices(from: parsed)
                        } else {
                            print("[ConsoleState] mapping JSON not in expected format. Keys should be slot numbers (\"1\", \"2\" …) with ip, udid and name fields")
                            lastLog = "⚠️ Refresh failed: invalid mapping format"
                            return
                        }
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

    private func updateDevices(from dict: [String: ConsoleSlotInfo]) {
        let maxSlot = dict.keys.compactMap { Int($0) }.max() ?? devices.count

        if maxSlot > devices.count {
            for slot in (devices.count + 1)...maxSlot {
                let dev = ChoirDevice(id: slot - 1,
                                      udid: "",
                                      name: "",
                                      midiChannel: 10,
                                      isPlaceholder: true)
                devices.append(dev)
                statuses[slot - 1] = .clean
            }
        }

        for idx in devices.indices {
            devices[idx].isPlaceholder = true
            devices[idx].udid = ""
            devices[idx].name = ""
            devices[idx].ip = ""
            devices[idx].midiChannel = 10
            devices[idx].listeningSlot = idx + 1
        }

        for (key, info) in dict {
            if let slot = Int(key), slot > 0, slot <= devices.count {
                let idx = slot - 1
                devices[idx].ip = info.ip
                devices[idx].udid = info.udid
                devices[idx].name = info.name
                devices[idx].isPlaceholder = false
                devices[idx].midiChannel = 10
                devices[idx].listeningSlot = slot
            }
        }

        updateAnyTorchOn()

        var groups: [Int: [Int]] = [:]
        for g in 1...9 { groups[g] = [] }
        let realSlots = devices.filter { !$0.isPlaceholder }.map { $0.listeningSlot }.sorted()
        var gIndex = 1
        for slot in realSlots {
            groups[gIndex]?.append(slot)
            gIndex = (gIndex % 9) + 1
        }
        groupMembers = groups
        print("[ConsoleState] groupMembers: \(groups)")
    }
    /// Stop playback of sound on a specific device slot (send audio/stop)
    public func stopSound(device: ChoirDevice) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                let slot = Int32(device.id + 1)
                try await osc.send(AudioStop(index: slot))
                await MainActor.run { self.lastLog = "/audio/stop [\(slot)]" }
                let base = device.id * 4
                for offset in 0..<4 {
                    await self.midi.sendNoteOff(UInt8(base + offset))
                }
            } catch {
                print("Error stopping sound for slot \(device.id + 1): \(error)")
            }
        }
    }
    
    /// Start a global ADSR envelope across all lamps
    public func startEnvelopeAll() {
        envelopeTask?.cancel()
        envelopeTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                let steps = 10
                // capture snapshot of actor-bound state
                let devicesList = await self.devices
                let attack = await self.attackMs
                let decay = await self.decayMs
                let sustainParam = await self.sustainPct
                // Attack phase
                for i in 0...steps {
                    let intensity = Float32(i) / Float32(steps)
                    for d in devicesList where !d.isPlaceholder {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(attack) * 1_000_000 / UInt64(steps))
                }
                // Decay to sustain
                let sustainLevel = Float32(sustainParam) / 100
                for i in 0...steps {
                    let t = Float32(i) / Float32(steps)
                    let intensity = (1 - t) + t * sustainLevel
                    for d in devicesList where !d.isPlaceholder {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(decay) * 1_000_000 / UInt64(steps))
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
        envelopeTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                let steps = 10
                // capture snapshot of actor-bound state
                let devicesList = await self.devices
                let releaseDur = await self.releaseMs
                let sustainParam = await self.sustainPct
                let sustainLevel = Float32(sustainParam) / 100
                for i in 0...steps {
                    let intensity = sustainLevel * (1 - Float32(i) / Float32(steps))
                    for d in devicesList where !d.isPlaceholder {
                        do { try await osc.send(FlashOn(index: Int32(d.id + 1), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(releaseDur) * 1_000_000 / UInt64(steps))
                }
                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
                await MainActor.run { self.lastLog = "/envelope release" }
            } catch {
                print("⚠️ releaseEnvelopeAll error: \(error)")
            }
        }
    }

    // MARK: – Strobe control
    private func startStrobe() {
        strobeTask?.cancel()
        strobeTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Constants controlling the strobe oscillation and update rate
            let oscillationHz: Float = 5        // 5 Hz brightness waveform
            let updateHz: Float = 12            // send ~12 frames per second
            let updateIntervalNs = UInt64(1_000_000_000 / updateHz)

            await MainActor.run { self.lastLog = "⚡️ Strobe active (12 Hz updates)" }
            do {
                let osc = try await self.broadcasterTask.value
                let devicesList = await self.devices

                // Start at -π/2 so the first frame begins at minimum
                // intensity and ramps upward rather than starting in the
                // middle of the waveform.
                var phase: Float = -.pi / 2
                let twoPi: Float = .pi * 2

                while await self.strobeActive {
                    let intensity = 0.5 * (1 + sin(phase))

                    for d in devicesList where !d.isPlaceholder {
                        try? await osc.send(
                            FlashOn(index: Int32(d.id + 1), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
            } catch {
                print("⚠️ startStrobe error: \(error)")
            }
            await MainActor.run { self.lastLog = "⚡️ Strobe stopped" }
        }
    }

    private func stopStrobe() {
        let task = strobeTask
        strobeTask = nil
        task?.cancel()

        Task.detached { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                for ch in 0..<16 {
                    self.midi.setChannel(ch + 1)
                    self.midi.sendControlChange(1, value: 0)
                }
                self.midi.setChannel(self.outputChannel)
            }
        }
    }

    private func startSlowStrobe() {
        slowStrobeTask?.cancel()
        slowStrobeTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Constants controlling the slow strobe oscillation and update rate
            let oscillationHz: Float = 1.25       // same 800 ms period as before
            let updateHz: Float = 12              // send ~12 frames per second
            let updateIntervalNs = UInt64(1_000_000_000 / updateHz)

            await MainActor.run { self.lastLog = "⚡️ Slow Strobe active (12 Hz updates)" }
            do {
                let osc = try await self.broadcasterTask.value
                let devicesList = await self.devices

                // Offset phase so the strobe ramps up from darkness
                var phase: Float = -.pi / 2
                let twoPi: Float = .pi * 2

                while await self.slowStrobeActive {
                    let intensity = 0.5 * (1 + sin(phase))

                    for d in devicesList where !d.isPlaceholder {
                        try? await osc.send(
                            FlashOn(index: Int32(d.id + 1), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
            } catch {
                print("⚠️ startSlowStrobe error: \(error)")
            }
            await MainActor.run { self.lastLog = "⚡️ Slow Strobe stopped" }
        }
    }

    private func stopSlowStrobe() {
        let task = slowStrobeTask
        slowStrobeTask = nil
        task?.cancel()

        Task.detached { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                for ch in 0..<16 {
                    self.midi.setChannel(ch + 1)
                    self.midi.sendControlChange(1, value: 0)
                }
                self.midi.setChannel(self.outputChannel)
            }
        }
    }

    private func startGlowRamp() {
        glowRampTask?.cancel()
        glowRampTask = Task.detached { [weak self] in
            guard let self = self else { return }

            let oscillationHz: Float = 0.625      // half speed of medium strobe
            let updateHz: Float = 12
            let updateIntervalNs = UInt64(1_000_000_000 / updateHz)

            await MainActor.run { self.lastLog = "⚡️ Glow Ramp active (12 Hz updates)" }
            do {
                let osc = try await self.broadcasterTask.value
                let devicesList = await self.devices

                // Begin at minimum brightness so the ramp grows from dark
                var phase: Float = -.pi / 2
                let twoPi: Float = .pi * 2

                while await self.glowRampActive {
                    let intensity = 0.5 * (1 + sin(phase))

                    for d in devicesList where !d.isPlaceholder {
                        try? await osc.send(
                            FlashOn(index: Int32(d.id + 1), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
            } catch {
                print("⚠️ startGlowRamp error: \(error)")
            }
            await MainActor.run { self.lastLog = "⚡️ Glow Ramp stopped" }
        }
    }

    private func stopGlowRamp() {
        let task = glowRampTask
        glowRampTask = nil
        task?.cancel()

        Task.detached { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                for ch in 0..<16 {
                    self.midi.setChannel(ch + 1)
                    self.midi.sendControlChange(1, value: 0)
                }
                self.midi.setChannel(self.outputChannel)
            }
        }
    }

    private func startSlowGlowRamp() {
        slowGlowRampTask?.cancel()
        slowGlowRampTask = Task.detached { [weak self] in
            guard let self = self else { return }

            let oscillationHz: Float = 0.3125     // half speed of glow ramp
            let updateHz: Float = 12
            let updateIntervalNs = UInt64(1_000_000_000 / updateHz)

            await MainActor.run { self.lastLog = "⚡️ Slow Glow Ramp active (12 Hz updates)" }
            do {
                let osc = try await self.broadcasterTask.value
                let devicesList = await self.devices

                // Offset start to -π/2 for an initial ramp-up from darkness
                var phase: Float = -.pi / 2
                let twoPi: Float = .pi * 2

                while await self.slowGlowRampActive {
                    let intensity = 0.5 * (1 + sin(phase))

                    for d in devicesList where !d.isPlaceholder {
                        try? await osc.send(
                            FlashOn(index: Int32(d.id + 1), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(d.id + 1))) } catch {}
                }
            } catch {
                print("⚠️ startSlowGlowRamp error: \(error)")
            }
            await MainActor.run { self.lastLog = "⚡️ Slow Glow Ramp stopped" }
        }
    }

    private func stopSlowGlowRamp() {
        let task = slowGlowRampTask
        slowGlowRampTask = nil
        task?.cancel()

        Task.detached { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                for ch in 0..<16 {
                    self.midi.setChannel(ch + 1)
                    self.midi.sendControlChange(1, value: 0)
                }
                self.midi.setChannel(self.outputChannel)
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
        for device in devices where !device.isPlaceholder {
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
        for device in devices where !device.isPlaceholder && statuses[device.id] == .buildReady {
            run(device: device)
        }
    }

    @discardableResult
    public func playAll() -> [ChoirDevice] {
        for idx in devices.indices where !devices[idx].isPlaceholder {
            devices[idx].torchOn = true
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let osc = try await self.broadcasterTask.value
                    try await osc.send(FlashOn(index: Int32(idx + 1), intensity: 1))
                } catch {
                    print("Error sending FlashOn for slot \(idx + 1): \(error)")
                }
            }
        }
        print("[ConsoleState] All torches turned on")
        updateAnyTorchOn()
        return devices
    }

    @discardableResult
    public func blackoutAll() -> [ChoirDevice] {
        for idx in devices.indices where !devices[idx].isPlaceholder {
            devices[idx].torchOn = false
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let osc = try await self.broadcasterTask.value
                    try await osc.send(FlashOff(index: Int32(idx + 1)))
                } catch {
                    print("Error sending FlashOff for slot \(idx + 1): \(error)")
                }
            }
        }
        print("[ConsoleState] All torches turned off")
        updateAnyTorchOn()
        return devices
    }

    /// Toggle all torches on or off depending on the current state.
    public func toggleAllTorches() {
        if isAnyTorchOn {
            _ = blackoutAll()
        } else {
            _ = playAll()
        }
    }
    
    // MARK: – Dynamic device management  📱
    /// Add a new device at runtime. Assigns next available zero-based id and initializes status.
    public func addDevice(name: String, ip: String, udid: String) {
        let newId = devices.count
        let device = ChoirDevice(id: newId,
                                 udid: udid,
                                 name: name,
                                 ip: ip,
                                 listeningSlot: newId + 1,
                                 midiChannel: 1)
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

    /// Update the MIDI channel for a device
    public func setDeviceChannel(_ deviceId: Int, _ newChannel: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[idx].midiChannel = newChannel
        objectWillChange.send()
        logMidi("Slot \(deviceId + 1) -> MIDI Ch \(newChannel)")
    }

    /// Assign a new listening slot to a specific device at runtime.
    /// Updates the local model and sends a unicast OSC message to notify the client.
    public func assignSlot(device: ChoirDevice, slot: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[idx].listeningSlot = slot
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                let msg = SetSlot(slot: Int32(slot))
                try await osc.sendUnicast(msg.encode(), toIP: device.ip)
                await MainActor.run { self.lastLog = "/set-slot [\(device.ip), \(slot)]" }
            } catch {
                await MainActor.run { self.lastLog = "⚠️ Failed to send set-slot to device at \(device.ip)" }
            }
        }
    }

    /// Update device info when a /hello is received from a client
    @MainActor
    func deviceDiscovered(slot: Int, ip: String) {
        guard slot > 0 && slot <= devices.count else { return }
        let idx = slot - 1
        devices[idx].ip = ip
        statuses[idx] = .live
        lastLog = "📳 Device \(slot) announced at \(ip)"
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

            // Call must be awaited because registerHelloHandler is actor-isolated.
            // deviceDiscovered is a synchronous @MainActor method, so no `await`.
            await broadcaster.registerHelloHandler { [weak self] slot, ip in
                Task { @MainActor in
                    self?.deviceDiscovered(slot: slot, ip: ip)
                }
            }
            print("[ConsoleState] Network stack started ✅")
        } catch let err as POSIXError where err.code == .EHOSTDOWN {
            lastLog = "⚠️ No active network interface"
            print("^Δ startNetwork host down: \(err)")
            isBroadcasting = false
        } catch {
            lastLog = "⚠️ Network start failed: \(error)"
            print("⚠️ startNetwork error: \(error)")
            isBroadcasting = false
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

// MARK: - MIDI Handling
extension ConsoleState {
    fileprivate func handleNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        let ch = Int(channel) + 1
        let val = Int(note)

        // Primer tones triggered by group channels 1–9
        if (1...9).contains(ch),
           (0...48).contains(val) || (50...98).contains(val) {
            let fileName = val < 50 ? "short\(val).mp3" : "long\(val).mp3"
            if let slots = groupMembers[ch] {
                for slot in slots {
                    Task.detached { [weak self] in
                        guard let self = self else { return }
                        do {
                            let osc = try await self.broadcasterTask.value
                            try await osc.send(AudioPlay(index: Int32(slot), file: fileName, gain: 1.0))
                        } catch {
                            print("Error sending primer tone to slot \(slot): \(error)")
                        }
                    }
                }
            }
            logMidi("Primer \(val) -> Group \(ch)")
            return
        }

        // Complex sound events from banks on channels 11–16
        if (11...16).contains(ch) {
            var slots: [Int] = []
            var prefix = ""
            var eventId = val

            switch ch {
            case 11:
                prefix = "seL-"; slots = (1...3).flatMap { groupMembers[$0] ?? [] }
            case 12:
                prefix = "seL-"; eventId += 128; slots = (1...3).flatMap { groupMembers[$0] ?? [] }
            case 13:
                prefix = "seC-"; slots = (4...6).flatMap { groupMembers[$0] ?? [] }
            case 14:
                prefix = "seC-"; eventId += 128; slots = (4...6).flatMap { groupMembers[$0] ?? [] }
            case 15:
                prefix = "seR-"; slots = (7...9).flatMap { groupMembers[$0] ?? [] }
            case 16:
                prefix = "seR-"; eventId += 128; slots = (7...9).flatMap { groupMembers[$0] ?? [] }
            default: break
            }

            let fileName = "\(prefix)\(eventId).mp3"
            for slot in slots {
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    do {
                        let osc = try await self.broadcasterTask.value
                        try await osc.send(AudioPlay(index: Int32(slot), file: fileName, gain: 1.0))
                    } catch {
                        print("Error sending sound event to slot \(slot): \(error)")
                    }
                }
            }

            let region = ch <= 12 ? "Left" : ch <= 14 ? "Center" : "Right"
            logMidi("SoundEvent \(eventId) -> \(region)")
            return
        }

        // Legacy per-device handling and group triggers
        if val >= midiNoteOffset + 1 && val < midiNoteOffset + 1 + devices.count {
            let slot = val - midiNoteOffset
            guard let idx = devices.firstIndex(where: { $0.listeningSlot == slot }) else {
                return
            }
            let device = devices[idx]
            if device.midiChannel == ch {
                glowingSlots.insert(val)
                switch keyboardTriggerMode {
                case .torch:
                    flashOn(id: idx)
                case .sound:
                    triggerSound(device: device)
                case .both:
                    flashOn(id: idx)
                    triggerSound(device: device)
                }
            }
        } else if val >= 96 && val <= 104 {
            let group = val - 95
            if let slots = groupMembers[group] {
                triggerSlots(realSlots: slots)
            }
        } else if val == 71 {
            slowGlowRampActive = true
        } else if val == 72 {
            glowRampActive = true
        } else if val == 105 {
            strobeActive = true
        } else if val == 106 {
            toggleAllTorches()
        }
        logMidi("NoteOn \(note) ch\(ch) vel \(velocity)")
    }

    fileprivate func handleNoteOff(note: UInt8, channel: UInt8) {
        let ch = Int(channel) + 1
        let val = Int(note)

        // Stop primer tones for group channels 1–9
        if (1...9).contains(ch),
           (0...48).contains(val) || (50...98).contains(val),
           let slots = groupMembers[ch] {
            for slot in slots {
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    do {
                        let osc = try await self.broadcasterTask.value
                        try await osc.send(AudioStop(index: Int32(slot)))
                    } catch {
                        print("Error stopping primer tone on slot \(slot): \(error)")
                    }
                }
            }
            logMidi("PrimerStop \(val) -> Group \(ch)")
            return
        }

        if val >= midiNoteOffset + 1 && val < midiNoteOffset + 1 + devices.count {
            let slot = val - midiNoteOffset
            guard let idx = devices.firstIndex(where: { $0.listeningSlot == slot }) else {
                return
            }
            let device = devices[idx]
            if device.midiChannel == ch {
                glowingSlots.remove(val)
                switch keyboardTriggerMode {
                case .torch:
                    flashOff(id: idx)
                case .sound:
                    stopSound(device: device)
                case .both:
                    flashOff(id: idx)
                    stopSound(device: device)
                }
            }
        } else if val == 71 {
            slowGlowRampActive = false
        } else if val == 72 {
            glowRampActive = false
        } else if val == 105 {
            strobeActive = false
        }
        logMidi("NoteOff \(note) ch\(ch)")
    }

    fileprivate func handleControlChange(cc: UInt8, value: UInt8, channel: UInt8) {
        let ctrl = Int(cc)
        let val = Int(value)
        if ctrl == 1 {
            let intensity = Float32(val) / 127.0
            let targetChannel = Int(channel + 1)
            for device in devices where !device.isPlaceholder {
                if device.midiChannel == targetChannel {
                    Task.detached { [weak self] in
                        guard let self = self else { return }
                        do {
                            let osc = try await self.broadcasterTask.value
                            if intensity > 0 {
                                try await osc.send(FlashOn(index: Int32(device.id + 1), intensity: intensity))
                            } else {
                                try await osc.send(FlashOff(index: Int32(device.id + 1)))
                            }
                        } catch {
                            print("Error sending brightness CC for device \(device.id+1): \(error)")
                        }
                    }
                }
            }
            Task { @MainActor in
                if val > 0 {
                    self.lastLog = "/flash/bright CH\(targetChannel) val \(val)"
                } else {
                    self.lastLog = "/flash/off [CH\(targetChannel)]"
                }
            }
        }
        logMidi("CC\(cc) ch\(channel+1) val \(value)")
    }
}

// MARK: - Typing MIDI Dispatch
extension ConsoleState {
    /// Send a MIDI Note On from the typing keyboard and handle it like incoming MIDI.
    public func typingNoteOn(_ note: UInt8, velocity: UInt8 = 127) {
        let idx = Int(note) - midiNoteOffset - 1
        let chan: UInt8 = idx >= 0 && idx < devices.count ? UInt8(devices[idx].midiChannel - 1) : 0
        handleNoteOn(note: note, velocity: velocity, channel: chan)
        midi.sendNoteOn(note, velocity: velocity)
    }

    /// Send a MIDI Note Off from the typing keyboard and handle it like incoming MIDI.
    public func typingNoteOff(_ note: UInt8) {
        let idx = Int(note) - midiNoteOffset - 1
        let chan: UInt8 = idx >= 0 && idx < devices.count ? UInt8(devices[idx].midiChannel - 1) : 0
        handleNoteOff(note: note, channel: chan)
        midi.sendNoteOff(note)
    }
}
