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
          let assetKey = args["assetKey"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected assetKey", details: nil))
          return
        }
        let volume = (args["volume"] as? Double) ?? 1.0
        let fallbackName = (args["fileName"] as? String) ?? assetKey
        self.playPrimerTone(assetKey: assetKey, fallbackName: fallbackName, volume: volume)
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

  private func playPrimerTone(assetKey: String, fallbackName: String, volume: Double) {
    guard let controller = flutterController else {
      NSLog("Primer playback skipped – no Flutter controller")
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.defaultToSpeaker, .mixWithOthers]
      )
      try session.setActive(true)
    } catch {
      NSLog("Failed to activate audio session: \(error)")
    }

    let resolvedKey = controller.lookupKey(forAsset: assetKey)
    let bundleRoot = Bundle.main.bundlePath as NSString
    var candidateKeys: [String] = [resolvedKey]
    if !resolvedKey.hasPrefix("Frameworks/") {
      candidateKeys.append("Frameworks/App.framework/flutter_assets/\(assetKey)")
    }
    candidateKeys.append(assetKey)

    var finalPath: String?
    for key in candidateKeys {
      let candidate = bundleRoot.appendingPathComponent(key)
      if FileManager.default.fileExists(atPath: candidate) {
        finalPath = candidate
        break
      }
    }

    guard let finalPath = finalPath else {
      NSLog("Primer file not found: \(assetKey) (fallback: \(fallbackName))")
      return
    }

    do {
      let url = URL(fileURLWithPath: finalPath)
      primerAudioPlayer?.stop()
      primerAudioPlayer = try AVAudioPlayer(contentsOf: url)
      let clampedVolume = Float(min(max(volume, 0.0), 1.0))
      primerAudioPlayer?.volume = clampedVolume
      primerAudioPlayer?.prepareToPlay()
      primerAudioPlayer?.play()
    } catch {
      NSLog("Failed to play primer tone \(assetKey): \(error)")
    }
  }

  private func stopPrimerTone() {
    primerAudioPlayer?.stop()
    primerAudioPlayer = nil
  }
}
