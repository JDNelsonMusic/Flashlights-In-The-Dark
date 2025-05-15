//
//  ContentView.swift
//  FlashlightsInTheDark
//
//  Created by Jonathan Nelson on 5/15/25.
//

import SwiftUI
import NIO
import OSCKit

/// Root view for the macOS “Composer Console”.
/// It simply verifies the two package dependencies are linked
/// and shows a basic UI placeholder that we can expand later.
struct ContentView: View {
    @State private var logMessage: String = "Initializing…"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flashlight.on.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("Flashlights in the Dark")
                .font(.title2)
                .fontWeight(.semibold)

            Text(logMessage)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear(perform: testPackageLinkage)
    }

    /// Simple runtime check that SwiftNIO + OSCKit are functional.
    private func testPackageLinkage() {
        // Spin up a tiny EventLoop just to prove NIO works without crashing.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Touch an OSCKit API so the optimiser can't tree‑shake it away.
        let _ = OSCAddressPattern("/hello")

        // If we got this far, both packages are present and initialised.
        logMessage = "SwiftNIO + OSCKit ready ✅"
        print(logMessage)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
