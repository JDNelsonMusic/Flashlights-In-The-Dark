import SwiftUI

struct EventTriggerStrip: View {
    @EnvironmentObject var state: ConsoleState
    private let previewCount = 3

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Event Recipes")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.white)
                Spacer()
                Text(instructionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .center, spacing: 16) {
                ForEach(previousEvents().reversed(), id: \.id) { event in
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

                ForEach(nextEvents(), id: \.id) { event in
                    EventPreviewCard(event: event,
                                     emphasis: .upcoming,
                                     isCurrent: false,
                                     isRecent: event.id == state.lastTriggeredEventID)
                        .onTapGesture { state.focusOnEvent(id: event.id) }
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
        let slice = state.eventRecipes[(state.currentEventIndex + 1)..<end]
        return Array(slice)
    }

    private var instructionText: String {
        if currentEvent() != nil {
            return "← / → to cue · Space to trigger"
        }
        return "Load event recipes to enable triggers"
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

    private var engagedParts: [PrimerColor] {
        event.primerAssignments.keys.sorted { $0.rawValue < $1.rawValue }
    }

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

            if !engagedParts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Primer tones ready: \(engagedParts.count) parts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(engagedParts, id: \.id) { color in
                            if let assignment = event.primerAssignments[color] {
                                MiniTag(color: color.displayName, detail: assignment.note ?? "")
                            }
                        }
                    }
                }
            } else {
                Text("No primer tones in this event")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Helper Views --------------------------------------------------------
private struct MiniTag: View {
    let color: String
    let detail: String

    var body: some View {
        HStack(spacing: 4) {
            Text(color)
                .font(.caption2)
                .bold()
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}

private extension EventRecipe {
    var measureText: String {
        if let measure { return "\(measure)" }
        return "—"
    }
}
