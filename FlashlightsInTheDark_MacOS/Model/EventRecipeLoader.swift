import Foundation

enum EventRecipeLoaderError: Error {
    case fileNotFound
    case decodingFailed
}

struct EventRecipeLoader {
    private let fileName = "event_recipes"
    private let fileExtension = "json"

    func loadRecipes() throws -> [EventRecipe] {
        if let bundled = Bundle.main.url(forResource: fileName, withExtension: fileExtension) {
            return try decode(from: bundled)
        }

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("FlashlightsInTheDark_MacOS/Resources")
            .appendingPathComponent("\(fileName).\(fileExtension)")

        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw EventRecipeLoaderError.fileNotFound
        }
        return try decode(from: fallback)
    }

    private func decode(from url: URL) throws -> [EventRecipe] {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let bundle = try decoder.decode(EventRecipeBundle.self, from: data)
            return bundle.events.map(sanitizeEvent)
        } catch {
            throw EventRecipeLoaderError.decodingFailed
        }
    }

    private func sanitizeEvent(_ event: EventRecipe) -> EventRecipe {
        var cleaned: [PrimerColor: PrimerAssignment] = [:]
        for (color, assignment) in event.primerAssignments {
            guard let rawSample = assignment.oscFileName,
                  let canonicalSample = canonicalSamplePath(for: rawSample) else { continue }
            let trimmedNote = assignment.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned[color] = PrimerAssignment(sample: canonicalSample, note: trimmedNote)
        }
        return EventRecipe(
            id: event.id,
            measure: event.measure,
            position: event.position,
            primerAssignments: cleaned
        )
    }

    private func canonicalSamplePath(for raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("./") {
            value.removeFirst(2)
        }

        let prefix = "primerTones/"
        if value.lowercased().hasPrefix(prefix.lowercased()) {
            value.removeFirst(prefix.count)
        }

        var fileName = value
        let lower = fileName.lowercased()
        if lower.hasPrefix("short") {
            let suffix = lower.dropFirst("short".count)
            fileName = "Short" + suffix
        } else if lower.hasPrefix("long") {
            let suffix = lower.dropFirst("long".count)
            fileName = "Long" + suffix
        }

        if !fileName.lowercased().hasSuffix(".mp3") {
            fileName += ".mp3"
        }

        return prefix + fileName
    }
}
