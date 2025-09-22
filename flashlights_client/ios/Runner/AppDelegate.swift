import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private weak var flutterController: FlutterViewController?
  private var primerAudioPlayer: AVAudioPlayer?

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
        self.playPrimerTone(fileName: fileName, assetKey: assetKey, volume: volume)
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

  private func playPrimerTone(fileName: String, assetKey: String?, volume: Double) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker]
      )
      try session.setActive(true)

      var trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
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

      let canonicalKey = (assetKey ?? "available-sounds/primerTones/\(trimmed)")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let fm = FileManager.default

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
          .appendingPathComponent("available-sounds/primerTones/\(trimmed)"))
      }

      appendCandidate(Bundle.main.bundleURL
        .appendingPathComponent("flutter_assets/\(canonicalKey)"))
      appendCandidate(Bundle.main.bundleURL
        .appendingPathComponent("flutter_assets/available-sounds/primerTones/\(trimmed)"))
      appendCandidate(Bundle.main.bundleURL
        .appendingPathComponent("Frameworks/App.framework/flutter_assets/\(canonicalKey)"))
      appendCandidate(Bundle.main.bundleURL
        .appendingPathComponent("Frameworks/App.framework/flutter_assets/available-sounds/primerTones/\(trimmed)"))

      if let alt = Bundle.main.url(forResource: trimmed,
                                   withExtension: nil,
                                   subdirectory: "available-sounds/primerTones") {
        appendCandidate(alt)
      }

      var soundURL: URL? = nil
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

      guard let finalURL = soundURL else {
        NSLog("Primer file not found: \(fileName) (canonical: \(trimmed)) assetKey: \(assetKey ?? "nil")")
        return
      }

      primerAudioPlayer?.stop()
      primerAudioPlayer = try AVAudioPlayer(contentsOf: finalURL)
      primerAudioPlayer?.volume = Float(volume)
      primerAudioPlayer?.prepareToPlay()
      primerAudioPlayer?.play()
    } catch {
      NSLog("Failed to play primer tone \(fileName): \(error)")
    }
  }

  private func stopPrimerTone() {
    primerAudioPlayer?.stop()
    primerAudioPlayer = nil
  }
}
