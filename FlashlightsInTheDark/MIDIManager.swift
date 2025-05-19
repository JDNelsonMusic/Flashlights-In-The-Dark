import Foundation
import CoreMIDI

/// Simple MIDI manager for sending note on/off and controls
final class MIDIManager {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()

    init() {
        MIDIClientCreate("FlashlightsMIDIClient" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "OutPort" as CFString, &outPort)
        let count = MIDIGetNumberOfDestinations()
        if count > 0 {
            destination = MIDIGetDestination(0)
        }
    }

    func sendNoteOn(_ note: UInt8, velocity: UInt8 = 127, channel: UInt8 = 0) {
        send(status: 0x90 | channel, data1: note, data2: velocity)
    }

    func sendNoteOff(_ note: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0) {
        send(status: 0x80 | channel, data1: note, data2: velocity)
    }

    func sendControlChange(_ control: UInt8, value: UInt8, channel: UInt8 = 0) {
        send(status: 0xB0 | channel, data1: control, data2: value)
    }

    private func send(status: UInt8, data1: UInt8, data2: UInt8) {
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = status
        packet.data.1 = data1
        packet.data.2 = data2
        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destination, &list)
    }
}