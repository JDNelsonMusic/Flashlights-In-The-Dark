import Foundation
import OSCKit

/// Lightweight wrapper so we don’t repeat the IP logic everywhere.
enum OscSender {
    static let port: UInt16 = 9000

    /// Send an OSC bundle to a single phone or broadcast.
    static func send(bundle: OSCBundle, to ip: String) {
        let targetHost = (ip == "broadcast") ? "255.255.255.255" : ip
        do {
            let client = OSCClient()
            if ip == "broadcast" {
                client.isIPv4BroadcastEnabled = true
            }
            try client.start()
            try client.send(bundle, to: targetHost, port: Self.port)
            print("✅ [OSC] Sent to \(targetHost): \(bundle.elements)")
        } catch {
            print("❌ [OSC] Failed to send to \(targetHost): \(error)")
        }
    }
}
