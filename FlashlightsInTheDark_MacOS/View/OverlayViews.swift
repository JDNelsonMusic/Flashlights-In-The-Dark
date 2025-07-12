import SwiftUI

/// Animated full-screen flash effect driven by ConsoleState and strobe flags.
struct FullScreenFlashView: View {
    @EnvironmentObject var state: ConsoleState
    var strobeActive: Bool
    var strobeOn: Bool

    var body: some View {
        Group {
            if strobeActive {
                Color.mintGlow
                    .opacity(strobeOn ? 0.8 : 0.0)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: strobeActive)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Persistent purple/navy tint overlay that sits above all content.
struct ColorOverlayVeil: View {
    var body: some View {
        Color.purpleNavy
            .opacity(0.2)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .zIndex(1)
    }
}

#if DEBUG
struct OverlayViews_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            FullScreenFlashView(strobeActive: true, strobeOn: true)
            ColorOverlayVeil()
        }
        .environmentObject(ConsoleState())
    }
}
#endif
