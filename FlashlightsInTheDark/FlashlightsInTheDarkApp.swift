//
//  FlashlightsInTheDarkApp.swift
//  FlashlightsInTheDark
//
//  Created by Jonathan Nelson on 5/15/25.
//

import SwiftUI
import AppKit

@main
struct FlashlightsInTheDarkApp: App {
    @StateObject private var state = ConsoleState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Provide state reference to AppDelegate for keyboard handling
        appDelegate.state = state
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onAppear {
                    // Immediately bootstrap network
                    Task { await state.startNetwork() }
                }
        }
    }
}
// Define a no-op stub to satisfy XCTest force-load symbol when built with -enable-testing
@_cdecl("__swift_FORCE_LOAD_$_XCTestSwiftSupport")
public func __swift_FORCE_LOAD_$_XCTestSwiftSupport() {}
