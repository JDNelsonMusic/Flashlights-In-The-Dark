import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: ConsoleState
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ComposerConsoleView()
            .environmentObject(state)
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
