import Cocoa
import SwiftUI

/// AppDelegate to handle global keyboard events for lamp control.
class AppDelegate: NSObject, NSApplicationDelegate {
    var state: ConsoleState!
    private let midi = MIDIManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  let c = chars.first else { return event }
            // Envelope trigger on “0” key (ADSR all lamps)
            if c == "0" {
                if event.type == .keyDown {
                    self?.state.startEnvelopeAll()
                } else {
                    self?.state.releaseEnvelopeAll()
                }
                return nil
            }
            // Map rows 1-4 & cols A-H
            let rows = ["12345678", "qwertyui", "asdfghjk", "zxcvbnm,"]
            for (r, row) in rows.enumerated() {
                if let idx = row.firstIndex(of: c) {
                    let col = row.distance(from: row.startIndex, to: idx)
                    let slot = r * 8 + col
                    if event.type == .keyDown {
                        // typing keyboard trigger modes
                        switch self?.state.keyboardTriggerMode {
                        case .torch:
                            self?.state.flashOn(id: slot)
                        case .sound:
                            if let device = self?.state.devices[slot] {
                                self?.state.triggerSound(device: device)
                            }
                        case .both:
                            self?.state.flashOn(id: slot)
                            if let device = self?.state.devices[slot] {
                                self?.state.triggerSound(device: device)
                            }
                        default:
                            break
                        }
                        // send MIDI note on
                        let noteOn = UInt8(36 + slot)
                        self?.midi.sendNoteOn(noteOn)
                    } else {
                        // typing keyboard trigger modes (release)
                        switch self?.state.keyboardTriggerMode {
                        case .torch:
                            self?.state.flashOff(id: slot)
                        case .sound:
                            if let device = self?.state.devices[slot] {
                                self?.state.stopSound(device: device)
                            }
                        case .both:
                            self?.state.flashOff(id: slot)
                            if let device = self?.state.devices[slot] {
                                self?.state.stopSound(device: device)
                            }
                        default:
                            break
                        }
                        // send MIDI note off
                        let noteOff = UInt8(36 + slot)
                        self?.midi.sendNoteOff(noteOff)
                    }
                    return nil
                }
            }
            // Spacebar for release envelope
            if event.keyCode == 49 { // space
                if event.type == .keyDown {
                    // sustain down
                    self?.midi.sendControlChange(64, value: 127)
                } else {
                    self?.state.releaseEnvelopeAll()
                    // sustain up
                    self?.midi.sendControlChange(64, value: 0)
                }
                return nil
            }
            return event
        }
    }
}