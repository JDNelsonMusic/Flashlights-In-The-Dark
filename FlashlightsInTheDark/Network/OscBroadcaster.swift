//
//  OscBroadcaster.swift
//  FlashlightsInTheDark
//
//  Created by ChatGPT on 5/15/25.
//

import Foundation
import NIOCore
import NIOPosix
import OSCKit          // OSCMessage, OSCAddressPattern

/// Broadcasts OSC messages over UDP to the local-network broadcast address
/// (`255.255.255.255`).  Designed for lightweight one-way cues.
// Slot mapping info for each device slot
struct SlotInfo: Codable {
    let ip: String
    let udid: String
    let name: String
}

public actor OscBroadcaster {
    // MARK: - Slot mapping (IP, UDID, singer name)  –––––––––––––––––––––––––––––
    let slotInfos: [Int: SlotInfo]

    // --------------------------------------------------------------------
    // MARK: - Stored properties
    // --------------------------------------------------------------------
    let channel: Channel
    let port: Int

    // --------------------------------------------------------------------
    // MARK: - Initialisation
    // --------------------------------------------------------------------
    public init(
        port: Int = 9000,
        routingFile: URL = Bundle.main.url(forResource: "flash_ip+udid_map", withExtension: "json")!,
        eventLoopGroup: MultiThreadedEventLoopGroup = .init(numberOfThreads: 1)
    ) async throws {
        self.port = port
        // load slot mapping once at launch
        if
            let data = try? Data(contentsOf: routingFile),
            let dict = try? JSONDecoder().decode([String: SlotInfo].self, from: data)
        {
            self.slotInfos = Dictionary(uniqueKeysWithValues:
                dict.compactMap { key, info in
                    guard let slot = Int(key) else { return nil }
                    return (slot, info)
                }
            )
        } else {
            self.slotInfos = [:]
            print("⚠️  No flash_ip+udid_map.json found – falling back to pure broadcast.")
        }

        // Datagram bootstrap with broadcast privileges.
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_broadcast), value: 1)

        // Bind to *all* interfaces on the chosen port.
        self.channel = try await bootstrap
            .bind(host: "0.0.0.0", port: port)
            .get()

        print("UDP broadcaster ready on 0.0.0.0:\(port) ✅")
    }

    // --------------------------------------------------------------------
    // MARK: - Public API
    // --------------------------------------------------------------------
    /// Broadcast a single OSC message to 255.255.255.255:9000
    public func send(_ osc: OSCMessage) async throws {
        // --- Encode OSCMessage ➜ Data -----------------------------------
        let data = try osc.rawData()

        // --- Copy into SwiftNIO ByteBuffer ------------------------------
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        // --- Build broadcast envelope -----------------------------------
        let addr     = try SocketAddress(ipAddress: "255.255.255.255", port: port)
        let envelope = AddressedEnvelope(remoteAddress: addr, data: buffer)

        // --- Send --------------------------------------------------------
        try await channel.writeAndFlush(envelope)
        print("→ \(osc.addressPattern.stringValue)")
    }

    // --------------------------------------------------------------------
    // MARK: - De-initialisation
    // --------------------------------------------------------------------
    deinit {
        let ch = channel   // capture the channel (avoid capturing `self`)
        Task { try? await ch.close() }
    }
}
