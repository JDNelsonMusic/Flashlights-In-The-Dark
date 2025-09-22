import SwiftUI

/// A data-rich routing view to manage slot assignments and device health.
struct RoutingView: View {
    @EnvironmentObject var state: ConsoleState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddDevice: Bool = false
    @State private var filterText: String = ""
    @State private var selectedColor: PrimerColor?
    @State private var showPlaceholders: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 360), spacing: 20, alignment: .top)
    ]

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                controlPanel

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredDevices) { device in
                            let status = state.statuses[device.id] ?? .clean
                            let color = state.colorForSlot(device.listeningSlot)
                            let lastHello = state.lastHelloDate(forSlot: device.listeningSlot)
                            let lastAck = state.lastAckDate(forSlot: device.listeningSlot)
                            let slotBinding = Binding<Int>(
                                get: {
                                    state.devices.first(where: { $0.id == device.id })?.listeningSlot ?? device.listeningSlot
                                },
                                set: { slot in
                                    state.assignSlot(device: device, slot: slot)
                                }
                            )
                            DeviceCard(
                                device: device,
                                status: status,
                                color: color,
                                lastHello: lastHello,
                                lastAck: lastAck,
                                relativeDescription: relativeDescription,
                                slotBinding: slotBinding,
                                onPing: { state.pingSlot(device.listeningSlot) }
                            )
                            .environmentObject(state)
                        }
                    }
                    .padding(.vertical, 8)

                    if showPlaceholders, !placeholderDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Placeholder Slots")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(placeholderDevices) { device in
                                    PlaceholderCard(device: device)
                                }
                            }
                        }
                        .padding(.top, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .navigationTitle("Device Routing")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddDevice = true }) {
                        Image(systemName: "plus")
                    }
                    .help("Add a manually configured device")
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

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Search by name, slot, UDID, or IP", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260, maxWidth: 320)

                Picker("Colour", selection: $selectedColor) {
                    Text("All Colours").tag(nil as PrimerColor?)
                    ForEach(PrimerColor.allCases) { color in
                        Text(color.displayName).tag(color as PrimerColor?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Toggle("Show placeholders", isOn: $showPlaceholders)
                    .toggleStyle(.switch)

                Spacer()

                Button {
                    pingVisibleDevices()
                } label: {
                    Label("Ping visible", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
            }

            if !filterText.isEmpty || selectedColor != nil {
                Text("Showing \(filteredDevices.count) of \(state.devices.count) devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filteredDevices: [ChoirDevice] {
        let search = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.devices.filter { device in
            guard !device.isPlaceholder else { return false }
            if let selectedColor, state.colorForSlot(device.listeningSlot) != selectedColor {
                return false
            }
            guard !search.isEmpty else { return true }
            let haystack = [
                "#\(device.id + 1)",
                "slot \(device.listeningSlot)",
                device.name,
                device.ip,
                device.udid
            ].joined(separator: " ").lowercased()
            return haystack.contains(search)
        }
    }

    private var placeholderDevices: [ChoirDevice] {
        state.devices.filter { $0.isPlaceholder }
    }

    private func pingVisibleDevices() {
        let slots = filteredDevices.map(\.listeningSlot)
        for slot in slots {
            state.pingSlot(slot)
        }
    }

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return "—" }
        return RoutingView.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct DeviceCard: View {
    @EnvironmentObject var state: ConsoleState

    let device: ChoirDevice
    let status: DeviceStatus
    let color: PrimerColor?
    let lastHello: Date?
    let lastAck: Date?
    let relativeDescription: (Date?) -> String
    let slotBinding: Binding<Int>
    let onPing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slot #\(device.listeningSlot)")
                        .font(.title3)
                        .bold()
                    if !device.name.isEmpty {
                        Text(device.name)
                            .font(.headline)
                    }
                    Text("Device ID #\(device.id + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(status: status)
            }

            if let color {
                Label(color.displayName, systemImage: "tag")
                    .font(.caption)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(colorTint(for: color).opacity(0.18))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                if !device.ip.isEmpty {
                    Label(device.ip, systemImage: "network")
                        .font(.caption)
                }
                if !device.udid.isEmpty {
                    Label(device.udid, systemImage: "iphone")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                HStack(spacing: 16) {
                    Label("Hello \(relativeDescription(lastHello))", systemImage: "waveform")
                        .font(.caption)
                    Label("Ack \(relativeDescription(lastAck))", systemImage: "checkmark.seal")
                        .font(.caption)
                }
                HStack(spacing: 16) {
                    Label(device.torchOn ? "Torch on" : "Torch off", systemImage: device.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.caption)
                    Label(device.audioPlaying ? "Audio playing" : "Audio idle", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                }
            }

            Divider()

            Picker("Listening Slot", selection: slotBinding) {
                ForEach(1...state.devices.count, id: \.self) { slot in
                    Text("\(slot)").tag(slot)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button(action: onPing) {
                    Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)

                Button {
                    state.triggerSound(device: device)
                } label: {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { @MainActor in
                        state.flashOn(id: device.id)
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        state.flashOff(id: device.id)
                    }
                } label: {
                    Label("Torch", systemImage: "flashlight.on.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch status {
        case .live: return Color.mintGlow.opacity(0.6)
        case .lostConnection: return Color.orange.opacity(0.6)
        case .buildFailed, .runFailed: return Color.red.opacity(0.5)
        default: return Color.white.opacity(0.1)
        }
    }

    private func colorTint(for color: PrimerColor) -> Color {
        switch color {
        case .blue: return .royalBlue
        case .red: return .brightRed
        case .green: return .slotGreen
        case .purple: return .slotPurple
        case .yellow: return .slotYellow
        case .pink: return .lightRose
        case .orange: return .slotOrange
        case .magenta: return .hotMagenta
        case .cyan: return .skyBlue
        }
    }

}

private struct PlaceholderCard: View {
    let device: ChoirDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Placeholder #\(device.id + 1)")
                .font(.headline)
            Text("Use the add-device button to assign a real client here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct StatusChip: View {
    let status: DeviceStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(status.color.opacity(0.2))
            .clipShape(Capsule())
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
