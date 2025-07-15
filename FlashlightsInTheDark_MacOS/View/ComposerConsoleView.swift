import SwiftUI
import AppKit

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState
    /// Returns true if any device's torch is currently on
    private var anyTorchOn: Bool {
        state.devices.contains { $0.torchOn }
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

    @State private var leftPanelWidth: CGFloat = 300
    @State private var startLeftPanelWidth: CGFloat?
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
                    let toneLabels = ["A": "primerTones",
                                      "B": "seL",
                                      "C": "seC",
                                      "D": "seR"]
                    let colorGroups = ["B": "Blue, Red, Green",
                                       "C": "Purple, Yellow, Pink",
                                       "D": "Orange, Magenta, Cyan"]
                    // Primer tones button
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
                        Text("Sound Events")
                            .font(.subheadline)
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
                                    // Icon for mode
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(state.midiLog.indices, id: \.self) { idx in
                                Text(state.midiLog[idx])
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
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
                        
                        // Open routing control panel
                        Button("Routing") {
                            showRouting = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .disabled(!state.isBroadcasting)
                    }
                    
                    VStack(spacing: 24) {
                        ForEach(slotRows.indices, id: \.self) { row in
                            HStack(spacing: 24) {
                                ForEach(slotRows[row], id: \.self) { slot in
                                    let device = state.devices[slot - 1]
                                    SlotCell(device: device,
                                             keyLabel: keyLabels[slot],
                                             outline: slotOutlineColors[slot],
                                             isTriggered: state.triggeredSlots.contains(slot))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach(1...9, id: \.self) { idx in
                            Button("C3-\(idx)") {
                                if let slots = tripleTriggers[idx] {
                                    state.triggerSlots(realSlots: slots)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(tripleColors[idx] ?? .white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
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
                    onKeyDown: { char in
                        if char == "]" {
                            state.glowRampActive.toggle()
                            return
                        }
                        if char == "[" {
                            state.slowGlowRampActive.toggle()
                            return
                        }
                        if char == "\\" {
                            state.toggleAllTorches()
                            return
                        }
                        if char == "=" {
                            state.strobeActive.toggle()
                            return
                        }
                        if char == "-" {
                            state.slowStrobeActive.toggle()
                            return
                        }
                        if let note = typingMapper.note(for: char) {
                            let slot = Int(note)
                            state.addTriggeredSlot(slot)
                            state.typingNoteOn(note)
                            return
                        }
                    },
                    onKeyUp: { char in
                        if let note = typingMapper.note(for: char) {
                            let slot = Int(note)
                            state.removeTriggeredSlot(slot)
                            state.typingNoteOff(note)
                            return
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
    
#if DEBUG
    struct ComposerConsoleView_Previews: PreviewProvider {
        static var previews: some View {
            ComposerConsoleView()
                .environmentObject(ConsoleState())
        }
    }
#endif

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
                            state.triggerSound(device: device)
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
                        .opacity((isTriggered || device.torchOn || state.glowingSlots.contains(device.id + 1)) ? 1 : 0)
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
                        state.toggleTorch(id: device.id)
                    case .sound:
                        state.triggerSound(device: device)
                    case .both:
                        state.toggleTorch(id: device.id)
                        state.triggerSound(device: device)
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
                Text("Ch \(channel)")
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Keyboard event capture for typing-trigger
    fileprivate struct KeyCaptureView: NSViewRepresentable {
        var onKeyDown: (Character) -> Void
        var onKeyUp: (Character) -> Void
        
        func makeNSView(context: Context) -> KeyCaptureNSView {
            let view = KeyCaptureNSView()
            view.onKeyDown = onKeyDown
            view.onKeyUp = onKeyUp
            return view
        }
        
        func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {}
    }
    
    fileprivate class KeyCaptureNSView: NSView {
        var onKeyDown: ((Character) -> Void)?
        var onKeyUp: ((Character) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        override func resignFirstResponder() -> Bool { return false }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        
        override func keyDown(with event: NSEvent) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first {
                onKeyDown?(c)
            }
            // keep focus
            _ = window?.makeFirstResponder(self)
        }
        
        override func keyUp(with event: NSEvent) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first {
                onKeyUp?(c)
            }
            // keep focus
            _ = window?.makeFirstResponder(self)
        }
        // Do not intercept mouse events: allow clicks through
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
