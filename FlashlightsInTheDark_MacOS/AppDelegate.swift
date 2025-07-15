import Cocoa
import SwiftUI

/// AppDelegate to handle global keyboard events for lamp control.
class AppDelegate: NSObject, NSApplicationDelegate {
    var state: ConsoleState!
    private let midi = MIDIManager()
    /// Base MIDI note number for slot 1
    private let baseNote: UInt8 = 1
    /// Offsets within an octave for each column (as per prototype scale)
    private let noteOffsets: [UInt8] = [0, 1, 3, 4, 7, 8, 10, 11]
    /// Sustain pedal state (SPACE key)
    private var sustainOn: Bool = false
    /// Currently held key slots
    private var heldSlots: Set<Int> = []
    /// Slots held beyond key release due to sustain
    private var sustainedSlots: Set<Int> = []
    /// Function key mapping (F1-F9 -> triple trigger group)
    private let fKeyToGroup: [UInt16: Int] = [
        122: 1, // F1
        120: 2, // F2
        99: 3,  // F3
        118: 4, // F4
        96: 5,  // F5
        97: 6,  // F6
        98: 7,  // F7
        100: 8, // F8
        101: 9  // F9
    ]

    private let groupSlots: [Int: [Int]] = [
        1: [27, 41, 42],
        2: [1, 14, 15],
        3: [16, 29, 44],
        4: [3, 4, 18],
        5: [7, 19, 34],
        6: [9, 20, 21],
        7: [23, 38, 51],
        8: [12, 24, 25],
        9: [40, 53, 54]
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // -------------------------------------------------------------
            // SAFETY: unwrap self once, then ALWAYS use `self.` inside
            // -------------------------------------------------------------
            guard let self = self else { return event }
            if let group = self.fKeyToGroup[event.keyCode], event.type == .keyDown {
                if let slots = self.groupSlots[group] {
                    self.state.triggerSlots(realSlots: slots)
                }
                return nil
            }
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  let c = chars.first else { return event }
            // Glow Ramp toggle on "]" and Slow Glow Ramp on "["
            if c == "]" && event.type == .keyDown {
                self.state.glowRampActive.toggle()
                return nil
            }
            if c == "[" && event.type == .keyDown {
                self.state.slowGlowRampActive.toggle()
                return nil
            }
            // Mapping from keyboard key to real slot number
            let keyToSlot = KeyboardKeyToSlot
            if let slot = keyToSlot[c] {
                let idx = slot - 1
                let isDown = (event.type == .keyDown)
                if isDown {
                    // ignore repeats
                    if self.heldSlots.contains(idx) { return nil }
                    self.heldSlots.insert(idx)
                    self.sustainedSlots.remove(idx)
                    // trigger flash and/or sound
                    switch self.state.keyboardTriggerMode {
                    case .torch:
                        self.state.flashOn(id: idx)
                    case .sound:
                        guard idx < self.state.devices.count else { return nil }
                        let device = self.state.devices[idx]
                        self.state.triggerSound(device: device)
                    case .both:
                        self.state.flashOn(id: idx)
                        guard idx < self.state.devices.count else { return nil }
                        let deviceBoth = self.state.devices[idx]
                        self.state.triggerSound(device: deviceBoth)
                    }
                    // send MIDI note on with scale mapping
                    let r = idx / 8
                    let col = idx % 8
                    let octaveOffset = UInt8(r * 12)
                    let offset = self.noteOffsets[col]
                    let noteOn = self.baseNote + octaveOffset + offset
                    self.midi.sendNoteOn(noteOn)
                } else {
                    // key up: handle sustain
                    if self.sustainOn {
                        self.heldSlots.remove(idx)
                        self.sustainedSlots.insert(idx)
                    } else {
                        self.heldSlots.remove(idx)
                        self.sustainedSlots.remove(idx)
                        // release flash and/or sound
                        switch self.state.keyboardTriggerMode {
                        case .torch:
                            self.state.flashOff(id: idx)
                        case .sound:
                            guard idx < self.state.devices.count else { return nil }
                            let device = self.state.devices[idx]
                            self.state.stopSound(device: device)
                        case .both:
                            self.state.flashOff(id: idx)
                            guard idx < self.state.devices.count else { return nil }
                            let deviceBothRel = self.state.devices[idx]
                            self.state.stopSound(device: deviceBothRel)
                        }
                        // send MIDI note off with mapping
                        let r = idx / 8
                        let col = idx % 8
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

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            state.blackoutAll()
            state.stopAllSounds()
            state.shutdown()
        }
    }
}