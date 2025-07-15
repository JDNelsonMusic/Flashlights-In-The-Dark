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
    }
}
