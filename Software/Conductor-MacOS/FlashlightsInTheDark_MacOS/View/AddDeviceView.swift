import SwiftUI

/// A view for entering new device details (name, IP, and persistent device ID).
struct AddDeviceView: View {
    @EnvironmentObject var state: ConsoleState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var ip: String = ""
    @State private var deviceId: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Info")) {
                    TextField("Name", text: $name)
                    TextField("IP Address", text: $ip)
                    TextField("Device ID", text: $deviceId)
                }
            }
            .navigationTitle("Add Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        state.addDevice(name: name.trimmingCharacters(in: .whitespaces),
                                        ip: ip.trimmingCharacters(in: .whitespaces),
                                        udid: deviceId.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(name.isEmpty || ip.isEmpty || deviceId.isEmpty)
                }
            }
        }
    }
}

#if DEBUG
struct AddDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        AddDeviceView()
            .environmentObject(ConsoleState())
    }
}
#endif
