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
        let leadingPlaceholders = max(0, previewCount - previous.count)
        let trailingPlaceholders = max(0, previewCount - next.count)

        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event Recipes")
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
                        TextField("Jump to event or measure…", text: $jumpQuery)
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
            .onChange(of: jumpFieldFocused, perform: handleFocusChange)

            HStack(alignment: .center, spacing: 16) {
                ForEach(0..<leadingPlaceholders, id: \.self) { _ in
                    EventPlaceholderCard()
                }

                ForEach(previous.reversed(), id: \.id) { event in
                    EventPreviewCard(event: event,
                                     emphasis: .previous,
                                     isCurrent: false,
                                     isRecent: event.id == state.lastTriggeredEventID)
                        .onTapGesture { state.focusOnEvent(id: event.id) }
                }

                if let current = currentEvent() {
                    CurrentEventCard(event: current,
                                     isRecent: current.id == state.lastTriggeredEventID,
                                     triggerAction: { state.triggerCurrentEvent() },
                                     movePrevious: { state.moveToPreviousEvent() },
                                     moveNext: { state.moveToNextEvent() })
                        .transition(.scale)
                } else {
                    Text(state.eventLoadError ?? "No timeline loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: 320)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                ForEach(next, id: \.id) { event in
                    EventPreviewCard(event: event,
                                     emphasis: .upcoming,
                                     isCurrent: false,
                                     isRecent: event.id == state.lastTriggeredEventID)
                        .onTapGesture { state.focusOnEvent(id: event.id) }
                }

                ForEach(0..<trailingPlaceholders, id: \.self) { _ in
                    EventPlaceholderCard()
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.currentEventIndex)
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
            return "← / → to cue · Space to trigger"
        }
        return "Load event recipes to enable triggers"
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
                jumpFeedback = "Jumped to Event #\(event.id)"
            } else {
                jumpFeedback = nil
            }
            jumpQuery = ""
        } else {
            jumpFeedback = "No event found for ‘\(trimmed)’"
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

        let normalized = trimmed.replacingOccurrences(of: "#", with: "")

        if let eventID = Int(normalized) {
            if let idx = state.eventRecipes.firstIndex(where: { $0.id == eventID }) {
                return idx
            }
        }

        let measureIndex = resolveMeasureQuery(from: normalized)
        if let measureIndex {
            return measureIndex
        }

        // Fallback: search by position string fragment
        let lowerFragment = normalized.lowercased()
        if let idx = state.eventRecipes.firstIndex(where: { recipe in
            recipe.position?.lowercased().contains(lowerFragment) == true
        }) {
            return idx
        }

        return nil
    }

    private func resolveMeasureQuery(from raw: String) -> Int? {
        var query = raw.lowercased()
        if query.hasPrefix("measure") {
            query.removeFirst("measure".count)
        } else if query.hasPrefix("m") {
            query.removeFirst()
        }
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var beatFragment: String?
        var measureString = query

        if let separatorIndex = query.firstIndex(where: { $0 == "." || $0 == " " || $0 == "-" }) {
            measureString = String(query[..<separatorIndex])
            let remainder = String(query[separatorIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
            if !remainder.isEmpty {
                beatFragment = remainder
            }
        }

        guard let measure = Int(measureString) else { return nil }

        let matching = state.eventRecipes.enumerated().filter { $0.element.measure == measure }

        guard !matching.isEmpty else { return nil }

        if let beatFragment, !beatFragment.isEmpty {
            let loweredFragment = beatFragment.replacingOccurrences(of: "of", with: " of ").lowercased()
            if let match = matching.first(where: { $0.element.position?.lowercased().contains(loweredFragment) == true }) {
                return match.offset
            }
        }

        return matching.first?.offset
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
            Text("#\(event.id)")
                .font(.headline)
                .foregroundStyle(.white)
            Text(event.measureText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(event.position ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minWidth: 80)
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

private struct CurrentEventCard: View {
    let event: EventRecipe
    let isRecent: Bool
    let triggerAction: () -> Void
    let movePrevious: () -> Void
    let moveNext: () -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(minimum: 90), spacing: 6, alignment: .leading),
        GridItem(.flexible(minimum: 90), spacing: 6, alignment: .leading),
        GridItem(.flexible(minimum: 90), spacing: 6, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event #\(event.id)")
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
            Text("Measure \(event.measureText) · \(event.position ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                let activeCount = event.primerAssignments.count
                Text("Primer tones ready: \(activeCount) parts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(PrimerColor.allCases, id: \.id) { color in
                        let assignment = event.primerAssignments[color]
                        MiniTag(color: color.displayName,
                                detail: assignment?.note ?? "—",
                                isInactive: assignment == nil)
                    }
                }
            }

            Button(action: triggerAction) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Trigger (Space)")
                        .bold()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mintGlow)
        }
        .padding(20)
        .frame(minWidth: 260)
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

private extension EventRecipe {
    var measureText: String {
        if let measure { return "\(measure)" }
        return "—"
    }
}
