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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.state = state
                    // Immediately bootstrap network
                    Task { await state.startNetwork() }
                }
        }
        .environmentObject(state)
        .commands {
            MenuCommands(state: state)
        }
    }
}
// Define a no-op stub to satisfy XCTest force-load symbol when built with -enable-testing
@_cdecl("__swift_FORCE_LOAD_$_XCTestSwiftSupport")
public func __swift_FORCE_LOAD_$_XCTestSwiftSupport() {}
