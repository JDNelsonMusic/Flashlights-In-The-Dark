import SwiftUI

/// Animated full-screen flash effect driven by ConsoleState and strobe flags.
struct FullScreenFlashView: View {
    @EnvironmentObject var state: ConsoleState
    var strobeActive: Bool
    var strobeOn: Bool

    var body: some View {
        Group {
            if state.isAnyTorchOn || strobeActive {
                Color.mintGlow
                    .opacity(strobeActive ? (strobeOn ? 0.8 : 0.0) : 0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: state.isAnyTorchOn || strobeActive)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Persistent purple/navy tint overlay that sits above all content.
struct ColorOverlayVeil: View {
    var body: some View {
        Color.purpleNavy
            .opacity(0.5)
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
