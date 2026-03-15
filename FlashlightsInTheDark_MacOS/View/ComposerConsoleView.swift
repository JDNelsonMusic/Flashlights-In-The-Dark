import AppKit
import SwiftUI

private struct StaffModuleDescriptor: Identifiable {
    let staff: LightStaff

    var id: String { staff.rawValue }
    var title: String { staff.label }
    var accent: Color { staff.accentColor }
    var seats: [LightStaffSeat] { staff.seats }
    var legacySlots: [Int] { staff.legacySlots }
}

struct ComposerConsoleView: View {
    @EnvironmentObject var state: ConsoleState

    @State private var showRouting = false
    @State private var strobeOn = false
    @State private var sidebarPinned = true

    private var stageModules: [StaffModuleDescriptor] {
        LightStaff.stageOrder.map { StaffModuleDescriptor(staff: $0) }
    }

    private var anyTorchOn: Bool {
        state.devices.contains { $0.torchOn }
    }

    private var preflightLabel: String {
        "\(state.connectedPerformanceDeviceCount)/\(state.expectedDeviceCount) connected"
    }

    var body: some View {
        GeometryReader { geometry in
            let wideLayout = geometry.size.width >= 1540
            let ultraWideLayout = geometry.size.width >= 2400
            let sidebarWidth = ultraWideLayout
                ? min(max(geometry.size.width * 0.24, 500), 620)
                : min(max(geometry.size.width * 0.28, 360), 460)

            ZStack {
                Color.deepPurple.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        summaryGrid(availableWidth: geometry.size.width)

                        if wideLayout {
                            HStack(alignment: .top, spacing: 20) {
                                if sidebarPinned {
                                    operatorRail(availableWidth: sidebarWidth)
                                        .frame(width: sidebarWidth)
                                        .frame(maxWidth: sidebarWidth, alignment: .topLeading)
                                }

                                mainStageColumn(availableWidth: geometry.size.width - (sidebarPinned ? sidebarWidth + 68 : 48))
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            VStack(spacing: 20) {
                                mainStageColumn(availableWidth: geometry.size.width - 48)
                                if sidebarPinned {
                                    operatorRail(availableWidth: geometry.size.width - 48)
                                }
                            }
                        }

                        footerCard
                    }
                    .padding(24)
                }
                .sheet(isPresented: $showRouting) {
                    RoutingView()
                        .frame(
                            width: (NSScreen.main?.visibleFrame.width ?? 1200) * 0.82,
                            height: (NSScreen.main?.visibleFrame.height ?? 860) * 0.82
                        )
                        .environmentObject(state)
                }
                .overlay(
                    FullScreenFlashView(
                        strobeActive: state.strobeActive || state.slowStrobeActive || state.glowRampActive || state.slowGlowRampActive,
                        strobeOn: strobeOn
                    )
                    .environmentObject(state)
                )
                .overlay(ColorOverlayVeil())
                .overlay(
                    Color.purpleNavy
                    .opacity(0.08)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                )
            }
        }
        .onChange(of: state.strobeActive) { _, _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.slowStrobeActive) { _, _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.glowRampActive) { _, _ in
            updateStrobeAnimation()
        }
        .onChange(of: state.slowGlowRampActive) { _, _ in
            updateStrobeAnimation()
        }
    }

    private var headerCard: some View {
        ConsoleSectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    headerIdentity
                    Spacer(minLength: 12)
                    headerControls(alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 16) {
                    headerIdentity
                    headerControls(alignment: .leading)
                }
            }
        }
    }

    private func summaryGrid(availableWidth: CGFloat) -> some View {
        return LazyVGrid(
            columns: summaryColumns(for: availableWidth),
            spacing: 16
        ) {
            SummaryCard(
                title: "Connected Devices",
                value: "\(state.connectedPerformanceDeviceCount)",
                subtitle: "Expected \(state.expectedDeviceCount)",
                tint: state.canArmStrict ? .green : .orange,
                symbol: "dot.radiowaves.left.and.right"
            )
            SummaryCard(
                title: "Current Trigger",
                value: currentTriggerSummary,
                subtitle: currentMeasureSummary,
                tint: .mintGlow,
                symbol: "sparkles.rectangle.stack"
            )
            SummaryCard(
                title: "Cue Delivery",
                value: cueDeliveryValue,
                subtitle: cueDeliverySubtitle,
                tint: cueDeliveryTint,
                symbol: "checkmark.circle"
            )
            SummaryCard(
                title: "Torch State",
                value: anyTorchOn ? "Active" : "Dark",
                subtitle: anyTorchOn ? "At least one staff lit" : "All torches off",
                tint: anyTorchOn ? .mintGlow : .secondary,
                symbol: anyTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            )
            SummaryCard(
                title: "Network Health",
                value: String(format: "%.1f PPS", state.packetRatePerSecond),
                subtitle: "Unknown \(state.unknownSenderEvents) · Failures \(state.totalSendFailures)",
                tint: .blue,
                symbol: "waveform.path.ecg"
            )
        }
    }

    private func mainStageColumn(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ConsoleSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "Stage Modules",
                        subtitle: "Six visible seats per staff. Large numbers show conductor-facing seat positions; small labels preserve legacy route IDs."
                    )

                    LazyVGrid(columns: stageColumns(for: availableWidth), spacing: 16) {
                        ForEach(stageModules) { module in
                            let devices = routedDevices(for: module)
                            StaffModuleCard(
                                module: module,
                                deviceBySlot: Dictionary(uniqueKeysWithValues: devices.map { ($0.listeningSlot, $0) }),
                                connectedCount: connectedDeviceCount(for: module),
                                hasTorch: devices.contains(where: \.torchOn),
                                hasAudio: devices.contains(where: \.audioPlaying),
                                isTriggered: module.legacySlots.contains(where: { state.triggeredSlots.contains($0) || state.glowingSlots.contains($0) }),
                                hasTargets: !actionDevices(for: module).isEmpty,
                                onTorch: { toggleModuleTorch(module) },
                                onSound: { triggerModuleSound(module) },
                                onBoth: { triggerModule(module) },
                                onPing: { pingModule(module) }
                            )
                            .environmentObject(state)
                        }
                    }
                }
            }

            ConsoleSectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "Quick Fire",
                        subtitle: "Trigger an entire staff using the current keyboard mode."
                    )

                    LazyVGrid(
                        columns: quickFireColumns(for: availableWidth),
                        spacing: 12
                    ) {
                        ForEach(stageModules) { module in
                            Button {
                                triggerModule(module)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(module.accent)
                                        .frame(width: 10, height: 10)
                                    Text(module.title)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(connectedDeviceCount(for: module))/\(module.staff.routedSeatCount)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(module.accent.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(module.accent.opacity(0.42), lineWidth: 1)
                                    )
                            )
                            .disabled(actionDevices(for: module).isEmpty)
                        }
                    }
                }
            }

            EventTriggerStrip()
                .environmentObject(state)
        }
    }

    private func operatorRail(availableWidth: CGFloat) -> some View {
        let twoColumnRail = availableWidth >= 900
        let columns = Array(
            repeating: GridItem(.flexible(minimum: twoColumnRail ? 260 : availableWidth), spacing: 16, alignment: .top),
            count: twoColumnRail ? 2 : 1
        )

        return LazyVGrid(columns: columns, spacing: 16) {
            TransportPanel(showRouting: $showRouting)
                .environmentObject(state)

            EnsembleFxPanel(anyTorchOn: anyTorchOn)
                .environmentObject(state)

            ManualCuePanel()
                .environmentObject(state)

            MidiDiagnosticsPanel()
                .environmentObject(state)
        }
    }

    private var footerCard: some View {
        ConsoleSectionCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "terminal")
                    .foregroundStyle(Color.mintGlow)
                Text(state.lastLog)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.mintGlow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var currentTriggerSummary: String {
        guard state.eventRecipes.indices.contains(state.currentEventIndex) else {
            return "No trigger"
        }
        let event = state.eventRecipes[state.currentEventIndex]
        return "TP\(event.id)"
    }

    private var currentMeasureSummary: String {
        guard state.eventRecipes.indices.contains(state.currentEventIndex) else {
            return "Trigger-point bundle missing"
        }
        let event = state.eventRecipes[state.currentEventIndex]
        return event.measureText + " · " + event.positionLabel
    }

    private var cueDeliveryValue: String {
        guard let snapshot = state.lastTriggerCueSnapshot else {
            return "Idle"
        }
        return snapshot.deliverySummary
    }

    private var cueDeliverySubtitle: String {
        guard let snapshot = state.lastTriggerCueSnapshot else {
            return "Fire a trigger to inspect acknowledgements"
        }
        if snapshot.unavailableCount > 0 {
            return "\(snapshot.headline) · \(snapshot.pendingCount) pending · \(snapshot.unavailableCount) unavailable"
        }
        return "\(snapshot.headline) · \(snapshot.pendingCount) pending"
    }

    private var cueDeliveryTint: Color {
        guard let snapshot = state.lastTriggerCueSnapshot else {
            return .secondary
        }
        if snapshot.ackedCount == snapshot.targetedCount && snapshot.targetedCount > 0 {
            return .green
        }
        if snapshot.unavailableCount > 0 {
            return .orange
        }
        return .blue
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flashlights in the Dark")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Conductor Console")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.mintGlow)
            Text("Six-stage module view with left-to-right seat numbering, trigger navigation, and direct section control.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func headerControls(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    StatusPill(title: state.isArmed ? "ARMED" : "SAFE", value: state.isArmed ? "Concert cues live" : "Cues blocked", tint: state.isArmed ? .red : .orange)
                    StatusPill(title: "Preflight", value: preflightLabel, tint: state.canArmStrict ? .green : .orange)
                }

                VStack(alignment: alignment, spacing: 8) {
                    StatusPill(title: state.isArmed ? "ARMED" : "SAFE", value: state.isArmed ? "Concert cues live" : "Cues blocked", tint: state.isArmed ? .red : .orange)
                    StatusPill(title: "Preflight", value: preflightLabel, tint: state.canArmStrict ? .green : .orange)
                }
            }

            HStack(spacing: 8) {
                Button(sidebarPinned ? "Hide Sidebar" : "Show Sidebar") {
                    sidebarPinned.toggle()
                }
                .buttonStyle(.bordered)

                Button("Routing") {
                    showRouting = true
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
    }

    private func stageColumns(for availableWidth: CGFloat) -> [GridItem] {
        let columnCount: Int
        if availableWidth >= 2500 {
            columnCount = 6
        } else if availableWidth >= 1500 {
            columnCount = 3
        } else if availableWidth >= 980 {
            columnCount = 2
        } else {
            columnCount = 1
        }

        return Array(
            repeating: GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16, alignment: .top),
            count: columnCount
        )
    }

    private func summaryColumns(for availableWidth: CGFloat) -> [GridItem] {
        let columnCount: Int
        if availableWidth >= 2200 {
            columnCount = 5
        } else if availableWidth >= 1760 {
            columnCount = 4
        } else if availableWidth >= 920 {
            columnCount = 2
        } else {
            columnCount = 1
        }

        return Array(
            repeating: GridItem(.flexible(minimum: 180, maximum: .infinity), spacing: 16, alignment: .top),
            count: columnCount
        )
    }

    private func quickFireColumns(for availableWidth: CGFloat) -> [GridItem] {
        let columnCount: Int
        if availableWidth >= 2100 {
            columnCount = 6
        } else if availableWidth >= 1200 {
            columnCount = 3
        } else if availableWidth >= 700 {
            columnCount = 2
        } else {
            columnCount = 1
        }

        return Array(
            repeating: GridItem(.flexible(minimum: 150, maximum: .infinity), spacing: 12, alignment: .top),
            count: columnCount
        )
    }

    private func routedDevices(for module: StaffModuleDescriptor) -> [ChoirDevice] {
        state.devices
            .filter { !$0.isPlaceholder && module.legacySlots.contains($0.listeningSlot) }
            .sorted { lhs, rhs in
                let lhsIndex = module.legacySlots.firstIndex(of: lhs.listeningSlot) ?? .max
                let rhsIndex = module.legacySlots.firstIndex(of: rhs.listeningSlot) ?? .max
                return lhsIndex < rhsIndex
            }
    }

    private func actionDevices(for module: StaffModuleDescriptor) -> [ChoirDevice] {
        routedDevices(for: module).filter { device in
            let status = state.statuses[device.id] ?? .clean
            return status == .live || !device.ip.isEmpty
        }
    }

    private func connectedDeviceCount(for module: StaffModuleDescriptor) -> Int {
        routedDevices(for: module).reduce(into: 0) { count, device in
            if (state.statuses[device.id] ?? .clean) == .live {
                count += 1
            }
        }
    }

    private func pingModule(_ module: StaffModuleDescriptor) {
        for slot in module.legacySlots {
            state.pingSlot(slot)
        }
    }

    private func toggleModuleTorch(_ module: StaffModuleDescriptor) {
        for device in actionDevices(for: module) {
            _ = state.toggleTorch(id: device.id, allowWhenDisarmed: true)
        }
    }

    private func triggerModuleSound(_ module: StaffModuleDescriptor) {
        for device in actionDevices(for: module) {
            state.triggerSound(device: device, allowWhenDisarmed: true)
        }
    }

    private func triggerModule(_ module: StaffModuleDescriptor) {
        switch state.keyboardTriggerMode {
        case .torch:
            toggleModuleTorch(module)
        case .sound:
            triggerModuleSound(module)
        case .both:
            toggleModuleTorch(module)
            triggerModuleSound(module)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

}

private struct ConsoleSectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct ToggleActionButton: View {
    let title: String
    let tint: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(isActive ? tint : tint.opacity(0.72))
            .frame(maxWidth: .infinity)
    }
}

private struct ConsoleSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TransportPanel: View {
    @EnvironmentObject var state: ConsoleState

    @Binding var showRouting: Bool

    var body: some View {
        ConsoleSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                ConsoleSectionHeader(title: "Transport", subtitle: "Concert arming, routing, refresh, and emergency actions.")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        refreshButton
                        refreshConnectionsButton
                    }

                    VStack(spacing: 10) {
                        refreshButton
                        refreshConnectionsButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        armButton
                        armOverrideButton
                        panicButton
                    }

                    VStack(spacing: 10) {
                        armButton
                        HStack(spacing: 10) {
                            armOverrideButton
                            panicButton
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        routingButton
                        exportLogButton
                    }

                    VStack(spacing: 10) {
                        routingButton
                        exportLogButton
                    }
                }

                if let warning = state.preflightWarning {
                    Text("⚠️ \(warning)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button("Refresh") {
            state.refreshDevices()
            Task { await state.startNetwork() }
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    private var refreshConnectionsButton: some View {
        Button("Refresh Connections") {
            state.refreshConnections()
        }
        .buttonStyle(.bordered)
        .tint(.teal)
        .disabled(!state.isBroadcasting)
    }

    private var armButton: some View {
        Button(state.isArmed ? "DISARM" : "ARM") {
            if state.isArmed {
                state.disarmConcertMode()
            } else {
                _ = state.armConcertMode()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(state.isArmed ? .red : (state.canArmStrict ? .green : .orange))
    }

    private var armOverrideButton: some View {
        Button("ARM Override") {
            _ = state.armConcertMode(override: true)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .disabled(state.isArmed || state.canArmStrict)
    }

    private var panicButton: some View {
        Button("PANIC") {
            state.panicAllStop()
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private var routingButton: some View {
        Button("Routing") {
            showRouting = true
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    private var exportLogButton: some View {
        Button("Export Network Log") {
            state.exportNetworkLog()
        }
        .buttonStyle(.bordered)
        .tint(.purple)
    }
}

private struct EnsembleFxPanel: View {
    @EnvironmentObject var state: ConsoleState

    let anyTorchOn: Bool

    var body: some View {
        ConsoleSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                ConsoleSectionHeader(title: "Ensemble FX", subtitle: "Global torch and diagnostic gestures for quick checks.")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        allTorchButton
                        playAllTonesButton
                    }

                    VStack(spacing: 10) {
                        allTorchButton
                        playAllTonesButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        slowGlowButton
                        glowRampButton
                    }

                    VStack(spacing: 10) {
                        slowGlowButton
                        glowRampButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        mediumStrobeButton
                        rapidStrobeButton
                    }

                    VStack(spacing: 10) {
                        mediumStrobeButton
                        rapidStrobeButton
                    }
                }
            }
        }
    }

    private var allTorchButton: some View {
        Button(anyTorchOn ? "All Off" : "All On") {
            state.toggleAllTorches()
        }
        .buttonStyle(.borderedProminent)
        .tint(anyTorchOn ? .red : Color.indigo.opacity(0.65))
        .disabled(!state.isBroadcasting)
    }

    private var playAllTonesButton: some View {
        Button("Play All Tones") {
            state.playAllTones()
        }
        .buttonStyle(.bordered)
        .tint(.cyan)
        .disabled(!state.isBroadcasting)
    }

    private var slowGlowButton: some View {
        ToggleActionButton(
            title: state.slowGlowRampActive ? "Stop Slow Glow" : "Slow Glow",
            tint: .mintGlow,
            isActive: state.slowGlowRampActive
        ) {
            state.slowGlowRampActive.toggle()
        }
        .disabled(!state.isBroadcasting)
    }

    private var glowRampButton: some View {
        ToggleActionButton(
            title: state.glowRampActive ? "Stop Glow" : "Glow Ramp",
            tint: .mintGlow,
            isActive: state.glowRampActive
        ) {
            state.glowRampActive.toggle()
        }
        .disabled(!state.isBroadcasting)
    }

    private var mediumStrobeButton: some View {
        ToggleActionButton(
            title: state.slowStrobeActive ? "Stop Medium" : "Medium Strobe",
            tint: .mintGlow,
            isActive: state.slowStrobeActive
        ) {
            state.slowStrobeActive.toggle()
        }
        .disabled(!state.isBroadcasting)
    }

    private var rapidStrobeButton: some View {
        ToggleActionButton(
            title: state.strobeActive ? "Stop Rapid" : "Rapid Strobe",
            tint: .mintGlow,
            isActive: state.strobeActive
        ) {
            state.strobeActive.toggle()
        }
        .disabled(!state.isBroadcasting)
    }
}

private struct ManualCuePanel: View {
    @EnvironmentObject var state: ConsoleState

    var body: some View {
        ConsoleSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                ConsoleSectionHeader(title: "Manual Cueing", subtitle: "Typing-mode behavior plus direct sound-bank toggles.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Keyboard Mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 84), spacing: 8), count: 3), spacing: 8) {
                        ForEach(ConsoleState.KeyboardTriggerMode.allCases, id: \.self) { mode in
                            Button {
                                state.keyboardTriggerMode = mode
                            } label: {
                                Label(mode.rawValue, systemImage: iconName(for: mode))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(state.keyboardTriggerMode == mode ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(state.keyboardTriggerMode == mode ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Manual Sound Banks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 84), spacing: 10), count: 3), spacing: 10) {
                        ManualBankChip(set: "B", label: "seL", subtitle: "Blue · Red · Green", isActive: state.activeToneSets.contains("B")) {
                            toggleManualBank("B")
                        }
                        ManualBankChip(set: "C", label: "seC", subtitle: "Purple · Yellow · Pink", isActive: state.activeToneSets.contains("C")) {
                            toggleManualBank("C")
                        }
                        ManualBankChip(set: "D", label: "seR", subtitle: "Orange · Magenta · Cyan", isActive: state.activeToneSets.contains("D")) {
                            toggleManualBank("D")
                        }
                    }
                }

                DisclosureGroup("Envelope Controls") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Attack: \(state.attackMs) ms", value: $state.attackMs, in: 0...2000, step: 50)
                        Stepper("Decay: \(state.decayMs) ms", value: $state.decayMs, in: 0...2000, step: 50)
                        Stepper("Sustain: \(state.sustainPct)%", value: $state.sustainPct, in: 0...100, step: 10)
                        Stepper("Release: \(state.releaseMs) ms", value: $state.releaseMs, in: 0...2000, step: 50)

                        HStack(spacing: 10) {
                            Button("0 Envelope") {
                                state.startEnvelopeAll()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Release Envelope") {
                                state.releaseEnvelopeAll()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 10)
                }
                    .tint(Color.mintGlow)
            }
        }
    }

    private func toggleManualBank(_ set: String) {
        if state.activeToneSets.contains(set) {
            state.activeToneSets.remove(set)
        } else {
            state.activeToneSets.insert(set)
        }
    }

    private func iconName(for mode: ConsoleState.KeyboardTriggerMode) -> String {
        switch mode {
        case .torch: return "flashlight.on.fill"
        case .sound: return "speaker.wave.2.fill"
        case .both: return "sparkles"
        }
    }
}

private struct MidiDiagnosticsPanel: View {
    @EnvironmentObject var state: ConsoleState
    private let channelColumns = Array(repeating: GridItem(.flexible(minimum: 40), spacing: 8), count: 4)

    var body: some View {
        ConsoleSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                ConsoleSectionHeader(title: "MIDI + Diagnostics", subtitle: "Device selection, I/O routing, and scrollback log.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("MIDI Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("MIDI Input", selection: $state.selectedMidiInput) {
                        ForEach(state.midiInputNames, id: \.self) { name in
                            Text(name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("MIDI Output")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("MIDI Output", selection: $state.selectedMidiOutput) {
                        ForEach(state.midiOutputNames, id: \.self) { name in
                            Text(name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("Output Channel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: channelColumns, spacing: 8) {
                        ForEach(1...16, id: \.self) { channel in
                            Button {
                                state.outputChannel = channel
                            } label: {
                                Text("\(channel)")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(state.outputChannel == channel ? Color.mintGlow.opacity(0.2) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(state.outputChannel == channel ? Color.mintGlow.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                    .onAppear {
                        state.refreshMidiDevices()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("MIDI Log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(state.midiLog.indices, id: \.self) { idx in
                                    Text(state.midiLog[idx])
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id("midi-bottom")
                            }
                        }
                        .frame(minHeight: 160, maxHeight: 220)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .onChange(of: state.midiLog.count) { _, _ in
                            proxy.scrollTo("midi-bottom", anchor: .bottom)
                        }
                        .onAppear {
                            proxy.scrollTo("midi-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct ManualBankChip: View {
    let set: String
    let label: String
    let subtitle: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(set)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isActive ? Color.black : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                        )
                    Spacer()
                    Text(label)
                        .font(.headline.weight(.bold))
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.26) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.68) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StaffModuleCard: View {
    @EnvironmentObject var state: ConsoleState

    let module: StaffModuleDescriptor
    let deviceBySlot: [Int: ChoirDevice]
    let connectedCount: Int
    let hasTorch: Bool
    let hasAudio: Bool
    let isTriggered: Bool
    let hasTargets: Bool
    let onTorch: () -> Void
    let onSound: () -> Void
    let onBoth: () -> Void
    let onPing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    moduleHeader
                    Spacer(minLength: 8)
                    moduleStatusCluster
                }

                VStack(alignment: .leading, spacing: 8) {
                    moduleHeader
                    moduleStatusCluster
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 40), spacing: 8, alignment: .top), count: 6),
                spacing: 8
            ) {
                ForEach(module.seats) { seat in
                    let device = seat.legacySlot.flatMap { deviceBySlot[$0] }
                    ModuleSeatBadge(
                        seat: seat,
                        device: device,
                        status: device.flatMap { state.statuses[$0.id] } ?? .clean,
                        accent: module.accent,
                        isTriggered: seat.legacySlot.map { state.glowingSlots.contains($0) || state.triggeredSlots.contains($0) } ?? false
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pingButton
                    torchButton
                    soundButton
                    bothButton
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 8), count: 2), spacing: 8) {
                    pingButton
                    torchButton
                    soundButton
                    bothButton
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(module.accent.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(module.accent.opacity(isTriggered || hasTorch || hasAudio ? 0.95 : 0.28), lineWidth: isTriggered || hasTorch || hasAudio ? 2 : 1)
        )
        .shadow(color: module.accent.opacity(isTriggered || hasTorch || hasAudio ? 0.24 : 0.08), radius: isTriggered || hasTorch || hasAudio ? 18 : 8, y: 8)
    }

    private var moduleHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(module.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("\(module.staff.routedSeatCount) routed · \(StageConsoleLayout.seatsPerStaff - module.staff.routedSeatCount) open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var moduleStatusCluster: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ModuleMetricPill(
                title: "Live",
                value: "\(connectedCount)/\(module.staff.routedSeatCount)",
                tint: connectedCount > 0 ? Color.mintGlow : Color.secondary
            )
            if hasTorch || hasAudio {
                ModuleMetricPill(
                    title: "State",
                    value: hasTorch && hasAudio ? "Torch + Audio" : (hasTorch ? "Torch active" : "Audio active"),
                    tint: module.accent
                )
            }
        }
    }

    private var pingButton: some View {
        Button {
            onPing()
        } label: {
            Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(module.accent)
        .disabled(!hasTargets)
    }

    private var torchButton: some View {
        Button {
            onTorch()
        } label: {
            Label("Torch", systemImage: "flashlight.on.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(module.accent)
        .disabled(!hasTargets)
    }

    private var soundButton: some View {
        Button {
            onSound()
        } label: {
            Label("Sound", systemImage: "speaker.wave.2.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(module.accent)
        .disabled(!hasTargets)
    }

    private var bothButton: some View {
        Button("Both") {
            onBoth()
        }
        .buttonStyle(.borderedProminent)
        .tint(module.accent)
        .disabled(!hasTargets)
    }
}

private struct ModuleMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct ModuleSeatBadge: View {
    let seat: LightStaffSeat
    let device: ChoirDevice?
    let status: DeviceStatus
    let accent: Color
    let isTriggered: Bool

    private var isRouteable: Bool {
        seat.legacySlot != nil
    }

    private var torchOn: Bool {
        device?.torchOn == true
    }

    private var audioPlaying: Bool {
        device?.audioPlaying == true
    }

    private var footerText: String {
        if let legacySlot = seat.legacySlot {
            return "#\(legacySlot)"
        }
        return "Open"
    }

    private var helpText: String {
        if let legacySlot = seat.legacySlot {
            if let device, !device.name.isEmpty {
                return "\(seat.displayLabel) · Legacy slot \(legacySlot) · \(device.name)"
            }
            return "\(seat.displayLabel) · Legacy slot \(legacySlot)"
        }
        return "\(seat.displayLabel) · No legacy route assigned"
    }

    var body: some View {
        VStack(spacing: 5) {
            Text("\(seat.seatNumber)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 18, height: 18)

                Circle()
                    .stroke(accent.opacity(audioPlaying ? 1 : 0.22), lineWidth: audioPlaying ? 2 : 1)
                    .frame(width: 22, height: 22)
            }

            Text(footerText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(isRouteable ? .secondary : Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: isTriggered ? 2 : 1)
        )
        .help(helpText)
    }

    private var circleFill: Color {
        if torchOn || isTriggered {
            return accent
        }
        if isRouteable {
            return status.color.opacity(0.82)
        }
        return Color.white.opacity(0.12)
    }

    private var backgroundFill: Color {
        if !isRouteable {
            return Color.white.opacity(0.04)
        }
        if torchOn || audioPlaying || isTriggered {
            return accent.opacity(0.18)
        }
        return Color.black.opacity(0.18)
    }

    private var borderColor: Color {
        if !isRouteable {
            return Color.white.opacity(0.08)
        }
        if isTriggered {
            return accent.opacity(0.95)
        }
        if audioPlaying {
            return accent.opacity(0.55)
        }
        return Color.white.opacity(0.08)
    }
}

#if DEBUG
struct ComposerConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        ComposerConsoleView()
            .environmentObject(ConsoleState())
            .frame(width: 1600, height: 980)
    }
}
#endif

private extension EventRecipe {
    var measureText: String {
        if let token = measureToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        if let measure {
            return "\(measure)"
        }
        return "—"
    }

    var positionLabel: String {
        guard let position, !position.isEmpty else { return "—" }
        let trimmed = position.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("beat") {
            return trimmed.replacingOccurrences(of: "beat", with: "Beat ")
        }
        return trimmed
    }
}
