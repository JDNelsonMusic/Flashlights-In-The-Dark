import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as? FlutterViewController
    let torchChannel = FlutterMethodChannel(name: "ai.keex.flashlights/torch",
                                            binaryMessenger: controller!.binaryMessenger)

    torchChannel.setMethodCallHandler { call, result in
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

    let audioChannel = FlutterMethodChannel(name: "ai.keex.flashlights/audio",
                                            binaryMessenger: controller!.binaryMessenger)
    audioChannel.setMethodCallHandler { call, result in
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
      try session.setCategory(.playAndRecord,
                              mode: .default,
                              options: [.defaultToSpeaker, .mixWithOthers])
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
}
