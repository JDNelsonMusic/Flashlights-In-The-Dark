import Foundation

// MARK: - Event Recipe Bundle -------------------------------------------------
/// Top-level bundle describing all pre-authored event recipes.
public struct EventRecipeBundle: Decodable {
    public let source: String?
    public let eventCount: Int?
    public let generated: String?
    public let events: [EventRecipe]
}

// MARK: - Event Recipe --------------------------------------------------------
public struct EventRecipe: Identifiable, Decodable {
    public let id: Int
    /// Official trigger-score measure for this event, not the sung-note onset.
    public let measure: Int?
    /// Official trigger-score beat position for this event, not the sung-note onset.
    public let position: String?
    public let primerAssignments: [PrimerColor: PrimerAssignment]
    public let lighting: EventLighting?

    enum CodingKeys: String, CodingKey {
        case id, measure, position, primer, lighting
    }

    public init(
        id: Int,
        measure: Int?,
        position: String?,
        primerAssignments: [PrimerColor: PrimerAssignment],
        lighting: EventLighting? = nil
    ) {
        self.id = id
        self.measure = measure
        self.position = position
        self.primerAssignments = primerAssignments
        self.lighting = lighting
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        measure = try container.decodeIfPresent(Int.self, forKey: .measure)
        position = try container.decodeIfPresent(String.self, forKey: .position)
        if let rawPrimer = try container.decodeIfPresent([String: PrimerAssignment].self, forKey: .primer) {
            var mapped: [PrimerColor: PrimerAssignment] = [:]
            for (key, assignment) in rawPrimer {
                if let color = PrimerColor(rawValue: key.lowercased()) {
                    mapped[color] = assignment
                }
            }
            primerAssignments = mapped
        } else {
            primerAssignments = [:]
        }
        lighting = try container.decodeIfPresent(EventLighting.self, forKey: .lighting)
    }
}

// MARK: - Lighting ------------------------------------------------------------
public struct EventLighting: Decodable {
    public let summary: String?
    public let scoreDynamics: String?
    public let designTags: [String]
    public let durationMs: Double?
    public let parts: [LightStaff: EventLightPartPlan]

    enum CodingKeys: String, CodingKey {
        case summary
        case scoreDynamics
        case designTags
        case durationMs
        case parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        scoreDynamics = try container.decodeIfPresent(String.self, forKey: .scoreDynamics)
        designTags = try container.decodeIfPresent([String].self, forKey: .designTags) ?? []
        durationMs = try container.decodeIfPresent(Double.self, forKey: .durationMs)

        if let rawParts = try container.decodeIfPresent([String: EventLightPartPlan].self, forKey: .parts) {
            var mapped: [LightStaff: EventLightPartPlan] = [:]
            for (key, value) in rawParts {
                if let staff = LightStaff(rawValue: key) {
                    mapped[staff] = value
                }
            }
            parts = mapped
        } else {
            parts = [:]
        }
    }
}

public struct EventLightPartPlan: Decodable {
    public let label: String
    public let summary: String
    public let motion: String
    public let peakLevel: Double
    public let durationMs: Double
    public let keyframes: [EventLightKeyframe]
}

public struct EventLightKeyframe: Decodable {
    public let atMs: Double
    public let level: Double
}

public enum LightStaff: String, CaseIterable, Codable, Identifiable {
    case sopranoL1 = "soprano_l1"
    case sopranoL2 = "soprano_l2"
    case tenorL = "tenor_l"
    case bassL = "bass_l"
    case altoL2 = "alto_l2"
    case altoL1 = "alto_l1"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sopranoL1: return "Sop-L1"
        case .sopranoL2: return "Sop-L2"
        case .tenorL: return "Ten-L"
        case .bassL: return "Bass-L"
        case .altoL2: return "Alto-L2"
        case .altoL1: return "Alto-L1"
        }
    }

    public static let stageOrder: [LightStaff] = [
        .sopranoL1,
        .sopranoL2,
        .tenorL,
        .bassL,
        .altoL2,
        .altoL1
    ]
}

// MARK: - Primer Assignment ---------------------------------------------------
public struct PrimerAssignment: Decodable {
    public let sample: String?
    public let note: String?

    /// Returns the filename (including subdirectory) that should be sent to clients.
    public var oscFileName: String? {
        guard let sample else { return nil }
        return sample.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the filename within the app bundle for local playback, normalising
    /// the short/long prefix to match the capitalised resource filenames.
    public var normalizedMacFileName: String? {
        guard var sample = oscFileName else { return nil }
        if sample.hasPrefix("primerTones/") {
            let suffix = sample.dropFirst("primerTones/".count)
            sample = String(suffix)
        }
        let lowered = sample.lowercased()
        if lowered.hasPrefix("short") {
            let numberPart = lowered.dropFirst("short".count)
            return "primerTones/Short\(numberPart)"
        } else if lowered.hasPrefix("long") {
            let numberPart = lowered.dropFirst("long".count)
            return "primerTones/Long\(numberPart)"
        }
        return "primerTones/\(sample)"
    }
}

// MARK: - Primer Color --------------------------------------------------------
/// Represents the nine Light Chorus colour groups used throughout the console.
public enum PrimerColor: String, CaseIterable, Codable, Identifiable {
    case blue
    case red
    case green
    case purple
    case yellow
    case pink
    case orange
    case magenta
    case cyan

    public var id: String { rawValue }

    /// Human-friendly display label.
    public var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .red: return "Red"
        case .green: return "Green"
        case .purple: return "Purple"
        case .yellow: return "Yellow"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .magenta: return "Magenta"
        case .cyan: return "Cyan"
        }
    }

    /// Associated Light Chorus group index (1-based) used elsewhere in the app.
    public var groupIndex: Int {
        switch self {
        case .blue: return 1
        case .red: return 2
        case .green: return 3
        case .purple: return 4
        case .yellow: return 5
        case .pink: return 6
        case .orange: return 7
        case .magenta: return 8
        case .cyan: return 9
        }
    }

    /// Returns the stereo placement group for bundled playback on macOS.
    public var panPosition: PrimerPanPosition {
        switch self {
        case .blue, .red, .green: return .left
        case .purple, .yellow, .pink: return .center
        case .orange, .magenta, .cyan: return .right
        }
    }
}

// MARK: - Pan Position --------------------------------------------------------
public enum PrimerPanPosition {
    case left
    case center
    case right
}
