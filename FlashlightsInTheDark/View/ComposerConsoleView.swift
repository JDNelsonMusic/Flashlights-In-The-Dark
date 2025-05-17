import SwiftUI

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState

    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
}

#if DEBUG
struct ComposerConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        ComposerConsoleView()
            .environmentObject(ConsoleState())
    }
}
#endif
