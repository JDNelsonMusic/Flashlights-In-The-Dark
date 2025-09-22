import Foundation
import Combine
import SwiftUI
import AppKit
import CoreAudio
import NIOPosix
//import Network   // auto-discovery removed
import Darwin           // for POSIXError & EHOSTDOWN
import OSCKit

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
    private let eventLoader = EventRecipeLoader()
    private let primerAudioEngine = PrimerToneAudioEngine()
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

    // Event timeline & audio routing
    @Published public private(set) var eventRecipes: [EventRecipe] = []
    @Published public var currentEventIndex: Int = 0
    @Published public var lastTriggeredEventID: Int?
    @Published public private(set) var audioOutputDevices: [AudioDeviceInfo] = []
    @Published public var selectedAudioDeviceID: UInt32 = 0 {
        didSet {
            guard selectedAudioDeviceID != oldValue else { return }
            if selectedAudioDeviceID == 0 {
                primerAudioEngine.setOutputDevice(nil)
            } else {
                primerAudioEngine.setOutputDevice(AudioDeviceID(selectedAudioDeviceID))
            }
        }
    }
    @Published public private(set) var eventLoadError: String?

    // Slots currently glowing for UI feedback
    @Published public var glowingSlots: Set<Int> = []
    /// Slots currently triggered via typing keyboard
    @Published public var triggeredSlots: Set<Int> = []

    /// Members for dynamic groups 1-9
    @Published public var groupMembers: [Int: [Int]] = [:]

    /// Default slot group mapping for primer tones
    private let defaultGroups: [Int: [Int]] = [
        1: [27, 41, 42],
        2: [1, 14, 15],
        3: [16, 29, 44],
        4: [3, 4, 18],
        5: [7, 19, 34],
        6: [9, 20, 21],
        7: [23, 38, 51],
        8: [12, 24, 25],
        9: [40, 53, 54]
    ]

    // MARK: – Init
    public init() {
        // If a session file exists in UserDefaults, load it; else use defaults.
        if let saved = Self.restoreLastSession() {
            self.devices = saved
        } else {
            self.devices = ChoirDevice.demo // demo already contains defaultChannelMap
        }

        // Override MIDI channel assignments from external JSON if present
        if let mapURL = Bundle.main.url(forResource: "channel_map", withExtension: "json"),
           let channelMap = ChoirDevice.loadChannelMap(from: mapURL) {
            for (slot, channels) in channelMap {
                if slot > 0 && slot <= devices.count {
                    let idx = slot - 1
                    devices[idx].midiChannels = channels
                }
            }
            print("✅ Custom MIDI channel map loaded")
        } else {
            print("ℹ️ Using default MIDI channel map")
        }

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
        groupMembers = defaultGroups
        loadEventRecipes()
        refreshAudioOutputs()
        let audioEngine = primerAudioEngine
        DispatchQueue.global(qos: .userInitiated).async {
            audioEngine.preloadPrimerTones()
        }
    }

    @Published public private(set) var devices: [ChoirDevice]
    @Published public var statuses: [Int: DeviceStatus] = [:]
    @Published public var lastLog: String = "🎛  Ready – tap a tile"

    /// Last time a /hello was heard from each slot.
    private var lastHello: [Int: Date] = [:]
    /// Last time an /ack was received from each slot.
    private var lastAckTimes: [Int: Date] = [:]
    private var heartbeatTimer: Timer?
    /// When we last probed a given slot with a /discover ping.
    private var lastHelloProbe: [Int: Date] = [:]

    private var sessionURL: URL?

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
    /// Active audio tone sets ("A","B","C","D"). All banks are enabled by
    /// default so the corresponding buttons start in the active state.
    @Published public var activeToneSets: Set<String> = ["A", "B", "C", "D"]
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

    /// Handle a tap cue from the proxy device.
    public func tapReceived() {
        lastLog = "🎵 Tap signal received"
        toggleAllTorches()
    }

    /// Track pressed typing slots for UI feedback
    public func addTriggeredSlot(_ slot: Int) {
        triggeredSlots.insert(slot)
    }

    public func removeTriggeredSlot(_ slot: Int) {
        triggeredSlots.remove(slot)
    }

    /// Send a flashlight-on command and retry once if not acknowledged.
    private func reliableFlashOn(slot: Int) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let slotNum = slot + 1
            do {
                let osc = try await self.broadcasterTask.value
                try await osc.send(FlashOn(index: Int32(slotNum), intensity: 1))
                await MainActor.run {
                    self.lastLog = "/flash/on [\(slotNum), 1] (sent)"
                    self.glow(slot: slotNum)
                }
                await self.midi.sendControlChange(UInt8(slotNum), value: 127)
                try await Task.sleep(nanoseconds: 100_000_000)
                let lastAck = await MainActor.run { self.lastAckTimes[slotNum] }
                if Date().timeIntervalSince(lastAck ?? .distantPast) > 0.1 {
                    try await osc.send(FlashOn(index: Int32(slotNum), intensity: 1))
                    await MainActor.run {
                        self.lastLog = "⚠️ Re-sent /flash/on to \(slotNum) (no ack)"
                    }
                }
            } catch {
                print("Error in reliableFlashOn(\(slotNum)): \(error)")
            }
        }
    }

    /// Append a MIDI message string to the log.  Older entries are retained so
    /// the user can scroll back through the full history.  Callers should
    /// consider truncating externally if extremely large logs become a concern.
    public func logMidi(_ message: String) {
        midiLog.append(message)
    }
    

    @discardableResult
    public func toggleTorch(id: Int) -> [ChoirDevice] {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        guard !devices[idx].isPlaceholder else { return devices }
        objectWillChange.send()
        devices[idx].torchOn.toggle()
        let isOn = devices[idx].torchOn
        if isOn {
            reliableFlashOn(slot: id)
        } else {
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let osc = try await self.broadcasterTask.value
                    try await osc.send(FlashOff(index: Int32(id + 1)))
                    await MainActor.run { self.lastLog = "/flash/off [\(id + 1)]" }
                    await self.midi.sendControlChange(UInt8(id + 1), value: 0)
                } catch {
                    print("Error toggling torch for slot \(id + 1): \(error)")
                }
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
        reliableFlashOn(slot: id)
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
                                      midiChannels: [10],
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
            devices[idx].midiChannels = [10]
            devices[idx].listeningSlot = idx + 1
        }

        for (key, info) in dict {
            if let slot = Int(key), slot > 0, slot <= devices.count {
                let idx = slot - 1
                devices[idx].ip = info.ip
                devices[idx].udid = info.udid
                devices[idx].name = info.name
                devices[idx].isPlaceholder = false
                devices[idx].midiChannels = ChoirDevice.defaultChannelMap[slot] ?? [10]
                devices[idx].listeningSlot = slot
            }
        }

        updateAnyTorchOn()

        groupMembers = defaultGroups
        print("[ConsoleState] groupMembers: \(defaultGroups)")
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

    /// Stop all audio playback on every device.
    public func stopAllSounds() {
        for device in devices where !device.isPlaceholder {
            stopSound(device: device)
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
                                 midiChannels: [1])
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

    /// Toggle listening for a MIDI channel on a device
    public func toggleDeviceChannel(_ deviceId: Int, _ channel: Int) {
        guard let idx = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        var dev = devices[idx]
        if dev.midiChannels.contains(channel) {
            dev.midiChannels.remove(channel)
        } else {
            dev.midiChannels.insert(channel)
        }
        devices[idx] = dev
        logMidi("Slot \(deviceId + 1) toggle MIDI Ch \(channel)")
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
    func deviceDiscovered(slot: Int, ip: String, udid: String?) {
        guard slot > 0 && slot <= devices.count else { return }
        let idx = slot - 1
        devices[idx].ip = ip
        statuses[idx] = .live
        lastHello[slot] = Date()
        lastHelloProbe.removeValue(forKey: slot)
        lastLog = "📳 Device \(slot) announced at \(ip)"
    }
}

// MARK: - Lifecycle helpers

extension ConsoleState {
    /// Restore the most recent session devices from UserDefaults.
    /// Returns nil if no session data was saved.
    static func restoreLastSession() -> [ChoirDevice]? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "lastSession") else { return nil }
        if let session = try? JSONDecoder().decode([ChoirDevice].self, from: data) {
            return session
        }
        return nil
    }
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
            await broadcaster.registerHelloHandler { [weak self] slot, ip, udid in
                Task { @MainActor in
                    self?.deviceDiscovered(slot: slot, ip: ip, udid: udid)
                }
            }
            await broadcaster.registerAckHandler { [weak self] slot in
                Task { @MainActor in
                    self?.lastLog = "✅ Ack from slot \(slot)"
                    self?.lastAckTimes[slot] = Date()
                }
            }
            await broadcaster.registerTapHandler { [weak self] in
                Task { @MainActor in
                    self?.tapReceived()
                }
            }
            heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.checkHeartbeats()
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
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        // ClockSyncService de-initialises itself when its Task is cancelled.
        // Add additional cleanup here (file handles, etc.) as the project grows.
        print("[ConsoleState] Network stack suspended 💤")
    }

    private func checkHeartbeats() {
        let now = Date()
        for slot in 1...devices.count {
            let idx = slot - 1
            let lastSeen = lastHello[slot]
            if let lastSeen, now.timeIntervalSince(lastSeen) <= 5 {
                if statuses[idx] == .lostConnection {
                    statuses[idx] = .live
                }
                continue
            }

            if statuses[idx] != .lostConnection {
                statuses[idx] = .lostConnection
            }

            let lastProbe = lastHelloProbe[slot] ?? .distantPast
            if now.timeIntervalSince(lastProbe) >= 10 {
                lastHelloProbe[slot] = now
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    do {
                        let broadcaster = try await self.broadcasterTask.value
                        await broadcaster.requestHello(forSlot: slot)
                    } catch {
                        print("⚠️ heartbeat probe error for slot \(slot): \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Event Timeline & Primer Playback
extension ConsoleState {
    private func loadEventRecipes() {
        do {
            let recipes = try eventLoader.loadRecipes()
            eventRecipes = recipes
            currentEventIndex = 0
            eventLoadError = nil
            if let first = recipes.first {
                lastLog = "Loaded \(recipes.count) event recipes · Next: Event #\(first.id)"
            }
        } catch {
            eventRecipes = []
            currentEventIndex = 0
            eventLoadError = "Event recipe file missing or unreadable"
            lastLog = "⚠️ Unable to load event recipes"
        }
    }

    public func refreshAudioOutputs() {
        let devices = primerAudioEngine.availableOutputDevices()
        audioOutputDevices = devices
        let current = primerAudioEngine.currentOutputDeviceID()
        if current != selectedAudioDeviceID {
            selectedAudioDeviceID = current
        }
    }

    public func triggerCurrentEvent(advanceAfterTrigger: Bool = true) {
        guard eventRecipes.indices.contains(currentEventIndex) else {
            lastLog = "⚠️ No event selected"
            return
        }
        let event = eventRecipes[currentEventIndex]
        lastTriggeredEventID = event.id
        Task { [weak self] in
            await self?.fire(event: event)
        }
        if advanceAfterTrigger {
            moveToNextEvent()
        }
    }

    public func moveToNextEvent() {
        guard !eventRecipes.isEmpty else { return }
        let nextIndex = min(currentEventIndex + 1, eventRecipes.count - 1)
        currentEventIndex = nextIndex
    }

    public func moveToPreviousEvent() {
        guard !eventRecipes.isEmpty else { return }
        let prevIndex = max(currentEventIndex - 1, 0)
        currentEventIndex = prevIndex
    }

    public func focusOnEvent(id: Int) {
        if let idx = eventRecipes.firstIndex(where: { $0.id == id }) {
            currentEventIndex = idx
        }
    }

    private func fire(event: EventRecipe) async {
        await sendPrimerAssignments(for: event)
        primerAudioEngine.play(assignments: event.primerAssignments)
        let measureText = event.measure.map { "M\($0)" } ?? "M?"
        let beatText = event.position ?? "?"
        await MainActor.run {
            lastLog = "▶︎ Event #\(event.id) • \(measureText) • \(beatText)"
        }
    }

    private func sendPrimerAssignments(for event: EventRecipe) async {
        guard !event.primerAssignments.isEmpty else { return }
        guard isBroadcasting else { return }
        do {
            let broadcaster = try await broadcasterTask.value
            for (color, assignment) in event.primerAssignments {
                guard let fileName = assignment.oscFileName else { continue }
                let targets = slots(for: color)
                guard !targets.isEmpty else { continue }
                for slot in targets {
                    try await broadcaster.send(AudioPlay(index: Int32(slot), file: fileName, gain: 1.0))
                }
            }
        } catch {
            await MainActor.run {
                lastLog = "⚠️ Failed to send event: \(error.localizedDescription)"
            }
        }
    }

    private func slots(for color: PrimerColor) -> [Int] {
        if let custom = groupMembers[color.groupIndex], !custom.isEmpty {
            return custom
        }
        if let defaults = defaultGroups[color.groupIndex] {
            return defaults
        }
        return []
    }
}

// MARK: - MIDI Handling
extension ConsoleState {
    fileprivate func handleNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        let ch = Int(channel) + 1
        let val = Int(note)

        // Dedicated flashlight channel
        if ch == 10 {
            if val >= 1 && val <= devices.count {
                if let idx = devices.firstIndex(where: { $0.listeningSlot == val }) {
                    let device = devices[idx]
                    if device.midiChannels.contains(ch) {
                        flashOn(id: idx)
                        glowingSlots.insert(val)
                    }
                }
            } else if val >= 96 && val <= 104 {
                let group = val - 95
                if let slots = groupMembers[group] {
                    for slot in slots {
                        let idx = slot - 1
                        let device = devices[idx]
                        if device.midiChannels.contains(ch) {
                            flashOn(id: idx)
                            glowingSlots.insert(slot)
                        }
                    }
                }
            } else if val == 105 {
                strobeActive = true
            } else if val == 106 {
                toggleAllTorches()
            }
            logMidi("TorchOn \(note) ch\(ch)")
            return
        }

        // Primer tones triggered by group channels 1–9
        if (1...9).contains(ch),
           (0...48).contains(val) || (50...98).contains(val) {
            let fileName = val < 50 ? "short\(val).mp3" : "long\(val).mp3"
            if let slots = groupMembers[ch] {
                for slot in slots {
                    let idx = slot - 1
                    guard idx >= 0 && idx < devices.count else { continue }
                    let device = devices[idx]
                    if device.midiChannels.contains(ch) {
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
                let idx = slot - 1
                guard idx >= 0 && idx < devices.count else { continue }
                let device = devices[idx]
                if device.midiChannels.contains(ch) {
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
            if device.midiChannels.contains(ch) {
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

        if ch == 10 {
            if val >= 1 && val <= devices.count {
                if let idx = devices.firstIndex(where: { $0.listeningSlot == val }) {
                    let device = devices[idx]
                    if device.midiChannels.contains(ch) {
                        flashOff(id: idx)
                        glowingSlots.remove(val)
                    }
                }
            } else if val >= 96 && val <= 104 {
                let group = val - 95
                if let slots = groupMembers[group] {
                    for slot in slots {
                        let idx = slot - 1
                        let device = devices[idx]
                        if device.midiChannels.contains(ch) {
                            flashOff(id: idx)
                            glowingSlots.remove(slot)
                        }
                    }
                }
            } else if val == 105 {
                strobeActive = false
            }
            logMidi("TorchOff \(note) ch\(ch)")
            return
        }

        // Stop primer tones for group channels 1–9
        if (1...9).contains(ch),
           (0...48).contains(val) || (50...98).contains(val),
           let slots = groupMembers[ch] {
            for slot in slots {
                let idx = slot - 1
                guard idx >= 0 && idx < devices.count else { continue }
                let device = devices[idx]
                if device.midiChannels.contains(ch) {
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
            if device.midiChannels.contains(ch) {
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
                if device.midiChannels.contains(targetChannel) {
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
        let chan: UInt8 = {
            guard idx >= 0 && idx < devices.count,
                  let first = devices[idx].midiChannels.sorted().first else { return 0 }
            return UInt8(first - 1)
        }()
        handleNoteOn(note: note, velocity: velocity, channel: chan)
        midi.sendNoteOn(note, velocity: velocity)
    }

    /// Send a MIDI Note Off from the typing keyboard and handle it like incoming MIDI.
    public func typingNoteOff(_ note: UInt8) {
        let idx = Int(note) - midiNoteOffset - 1
        let chan: UInt8 = {
            guard idx >= 0 && idx < devices.count,
                  let first = devices[idx].midiChannels.sorted().first else { return 0 }
            return UInt8(first - 1)
        }()
        handleNoteOff(note: note, channel: chan)
        midi.sendNoteOff(note)
    }
}

// MARK: - Session Persistence
extension ConsoleState {
    private struct DeviceSession: Codable {
        var id: Int
        var listeningSlot: Int
        var channels: [Int]
    }

    private struct SessionData: Codable {
        var devices: [DeviceSession]
        var groups: [Int: [Int]]
    }

    /// Save current state to a file, using existing sessionURL if available.
    @MainActor
    public func saveSession() {
        if let url = sessionURL {
            try? writeSession(to: url)
        } else {
            saveSessionAs()
        }
    }

    /// Prompt for location and save session.
    @MainActor
    public func saveSessionAs() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["flashlights"]
        panel.nameFieldStringValue = "Session.flashlights"
        if panel.runModal() == .OK, let url = panel.url {
            sessionURL = url
            try? writeSession(to: url)
        }
    }

    /// Prompt user to open a saved session.
    @MainActor
    public func openSession() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["flashlights"]
        if panel.runModal() == .OK, let url = panel.url {
            sessionURL = url
            try? readSession(from: url)
        }
    }

    private func writeSession(to url: URL) throws {
        let devs = devices.map { DeviceSession(id: $0.id, listeningSlot: $0.listeningSlot, channels: Array($0.midiChannels)) }
        let data = SessionData(devices: devs, groups: groupMembers)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: url)
    }

    @MainActor
    private func readSession(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(SessionData.self, from: data)
        objectWillChange.send()
        for dev in session.devices {
            if let idx = devices.firstIndex(where: { $0.id == dev.id }) {
                devices[idx].listeningSlot = dev.listeningSlot
                devices[idx].midiChannels = Set(dev.channels)
            }
        }
        groupMembers = session.groups
    }
}
