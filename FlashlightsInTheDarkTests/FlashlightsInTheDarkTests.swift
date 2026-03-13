//
//  FlashlightsInTheDarkTests.swift
//  FlashlightsInTheDarkTests
//
//  Created by Jonathan Nelson on 5/15/25.
//

import XCTest
import OSCKit
@testable import FlashlightsInTheDark

final class OscMessagesTests: XCTestCase {
    func testFlashOnRoundTrip() {
        let original = FlashOn(index: 1, intensity: 0.5)
        let msg = original.encode()
        let decoded = FlashOn(from: msg)
        XCTAssertEqual(decoded?.index, original.index)
        XCTAssertEqual(decoded?.intensity, original.intensity)
    }

    func testFlashOffRoundTrip() {
        let original = FlashOff(index: 2)
        let msg = original.encode()
        let decoded = FlashOff(from: msg)
        XCTAssertEqual(decoded?.index, original.index)
    }

    func testAudioPlayRoundTrip() {
        let original = AudioPlay(index: 3, file: "test.wav", gain: 0.75, startAtMs: 1234.5)
        let msg = original.encode()
        let decoded = AudioPlay(from: msg)
        XCTAssertEqual(decoded?.index, original.index)
        XCTAssertEqual(decoded?.file, original.file)
        XCTAssertEqual(decoded?.gain, original.gain)
        XCTAssertEqual(decoded?.startAtMs, original.startAtMs)
    }

    func testAudioPlayBackwardCompatibility() {
        let legacy = AudioPlay(index: 2, file: "legacy.mp3", gain: 1.0)
        let msg = legacy.encode()
        let decoded = AudioPlay(from: msg)
        XCTAssertEqual(decoded?.startAtMs, nil)
    }

    func testAudioStopRoundTrip() {
        let original = AudioStop(index: 4)
        let msg = original.encode()
        let decoded = AudioStop(from: msg)
        XCTAssertEqual(decoded?.index, original.index)
    }

    func testMicRecordRoundTrip() {
        let original = MicRecord(index: 5, maxDuration: 10.0)
        let msg = original.encode()
        let decoded = MicRecord(from: msg)
        XCTAssertEqual(decoded?.index, original.index)
        XCTAssertEqual(decoded?.maxDuration, original.maxDuration)
    }

    func testSyncMessageRoundTrip() {
        let ts: OSCTimeTag = OSCTimeTag(UInt64(1_234_567_890))
        let original = SyncMessage(timestamp: ts)
        let msg = original.encode()
        let decoded = SyncMessage(from: msg)
        XCTAssertEqual(decoded?.timestamp, original.timestamp)
    }
}

@MainActor
final class ConsoleStateTests: XCTestCase {
    func testDeviceDiscoveryRetainsPhysicalDeviceIdentityAcrossSlotChanges() {
        let state = ConsoleState()

        state.deviceDiscovered(slot: 1, ip: "10.0.0.1", deviceId: "device-A")
        XCTAssertEqual(state.devices[0].udid, "device-A")
        XCTAssertEqual(state.devices[0].listeningSlot, 1)

        state.deviceDiscovered(slot: 27, ip: "10.0.0.27", deviceId: "device-A")

        XCTAssertEqual(state.devices[0].udid, "device-A")
        XCTAssertEqual(state.devices[0].ip, "10.0.0.27")
        XCTAssertEqual(state.devices[0].listeningSlot, 27)
        XCTAssertEqual(state.statuses[state.devices[0].id], .live)
        XCTAssertNotEqual(state.devices[26].udid, "device-A")
        XCTAssertNotNil(state.lastHelloDate(forSlot: 27))
    }

    func testTriggerSlotsUsesAssignedListeningSlot() {
        let state = ConsoleState()
        state.isArmed = true
        state.keyboardTriggerMode = .torch

        state.assignSlot(device: state.devices[0], slot: 27)
        state.assignSlot(device: state.devices[26], slot: 1)

        state.triggerSlots(realSlots: [27])

        XCTAssertTrue(state.devices[0].torchOn)
        XCTAssertFalse(state.devices[26].torchOn)
    }
}
