import SwiftUI
import AppKit

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState
    
    private struct StaffModule: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let slots: [Int]
        
        var slotSummary: String {
            slots.map(String.init).joined(separator: " · ")
        }
    }
    
    private let staffModules: [StaffModule] = [
        StaffModule(id: "sop-l1", title: "Sop-L1", accent: .slotGreen, slots: [16, 29, 44]),
        StaffModule(id: "sop-l2", title: "Sop-L2", accent: .hotMagenta, slots: [12, 24, 25, 23, 38, 51]),
        StaffModule(id: "ten-l", title: "Ten-L", accent: .slotYellow, slots: [7, 19, 34]),
        StaffModule(id: "bass-l", title: "Bass-L", accent: .lightRose, slots: [9, 20, 21, 3, 4, 18]),
        StaffModule(id: "alto-l2", title: "Alto-L2", accent: .brightRed, slots: [1, 14, 15, 40, 53, 54]),
        StaffModule(id: "alto-l1", title: "Alto-L1", accent: .royalBlue, slots: [27, 41, 42])
    ]

    /// Returns true if any device's torch is currently on
    private var anyTorchOn: Bool {
        state.devices.contains { $0.torchOn }
    }
    private var preflightLabel: String {
        "\(state.connectedPerformanceDeviceCount)/\(state.expectedDeviceCount) connected"
    }
    @State private var showRouting: Bool = false

    // Strobe effect state
    @State private var strobeOn: Bool = false
    private let columns = Array(repeating: GridItem(.flexible()), count: 8)
    // Mapping from keyboard key to real slot number
    private static let keyToSlot = KeyboardKeyToSlot
    // Reverse lookup so each slot can display its bound key
    private var keyLabels: [Int: String] {
        Dictionary(uniqueKeysWithValues: Self.keyToSlot.map { ($0.value, String($0.key)) })
    }
    // Mapper converting typed characters to MIDI note numbers
    private var typingMapper = TypingMidiMapper(keyToSlot: Self.keyToSlot)
    private let slotRows: [[Int]] = [
        Array(1...12),
        Array(13...26),
        Array(27...40),
        Array(41...54)
    ]

    private let slotOutlineColors: [Int: Color] = [
        27: .royalBlue, 41: .royalBlue, 42: .royalBlue,
        1: .brightRed, 14: .brightRed, 15: .brightRed,
        16: .slotGreen, 29: .slotGreen, 44: .slotGreen,
        3: .slotPurple, 4: .slotPurple, 18: .slotPurple,
        7: .slotYellow, 19: .slotYellow, 34: .slotYellow,
        9: .lightRose, 20: .lightRose, 21: .lightRose,
        23: .slotOrange, 38: .slotOrange, 51: .slotOrange,
        12: .hotMagenta, 24: .hotMagenta, 25: .hotMagenta,
        40: .skyBlue, 53: .skyBlue, 54: .skyBlue,
        5: .white
    ]

    private let tripleTriggers: [Int: [Int]] = [
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

    private let tripleColors: [Int: Color] = [
        1: .royalBlue,
        2: .brightRed,
        3: .slotGreen,
        4: .slotPurple,
        5: .slotYellow,
        6: .lightRose,
        7: .slotOrange,
        8: .hotMagenta,
        9: .skyBlue
    ]

    private let tripleLabels: [Int: String] = [
        1: "Blue",
        2: "Red",
        3: "Green",
        4: "Purple",
        5: "Yellow",
        6: "Pink",
        7: "Orange",
        8: "Magenta",
        9: "Cyan"
    ]

    /// Human readable labels for MIDI channels
    private static let channelLabels: [Int: String] = [
        1: "primerTones Blue",
        2: "primerTones Red",
        3: "primerTones Green",
        4: "primerTones Purple",
        5: "primerTones Yellow",
        6: "primerTones Pink",
        7: "primerTones Orange",
        8: "primerTones Magenta",
        9: "primerTones Cyan",
        10: "torchSignals",
        11: "seLeft:0-127",
        12: "seLeft:128-255",
        13: "seCenter:0-127",
        14: "seCenter:128-255",
        15: "seRight:0-127",
        16: "seRight:128-255"
    ]

    @State private var leftPanelWidth: CGFloat = 300
    @State private var startLeftPanelWidth: CGFloat?
    @State private var midiLogHeight: CGFloat = 100
    @State private var startMidiLogHeight: CGFloat?
    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                // Envelope & tone-set controls
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        Stepper("Attack: \(state.attackMs) ms", value: $state.attackMs, in: 0...2000, step: 50)
                        Stepper("Decay: \(state.decayMs) ms", value: $state.decayMs, in: 0...2000, step: 50)
                        Stepper("Sustain: \(state.sustainPct)%", value: $state.sustainPct, in: 0...100, step: 10)
                        Stepper("Release: \(state.releaseMs) ms", value: $state.releaseMs, in: 0...2000, step: 50)
                    }
                    HStack {
                        Button("0 Envelope") { state.startEnvelopeAll() }
                            .buttonStyle(.borderedProminent)
                        Button("Release Envelope") { state.releaseEnvelopeAll() }
                            .buttonStyle(.bordered)
                    }
                    Divider()
                    Text("Tone Sets:") .font(.headline)
                    // Mapping of set identifier to display label
                    let toneLabels = ["A": "pT",
                                      "B": "seL",
                                      "C": "seC",
                                      "D": "seR"]
                    let colorGroups = ["A": "primerTones[0-48:short, 50-98:long]",
                                       "B": "Blue, Red, Green",
                                       "C": "Purple, Yellow, Pink",
                                       "D": "Orange, Magenta, Cyan"]
                    // Primer tones button
                    HStack(alignment: .center, spacing: 6) {
                        Button(action: {
                            if state.activeToneSets.contains("A") {
                                state.activeToneSets.remove("A")
                            } else {
                                state.activeToneSets.insert("A")
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(state.activeToneSets.contains("A")
                                          ? Color.accentColor
                                          : Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                Text(toneLabels["A"]!)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Toggle tone set primerTones")
                        Text(colorGroups["A"]!)
                            .font(.caption)
                    }
                    // Sound Events group
                    HStack(alignment: .center, spacing: 4) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(["B", "C", "D"], id: \.self) { set in
                                HStack(alignment: .center, spacing: 6) {
                                    Button(action: {
                                        if state.activeToneSets.contains(set) {
                                            state.activeToneSets.remove(set)
                                        } else {
                                            state.activeToneSets.insert(set)
                                        }
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(state.activeToneSets.contains(set)
                                                      ? Color.accentColor
                                                      : Color.gray.opacity(0.3))
                                                .frame(width: 40, height: 40)
                                            Text(toneLabels[set]!)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help("Toggle tone set \(toneLabels[set]!)")
                                    Text(colorGroups[set]!)
                                        .font(.caption)
                                }
                            }
                        }
                        VStack(spacing: 0) {
                            Text("⎫")
                            Text("⎬")
                            Text("⎭")
                        }
                        .font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound Events")
                                .font(.subheadline)
                            Text("(0-255:LCR)")
                                .font(.caption)
                        }
                    }
                    // Typing keyboard trigger mode selection
                    Divider()
                    Text("Typing Keyboard Mode:")
                        .font(.headline)
                    HStack(spacing: 12) {
                        ForEach(ConsoleState.KeyboardTriggerMode.allCases, id: \.self) { mode in
                            Button(action: { state.keyboardTriggerMode = mode }) {
                                ZStack {
                                    Circle()
                                        .fill(state.keyboardTriggerMode == mode
                                              ? Color.accentColor
                                              : Color.gray.opacity(0.3))
                                        .frame(width: 40, height: 40)
                                    Group {
                                        if mode == .torch {
                                            Image(systemName: "flashlight.on.fill")
                                        } else if mode == .sound {
                                            Image(systemName: "speaker.wave.2.fill")
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "flashlight.on.fill")
                                                Image(systemName: "speaker.wave.2.fill")
                                            }
                                        }
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Keyboard: \(mode.rawValue)")
                        }
                    }
                    Divider()
                    Text("Audio Output:")
                        .font(.headline)
                    Picker("Device", selection: $state.selectedAudioDeviceID) {
                        Text("System Default").tag(UInt32(0))
                        ForEach(state.audioOutputDevices, id: \.id) { device in
                            Text(device.name)
                                .tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .onAppear { state.refreshAudioOutputs() }
                    Button {
                        state.refreshAudioOutputs()
                    } label: {
                        Label("Refresh Outputs", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    Divider()
                    HStack(spacing: 4) {
                        Text("MIDI Controls:")
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .help("Select a Pro Tools MIDI output here to receive cues from your DAW in real time. This app will respond to MIDI notes and mod-wheel (CC1) from your Pro Tools track. Likewise, choosing a Pro Tools input as MIDI Output will send triggers performed here back to your DAW as MIDI events.")
                    }
                    .font(.headline)
                    Picker("MIDI Input", selection: $state.selectedMidiInput) {
                        ForEach(state.midiInputNames, id: \.self) { name in
                            Text(name)
                        }
                    }
                    Picker("MIDI Output", selection: $state.selectedMidiOutput) {
                        ForEach(state.midiOutputNames, id: \.self) { name in
                            Text(name)
                        }
                    }
                    Picker("Output Channel", selection: $state.outputChannel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("\(ch)")
                        }
                    }
                    .onAppear { state.refreshMidiDevices() }
                    Divider()
                    Text("MIDI Log:")
                        .font(.headline)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(state.midiLog.indices, id: \.self) { idx in
                                    Text(state.midiLog[idx])
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Color.clear.frame(height: 1).id("midiBottom")
                            }
                        }
                        .onChange(of: state.midiLog.count) { _ in
                            proxy.scrollTo("midiBottom", anchor: .bottom)
                        }
                        .onAppear {
                            proxy.scrollTo("midiBottom", anchor: .bottom)
                        }
                    }
                    .frame(height: midiLogHeight)
                    .border(Color.gray.opacity(0.3))
                    .overlay(
                        GeometryReader { geo in
                            // grab handle bottom-right
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .resizable()
                                .frame(width: 12, height: 12)
                                .foregroundColor(.secondary)
                                .position(x: geo.size.width - 8, y: geo.size.height - 8)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            if startMidiLogHeight == nil {
                                                startMidiLogHeight = midiLogHeight
                                            }
                                            let newHeight = (startMidiLogHeight ?? midiLogHeight) - value.translation.height
                                            midiLogHeight = max(80, min(newHeight, 500))
                                        }
                                        .onEnded { _ in
                                            startMidiLogHeight = nil
                                        }
                                )
                        }
                    )
                    Spacer()
                }
                .frame(width: leftPanelWidth)
                .padding()
                // Draggable divider
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if startLeftPanelWidth == nil {
                                    startLeftPanelWidth = leftPanelWidth
                                }
                                let newWidth = (startLeftPanelWidth ?? leftPanelWidth) + value.translation.width
                                leftPanelWidth = max(150, min(newWidth, 600))
                            }
                            .onEnded { _ in
                                startLeftPanelWidth = nil
                            }
                    )
                // Main console content
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        // Refresh device list and resend hello packets
                        Button("Refresh") {
                            state.refreshDevices()
                            Task { await state.startNetwork() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        Text(preflightLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(state.canArmStrict ? Color.green.opacity(0.2) : Color.orange.opacity(0.25))
                            .clipShape(Capsule())

                        Text("PPS \(state.packetRatePerSecond, specifier: "%.1f")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Unknown \(state.unknownSenderEvents)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button(state.isArmed ? "DISARM" : "ARM") {
                            if state.isArmed {
                                state.disarmConcertMode()
                            } else {
                                _ = state.armConcertMode()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(state.isArmed ? .red : (state.canArmStrict ? .green : .orange))

                        Button("ARM Override") {
                            _ = state.armConcertMode(override: true)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(state.isArmed || state.canArmStrict)

                        Button("PANIC") {
                            state.panicAllStop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Spacer(minLength: 20)
                        Button(anyTorchOn ? "All Off" : "All On") {
                            state.toggleAllTorches()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(anyTorchOn ? .red : Color.indigo.opacity(0.6))
                        .disabled(!state.isBroadcasting)

                        Button(state.slowGlowRampActive ? "Stop Slow Glow" : "Slow Glow Ramp") {
                            state.slowGlowRampActive.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mintGlow)
                        .disabled(!state.isBroadcasting)
                        Button(state.glowRampActive ? "Stop Glow" : "Glow Ramp") {
                            state.glowRampActive.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mintGlow)
                        .disabled(!state.isBroadcasting)

                        Button(state.slowStrobeActive ? "Stop Medium" : "Medium Strobe") {
                            state.slowStrobeActive.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mintGlow)
                        .disabled(!state.isBroadcasting)

                        Button(state.strobeActive ? "Stop Rapid" : "Rapid Strobe") {
                            state.strobeActive.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mintGlow)
                        .disabled(!state.isBroadcasting)
                        // Play all tones
                        Button("Play All Tones") {
                            state.playAllTones()
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                        .disabled(!state.isBroadcasting)

                        Button("Refresh Connections") {
                            state.refreshConnections()
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                        .disabled(!state.isBroadcasting)
                        .help("Rebinds the UDP socket and rebroadcasts /discover.")

                        Button("Export Network Log") {
                            state.exportNetworkLog()
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .help("Save a JSON log of all network activity to Documents/FlashlightsLogs.")

                        // Open routing control panel
                        Button("Routing") {
                            showRouting = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .disabled(!state.isBroadcasting)
                    }

                    if let warning = state.preflightWarning {
                        Text("⚠️ \(warning)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    // Heading
                    VStack(spacing: 2) {
                        Text("Flashlights in the Dark")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("MIDI-to-ChorusOfSmartphones Control Interface")
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.2))

                    staffModuleSection
                    groupTriggerStripe
                    Spacer(minLength: 8)
                    // Status bar
                    Text(state.lastLog)
                        .font(.caption2)
                        .foregroundStyle(Color.mintGlow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color.deepPurple.ignoresSafeArea())
            }
            
            

            // Routing sheet
            .sheet(isPresented: $showRouting) {
                RoutingView()
                // size to 80% of main screen
                    .frame(
                        width: (NSScreen.main?.visibleFrame.width ?? 1024) * 0.8,
                        height: (NSScreen.main?.visibleFrame.height ?? 768) * 0.8
                    )
                    .environmentObject(state)
            }
            // Overlay effects stacked above console content
            .overlay(
                FullScreenFlashView(strobeActive: state.strobeActive || state.slowStrobeActive || state.glowRampActive || state.slowGlowRampActive, strobeOn: strobeOn)
                    .environmentObject(state)
            )
            .overlay(
                ColorOverlayVeil()
            )
            .overlay(
                KeyCaptureView(
                    isEnabled: state.isKeyCaptureEnabled,
                    onKeyDown: { char in
                        Task { @MainActor in
                            handleTypingKeyDown(char)
                        }
                    },
                    onKeyUp: { char in
                        Task { @MainActor in
                            handleTypingKeyUp(char)
                        }
                    },
                    onSpecialKeyDown: { event in
                        Task { @MainActor in
                            handleSpecialKeyDown(event)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            // Routing sheet
            .sheet(isPresented: $showRouting) {
                RoutingView()
                // size to 80% of main screen
                    .frame(
                        width: (NSScreen.main?.visibleFrame.width ?? 1024) * 0.8,
                        height: (NSScreen.main?.visibleFrame.height ?? 768) * 0.8
                    )
                    .environmentObject(state)
            }
            // Always-on purple/navy veil overlay
            Color.purpleNavy
                // Subtler overlay to reduce intensity
                .opacity(0.1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(1)
        }
        // Respond to strobe state changes
        .onChange(of: state.strobeActive) { _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.slowStrobeActive) { _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.glowRampActive) { _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.slowGlowRampActive) { _ in
            updateStrobeAnimation()
        }
    }

    private func updateStrobeAnimation() {
        let isActive = state.strobeActive || state.slowStrobeActive || state.glowRampActive || state.slowGlowRampActive
        let duration: Double = {
            if state.strobeActive { return 0.1 }
            if state.slowStrobeActive { return 0.4 }
            if state.glowRampActive { return 0.8 }
            if state.slowGlowRampActive { return 1.6 }
            return 0.1
        }()
        if isActive {
            withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: true)) {
                strobeOn.toggle()
            }
        } else {
            strobeOn = false
        }
    }

    @MainActor
    private func handleTypingKeyDown(_ char: Character) {
        switch char {
        case " ":
            state.triggerCurrentEvent()
            return
        case "]":
            state.glowRampActive.toggle()
            return
        case "[":
            state.slowGlowRampActive.toggle()
            return
        case "\\":
            state.toggleAllTorches()
            return
        case "=":
            state.strobeActive.toggle()
            return
        case "-":
            state.slowStrobeActive.toggle()
            return
        default:
            break
        }

        if let note = typingMapper.note(for: char) {
            let slot = Int(note)
            state.addTriggeredSlot(slot)
            state.typingNoteOn(note)
        }
    }

    @MainActor
    private func handleTypingKeyUp(_ char: Character) {
        if let note = typingMapper.note(for: char) {
            let slot = Int(note)
            state.removeTriggeredSlot(slot)
            state.typingNoteOff(note)
        }
    }

    @MainActor
    private func handleSpecialKeyDown(_ event: NSEvent) {
        guard let key = event.specialKey else { return }
        let modifiers = event.modifierFlags
        switch key {
        case .leftArrow:
            if modifiers.contains(.shift) {
                state.moveEvents(by: -10)
            } else {
                state.moveToPreviousEvent()
            }
        case .rightArrow:
            if modifiers.contains(.shift) {
                state.moveEvents(by: 10)
            } else {
                state.moveToNextEvent()
            }
        default:
            break
        }
    }

    private var staffModuleSection: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 150), spacing: 16), count: 6),
            spacing: 16
        ) {
            ForEach(staffModules) { module in
                StaffModuleCard(
                    module: module,
                    devices: orderedDevices(for: module),
                    connectedCount: connectedDeviceCount(for: module),
                    hasTorch: orderedDevices(for: module).contains(where: \.torchOn),
                    hasAudio: orderedDevices(for: module).contains(where: \.audioPlaying),
                    isTriggered: module.slots.contains(where: { state.triggeredSlots.contains($0) || state.glowingSlots.contains($0) }),
                    hasTargets: !actionDevices(for: module).isEmpty,
                    onTorch: { toggleModuleTorch(module) },
                    onSound: { triggerModuleSound(module) },
                    onBoth: { triggerModule(module) }
                )
                .environmentObject(state)
            }
        }
    }

    private func orderedDevices(for module: StaffModule) -> [ChoirDevice] {
        state.devices
            .filter { !$0.isPlaceholder && module.slots.contains($0.listeningSlot) }
            .sorted { lhs, rhs in
                let lhsIndex = module.slots.firstIndex(of: lhs.listeningSlot) ?? .max
                let rhsIndex = module.slots.firstIndex(of: rhs.listeningSlot) ?? .max
                return lhsIndex < rhsIndex
            }
    }

    private func actionDevices(for module: StaffModule) -> [ChoirDevice] {
        orderedDevices(for: module).filter { device in
            let status = state.statuses[device.id] ?? .clean
            return status == .live || !device.ip.isEmpty
        }
    }

    private func connectedDeviceCount(for module: StaffModule) -> Int {
        orderedDevices(for: module).reduce(into: 0) { count, device in
            if (state.statuses[device.id] ?? .clean) == .live {
                count += 1
            }
        }
    }

    private func toggleModuleTorch(_ module: StaffModule) {
        for device in actionDevices(for: module) {
            _ = state.toggleTorch(id: device.id, allowWhenDisarmed: true)
        }
    }

    private func triggerModuleSound(_ module: StaffModule) {
        for device in actionDevices(for: module) {
            state.triggerSound(device: device, allowWhenDisarmed: true)
        }
    }

    private func triggerModule(_ module: StaffModule) {
        switch state.keyboardTriggerMode {
        case .torch:
            toggleModuleTorch(module)
        case .sound:
            triggerModuleSound(module)
        case .both:
            toggleModuleTorch(module)
            triggerModuleSound(module)
        }
    }

#if DEBUG
    struct ComposerConsoleView_Previews: PreviewProvider {
        static var previews: some View {
            ComposerConsoleView()
                .environmentObject(ConsoleState())
        }
    }
#endif


    private var groupTriggerStripe: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(staffModules) { module in
                    Button(module.title) {
                        triggerModule(module)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(module.accent)
                    .controlSize(.large)
                    .disabled(actionDevices(for: module).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            EventTriggerStrip()
                .environmentObject(state)
        }
    }

    private struct StaffModuleCard: View {
        @EnvironmentObject var state: ConsoleState

        let module: StaffModule
        let devices: [ChoirDevice]
        let connectedCount: Int
        let hasTorch: Bool
        let hasAudio: Bool
        let isTriggered: Bool
        let hasTargets: Bool
        let onTorch: () -> Void
        let onSound: () -> Void
        let onBoth: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(module.title)
                        .font(.headline)
                    Spacer()
                    Text("\(connectedCount)/\(devices.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(connectedCount > 0 ? Color.mintGlow : .secondary)
                }

                Text("Slots \(module.slotSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(hasTorch ? "Torch on" : "Torch idle", systemImage: hasTorch ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.caption2)
                    Label(hasAudio ? "Audio" : "Idle", systemImage: "speaker.wave.2.fill")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    ForEach(devices) { device in
                        ModuleMemberBadge(
                            slot: device.listeningSlot,
                            status: state.statuses[device.id] ?? .clean,
                            accent: module.accent,
                            torchOn: device.torchOn,
                            audioPlaying: device.audioPlaying
                        )
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        onTorch()
                    } label: {
                        Image(systemName: "flashlight.on.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(module.accent)
                    .disabled(!hasTargets)

                    Button {
                        onSound()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(module.accent)
                    .disabled(!hasTargets)

                    Button("Both") {
                        onBoth()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(module.accent)
                    .disabled(!hasTargets)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(module.accent.opacity(isTriggered || hasTorch || hasAudio ? 0.95 : 0.45), lineWidth: 2)
            )
            .shadow(
                color: module.accent.opacity(isTriggered || hasTorch || hasAudio ? 0.35 : 0.12),
                radius: isTriggered || hasTorch || hasAudio ? 18 : 10
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture {
                guard hasTargets else { return }
                onBoth()
            }
        }
    }

    private struct ModuleMemberBadge: View {
        let slot: Int
        let status: DeviceStatus
        let accent: Color
        let torchOn: Bool
        let audioPlaying: Bool

        var body: some View {
            VStack(spacing: 4) {
                Circle()
                    .fill(torchOn ? accent : status.color.opacity(0.7))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(audioPlaying ? 1 : 0.35), lineWidth: audioPlaying ? 2 : 1)
                    )
                Text("\(slot)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Slot Cell View
    struct SlotCell: View {
        @EnvironmentObject var state: ConsoleState
        let device: ChoirDevice
        let keyLabel: String?
        let outline: Color?
        let isTriggered: Bool

        /// Convenience accessors for the device’s status text & color
        private var statusText: String {
            state.statuses[device.id]?.rawValue ?? ""
        }
        private var statusColor: Color {
            state.statuses[device.id]?.color ?? .clear
        }

        var body: some View {
            if device.isPlaceholder {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        if let keyLabel = keyLabel {
                            Text(keyLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "flashlight.on.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(device.torchOn ? Color.mintGlow : .gray)
                            .shadow(color: device.torchOn ? Color.mintGlow.opacity(0.9) : .clear,
                                    radius: device.torchOn ? 12 : 0)
                        Text("#\(device.id + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(device.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                        Button {
                            state.triggerSound(device: device, allowWhenDisarmed: true)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(Color.mintGlow)
                                .help("Trigger sound on \(device.name)…")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(outline ?? .clear, lineWidth: 3)
                            .shadow(color: outline?.opacity(0.8) ?? .clear, radius: 12)
                    )
                    .overlay(
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.95), .clear]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 36
                                    )
                                )
                            LightRaysView(color: .mintGlow)
                        }
                        .opacity((isTriggered || device.torchOn || state.glowingSlots.contains(device.listeningSlot)) ? 1 : 0)
                        .allowsHitTesting(false)
                    )
                    Menu {
                        ForEach(1...16, id: \.self) { ch in
                            Button(action: { state.toggleDeviceChannel(device.id, ch) }) {
                                ChannelMenuItem(channel: ch, selected: device.midiChannels.contains(ch))
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .menuIndicator(.hidden)
                    .help("Assign MIDI channel for this slot")
                    .padding(4)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    switch state.keyboardTriggerMode {
                    case .torch:
                        state.toggleTorch(id: device.id, allowWhenDisarmed: true)
                    case .sound:
                        state.triggerSound(device: device, allowWhenDisarmed: true)
                    case .both:
                        state.toggleTorch(id: device.id, allowWhenDisarmed: true)
                        state.triggerSound(device: device, allowWhenDisarmed: true)
                    }
                }
            }
        }
    }

    private struct LightRaysView: View {
        var color: Color
        var body: some View {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [color.opacity(0.8), .clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2, height: 24)
                        .offset(y: -12)
                        .rotationEffect(.degrees(Double(i) / 8 * 360))
                }
            }
        }
    }

    /// Menu item for channel selection with trailing checkmark
    private struct ChannelMenuItem: View {
        var channel: Int
        var selected: Bool

        var body: some View {
            HStack {
                if let label = ComposerConsoleView.channelLabels[channel] {
                    Text("Ch \(channel) (\(label))")
                } else {
                    Text("Ch \(channel)")
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Keyboard event capture for typing-trigger
    fileprivate struct KeyCaptureView: NSViewRepresentable {
        var isEnabled: Bool
        var onKeyDown: (Character) -> Void
        var onKeyUp: (Character) -> Void
        var onSpecialKeyDown: ((NSEvent) -> Void)? = nil
        var onSpecialKeyUp: ((NSEvent) -> Void)? = nil
        
        func makeNSView(context: Context) -> KeyCaptureNSView {
            let view = KeyCaptureNSView()
            view.isEnabled = isEnabled
            view.onKeyDown = onKeyDown
            view.onKeyUp = onKeyUp
            view.onSpecialKeyDown = onSpecialKeyDown
            view.onSpecialKeyUp = onSpecialKeyUp
            return view
        }
        
        func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
            nsView.isEnabled = isEnabled
        }
    }
    
    fileprivate class KeyCaptureNSView: NSView {
        var isEnabled: Bool = true {
            didSet {
                if isEnabled {
                    window?.makeFirstResponder(self)
                } else if window?.firstResponder == self {
                    _ = window?.makeFirstResponder(nil)
                }
            }
        }
        var onKeyDown: ((Character) -> Void)?
        var onKeyUp: ((Character) -> Void)?
        var onSpecialKeyDown: ((NSEvent) -> Void)?
        var onSpecialKeyUp: ((NSEvent) -> Void)?
        
        override var acceptsFirstResponder: Bool { isEnabled }
        override func resignFirstResponder() -> Bool { true }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if isEnabled {
                window?.makeFirstResponder(self)
            }
        }
        
        override func keyDown(with event: NSEvent) {
            guard isEnabled else {
                nextResponder?.keyDown(with: event)
                return
            }
            if event.specialKey != nil {
                onSpecialKeyDown?(event)
                _ = window?.makeFirstResponder(self)
                return
            }
            if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first {
                onKeyDown?(c)
            }
            _ = window?.makeFirstResponder(self)
        }
        
        override func keyUp(with event: NSEvent) {
            guard isEnabled else {
                nextResponder?.keyUp(with: event)
                return
            }
            if event.specialKey != nil {
                onSpecialKeyUp?(event)
                _ = window?.makeFirstResponder(self)
                return
            }
            if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first {
                onKeyUp?(c)
            }
            _ = window?.makeFirstResponder(self)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
