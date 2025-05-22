import SwiftUI

/// A view for controlling device-to-slot assignments dynamically.
struct RoutingView: View {
    @EnvironmentObject var state: ConsoleState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddDevice: Bool = false

    var body: some View {
        NavigationView {
            List {
                ForEach(state.devices) { device in
                    HStack(alignment: .top, spacing: 12) {
                        // Connectivity indicator: green if live, gray otherwise
                        let stat = state.statuses[device.id] ?? .clean
                        Circle()
                            .fill(stat == .live ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
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
                // Use automatic placement for macOS toolbars
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddDevice = true }) {
                        Image(systemName: "plus")
                    }
                    .help("Add a new device")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddDevice) {
                AddDeviceView()
                    .environmentObject(state)
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