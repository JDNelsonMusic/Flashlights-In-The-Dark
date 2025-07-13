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
    let channel = FlutterMethodChannel(name: "ai.keex.flashlights/torch",
                                       binaryMessenger: controller!.binaryMessenger)

    channel.setMethodCallHandler { call, result in
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
}
