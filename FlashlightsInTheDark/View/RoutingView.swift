import SwiftUI

/// A view for controlling device-to-slot assignments dynamically.
struct RoutingView: View {
    @EnvironmentObject var state: ConsoleState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(state.devices) { device in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            // Device identifier and name
                            Text("#\(device.id + 1)  \(device.name)")
                                .font(.headline)
                            // UDID and IP
                            Text("UDID: \(device.udid)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !device.ip.isEmpty {
                                Text("IP: \(device.ip)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        // Picker for slot assignment
                        Picker("Slot", selection: Binding(
                            get: { device.listeningSlot },
                            set: { newSlot in state.assignSlot(device: device, slot: newSlot) }
                        )) {
                            ForEach(1...(state.devices.count), id: \.self) { slot in
                                Text("\(slot)").tag(slot)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Device Routing")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
struct RoutingView_Previews: PreviewProvider {
    static var previews: some View {
        RoutingView()
            .environmentObject(ConsoleState())
    }
}
#endif