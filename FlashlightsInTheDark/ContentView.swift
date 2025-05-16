import SwiftUI

struct ContentView: View {
    @StateObject private var state = ConsoleState()

    var body: some View {
        ComposerConsoleView()
            .environmentObject(state)
            .frame(minWidth: 820, minHeight: 550)   // roomy default window
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
