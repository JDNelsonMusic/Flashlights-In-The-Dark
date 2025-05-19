import SwiftUI
import AppKit

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState
    @State private var showRouting: Bool = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Tone-set toggles
            VStack(spacing: 12) {
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
