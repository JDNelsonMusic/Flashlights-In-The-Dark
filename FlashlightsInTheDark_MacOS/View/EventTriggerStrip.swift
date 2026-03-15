import SwiftUI

struct EventTriggerStrip: View {
    @EnvironmentObject var state: ConsoleState
    private let previewCount = 3
    @State private var jumpQuery: String = ""
    @State private var jumpFeedback: String?
    @FocusState private var jumpFieldFocused: Bool
    @State private var ignoreOutsideTap = false

    var body: some View {
        let previous = previousEvents()
        let next = nextEvents()

        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger Points")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.white)
                    Text(instructionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("Jump to trigger #…", text: $jumpQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit(handleQuickJump)
                            .focused($jumpFieldFocused)
                            .onTapGesture {
                                ignoreOutsideTap = true
                                state.isKeyCaptureEnabled = false
                                jumpFieldFocused = true
                            }
                        Button("Jump") { handleQuickJump() }
                            .disabled(jumpQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let feedback = jumpFeedback {
                        Text(feedback)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .onChange(of: jumpFieldFocused) { _, isFocused in
                handleFocusChange(isFocused)
            }

            if let current = currentEvent() {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            EventPreviewColumn(
                                title: "Previous",
                                events: previous.reversed(),
                                emphasis: .previous,
                                recentEventID: state.lastTriggeredEventID,
                                onSelect: { state.focusOnEvent(id: $0) }
                            )
                            .frame(minWidth: 190, maxWidth: 240, alignment: .top)

                            CurrentEventCard(
                                event: current,
                                isRecent: current.id == state.lastTriggeredEventID,
                                triggerAction: { state.triggerCurrentEvent() },
                                movePrevious: { state.moveToPreviousEvent() },
                                moveNext: { state.moveToNextEvent() }
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                            .transition(.scale)

                            EventPreviewColumn(
                                title: "Upcoming",
                                events: next,
                                emphasis: .upcoming,
                                recentEventID: state.lastTriggeredEventID,
                                onSelect: { state.focusOnEvent(id: $0) }
                            )
                            .frame(minWidth: 190, maxWidth: 240, alignment: .top)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            CurrentEventCard(
                                event: current,
                                isRecent: current.id == state.lastTriggeredEventID,
                                triggerAction: { state.triggerCurrentEvent() },
                                movePrevious: { state.moveToPreviousEvent() },
                                moveNext: { state.moveToNextEvent() }
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .transition(.scale)

                            if !previous.isEmpty {
                                EventPreviewGridSection(
                                    title: "Previous",
                                    events: previous.reversed(),
                                    emphasis: .previous,
                                    recentEventID: state.lastTriggeredEventID,
                                    onSelect: { state.focusOnEvent(id: $0) }
                                )
                            }

                            if !next.isEmpty {
                                EventPreviewGridSection(
                                    title: "Upcoming",
                                    events: next,
                                    emphasis: .upcoming,
                                    recentEventID: state.lastTriggeredEventID,
                                    onSelect: { state.focusOnEvent(id: $0) }
                                )
                            }
                        }
                    }

                    if let snapshot = state.lastTriggerCueSnapshot {
                        CueVerificationCard(
                            snapshot: snapshot,
                            isArmed: state.isArmed,
                            resendPending: { state.resendLastTriggeredCueToPendingSlots() },
                            resendStaff: { staff in
                                state.resendLastTriggeredCue(for: staff)
                            }
                        )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.currentEventIndex)
            } else {
                Text(state.eventLoadError ?? "No trigger-point bundle loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: 320)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .blendMode(.plusLighter)
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                if ignoreOutsideTap {
                    ignoreOutsideTap = false
                    return
                }
                if jumpFieldFocused {
                    jumpFieldFocused = false
                }
                state.isKeyCaptureEnabled = true
            }
        )
    }

    private func currentEvent() -> EventRecipe? {
        guard state.eventRecipes.indices.contains(state.currentEventIndex) else { return nil }
        return state.eventRecipes[state.currentEventIndex]
    }

    private func previousEvents() -> [EventRecipe] {
        guard !state.eventRecipes.isEmpty, state.currentEventIndex > 0 else { return [] }
        let start = max(0, state.currentEventIndex - previewCount)
        return Array(state.eventRecipes[start..<state.currentEventIndex])
    }

    private func nextEvents() -> [EventRecipe] {
        guard !state.eventRecipes.isEmpty else { return [] }
        let end = min(state.eventRecipes.count, state.currentEventIndex + previewCount + 1)
        let start = min(max(state.currentEventIndex + 1, 0), end)
        guard start < end else { return [] }
        let slice = state.eventRecipes[start..<end]
        return Array(slice)
    }

    private var instructionText: String {
        if currentEvent() != nil {
            return "←/→ cue · Shift+←/Shift+→ skip 10 · Space trigger"
        }
        return "Load the trigger-point bundle to enable cues"
    }

    private func handleQuickJump() {
        let trimmed = jumpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previousIndex = state.currentEventIndex
        if let targetIndex = resolveEventIndex(from: trimmed) {
            withAnimation {
                state.currentEventIndex = targetIndex
            }
            if state.eventRecipes.indices.contains(targetIndex) {
                let event = state.eventRecipes[targetIndex]
                jumpFeedback = "Jumped to Trigger #\(event.id)"
            } else {
                jumpFeedback = nil
            }
            jumpQuery = ""
        } else {
            jumpFeedback = "No trigger found for ‘\(trimmed)’"
            state.currentEventIndex = previousIndex
        }
        jumpFieldFocused = false
        state.isKeyCaptureEnabled = true
    }

    private func handleFocusChange(_ isFocused: Bool) {
        state.isKeyCaptureEnabled = !isFocused
    }

    private func resolveEventIndex(from query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let digitsOnly = trimmed
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let eventID = Int(digitsOnly) else { return nil }
        return state.eventRecipes.firstIndex(where: { $0.id == eventID })
    }
}

// MARK: - Supporting Cards ----------------------------------------------------
private enum EventCardEmphasis {
    case previous
    case upcoming
}

private struct EventPreviewCard: View {
    let event: EventRecipe
    let emphasis: EventCardEmphasis
    let isCurrent: Bool
    let isRecent: Bool

    private var opacity: Double {
        switch emphasis {
        case .previous: return 0.45
        case .upcoming: return 0.65
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("TP\(event.id)")
                .font(.headline)
                .foregroundStyle(.white)
            Text(event.measureText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(event.positionLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let summary = event.lighting?.summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minWidth: 110)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isRecent ? Color.mintGlow.opacity(0.6) : .clear, lineWidth: 1)
                )
        )
        .opacity(opacity)
        .scaleEffect(isRecent ? 1.05 : 0.9)
    }
}

private struct EventPreviewColumn: View {
    let title: String
    let events: [EventRecipe]
    let emphasis: EventCardEmphasis
    let recentEventID: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(events, id: \.id) { event in
                EventPreviewCard(
                    event: event,
                    emphasis: emphasis,
                    isCurrent: false,
                    isRecent: event.id == recentEventID
                )
                .onTapGesture { onSelect(event.id) }
            }

            ForEach(events.count..<3, id: \.self) { _ in
                EventPlaceholderCard()
            }
        }
    }
}

private struct EventPreviewGridSection: View {
    let title: String
    let events: [EventRecipe]
    let emphasis: EventCardEmphasis
    let recentEventID: Int?
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(events, id: \.id) { event in
                    EventPreviewCard(
                        event: event,
                        emphasis: emphasis,
                        isCurrent: false,
                        isRecent: event.id == recentEventID
                    )
                    .onTapGesture { onSelect(event.id) }
                }
            }
        }
    }
}

private struct CurrentEventCard: View {
    let event: EventRecipe
    let isRecent: Bool
    let triggerAction: () -> Void
    let movePrevious: () -> Void
    let moveNext: () -> Void
    private let tagColumns = [GridItem(.adaptive(minimum: 110, maximum: 220), spacing: 8, alignment: .leading)]
    private let staffColumns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trigger #\(event.id)")
                    .font(.title2)
                    .bold()
                Spacer()
                HStack(spacing: 16) {
                    Button(action: movePrevious) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    Button(action: moveNext) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            Text("Measure \(event.measureText) · \(event.positionLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let lighting = event.lighting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Light show")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lighting.summary ?? "No lighting summary")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.9))
                    LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 8) {
                        MiniTag(color: "Dynamics", detail: lighting.scoreDynamics ?? "—", isInactive: false)
                        MiniTag(color: "Span", detail: durationLabel(lighting.durationMs), isInactive: false)
                    }
                    LazyVGrid(columns: staffColumns, alignment: .leading, spacing: 8) {
                        ForEach(LightStaff.stageOrder) { staff in
                            LightStaffPlanCard(
                                staff: staff,
                                plan: lighting.parts[staff]
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Electronics routing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 6) {
                    MiniTag(color: "Soprano", detail: "Left", isInactive: false)
                    MiniTag(color: "Alto", detail: "Right", isInactive: false)
                    MiniTag(color: "Ten/Bass", detail: "Mono sum", isInactive: false)
                }
            }

            Button(action: triggerAction) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Fire Trigger (Space)")
                        .bold()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.mintGlow)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isRecent ? Color.mintGlow.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 14, x: 0, y: 8)
    }
}

private struct EventPlaceholderCard: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("#000")
                .font(.headline)
            Text("—")
                .font(.caption)
            Text(" ")
                .font(.caption2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minWidth: 80)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clear)
        )
        .opacity(0)
    }
}

// MARK: - Helper Views --------------------------------------------------------
private struct CueVerificationCard: View {
    let snapshot: TriggerCueSnapshot
    let isArmed: Bool
    let resendPending: () -> Void
    let resendStaff: (LightStaff) -> Void

    private let staffColumns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 10, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    headerCopy
                    Spacer(minLength: 8)
                    buttonCluster
                }

                VStack(alignment: .leading, spacing: 10) {
                    headerCopy
                    buttonCluster
                }
            }

            LazyVGrid(columns: staffColumns, spacing: 10) {
                ForEach(LightStaff.stageOrder) { staff in
                    CueStaffStatusCard(
                        staff: staff,
                        statuses: snapshot.statuses(for: staff),
                        resendAction: { resendStaff(staff) }
                    )
                    .disabled(!isArmed)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Cue Health")
                .font(.headline)
                .foregroundStyle(.white)
            Text("\(snapshot.headline) • \(snapshot.deliverySummary) • \(snapshot.pendingCount) pending • \(snapshot.unavailableCount) unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sent \(snapshot.sentAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonCluster: some View {
        HStack(spacing: 8) {
            Button("Resend Missing") {
                resendPending()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.mintGlow)
            .disabled(!isArmed || snapshot.pendingCount == 0 && snapshot.unavailableCount == 0)
        }
    }
}

private struct CueStaffStatusCard: View {
    let staff: LightStaff
    let statuses: [TriggerCueSlotStatus]
    let resendAction: () -> Void

    private var ackedCount: Int {
        statuses.filter { $0.state == .acked }.count
    }

    private var pendingCount: Int {
        statuses.filter { $0.state == .pending }.count
    }

    private var unavailableCount: Int {
        statuses.filter { $0.state == .unavailable }.count
    }

    private var latencyLabel: String {
        let latencies = statuses.compactMap(\.latencyMs)
        guard let minLatency = latencies.min(),
              let maxLatency = latencies.max() else {
            return "No ack yet"
        }
        if minLatency == maxLatency {
            return "\(minLatency) ms"
        }
        return "\(minLatency)-\(maxLatency) ms"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(staffAccent)
                    .frame(width: 8, height: 8)
                Text(staff.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(ackedCount)/\(statuses.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(pendingCount) pending · \(unavailableCount) unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(latencyLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(statuses) { status in
                    CueSeatBadge(status: status, accent: staffAccent)
                }
            }

            Button(pendingCount + unavailableCount > 0 ? "Resend Staff" : "All Acked") {
                resendAction()
            }
            .buttonStyle(.bordered)
            .tint(staffAccent)
            .disabled(pendingCount + unavailableCount == 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(staffAccent.opacity(0.22), lineWidth: 1)
        )
    }

    private var staffAccent: Color {
        switch staff {
        case .sopranoL1: return .slotGreen
        case .sopranoL2: return .hotMagenta
        case .tenorL: return .slotYellow
        case .bassL: return .lightRose
        case .altoL2: return .brightRed
        case .altoL1: return .royalBlue
        }
    }
}

private struct CueSeatBadge: View {
    let status: TriggerCueSlotStatus
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(status.seatNumber.map { String($0) } ?? "•")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            Circle()
                .fill(fillColor)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
        .help(statusHelpText)
    }

    private var fillColor: Color {
        switch status.state {
        case .acked:
            return .green
        case .pending:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var statusHelpText: String {
        switch status.state {
        case .acked:
            if let latencyMs = status.latencyMs {
                return "\(status.staffLabel) \(status.seatLabel) · acked in \(latencyMs) ms"
            }
            return "\(status.staffLabel) \(status.seatLabel) · acked"
        case .pending:
            return "\(status.staffLabel) \(status.seatLabel) · awaiting ack"
        case .unavailable:
            return "\(status.staffLabel) \(status.seatLabel) · \(status.failureReason ?? "unavailable")"
        }
    }
}

private struct MiniTag: View {
    let color: String
    let detail: String
    let isInactive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(color)
                .font(.caption2)
                .bold()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(isInactive ? Color.secondary.opacity(0.35) : Color.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(isInactive ? Color.white.opacity(0.04) : Color.white.opacity(0.12))
        )
        .opacity(isInactive ? 0.55 : 1)
    }
}

private struct LightStaffPlanCard: View {
    let staff: LightStaff
    let plan: EventLightPartPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(staffAccent)
                    .frame(width: 8, height: 8)
                Text(staff.label)
                    .font(.caption)
                    .bold()
            }
            Text(peakLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(plan?.summary ?? "No cue")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var peakLabel: String {
        guard let peak = plan?.peakLevel else { return "—" }
        return "\(Int((peak * 100).rounded()))% max"
    }

    private var staffAccent: Color {
        switch staff {
        case .sopranoL1: return .slotGreen
        case .sopranoL2: return .hotMagenta
        case .tenorL: return .slotYellow
        case .bassL: return .lightRose
        case .altoL2: return .brightRed
        case .altoL1: return .royalBlue
        }
    }
}

private extension EventRecipe {
    var measureText: String {
        if let token = measureToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        if let measure { return "\(measure)" }
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

private func durationLabel(_ durationMs: Double?) -> String {
    guard let durationMs else { return "—" }
    return String(format: "%.1fs", durationMs / 1000.0)
}
