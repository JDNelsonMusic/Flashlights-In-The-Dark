import SwiftUI

struct ContentView: View {
    @StateObject private var state = ConsoleState()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ComposerConsoleView()
            .environmentObject(state)
            .task { await state.startNetwork() }           // bootstrap NIO + clock
            .onChange(of: phase) { _, newPhase in
                if newPhase != .active { state.shutdown() }
            }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
