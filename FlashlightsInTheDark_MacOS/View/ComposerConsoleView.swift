import SwiftUI
import AppKit

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState
    @State private var showRouting: Bool = false

    @State private var triggeredSlots: Set<Int> = []
    // Strobe effect state
    @State private var strobeActive: Bool = false
    @State private var strobeOn: Bool = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 8)
    // Mapping from keyboard key to real slot number
    private let keyToSlot: [Character: Int] = [
        "2": 1, "3": 3, "4": 4, "5": 5, "u": 7, "7": 9, "9": 12,
        "q": 14, "w": 15, "d": 16, "e": 18, "r": 19, "k": 20, "i": 21,
        "8": 23, "o": 24, "p": 25, "a": 27, "s": 29, "j": 34, "l": 38,
        ";": 40, "x": 41, "c": 42, "v": 44, "m": 51, ",": 53, ".": 54
    ]
    // Reverse lookup so each slot can display its bound key
    private var keyLabels: [Int: String] {
        Dictionary(uniqueKeysWithValues: keyToSlot.map { ($0.value, String($0.key)) })
    }
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
    /// Returns true when any connected device's torch is currently on.
    private var anyTorchOn: Bool {
        state.devices.contains { $0.torchOn }
    }
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
                    ForEach(["A", "B", "C", "D"], id: \.self) { set in
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
                                          ? Color.blue
                                          : Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                Text(set)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Toggle tone set \(set)")
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
                                              ? Color.blue
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
                    Text("MIDI Controls:")
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
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                let newWidth = value.location.x
                                leftPanelWidth = max(150, min(newWidth, 600))
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
                        Button("Blackout") {
                            state.blackoutAll()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!state.isBroadcasting)
                        
                        Button("All-On") {
                            state.playAll()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.indigo.opacity(0.6))
                        .disabled(!state.isBroadcasting)

                        Button(strobeActive ? "Stop Strobe" : "Strobe") {
                            if strobeActive {
                                strobeActive = false
                                strobeOn = false
                            } else {
                                strobeActive = true
                                withAnimation(Animation.linear(duration: 0.1).repeatForever(autoreverses: true)) {
                                    strobeOn.toggle()
                                }
                            }
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
                                             isTriggered: triggeredSlots.contains(slot))
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
            .overlay(
                KeyCaptureView(
                    onKeyDown: { char in
                        // Envelope on “0”
                        if char == "0" {
                            state.startEnvelopeAll()
                            return
                        }
                        if let slot = keyToSlot[char] {
                            let idx = slot - 1
                            triggeredSlots.insert(slot)
                            switch state.keyboardTriggerMode {
                            case .torch:
                                state.flashOn(id: idx)
                            case .sound:
                                let device = state.devices[idx]
                                state.triggerSound(device: device)
                            case .both:
                                state.flashOn(id: idx)
                                let deviceBoth = state.devices[idx]
                                state.triggerSound(device: deviceBoth)
                            }
                            return
                        }
                    },
                    onKeyUp: { char in
                        // Envelope release on “0”
                        if char == "0" {
                            state.releaseEnvelopeAll()
                            return
                        }
                        if let slot = keyToSlot[char] {
                            let idx = slot - 1
                            triggeredSlots.remove(slot)
                            switch state.keyboardTriggerMode {
                            case .torch:
                                state.flashOff(id: idx)
                            case .sound:
                                let device = state.devices[idx]
                                state.stopSound(device: device)
                            case .both:
                                state.flashOff(id: idx)
                                let deviceBoth = state.devices[idx]
                                state.stopSound(device: deviceBoth)
                            }
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
            // Full-screen flash overlay when torches or strobe are active
            if anyTorchOn || strobeActive {
                Color.mintGlow
                    .opacity(strobeActive ? (strobeOn ? 0.8 : 0.0) : 0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: anyTorchOn || strobeActive)
                    .allowsHitTesting(false)
            }
            // Always-on purple/navy veil overlay
            Color.purpleNavy
                .opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(1)
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

        var body: some View {
            Group {
                if device.isPlaceholder {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
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
                        let st = state.statuses[device.id] ?? .clean
                        Text(st.rawValue)
                            .font(.caption2)
                            .foregroundStyle(st.color)
                        Button {
                            state.triggerSound(device: device)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.cyan)
                                .help("Trigger sound on \(device.name)…")
                        }
                        .buttonStyle(.plain)
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
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(outline ?? .clear, lineWidth: 3)
                            .shadow(color: outline?.opacity(0.8) ?? .clear, radius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.clear, lineWidth: 0)
                            .shadow(color: (isTriggered || device.torchOn || state.glowingSlots.contains(device.id + 1)) ? Color.white.opacity(0.95) : .clear,
                                    radius: (isTriggered || device.torchOn || state.glowingSlots.contains(device.id + 1)) ? 36 : 0)
                    )
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
