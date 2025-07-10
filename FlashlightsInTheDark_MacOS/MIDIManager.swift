import Foundation
import CoreMIDI

/// MIDI manager creating a virtual bridge for ProTools communication.
final class MIDIManager {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var inPort  = MIDIPortRef()
    private var virtualSrc = MIDIEndpointRef()
    private var virtualDst = MIDIEndpointRef()

    /// Handlers for incoming MIDI messages.
    var noteOnHandler: ((UInt8, UInt8) -> Void)?
    var noteOffHandler: ((UInt8) -> Void)?
    var controlChangeHandler: ((UInt8, UInt8) -> Void)?

    init() {
        MIDIClientCreate("FlashlightsMIDIClient" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "OutPort" as CFString, &outPort)
        MIDIInputPortCreate(client,
                           "InPort" as CFString,
                           MIDIManager.readProc,
                           UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                           &inPort)
        MIDISourceCreate(client, "Flashlights Bridge" as CFString, &virtualSrc)
        MIDIDestinationCreate(client,
                              "Flashlights Bridge In" as CFString,
                              MIDIManager.readProc,
                              UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                              &virtualDst)
    }

    // MARK: - Sending
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
        // Send to our virtual source so DAWs can receive it.
        MIDIReceived(virtualSrc, &list)
    }

    // MARK: - Receiving
    private static let readProc: MIDIReadProc = { packetList, refCon, _ in
        guard let refCon = refCon else { return }
        let manager = Unmanaged<MIDIManager>.fromOpaque(refCon).takeUnretainedValue()
        let list = packetList.pointee
        var packet: UnsafePointer<MIDIPacket> = withUnsafePointer(to: list.packet) { $0 }
        for _ in 0..<list.numPackets {
            let status = packet.pointee.data.0
            let data1  = packet.pointee.data.1
            let data2  = packet.pointee.data.2
            let type = status & 0xF0
            switch type {
            case 0x90:
                if data2 > 0 {
                    manager.noteOnHandler?(data1, data2)
                } else {
                    manager.noteOffHandler?(data1)
                }
            case 0x80:
                manager.noteOffHandler?(data1)
            case 0xB0:
                manager.controlChangeHandler?(data1, data2)
            default:
                break
            }
            packet = MIDIPacketNext(packet)
        }
    }
}
