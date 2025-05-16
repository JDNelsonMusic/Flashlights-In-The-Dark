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
                .disabled(state.isBroadcasting)

                Button("All-On") {
                    state.playAll()
                }
                .buttonStyle(.bordered)
                .disabled(state.isBroadcasting)
            }

            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(state.devices) { device in
                    VStack(spacing: 4) {
                        Image(systemName: "flashlight.on.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(device.torchOn ? .yellow : .gray)

                        Text("#\(device.id)")
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
        }
        .padding()
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