import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

public struct AudioDeviceInfo: Identifiable, Hashable {
    public let deviceID: AudioDeviceID
    public let name: String

    public var id: UInt32 { deviceID }
}

final class PrimerToneAudioEngine {
    private let engine = AVAudioEngine()
    private let leftMixer = AVAudioMixerNode()
    private let centerMixer = AVAudioMixerNode()
    private let rightMixer = AVAudioMixerNode()
    private let playerQueue = DispatchQueue(label: "PrimerToneAudioEngine.players")

    private struct BufferEnvelope {
        let buffer: AVAudioPCMBuffer
        let format: AVAudioFormat
    }

    private var buffers: [String: BufferEnvelope] = [:]

    init() {
        setupEngine()
    }

    private func setupEngine() {
        engine.attach(leftMixer)
        engine.attach(centerMixer)
        engine.attach(rightMixer)

        leftMixer.pan = -1.0
        centerMixer.pan = 0.0
        rightMixer.pan = 1.0

        engine.connect(leftMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(centerMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(rightMixer, to: engine.mainMixerNode, format: nil)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("⚠️ PrimerToneAudioEngine failed to start: \(error)")
        }
    }

    func preloadPrimerTones() {
        var loadedAny = false
        var deduplication = Set<String>()

        // Primary: look for the curated bundle subdirectory first
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: "Audio/primerTones") {
            for url in urls where isPrimerTone(url.lastPathComponent) {
                let key = url.lastPathComponent.lowercased()
                guard !deduplication.contains(key) else { continue }
                deduplication.insert(key)
                loadBuffer(for: url)
                loadedAny = true
            }
        }

        // Secondary: fallback to the bundle root if the assets were copied there
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) {
            for url in urls where isPrimerTone(url.lastPathComponent) {
                let key = url.lastPathComponent.lowercased()
                guard !deduplication.contains(key) else { continue }
                deduplication.insert(key)
                loadBuffer(for: url)
                loadedAny = true
            }
        }

        if loadedAny { return }

        // Development fallback for running from the repo without bundling assets yet.
        let fallbackDirectories = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlashlightsInTheDark_MacOS/Audio/primerTones", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlashlightsInTheDark_MacOS/Audio", isDirectory: true)
        ]

        var foundFallback = false
        for directory in fallbackDirectories {
            if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "mp3" && isPrimerTone(fileURL.lastPathComponent) {
                    let key = fileURL.lastPathComponent.lowercased()
                    guard !deduplication.contains(key) else { continue }
                    deduplication.insert(key)
                    loadBuffer(for: fileURL)
                    foundFallback = true
                }
            }
        }

        if !loadedAny && !foundFallback {
            print("⚠️ No primer tone assets found in bundle or fallback path.")
        }
    }

    private func loadBuffer(for url: URL) {
        let key = normalisedKey(for: url)
        if buffers[key] != nil { return }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                                frameCapacity: AVAudioFrameCount(audioFile.length)) else {
                return
            }
            try audioFile.read(into: buffer)
            buffers[key] = BufferEnvelope(buffer: buffer, format: audioFile.processingFormat)
        } catch {
            print("⚠️ Failed to load primer tone \(url.lastPathComponent): \(error)")
        }
    }

    private func normalisedKey(for url: URL) -> String {
        url.lastPathComponent.lowercased()
    }

    func play(assignments: [PrimerColor: PrimerAssignment]) {
        playerQueue.async { [weak self] in
            guard let self else { return }
            for (color, assignment) in assignments {
                guard let sample = assignment.normalizedMacFileName else { continue }
                let key = sample.components(separatedBy: "/").last?.lowercased() ?? sample.lowercased()
                guard let envelope = self.buffers[key] ?? self.loadBufferAndReturn(sample: sample) else { continue }
                let player = AVAudioPlayerNode()
                self.engine.attach(player)

                let destination: AVAudioMixerNode
                switch color.panPosition {
                case .left: destination = self.leftMixer
                case .center: destination = self.centerMixer
                case .right: destination = self.rightMixer
                }

                self.engine.connect(player, to: destination, format: envelope.format)
                player.scheduleBuffer(envelope.buffer, at: nil, options: []) { [weak self, weak player] in
                    guard let self, let player else { return }
                    self.playerQueue.async {
                        self.engine.detach(player)
                    }
                }
                player.play()
            }
        }
    }

    private func loadBufferAndReturn(sample: String) -> BufferEnvelope? {
        guard let url = urlForSample(sample) else { return nil }
        loadBuffer(for: url)
        let key = normalisedKey(for: url)
        return buffers[key]
    }

    private func urlForSample(_ sample: String) -> URL? {
        var adjusted = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if adjusted.hasPrefix("primerTones/") {
            adjusted.removeFirst("primerTones/".count)
        }
        if adjusted.hasPrefix("./") {
            adjusted.removeFirst(2)
        }

        let components = adjusted.split(separator: "/").map(String.init)
        guard let rawFileName = components.last else {
            return nil
        }

        let candidateNames = normalisedFileNames(for: rawFileName)

        for name in candidateNames {
            if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Audio/primerTones") {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: nil) {
                return url
            }
        }

        // Development fallback when running from source tree
        let searchRoots = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlashlightsInTheDark_MacOS/Audio/primerTones", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlashlightsInTheDark_MacOS/Audio", isDirectory: true)
        ]

        for root in searchRoots {
            for name in candidateNames {
                let candidate = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func normalisedFileNames(for rawFileName: String) -> [String] {
        var fileName = rawFileName
        if !fileName.lowercased().hasSuffix(".mp3") {
            fileName += ".mp3"
        }

        let lower = fileName.lowercased()
        if lower.hasPrefix("short") {
            let suffix = lower.dropFirst("short".count)
            let capitalised = "Short" + suffix
            return [capitalised, String(lower)]
        }
        if lower.hasPrefix("long") {
            let suffix = lower.dropFirst("long".count)
            let capitalised = "Long" + suffix
            return [capitalised, String(lower)]
        }
        return [fileName]
    }

    private func isPrimerTone(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("short") || lower.hasPrefix("long")
    }

    // MARK: - Audio Device Handling -----------------------------------------
    func availableOutputDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                                    &propertyAddress,
                                                    0,
                                                    nil,
                                                    &dataSize)
        if status != noErr || dataSize == 0 { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                            &propertyAddress,
                                            0,
                                            nil,
                                            &dataSize,
                                            &ids)
        if status != noErr { return [] }

        var results: [AudioDeviceInfo] = []
        for deviceID in ids {
            if outputChannelCount(deviceID: deviceID) == 0 { continue }
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID,
                                                &nameAddress,
                                                0,
                                                nil,
                                                &nameSize,
                                                &name)
            let deviceName = (status == noErr) ? (name as String) : "Device \(deviceID)"
            results.append(AudioDeviceInfo(deviceID: deviceID, name: deviceName))
        }
        return results.sorted { $0.name < $1.name }
    }

    private func outputChannelCount(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 0
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        if status != noErr || dataSize == 0 { return 0 }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPointer)
        if status != noErr { return 0 }

        let bufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferList)
        var channels = 0
        for buffer in audioBufferList {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    func currentOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                0,
                                                nil,
                                                &size,
                                                &deviceID)
        if status != noErr { return 0 }
        return deviceID
    }

    func setOutputDevice(_ deviceID: AudioDeviceID?) {
        let target = deviceID ?? currentOutputDeviceID()
        var mutableID = target
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard let audioUnit = engine.outputNode.audioUnit else {
            print("⚠️ Unable to retrieve output audio unit for device switching.")
            return
        }
        let status = AudioUnitSetProperty(audioUnit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &mutableID,
                                          size)
        if status != noErr {
            print("⚠️ Failed to set audio output device: \(status)")
        }
    }
}
