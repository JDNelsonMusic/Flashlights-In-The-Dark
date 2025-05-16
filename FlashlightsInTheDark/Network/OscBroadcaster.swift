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
public actor OscBroadcaster {

    // --------------------------------------------------------------------
    // MARK: - Stored properties
    // --------------------------------------------------------------------
    private let channel: Channel
    private let port: Int

    // --------------------------------------------------------------------
    // MARK: - Initialisation
    // --------------------------------------------------------------------
    public init(
        port: Int = 9000,
        eventLoopGroup: MultiThreadedEventLoopGroup = .init(numberOfThreads: 1)
    ) async throws {
        self.port = port

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
