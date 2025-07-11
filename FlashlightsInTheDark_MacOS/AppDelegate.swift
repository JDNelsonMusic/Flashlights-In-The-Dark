import Cocoa
import SwiftUI

/// AppDelegate to handle global keyboard events for lamp control.
class AppDelegate: NSObject, NSApplicationDelegate {
    var state: ConsoleState!
    private let midi = MIDIManager()
    /// Base MIDI note number for slot 0 (C2)
    private let baseNote: UInt8 = 36
    /// Offsets within an octave for each column (as per prototype scale)
    private let noteOffsets: [UInt8] = [0, 1, 3, 4, 7, 8, 10, 11]
    /// Sustain pedal state (SPACE key)
    private var sustainOn: Bool = false
    /// Currently held key slots
    private var heldSlots: Set<Int> = []
    /// Slots held beyond key release due to sustain
    private var sustainedSlots: Set<Int> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // -------------------------------------------------------------
            // SAFETY: unwrap self once, then ALWAYS use `self.` inside
            // -------------------------------------------------------------
            guard let self = self else { return event }
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  let c = chars.first else { return event }
            // Envelope trigger on “0” key (ADSR all lamps)
            if c == "0" {
                if event.type == .keyDown {
                    self.state.startEnvelopeAll()
                } else {
                    self.state.releaseEnvelopeAll()
                }
                return nil
            }
            // Mapping from keyboard key to real slot number
            let keyToSlot: [Character: Int] = [
                "2": 1, "3": 3, "4": 4, "5": 5, "u": 7, "7": 9, "9": 12,
                "q": 14, "w": 15, "d": 16, "e": 18, "r": 19, "k": 20, "i": 21,
                "8": 23, "o": 24, "p": 25, "a": 27, "s": 29, "j": 34, "l": 38,
                ";": 40, "x": 41, "c": 42, "v": 44, "m": 51, ",": 53, ".": 54
            ]
            if let slot = keyToSlot[c] {
                let isDown = (event.type == .keyDown)
                if isDown {
                    // ignore repeats
                    if self.heldSlots.contains(slot) { return nil }
                    self.heldSlots.insert(slot)
                    self.sustainedSlots.remove(slot)
                    // trigger flash and/or sound
                    switch self.state.keyboardTriggerMode {
                    case .torch:
                        self.state.flashOn(id: slot)
                    case .sound:
                        guard slot < self.state.devices.count else { return nil }
                        let device = self.state.devices[slot]
                        self.state.triggerSound(device: device)
                    case .both:
                        self.state.flashOn(id: slot)
                        guard slot < self.state.devices.count else { return nil }
                        let deviceBoth = self.state.devices[slot]
                        self.state.triggerSound(device: deviceBoth)
                    }
                    // send MIDI note on with scale mapping
                    let r = slot / 8
                    let col = slot % 8
                    let octaveOffset = UInt8(r * 12)
                    let offset = self.noteOffsets[col]
                    let noteOn = self.baseNote + octaveOffset + offset
                    self.midi.sendNoteOn(noteOn)
                } else {
                    // key up: handle sustain
                    if self.sustainOn {
                        self.heldSlots.remove(slot)
                        self.sustainedSlots.insert(slot)
                    } else {
                        self.heldSlots.remove(slot)
                        self.sustainedSlots.remove(slot)
                        // release flash and/or sound
                        switch self.state.keyboardTriggerMode {
                        case .torch:
                            self.state.flashOff(id: slot)
                        case .sound:
                            guard slot < self.state.devices.count else { return nil }
                            let device = self.state.devices[slot]
                            self.state.stopSound(device: device)
                        case .both:
                            self.state.flashOff(id: slot)
                            guard slot < self.state.devices.count else { return nil }
                            let deviceBothRel = self.state.devices[slot]
                            self.state.stopSound(device: deviceBothRel)
                        }
                        // send MIDI note off with mapping
                        let r = slot / 8
                        let col = slot % 8
                        let octaveOffset = UInt8(r * 12)
                        let offset = self.noteOffsets[col]
                        let noteOff = self.baseNote + octaveOffset + offset
                        self.midi.sendNoteOff(noteOff)
                    }
                }
                return nil
            }
            // Spacebar for sustain pedal
            if event.keyCode == 49 { // space
                if event.type == .keyDown {
                    self.sustainOn = true
                    self.midi.sendControlChange(64, value: 127)
                } else {
                    // release sustain pedal
                    self.sustainOn = false
                    // release any slots held due to sustain
                    self.sustainedSlots.forEach { slot in
                        switch self.state.keyboardTriggerMode {
                        case .torch:
                            self.state.flashOff(id: slot)
                        case .sound:
                            guard slot < self.state.devices.count else { return }
                            let device = self.state.devices[slot]
                            self.state.stopSound(device: device)
                        case .both:
                            self.state.flashOff(id: slot)
                            guard slot < self.state.devices.count else { return }
                            let device = self.state.devices[slot]
                            self.state.stopSound(device: device)
                        default:
                            break
                        }
                        // send MIDI note off for sustained slot
                        let r = slot / 8
                        let col = slot % 8
                        let octaveOffset = UInt8(r * 12)
                        let offset = self.noteOffsets[col]
                        let noteOff = self.baseNote + octaveOffset + offset
                        self.midi.sendNoteOff(noteOff)
                    }
                    self.sustainedSlots.removeAll()
                    self.midi.sendControlChange(64, value: 0)
                }
                return nil
            }
            return event
        }
    }
}