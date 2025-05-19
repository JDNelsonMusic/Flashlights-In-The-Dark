import SwiftUI
import AppKit

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState
    @State private var showRouting: Bool = false
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 8)
    // Keyboard mapping rows for 32 keys
    private let keyRows = ["12345678", "qwertyui", "asdfghjk", "zxcvbnm,"]
    private var keyLabels: [String] {
        keyRows.flatMap { row in row.map { String($0) } }
    }
    
    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 16) {
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
                    Spacer()
                }
                // Main console content
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button("Build All") {
                            state.buildAll()
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .disabled(!state.isBroadcasting)
                        
                        Button("Run All") {
                            state.runAll()
                        }
                        .buttonStyle(.bordered)
                        .tint(.mint)
                        .disabled(!state.isBroadcasting)
                        
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
                    
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(state.devices) { device in
                            VStack(spacing: 4) {
                                // Keyboard key label
                                if keyLabels.indices.contains(device.id) {
                                    Text(keyLabels[device.id])
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
                                // Singer name
                                Text(device.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                // Status
                                let st = state.statuses[device.id] ?? .clean
                                Text(st.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(st.color)
                                
                                // 🆕 Build & Run button
                                Button {
                                    state.buildAndRun(device: device)
                                } label: {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.mint)
                                        .help("Build & run on \(device.udid.prefix(6))…")
                                }
                                .buttonStyle(.plain)
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
                                state.toggleTorch(id: device.id)
                            }
                        }
                    }
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
                        // Find slot for key
                        for (r, row) in keyRows.enumerated() {
                            if let idx = row.firstIndex(of: char) {
                                let col = row.distance(from: row.startIndex, to: idx)
                                let slot = r * 8 + col
                                // Torch and/or sound per mode
                                switch state.keyboardTriggerMode {
                                case .torch:
                                    state.flashOn(id: slot)
                                case .sound:
                                    let device = state.devices[slot]
                                    state.triggerSound(device: device)
                                case .both:
                                    state.flashOn(id: slot)
                                    let deviceBoth = state.devices[slot]
                                    state.triggerSound(device: deviceBoth)
                                }
                                return
                            }
                        }
                    },
                    onKeyUp: { char in
                        // Envelope release on “0”
                        if char == "0" {
                            state.releaseEnvelopeAll()
                            return
                        }
                        // Find slot for key
                        for (r, row) in keyRows.enumerated() {
                            if let idx = row.firstIndex(of: char) {
                                let col = row.distance(from: row.startIndex, to: idx)
                                let slot = r * 8 + col
                                // Torch and/or sound release per mode
                                switch state.keyboardTriggerMode {
                                case .torch:
                                    state.flashOff(id: slot)
                                case .sound:
                                    let device = state.devices[slot]
                                    state.stopSound(device: device)
                                case .both:
                                    state.flashOff(id: slot)
                                    let deviceBoth = state.devices[slot]
                                    state.stopSound(device: deviceBoth)
                                }
                                return
                            }
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
            // keep focus for continued key capture
            _ = window?.makeFirstResponder(self)
        }
        
        override func keyUp(with event: NSEvent) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first {
                onKeyUp?(c)
            }
            // keep focus for continued key capture
            _ = window?.makeFirstResponder(self)
        }
    }
}
