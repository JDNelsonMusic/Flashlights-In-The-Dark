import Foundation
import OSCKit

/// Periodically multicasts /sync OSC messages containing an NTP-style
/// timestamp so that phone clients can clock-lock to the laptop.
public final class ClockSyncService {
    // ---------------------------------------------------------------------
    // MARK: – Stored properties
    // ---------------------------------------------------------------------
    private let broadcaster: OscBroadcaster
    /// Keeps a strong reference to the repeating task so we can cancel it.
    private var loop: Task<Void, Never>?

    // ---------------------------------------------------------------------
    // MARK: – Init / Deinit
    // ---------------------------------------------------------------------
    public init(broadcaster: OscBroadcaster) {
        self.broadcaster = broadcaster                       // ✅ allowed

        // Create the ticker **before** we touch actor-isolated state.
        let ticker = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)   // 200 ms
                    let ts = OSCTimeTag(
                        UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
                    )
                    try await self.broadcaster.send(
                        SyncMessage(timestamp: ts).encode()
                    )
                    print("✔︎ /sync @ \(ts)")                // String-Convertible
                } catch {
                    // ignore any errors (sleep or send)
                }
            }
        }

        self.loop = ticker                                   // isolation OK now
    }

    deinit {
        loop?.cancel()
    }
}