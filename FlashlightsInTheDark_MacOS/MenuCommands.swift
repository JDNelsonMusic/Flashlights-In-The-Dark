import SwiftUI

struct MenuCommands: Commands {
    @EnvironmentObject var state: ConsoleState

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save '.flashlights' Session") {
                state.saveSession()
            }
            .keyboardShortcut("s")
            Button("Save As…") {
                state.saveSessionAs()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open '.flashlights' Session") {
                state.openSession()
            }
        }
        CommandMenu("Event Timeline") {
            Button("Trigger Current Event") {
                state.triggerCurrentEvent()
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("Previous Event") {
                state.moveToPreviousEvent()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Event") {
                state.moveToNextEvent()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }
}
