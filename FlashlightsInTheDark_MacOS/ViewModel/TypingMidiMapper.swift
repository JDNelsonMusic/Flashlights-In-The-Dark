import Foundation

/// Maps typing keyboard characters to MIDI note numbers.
struct TypingMidiMapper {
    private let keyToNote: [Character: UInt8]

    init(keyToSlot: [Character: Int]) {
        var map: [Character: UInt8] = [:]
        for (key, slot) in keyToSlot {
            if slot > 0 && slot < 128 {
                map[key] = UInt8(slot)
            }
        }
        self.keyToNote = map
    }

    func note(for char: Character) -> UInt8? {
        keyToNote[char]
    }
}
