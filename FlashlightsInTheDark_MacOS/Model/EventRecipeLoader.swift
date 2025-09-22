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
            return bundle.events
        } catch {
            throw EventRecipeLoaderError.decodingFailed
        }
    }
}
