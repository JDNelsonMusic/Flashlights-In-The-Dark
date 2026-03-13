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
    private let diagnostics = NetworkDiagnostics()
    private lazy var broadcasterTask: Task<OscBroadcaster, Error> = Task {
        try await OscBroadcaster(diagnostics: diagnostics)
    }
    // Track ongoing run processes to monitor connection/state
    private var runProcesses: [Int: Process] = [:]
    private let midi = MIDIManager()
    private let eventLoader = EventRecipeLoader()
    private let primerAudioEngine = PrimerToneAudioEngine()
    private let primerLeadTimeMs: Double = 180.0
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
    @Published public private(set) var eventRecipes: [EventRecipe] = [] {
        didSet {
            clampCurrentEventIndex()
        }
    }
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
    @Published public var groupMembers: [Int: [Int]] = [:] {
        didSet {
            guard !isApplyingGroupSanitization else { return }
            sanitizeGroupMembers()
        }
    }

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

    private let performanceSlots: [Int] = [
        1, 3, 4, 7, 9, 12, 14, 15, 16, 18, 19, 20, 21, 23, 24, 25,
        27, 29, 34, 38, 40, 41, 42, 44, 51, 53, 54
    ]

    private lazy var canonicalSlots: Set<Int> = {
        Set(performanceSlots)
    }()
    private var isApplyingGroupSanitization = false

    private func resetGroupMembersToDefault() {
        groupMembers = defaultGroups
    }

    private func sanitizeGroupMembers() {
        let currentGroups = groupMembers
        let sanitized = defaultGroups

        if sanitized != currentGroups {
            print("[ConsoleState] Normalised group membership to canonical slot mapping")
            isApplyingGroupSanitization = true
            groupMembers = sanitized
            isApplyingGroupSanitization = false
        }
    }

    private func clampCurrentEventIndex() {
        let boundedIndex: Int
        if eventRecipes.isEmpty {
            boundedIndex = 0
        } else {
            let upperBound = eventRecipes.count - 1
            let lowerBound = 0
            boundedIndex = min(max(currentEventIndex, lowerBound), upperBound)
        }
        if boundedIndex != currentEventIndex {
            currentEventIndex = boundedIndex
        }
    }

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
        resetGroupMembersToDefault()
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
    @Published public var isKeyCaptureEnabled: Bool = true
    @Published public private(set) var showSessionId: String = UUID().uuidString
    @Published public private(set) var protocolVersion: Int = Int(ConcertProtocol.version)
    @Published public var expectedDeviceCount: Int = ConcertProtocol.expectedDeviceCount
    @Published public var isArmed: Bool = false {
        didSet {
            Task.detached { [weak self] in
                guard let self else { return }
                if let broadcaster = try? await self.broadcasterTask.value {
                    await broadcaster.setArmed(self.isArmed)
                }
            }
        }
    }
    @Published public var preflightWarning: String?
    @Published public private(set) var unknownSenderEvents: Int = 0
    @Published public private(set) var packetRatePerSecond: Double = 0
    @Published public private(set) var totalSendFailures: Int = 0
    @Published public private(set) var interfaceHealthSummary: [NetworkDiagnosticsSnapshot.InterfaceSummary] = []

    /// Last time a /hello was heard from each slot.
    private var lastHello: [Int: Date] = [:]
    /// Last time an /ack was received from each slot.
    private var lastAckTimes: [Int: Date] = [:]
    private var heartbeatTimer: Timer?
    private var discoveryRefreshTimer: Timer?
    private var discoveryRefreshInFlight = false
    private var lastDiscoveryRefresh: Date?
    private let discoveryRefreshInterval: TimeInterval = 45
    private let minimumDiscoveryRefreshSpacing: TimeInterval = 5
    private let heartbeatTimerInterval: TimeInterval = 5
    private let heartbeatGraceInterval: TimeInterval = 18
    private let heartbeatProbeSpacing: TimeInterval = 20
    private let conductorHelloInterval: TimeInterval = 1.5
    private let conductorHandshakeTimeout: TimeInterval = 45
    /// When we last probed a given slot with a /discover ping.
    private var lastHelloProbe: [Int: Date] = [:]
    private var conductorHelloTimer: Timer?
    private var conductorHelloStartedAt: Date?
    private var metricsTimer: Timer?

    private var sessionURL: URL?
    /// Monotonic per-slot counter so flashlight retries abandon stale intents.
    private var torchIntentGeneration: [Int: Int] = [:]

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

    private func ensureArmedForCue(_ action: String) -> Bool {
        guard isArmed else {
            lastLog = "⚠️ SAFE mode: arm before \(action)"
            return false
        }
        return true
    }

    private func ensureCueAuthorized(_ action: String, allowWhenDisarmed: Bool) -> Bool {
        if isArmed || allowWhenDisarmed {
            return true
        }
        lastLog = "⚠️ SAFE mode: arm before \(action)"
        return false
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

    nonisolated func cueSlot(for device: ChoirDevice) -> Int {
        max(device.listeningSlot, 1)
    }

    private func nextTorchGeneration(forDeviceID deviceID: Int) -> Int {
        let next = (torchIntentGeneration[deviceID] ?? 0) &+ 1
        torchIntentGeneration[deviceID] = next
        return next
    }

    private func torchIntentMatches(deviceID: Int, generation: Int, expectsOn: Bool) -> Bool {
        guard torchIntentGeneration[deviceID] == generation,
              let idx = devices.firstIndex(where: { $0.id == deviceID }) else { return false }
        return devices[idx].torchOn == expectsOn
    }

    /// Send a flashlight-on command and retry once if not acknowledged, but abort if intent changes.
    private func reliableFlashOn(
        deviceID: Int,
        targetSlot: Int,
        generation: Int,
        allowWhenDisarmed: Bool
    ) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let slotNum = targetSlot
            do {
                let osc = try await self.broadcasterTask.value
                let shouldSend = await MainActor.run {
                    self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: true)
                }
                guard shouldSend else { return }
                try await osc.send(
                    FlashOn(index: Int32(slotNum), intensity: 1),
                    allowWhenDisarmed: allowWhenDisarmed
                )
                await MainActor.run {
                    guard self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: true) else { return }
                    self.lastLog = "/flash/on [\(slotNum), 1] (sent)"
                    self.glow(slot: slotNum)
                }
                await self.midi.sendControlChange(UInt8(slotNum), value: 127)
                try await Task.sleep(nanoseconds: 100_000_000)
                let retryState = await MainActor.run { () -> (Bool, Date?) in
                    (self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: true),
                     self.lastAckTimes[slotNum])
                }
                guard retryState.0 else { return }
                if Date().timeIntervalSince(retryState.1 ?? .distantPast) > 0.1 {
                    try await osc.send(
                        FlashOn(index: Int32(slotNum), intensity: 1),
                        allowWhenDisarmed: allowWhenDisarmed
                    )
                    await MainActor.run {
                        guard self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: true) else { return }
                        self.lastLog = "⚠️ Re-sent /flash/on to \(slotNum) (no ack)"
                    }
                }
            } catch {
                print("Error in reliableFlashOn(\(slotNum)): \(error)")
            }
        }
    }

    private func sendFlashOff(
        deviceID: Int,
        targetSlot: Int,
        generation: Int,
        allowWhenDisarmed: Bool
    ) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let slotNum = targetSlot
            do {
                let osc = try await self.broadcasterTask.value
                let shouldSend = await MainActor.run {
                    self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: false)
                }
                guard shouldSend else { return }
                try await osc.send(
                    FlashOff(index: Int32(slotNum)),
                    allowWhenDisarmed: allowWhenDisarmed
                )
                await MainActor.run {
                    guard self.torchIntentMatches(deviceID: deviceID, generation: generation, expectsOn: false) else { return }
                    self.lastLog = "/flash/off [\(slotNum)]"
                }
                await self.midi.sendControlChange(UInt8(slotNum), value: 0)
            } catch {
                print("Error sending FlashOff for slot \(slotNum): \(error)")
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
    public func toggleTorch(id: Int, allowWhenDisarmed: Bool = false) -> [ChoirDevice] {
        guard ensureCueAuthorized("sending cues", allowWhenDisarmed: allowWhenDisarmed) else { return devices }
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return devices }
        guard !devices[idx].isPlaceholder else { return devices }
        objectWillChange.send()
        let newState = !devices[idx].torchOn
        let targetSlot = cueSlot(for: devices[idx])
        let generation = nextTorchGeneration(forDeviceID: id)
        devices[idx].torchOn = newState
        if newState {
            reliableFlashOn(
                deviceID: id,
                targetSlot: targetSlot,
                generation: generation,
                allowWhenDisarmed: allowWhenDisarmed
            )
        } else {
            sendFlashOff(
                deviceID: id,
                targetSlot: targetSlot,
                generation: generation,
                allowWhenDisarmed: allowWhenDisarmed
            )
        }
        print("[ConsoleState] Torch toggled on #\(id) ⇒ \(newState)")
        updateAnyTorchOn()
        return devices
    }
    
    /// Directly flash on a specific lamp slot (no toggle) and update state.
    public func flashOn(id: Int, allowWhenDisarmed: Bool = false) {
        guard ensureCueAuthorized("sending cues", allowWhenDisarmed: allowWhenDisarmed) else { return }
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        objectWillChange.send()
        let targetSlot = cueSlot(for: devices[idx])
        let generation = nextTorchGeneration(forDeviceID: id)
        devices[idx].torchOn = true
        reliableFlashOn(
            deviceID: id,
            targetSlot: targetSlot,
            generation: generation,
            allowWhenDisarmed: allowWhenDisarmed
        )
        updateAnyTorchOn()
    }
    /// Directly flash off a specific lamp slot and update state.
    public func flashOff(id: Int, allowWhenDisarmed: Bool = false) {
        guard ensureCueAuthorized("sending cues", allowWhenDisarmed: allowWhenDisarmed) else { return }
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        objectWillChange.send()
        let targetSlot = cueSlot(for: devices[idx])
        let generation = nextTorchGeneration(forDeviceID: id)
        devices[idx].torchOn = false
        sendFlashOff(
            deviceID: id,
            targetSlot: targetSlot,
            generation: generation,
            allowWhenDisarmed: allowWhenDisarmed
        )
        updateAnyTorchOn()
    }

    /// Trigger a list of real slots according to the current keyboardTriggerMode.
    public func triggerSlots(realSlots: [Int], allowWhenDisarmed: Bool = false) {
        for real in realSlots {
            guard let idx = devices.firstIndex(where: { !$0.isPlaceholder && $0.listeningSlot == real }) else {
                continue
            }
            let device = devices[idx]
            switch keyboardTriggerMode {
            case .torch:
                _ = toggleTorch(id: device.id, allowWhenDisarmed: allowWhenDisarmed)
            case .sound:
                triggerSound(device: device, allowWhenDisarmed: allowWhenDisarmed)
            case .both:
                _ = toggleTorch(id: device.id, allowWhenDisarmed: allowWhenDisarmed)
                triggerSound(device: device, allowWhenDisarmed: allowWhenDisarmed)
            }
        }
    }
    
    // MARK: – One-click build & run  🚀
    public func buildAndRun(device: ChoirDevice) {
        let slot = cueSlot(for: device)
        Task.detached {
            let udid  = device.udid
            guard let projectURL = Self.resolveFlutterProjectURL() else {
                await MainActor.run {
                    self.lastLog = "⚠️ Could not locate flashlights_client/ for flutter run"
                }
                return
            }

            /// Construct: flutter run -d <UDID> --release --dart-define=SLOT=<N>
            let args  = ["run",
                         "-d", udid,
                         "--release",
                         "--dart-define=SLOT=\(slot)"]

            let proc = Process()
            proc.launchPath = "/usr/bin/env"
            proc.arguments  = ["flutter"] + args
            proc.currentDirectoryURL = projectURL

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
    public func triggerSound(device: ChoirDevice, allowWhenDisarmed: Bool = false) {
        guard ensureCueAuthorized("triggering sound", allowWhenDisarmed: allowWhenDisarmed) else { return }
        guard !device.isPlaceholder else { return }

        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                // --- Cross-actor property: broadcasterTask ---
                let oscBroadcaster = try await self.broadcasterTask.value

                let slotNumber = device.listeningSlot
                let slot = Int32(slotNumber)
                let gain: Float32 = 1.0
                let startAtMs = Date().timeIntervalSince1970 * 1000.0 + self.primerLeadTimeMs

                // --- Collect main-actor data once, then use it ---
                let toneSets: [String] = await MainActor.run {
                    let raw = self.activeToneSets
                    return raw.isEmpty ? ["A"] : raw.sorted()
                }

                for set in toneSets {
                    let prefix = set.lowercased()
                    let file = "\(prefix)\(slotNumber).mp3"

                    let message = AudioPlay(index: slot,
                                             file: file,
                                             gain: gain,
                                             startAtMs: startAtMs)
                    try await oscBroadcaster.send(
                        message,
                        allowWhenDisarmed: allowWhenDisarmed
                    )

                    await MainActor.run {
                        self.lastLog = "/audio/play \(slotNumber) \(file)"
                    }

                    // --- Cross-actor property: midi ---
                    let noteBase = slotNumber * 4
                    let noteOffset: Int = switch set.lowercased() {
                        case "a": 0
                        case "b": 1
                        case "c": 2
                        default:  3
                    }
                    await self.midi.sendNoteOn(UInt8(noteBase + noteOffset), velocity: 127)
                }

                // --- Cross-actor call: glow ---
                await self.glow(slot: slotNumber)
            } catch {
                await MainActor.run {
                    self.lastLog = "⚠️ Cue blocked or failed: \(error.localizedDescription)"
                }
            }
        }
    }
    /// Play audio on all devices slots based on current activeToneSets
    public func playAllTones() {
        guard ensureArmedForCue("triggering tones") else { return }
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
        let canonical = canonicalSlots
        let maxSlot = max(canonical.max() ?? devices.count, devices.count)

        if maxSlot > devices.count {
            for slot in (devices.count + 1)...maxSlot {
                let isKnownReal = canonical.contains(slot)
                let dev = ChoirDevice(
                    id: slot - 1,
                    udid: "",
                    name: "",
                    midiChannels: ChoirDevice.defaultChannelMap[slot] ?? [10],
                    isPlaceholder: !isKnownReal
                )
                devices.append(dev)
                statuses[slot - 1] = .clean
            }
        }

        let snapshot = devices

        for idx in devices.indices {
            let slot = idx + 1
            var device = devices[idx]
            let previous = snapshot[idx]
            let mapping = dict[String(slot)]

            if !canonical.contains(slot) {
                if mapping != nil {
                    print("[ConsoleState] Ignoring mapping entry for placeholder slot #\(slot)")
                }
                device.isPlaceholder = true
                device.ip = ""
                device.udid = ""
                device.name = previous.name
                device.midiChannels = previous.midiChannels
                device.listeningSlot = previous.listeningSlot
                devices[idx] = device
                continue
            }

            device.isPlaceholder = false
            device.listeningSlot = slot
            device.midiChannels = ChoirDevice.defaultChannelMap[slot] ?? previous.midiChannels

            if let mapping {
                device.ip = mapping.ip
                device.udid = mapping.udid
                device.name = mapping.name
            } else {
                device.ip = previous.ip
                device.udid = previous.udid
                device.name = previous.name
            }

            devices[idx] = device
        }

        updateAnyTorchOn()
        sanitizeGroupMembers()
    }
    /// Stop playback of sound on a specific device slot (send audio/stop)
    public func stopSound(device: ChoirDevice, allowWhenDisarmed: Bool = true) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        guard !devices[idx].isPlaceholder else { return }
        let slotNumber = cueSlot(for: device)
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let osc = try await self.broadcasterTask.value
                let slot = Int32(slotNumber)
                try await osc.send(
                    AudioStop(index: slot),
                    allowWhenDisarmed: allowWhenDisarmed
                )
                await MainActor.run { self.lastLog = "/audio/stop [\(slot)]" }
                let noteBase = slotNumber * 4
                for offset in 0..<4 {
                    await self.midi.sendNoteOff(UInt8(noteBase + offset))
                }
            } catch {
                print("Error stopping sound for slot \(slotNumber): \(error)")
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
                        do { try await osc.send(FlashOn(index: Int32(self.cueSlot(for: d)), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(attack) * 1_000_000 / UInt64(steps))
                }
                // Decay to sustain
                let sustainLevel = Float32(sustainParam) / 100
                for i in 0...steps {
                    let t = Float32(i) / Float32(steps)
                    let intensity = (1 - t) + t * sustainLevel
                    for d in devicesList where !d.isPlaceholder {
                        do { try await osc.send(FlashOn(index: Int32(self.cueSlot(for: d)), intensity: intensity)) } catch {}
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
                        do { try await osc.send(FlashOn(index: Int32(self.cueSlot(for: d)), intensity: intensity)) } catch {}
                    }
                    try await Task.sleep(nanoseconds: UInt64(releaseDur) * 1_000_000 / UInt64(steps))
                }
                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(self.cueSlot(for: d)))) } catch {}
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
                            FlashOn(index: Int32(self.cueSlot(for: d)), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(self.cueSlot(for: d)))) } catch {}
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
                            FlashOn(index: Int32(self.cueSlot(for: d)), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(self.cueSlot(for: d)))) } catch {}
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
                            FlashOn(index: Int32(self.cueSlot(for: d)), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(self.cueSlot(for: d)))) } catch {}
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
                            FlashOn(index: Int32(self.cueSlot(for: d)), intensity: Float32(intensity))
                        )
                    }

                    phase += twoPi * oscillationHz / updateHz
                    if phase >= twoPi { phase -= twoPi }

                    try? await Task.sleep(nanoseconds: updateIntervalNs)
                }

                for d in devicesList where !d.isPlaceholder {
                    do { try await osc.send(FlashOff(index: Int32(self.cueSlot(for: d)))) } catch {}
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
        let slot = cueSlot(for: device)
        Task.detached {
            guard let projectURL = Self.resolveFlutterProjectURL() else {
                await MainActor.run {
                    self.statuses[device.id] = .buildFailed
                    self.lastLog = "⚠️ Could not locate flashlights_client/ for flutter build"
                }
                return
            }
            let args = ["build", "ios", "--release", "--dart-define=SLOT=\(slot)"]
            let proc = Process()
            proc.launchPath = "/usr/bin/env"
            proc.arguments = ["flutter"] + args
            proc.currentDirectoryURL = projectURL
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
        guard let projectURL = Self.resolveFlutterProjectURL() else {
            statuses[device.id] = .runFailed
            lastLog = "⚠️ Could not locate flashlights_client/ for flutter run"
            return
        }
        // terminate any existing run process
        if let prev = runProcesses[device.id] {
            prev.terminate()
            runProcesses[device.id] = nil
        }
        let slot = cueSlot(for: device)
        let args = ["run", "-d", device.udid, "--release", "--dart-define=SLOT=\(slot)"]
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["flutter"] + args
        proc.currentDirectoryURL = projectURL
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
        guard ensureArmedForCue("sending cues") else { return devices }
        for idx in devices.indices where !devices[idx].isPlaceholder {
            devices[idx].torchOn = true
            let slot = cueSlot(for: devices[idx])
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let osc = try await self.broadcasterTask.value
                    try await osc.send(FlashOn(index: Int32(slot), intensity: 1))
                } catch {
                    print("Error sending FlashOn for slot \(slot): \(error)")
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
        }
        panicAllStop()
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
        Task { [diagnostics] in
            await diagnostics.record(
                .slotAssignmentRequested,
                slot: slot,
                message: "Manual slot assignment for device #\(device.id + 1)"
            )
        }
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
    func deviceDiscovered(slot: Int, ip: String, deviceId: String?) {
        guard slot > 0 && slot <= devices.count else { return }
        guard canonicalSlots.contains(slot) else {
            Task { [diagnostics] in
                await diagnostics.record(
                    .unknownSender,
                    slot: slot,
                    ipAddress: ip,
                    message: "Ignored /hello for non-performance slot"
                )
            }
            return
        }
        let idx = resolvedDeviceIndex(forDiscoveredSlot: slot, deviceId: deviceId) ?? (slot - 1)
        guard devices.indices.contains(idx) else { return }
        devices[idx].ip = ip
        if let deviceId, !deviceId.isEmpty {
            devices[idx].udid = deviceId
        }
        devices[idx].listeningSlot = slot
        statuses[devices[idx].id] = .live
        lastHello[slot] = Date()
        lastHelloProbe.removeValue(forKey: slot)
        lastLog = "📳 Device \(slot) announced at \(ip)"
    }
}

// MARK: - Lifecycle helpers

extension ConsoleState {
    private func resolvedDeviceIndex(forDiscoveredSlot slot: Int, deviceId: String?) -> Int? {
        if let deviceId, !deviceId.isEmpty,
           let idx = devices.firstIndex(where: { $0.udid == deviceId }) {
            return idx
        }
        if let idx = devices.firstIndex(where: { !$0.isPlaceholder && $0.listeningSlot == slot }) {
            return idx
        }
        let fallback = slot - 1
        guard devices.indices.contains(fallback) else { return nil }
        return fallback
    }

    nonisolated private static func resolveFlutterProjectURL() -> URL? {
        let fileManager = FileManager.default
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ViewModel
            .deletingLastPathComponent() // FlashlightsInTheDark_MacOS
            .deletingLastPathComponent() // repo root

        let initialCandidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.resourceURL,
            sourceRoot
        ].compactMap { $0 }

        var seen = Set<String>()
        for candidate in initialCandidates {
            var cursor = candidate
            for _ in 0..<6 {
                let repoCandidate = cursor.appendingPathComponent("flashlights_client", isDirectory: true)
                let pubspec = repoCandidate.appendingPathComponent("pubspec.yaml")
                if fileManager.fileExists(atPath: pubspec.path) {
                    return repoCandidate
                }

                let directPubspec = cursor.appendingPathComponent("pubspec.yaml")
                if cursor.lastPathComponent == "flashlights_client",
                   fileManager.fileExists(atPath: directPubspec.path) {
                    return cursor
                }

                let key = cursor.standardizedFileURL.path
                if !seen.insert(key).inserted {
                    break
                }

                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path {
                    break
                }
                cursor = parent
            }
        }

        return nil
    }

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
        showSessionId = UUID().uuidString
        isArmed = false
        preflightWarning = nil
        lastLog = "🛰  Starting conductor session \(showSessionId.prefix(8))"
        do {
            let broadcaster = try await broadcasterTask.value
            await broadcaster.registerHelloHandler { [weak self] slot, ip, udid in
                Task { @MainActor in
                    self?.deviceDiscovered(slot: slot, ip: ip, deviceId: udid)
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
            await broadcaster.configureConcert(
                showSessionId: showSessionId,
                protocolVersion: Int32(protocolVersion),
                expectedDeviceCount: expectedDeviceCount
            )
            await broadcaster.setArmed(isArmed)
            try await broadcaster.start()

            heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatTimerInterval, repeats: true) { [weak self] _ in
                self?.checkHeartbeats()
            }
            scheduleDiscoveryRefreshTimer()
            startConductorHelloLoop()
            startMetricsLoop()
            lastLog = "🛰  Session \(showSessionId.prefix(8)) live · SAFE"
        } catch let err as POSIXError where err.code == .EHOSTDOWN {
            lastLog = "⚠️ No active network interface"
            isBroadcasting = false
        } catch {
            lastLog = "⚠️ Network start failed: \(error)"
            isBroadcasting = false
        }
    }

    /// Gracefully cancel background tasks when the app resigns active.
    @MainActor
    public func shutdown() {
        isBroadcasting = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        conductorHelloTimer?.invalidate()
        conductorHelloTimer = nil
        conductorHelloStartedAt = nil
        metricsTimer?.invalidate()
        metricsTimer = nil
        discoveryRefreshTimer?.invalidate()
        discoveryRefreshTimer = nil
        discoveryRefreshInFlight = false
        lastDiscoveryRefresh = nil
        isArmed = false
    }

    private func checkHeartbeats() {
        let now = Date()
        for slot in performanceSlots {
            let idx = slot - 1
            guard idx >= 0 && idx < devices.count else { continue }
            let lastSeen = lastHello[slot]
            if let lastSeen {
                let gap = now.timeIntervalSince(lastSeen)
                if gap <= heartbeatGraceInterval {
                    if statuses[idx] == .lostConnection {
                        statuses[idx] = .live
                        Task { [diagnostics] in
                            await diagnostics.record(
                                .heartbeatRecovered,
                                slot: slot,
                                message: "Recovered after \(Int(gap))s gap"
                            )
                        }
                    }
                    continue
                }
            }

            if statuses[idx] != .lostConnection {
                statuses[idx] = .lostConnection
                let gapDescription: String
                if let lastSeen {
                    let gap = now.timeIntervalSince(lastSeen)
                    gapDescription = "\(Int(gap))s without /hello"
                } else {
                    gapDescription = "No /hello received yet"
                }
                Task { [diagnostics] in
                    await diagnostics.record(
                        .heartbeatLost,
                        slot: slot,
                        message: gapDescription
                    )
                }
            }

            let lastProbe = lastHelloProbe[slot] ?? .distantPast
            if now.timeIntervalSince(lastProbe) >= heartbeatProbeSpacing {
                lastHelloProbe[slot] = now
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    do {
                        let broadcaster = try await self.broadcasterTask.value
                        await broadcaster.requestHello(forSlot: slot)
                    } catch {
                        await self.diagnostics.record(
                            .sendFailed,
                            slot: slot,
                            message: "Heartbeat probe error: \(error.localizedDescription)"
                        )
                    }
                }
                triggerDiscoveryRefresh(reason: .slot(slot))
            }
        }
    }

    private func scheduleDiscoveryRefreshTimer() {
        discoveryRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: discoveryRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.triggerDiscoveryRefresh(reason: .periodic)
        }
        timer.tolerance = discoveryRefreshInterval * 0.2
        discoveryRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startConductorHelloLoop() {
        conductorHelloTimer?.invalidate()
        conductorHelloStartedAt = Date()
        sendConductorHelloTick()
        let timer = Timer.scheduledTimer(withTimeInterval: conductorHelloInterval, repeats: true) { [weak self] _ in
            self?.sendConductorHelloTick()
        }
        timer.tolerance = conductorHelloInterval * 0.2
        conductorHelloTimer = timer
    }

    private func sendConductorHelloTick() {
        let connected = connectedPerformanceDeviceCount
        if connected >= expectedDeviceCount {
            preflightWarning = nil
        } else if let started = conductorHelloStartedAt,
                  Date().timeIntervalSince(started) > conductorHandshakeTimeout {
            preflightWarning = "Handshake timeout: \(connected)/\(expectedDeviceCount) connected"
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let broadcaster = try await self.broadcasterTask.value
                try await broadcaster.broadcastConductorHello()
            } catch {
                await self.diagnostics.record(
                    .sendFailed,
                    message: "Conductor /hello failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func startMetricsLoop() {
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshMetricsSnapshot()
        }
        refreshMetricsSnapshot()
    }

    private func refreshMetricsSnapshot() {
        Task.detached { [weak self] in
            guard let self else { return }
            let diagnosticsSnapshot = await self.diagnostics.snapshot()
            let broadcaster = try? await self.broadcasterTask.value
            let routeMetrics: CueSendMetricsSnapshot?
            if let broadcaster {
                routeMetrics = await broadcaster.metricsSnapshot()
            } else {
                routeMetrics = nil
            }

            await MainActor.run {
                self.unknownSenderEvents = diagnosticsSnapshot.unknownSenderCount
                self.totalSendFailures = diagnosticsSnapshot.totalSendFailed
                self.packetRatePerSecond = routeMetrics?.packetsPerSecond ?? diagnosticsSnapshot.packetsPerSecond
                self.interfaceHealthSummary = diagnosticsSnapshot.interfaceSummaries
            }
        }
    }

    private func triggerDiscoveryRefresh(reason: DiscoveryRefreshReason) {
        if discoveryRefreshInFlight { return }

        let now = Date()
        if let last = lastDiscoveryRefresh,
           now.timeIntervalSince(last) < minimumDiscoveryRefreshSpacing,
           reason.shouldRespectSpacing {
            return
        }

        discoveryRefreshInFlight = true
        lastDiscoveryRefresh = now

        if reason.shouldLog {
            lastLog = "🔄 Refreshing connections\(reason.logSuffix)"
            Task { [diagnostics] in
                await diagnostics.record(
                    .manualRefresh,
                    message: "Discovery refresh\(reason.logSuffix)"
                )
            }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let broadcaster = try await self.broadcasterTask.value
                try await broadcaster.discoverKnownDevices()
                await MainActor.run {
                    if reason.shouldLog {
                        self.lastLog = "📡 Connections refreshed\(reason.logSuffix)"
                    }
                    self.discoveryRefreshInFlight = false
                }
                await self.diagnostics.record(
                    .manualRefresh,
                    message: "Discovery refresh\(reason.logSuffix) complete"
                )
            } catch {
                await MainActor.run {
                    self.lastLog = "⚠️ Discovery refresh failed: \(error.localizedDescription)"
                    self.discoveryRefreshInFlight = false
                }
                await self.diagnostics.record(
                    .manualRefresh,
                    message: "Discovery refresh\(reason.logSuffix) failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func performNetworkInterfaceRefresh(reason: String) {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let broadcaster = try await self.broadcasterTask.value
                await self.diagnostics.record(
                    .manualRefresh,
                    message: "Network interface refresh (\(reason))"
                )
                await broadcaster.refreshNetworkInterfaces(reason: reason)
                await self.diagnostics.record(
                    .manualRefresh,
                    message: "Network interface refresh complete (\(reason))"
                )
            } catch {
                await self.diagnostics.record(
                    .manualRefresh,
                    message: "Network interface refresh failed (\(reason)): \(error.localizedDescription)"
                )
                await MainActor.run {
                    self.lastLog = "⚠️ Network interface refresh failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum DiscoveryRefreshReason {
    case periodic
    case manual
    case slot(Int)

    var logSuffix: String {
        switch self {
        case .periodic:
            return ""
        case .manual:
            return " (manual)"
        case let .slot(slot):
            return " · slot #\(slot)"
        }
    }

    var shouldLog: Bool {
        switch self {
        case .periodic:
            return false
        case .manual, .slot:
            return true
        }
    }

    var shouldRespectSpacing: Bool {
        switch self {
        case .manual:
            return false
        case .periodic, .slot:
            return true
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

    /// Last time a client at the specified slot sent a /hello message.
    public func lastHelloDate(forSlot slot: Int) -> Date? {
        lastHello[slot]
    }

    /// Last time a client at the specified slot acknowledged a command.
    public func lastAckDate(forSlot slot: Int) -> Date? {
        lastAckTimes[slot]
    }

    /// Attempts to infer the primary colour group for a slot number.
    public func colorForSlot(_ slot: Int) -> PrimerColor? {
        for color in PrimerColor.allCases {
            if slots(for: color).contains(slot) {
                return color
            }
        }
        return nil
    }

    /// Sends a discovery ping to prompt the specified slot to announce itself.
    public func pingSlot(_ slot: Int) {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                await self.diagnostics.record(
                    .manualRefresh,
                    slot: slot,
                    message: "Manual ping"
                )
                let broadcaster = try await self.broadcasterTask.value
                await broadcaster.requestHello(forSlot: slot)
                await MainActor.run {
                    self.lastLog = "📡 Pinged slot #\(slot)"
                }
            } catch {
                await MainActor.run {
                    self.lastLog = "⚠️ Ping slot #\(slot) failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func refreshConnections() {
        guard isBroadcasting else {
            lastLog = "⚠️ Network is paused"
            return
        }
        performNetworkInterfaceRefresh(reason: "manual UI refresh")
        triggerDiscoveryRefresh(reason: .manual)
    }

    public func exportNetworkLog() {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                await self.diagnostics.record(
                    .manualExport,
                    message: "Export initiated"
                )
                let url = try await self.diagnostics.export()
                await self.diagnostics.record(
                    .manualExport,
                    message: "Exported to \(url.lastPathComponent)"
                )
                await MainActor.run {
                    self.lastLog = "📝 Network log saved to \(url.path)"
                }
            } catch {
                await self.diagnostics.record(
                    .manualExport,
                    message: "Export failed: \(error.localizedDescription)"
                )
                await MainActor.run {
                    self.lastLog = "⚠️ Log export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func networkDiagnosticsSnapshot() async -> NetworkDiagnosticsSnapshot {
        await diagnostics.snapshot()
    }

    public var connectedPerformanceDeviceCount: Int {
        let now = Date()
        return performanceSlots.reduce(into: 0) { count, slot in
            guard let last = lastHello[slot],
                  now.timeIntervalSince(last) <= heartbeatGraceInterval else { return }
            count += 1
        }
    }

    public var canArmStrict: Bool {
        connectedPerformanceDeviceCount >= expectedDeviceCount
    }

    @discardableResult
    public func armConcertMode(override: Bool = false) -> Bool {
        if canArmStrict || override {
            isArmed = true
            preflightWarning = nil
            lastLog = "🔴 ARMED · Session \(showSessionId.prefix(8))"
            return true
        }
        preflightWarning = "Preflight incomplete: \(connectedPerformanceDeviceCount)/\(expectedDeviceCount) connected"
        lastLog = "⚠️ Cannot arm: \(connectedPerformanceDeviceCount)/\(expectedDeviceCount) connected"
        isArmed = false
        return false
    }

    public func disarmConcertMode() {
        isArmed = false
        lastLog = "🟢 SAFE · Cues blocked"
    }

    public func panicAllStop() {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let broadcaster = try await self.broadcasterTask.value
                try await broadcaster.broadcastPanicAllStop()
                await MainActor.run {
                    for idx in self.devices.indices where !self.devices[idx].isPlaceholder {
                        self.devices[idx].torchOn = false
                    }
                    self.updateAnyTorchOn()
                    self.lastLog = "🛑 Panic all-stop broadcast"
                }
            } catch {
                await MainActor.run {
                    self.lastLog = "⚠️ Panic all-stop failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func triggerCurrentEvent(advanceAfterTrigger: Bool = true) {
        guard ensureArmedForCue("triggering events") else { return }
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
        moveEvents(by: 1)
    }

    public func moveToPreviousEvent() {
        moveEvents(by: -1)
    }

    public func moveEvents(by offset: Int) {
        guard !eventRecipes.isEmpty, offset != 0 else { return }
        let target = currentEventIndex + offset
        let clamped = min(max(target, 0), eventRecipes.count - 1)
        currentEventIndex = clamped
    }

    public func focusOnEvent(id: Int) {
        if let idx = eventRecipes.firstIndex(where: { $0.id == id }) {
            currentEventIndex = idx
        }
    }

    private func fire(event: EventRecipe) async {
        let startAtMs = Date().timeIntervalSince1970 * 1000.0 + primerLeadTimeMs
        if !event.primerAssignments.isEmpty {
            primerAudioEngine.play(assignments: event.primerAssignments, startAt: startAtMs)
        }
        await sendEventTriggers(for: event, startAtMs: startAtMs)
        let measureText = event.measure.map { "M\($0)" } ?? "M?"
        let beatText = event.position ?? "?"
        await MainActor.run {
            lastLog = "▶︎ Event #\(event.id) • \(measureText) • \(beatText)"
        }
    }

    private func sendEventTriggers(for event: EventRecipe, startAtMs: Double) async {
        guard !event.primerAssignments.isEmpty, isBroadcasting else { return }
        do {
            let broadcaster = try await broadcasterTask.value
            for color in event.primerAssignments.keys.sorted(by: { $0.groupIndex < $1.groupIndex }) {
                let targetSlots = slots(for: color).sorted()
                guard !targetSlots.isEmpty else { continue }
                for slot in targetSlots {
                    let msg = EventTrigger(index: Int32(slot),
                                           eventId: Int32(event.id),
                                           startAtMs: startAtMs)
                    try await broadcaster.send(msg)
                }
            }
            if let fileName = event.primerAssignments.first?.value.oscFileName {
                await MainActor.run {
                    self.lastLog = "▶︎ Sent event triggers for Event #\(event.id) (\(fileName))"
                }
            }
        } catch {
            await MainActor.run {
                lastLog = "⚠️ Failed to send event: \(error.localizedDescription)"
            }
        }
    }

    func slots(for color: PrimerColor) -> [Int] {
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
            let startAtMs = Date().timeIntervalSince1970 * 1000.0 + primerLeadTimeMs
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
                                try await osc.send(AudioPlay(index: Int32(slot), file: fileName, gain: 1.0, startAtMs: startAtMs))
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
            let startAtMs = Date().timeIntervalSince1970 * 1000.0 + primerLeadTimeMs

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
                            try await osc.send(AudioPlay(index: Int32(slot), file: fileName, gain: 1.0, startAtMs: startAtMs))
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
                                try await osc.send(FlashOn(index: Int32(self.cueSlot(for: device)), intensity: intensity))
                            } else {
                                try await osc.send(FlashOff(index: Int32(self.cueSlot(for: device))))
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
