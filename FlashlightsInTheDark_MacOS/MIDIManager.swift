import Foundation
import CoreMIDI

/// MIDI manager creating a virtual bridge for ProTools communication.
final class MIDIManager {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var inPort  = MIDIPortRef()
    private var virtualSrc = MIDIEndpointRef()
    private var virtualDst = MIDIEndpointRef()
    private var selectedOutput = MIDIEndpointRef()
    private var selectedInput  = MIDIEndpointRef()
    private var connectedInputs: [MIDIEndpointRef] = []
    private var channel: UInt8 = 0 // MIDI channel 1

    /// Handlers for incoming MIDI messages.
    var noteOnHandler: ((UInt8, UInt8, UInt8) -> Void)?
    var noteOffHandler: ((UInt8, UInt8) -> Void)?
    var controlChangeHandler: ((UInt8, UInt8, UInt8) -> Void)?

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
        selectedOutput = 0
        selectedInput = 0
        channel = 0
    }

    // MARK: - Device Enumeration
    var inputNames: [String] {
        (0..<MIDIGetNumberOfSources()).map { idx in
            endpointName(MIDIGetSource(idx))
        }
    }

    var outputNames: [String] {
        (0..<MIDIGetNumberOfDestinations()).map { idx in
            endpointName(MIDIGetDestination(idx))
        }
    }

    func setChannel(_ chan: Int) {
        channel = UInt8(min(max(chan - 1, 0), 15))
    }

    private func endpointName(_ ep: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &name) == noErr,
           let str = name?.takeRetainedValue() {
            return str as String
        }
        return "Unknown"
    }

    func connectInput(named name: String) {
        // Disconnect any previously connected sources
        for src in connectedInputs {
            MIDIPortDisconnectSource(inPort, src)
        }
        connectedInputs.removeAll()
        selectedInput = 0
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            if endpointName(src) == name {
                MIDIPortConnectSource(inPort, src, nil)
                selectedInput = src
                connectedInputs = [src]
                break
            }
        }
    }

    func connectAllInputs() {
        // Disconnect any previously connected sources
        for src in connectedInputs {
            MIDIPortDisconnectSource(inPort, src)
        }
        connectedInputs.removeAll()
        selectedInput = 0
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inPort, src, nil)
            connectedInputs.append(src)
        }
    }

    func connectOutput(named name: String) {
        selectedOutput = 0
        for i in 0..<MIDIGetNumberOfDestinations() {
            let dst = MIDIGetDestination(i)
            if endpointName(dst) == name {
                selectedOutput = dst
                break
            }
        }
    }

    // MARK: - Sending
    func sendNoteOn(_ note: UInt8, velocity: UInt8 = 127) {
        send(status: 0x90 | channel, data1: note, data2: velocity)
    }

    func sendNoteOff(_ note: UInt8, velocity: UInt8 = 0) {
        send(status: 0x80 | channel, data1: note, data2: velocity)
    }

    func sendControlChange(_ control: UInt8, value: UInt8) {
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
        if selectedOutput != 0 {
            MIDISend(outPort, selectedOutput, &list)
        }
    }

    // MARK: - Receiving
    private static let readProc: MIDIReadProc = { packetList, refCon, _ in
        guard let refCon = refCon else { return }
        let manager = Unmanaged<MIDIManager>.fromOpaque(refCon).takeUnretainedValue()
        var list = packetList.pointee
        // Use a *mutable* pointer so we can advance it with MIDIPacketNext.
        var packet: UnsafeMutablePointer<MIDIPacket> =
            withUnsafeMutablePointer(to: &list.packet) { $0 }
        for _ in 0..<list.numPackets {
            let status = packet.pointee.data.0
            let data1  = packet.pointee.data.1
            let data2  = packet.pointee.data.2
            let messageType = status & 0xF0
            let channel = status & 0x0F
            switch messageType {
            case 0x90:
                if data2 > 0 {
                    manager.noteOnHandler?(data1, data2, channel)
                } else {
                    manager.noteOffHandler?(data1, channel)
                }
            case 0x80:
                manager.noteOffHandler?(data1, channel)
            case 0xB0:
                manager.controlChangeHandler?(data1, data2, channel)
            default:
                break
            }
            packet = MIDIPacketNext(packet)
        }
    }
}
