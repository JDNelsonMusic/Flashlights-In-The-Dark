import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private weak var flutterController: FlutterViewController?
  private var primerPlayers: [String: AVAudioPlayer] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    flutterController = controller

    let torchChannel = FlutterMethodChannel(
      name: "ai.keex.flashlights/torch",
      binaryMessenger: controller.binaryMessenger
    )

    torchChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "NO_CONTROLLER", message: nil, details: nil))
        return
      }
      if call.method == "setTorchLevel" {
        if let level = call.arguments as? Double {
          self.setTorchLevel(level: level)
          result(nil)
        } else {
          result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let audioChannel = FlutterMethodChannel(
      name: "ai.keex.flashlights/audio",
      binaryMessenger: controller.binaryMessenger
    )
    audioChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "NO_CONTROLLER", message: nil, details: nil))
        return
      }
      switch call.method {
      case "forceSpeaker":
        self.forceSpeaker()
        result(nil)
      case "resetAudio":
        self.resetAudio()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let audioNativeChannel = FlutterMethodChannel(
      name: "ai.keex.flashlights/audioNative",
      binaryMessenger: controller.binaryMessenger
    )
    audioNativeChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "NO_CONTROLLER", message: nil, details: nil))
        return
      }
      switch call.method {
      case "playPrimerTone":
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["fileName"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected fileName", details: nil))
          return
        }
        let volume = (args["volume"] as? Double) ?? 1.0
        let assetKey = args["assetKey"] as? String
        let payload = args["bytes"] as? FlutterStandardTypedData
        self.playPrimerTone(
          fileName: fileName,
          assetKey: assetKey,
          volume: volume,
          data: payload?.data
        )
        result(nil)
      case "preloadPrimerTone":
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["fileName"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected fileName", details: nil))
          return
        }
        let assetKey = args["assetKey"] as? String
        let payload = args["bytes"] as? FlutterStandardTypedData
        self.preloadPrimerTone(
          fileName: fileName,
          assetKey: assetKey,
          data: payload?.data
        )
        result(nil)
      case "stopPrimerTone":
        self.stopPrimerTone()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setTorchLevel(level: Double) {
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      if level <= 0 {
        device.torchMode = .off
      } else {
        let clamped = min(max(level, 0.0), 1.0)
        try device.setTorchModeOn(level: Float(clamped))
      }
      device.unlockForConfiguration()
    } catch {
      NSLog("Torch error: \(error)")
    }
  }

  private func forceSpeaker() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .mixWithOthers]
      )
      try session.setActive(true, options: [])
    } catch {
      NSLog("Audio session error: \(error)")
    }
  }

  private func resetAudio() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
    } catch {
      NSLog("Audio session reset error: \(error)")
    }
  }

  private func playPrimerTone(fileName: String, assetKey: String?, volume: Double, data: Data?) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
      try session.setActive(true)

      let canonicalName = canonicalFileName(from: fileName)
      let canonicalKey = canonicalAssetKey(for: canonicalName, assetKey: assetKey)

      let player = try resolvePlayer(
        canonicalKey: canonicalKey,
        fileName: canonicalName,
        assetKey: assetKey,
        data: data
      )
      player.currentTime = 0
      player.volume = Float(volume)
      if !player.isPlaying {
        player.prepareToPlay()
      }
      player.play()
    } catch {
      NSLog("Failed to play primer tone \(fileName): \(error)")
    }
  }

  private func preloadPrimerTone(fileName: String, assetKey: String?, data: Data?) {
    do {
      let canonicalName = canonicalFileName(from: fileName)
      let canonicalKey = canonicalAssetKey(for: canonicalName, assetKey: assetKey)
      let player = try resolvePlayer(
        canonicalKey: canonicalKey,
        fileName: canonicalName,
        assetKey: assetKey,
        data: data
      )
      player.prepareToPlay()
      player.currentTime = 0
    } catch {
      NSLog("Failed to preload primer tone \(fileName): \(error)")
    }
  }

  private func stopPrimerTone() {
    for player in primerPlayers.values {
      player.stop()
      player.currentTime = 0
    }
  }

  private func resolvePlayer(canonicalKey: String, fileName: String, assetKey: String?, data: Data?) throws -> AVAudioPlayer {
    if let existing = primerPlayers[canonicalKey] {
      if existing.isPlaying {
        existing.stop()
      }
      return existing
    }

    if let data {
      let created = try AVAudioPlayer(data: data)
      primerPlayers[canonicalKey] = created
      return created
    }

    guard let url = locatePrimerURL(canonicalKey: canonicalKey, fileName: fileName, assetKey: assetKey) else {
      throw NSError(domain: "ai.keex.flashlights", code: -1, userInfo: [NSLocalizedDescriptionKey: "Primer file not found: \(canonicalKey)"])
    }
    let created = try AVAudioPlayer(contentsOf: url)
    primerPlayers[canonicalKey] = created
    return created
  }

  private func locatePrimerURL(canonicalKey: String, fileName: String, assetKey: String?) -> URL? {
    var candidates = [URL]()
    func appendCandidate(_ url: URL?) {
      guard let url else { return }
      candidates.append(url)
    }

    if let controller = flutterController {
      let lookup = controller.lookupKey(forAsset: canonicalKey)
      appendCandidate(Bundle.main.bundleURL.appendingPathComponent(lookup))
      if let privateFrameworks = Bundle.main.privateFrameworksURL?
        .appendingPathComponent("App.framework/flutter_assets") {
        appendCandidate(privateFrameworks.appendingPathComponent(lookup))
      }
    }

    if let privateFrameworks = Bundle.main.privateFrameworksURL?
      .appendingPathComponent("App.framework/flutter_assets") {
      appendCandidate(privateFrameworks.appendingPathComponent(canonicalKey))
      appendCandidate(privateFrameworks
        .appendingPathComponent("available-sounds/primerTones/\(fileName)"))
    }

    appendCandidate(Bundle.main.bundleURL
      .appendingPathComponent("flutter_assets/\(canonicalKey)"))
    appendCandidate(Bundle.main.bundleURL
      .appendingPathComponent("flutter_assets/available-sounds/primerTones/\(fileName)"))
    appendCandidate(Bundle.main.bundleURL
      .appendingPathComponent("available-sounds/primerTones/\(fileName)"))

    let fm = FileManager.default
    var soundURL: URL?
    var seenPaths = Set<String>()
    for url in candidates {
      let path = url.path
      if seenPaths.contains(path) { continue }
      seenPaths.insert(path)
      if fm.fileExists(atPath: path) {
        soundURL = url
        break
      }
    }
    return soundURL
  }

  private func canonicalFileName(from raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let slash = trimmed.lastIndex(of: "/") {
      trimmed = String(trimmed[trimmed.index(after: slash)...])
    }
    if trimmed.lowercased().hasPrefix("short") {
      trimmed = "Short" + trimmed.dropFirst(5)
    } else if trimmed.lowercased().hasPrefix("long") {
      trimmed = "Long" + trimmed.dropFirst(4)
    }
    if !trimmed.lowercased().hasSuffix(".mp3") {
      trimmed += ".mp3"
    }
    return trimmed
  }

  private func canonicalAssetKey(for canonicalName: String, assetKey: String?) -> String {
    return (assetKey ?? "available-sounds/primerTones/\(canonicalName)")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }
}
