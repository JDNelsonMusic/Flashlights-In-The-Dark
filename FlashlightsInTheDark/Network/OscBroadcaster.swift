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
import OSCKitCore      // OSCPacket

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
        // --- Encode OSCMessage ➜ ByteBuffer -----------------------------
        let buf = try OSCPacket(osc).byteBuffer(channel: channel)

        // --- Build broadcast envelope -----------------------------------
        let addr = try SocketAddress(ipAddress: "255.255.255.255", port: port)
        let env  = AddressedEnvelope(remoteAddress: addr, data: buf)

        // --- Send --------------------------------------------------------
        try await channel.writeAndFlush(env)
        print("→ \(osc.addressPattern)")
    }

    // --------------------------------------------------------------------
    // MARK: - De-initialisation
    // --------------------------------------------------------------------
    deinit {
        let ch = channel   // capture the channel (avoid capturing `self`)
        Task { try? await ch.close() }
    }
}
