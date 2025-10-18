import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private weak var flutterController: FlutterViewController?
  private let primerAudio = PrimerAudioEngine()

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
      case "initializePrimerLibrary":
        guard
          let args = call.arguments as? [String: Any],
          let assets = args["assets"] as? [String]
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected assets", details: nil))
          return
        }
        let canonical = args["canonical"] as? [String] ?? []
        let manifest: [(asset: String, canonical: String)] = assets.enumerated().map { index, asset in
          let provided = index < canonical.count ? canonical[index] : nil
          let resolved = (provided?.isEmpty ?? true)
            ? PrimerAudioEngine.canonicalFileName(from: asset)
            : provided!
          return (asset: asset, canonical: resolved)
        }

        self.primerAudio.initialize(with: controller, manifest: manifest) { initResult in
          switch initResult {
          case .success(let payload):
            result(payload)
          case .failure(let error):
            result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      case "playPrimerTone":
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["fileName"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected fileName", details: nil))
          return
        }
        let volume = (args["volume"] as? Double) ?? 1.0
        self.primerAudio.play(canonicalName: fileName, gain: volume)
        result(nil)
      case "stopPrimerTone":
        self.primerAudio.stopAll()
        result(nil)
      case "diagnostics":
        result(self.primerAudio.diagnosticsPayload())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    primerAudio.handleAppWillResignActive()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    primerAudio.handleAppDidBecomeActive()
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
      try? session.overrideOutputAudioPort(.speaker)
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

private final class PrimerAudioEngine: NSObject, AVAudioPlayerDelegate {
  private struct PrimerSound {
    let data: Data
    let duration: TimeInterval
    let byteCount: Int
  }

  private let queue = DispatchQueue(
    label: "ai.keex.flashlights.primer-audio",
    qos: .userInitiated
  )
  private weak var flutterController: FlutterViewController?

  private var sounds: [String: PrimerSound] = [:]
  private var idlePlayers: [String: [AVAudioPlayer]] = [:]
  private var activePlayers: [ObjectIdentifier: AVAudioPlayer] = [:]
  private var playerCanonical: [ObjectIdentifier: String] = [:]
  private var currentCanonical: String?
  private var lastCanonical: String?
  private var lastPlaybackStartedAtMs: Double = 0
  private var initialised = false
  private var totalBufferDuration: TimeInterval = 0
  private var totalBufferBytes: Int = 0
  private var lastInitialisationMs: Double = 0
  private var requestedAssets: Int = 0
  private var lastFailures: [[String: Any]] = []
  private var currentStatus: String = "not_initialized"
  private var sessionConfigured = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func initialize(
    with controller: FlutterViewController,
    manifest: [(asset: String, canonical: String)],
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    queue.async {
      if self.initialised {
        let payload = self.diagnosticsPayloadLocked()
        DispatchQueue.main.async {
          completion(.success(payload))
        }
        return
      }

      self.flutterController = controller

      do {
        let startWall = Date()
        try self.configureSession()
        self.sounds.removeAll(keepingCapacity: true)
        self.idlePlayers.removeAll(keepingCapacity: true)
        self.activePlayers.removeAll(keepingCapacity: true)
        self.playerCanonical.removeAll(keepingCapacity: true)
        self.currentCanonical = nil
        self.lastCanonical = nil
        self.lastPlaybackStartedAtMs = 0
        self.totalBufferDuration = 0
        self.totalBufferBytes = 0
        self.requestedAssets = manifest.count
        self.lastFailures = []
        self.currentStatus = "initializing"
        self.sessionConfigured = false

        var loaded = 0
        for entry in manifest {
          let assetKey = entry.asset
          var canonical = entry.canonical
          if canonical.isEmpty {
            canonical = PrimerAudioEngine.canonicalFileName(from: assetKey)
          }
          guard !canonical.isEmpty else { continue }

          guard let url = self.locateAssetURL(assetKey: assetKey, canonical: canonical) else {
            self.lastFailures.append([
              "asset": assetKey,
              "canonical": canonical,
              "reason": "Asset not found"
            ])
            continue
          }

          do {
            let sound = try self.loadSound(from: url)
            self.sounds[canonical] = sound
            self.totalBufferDuration += sound.duration
            self.totalBufferBytes += sound.byteCount

            let player = try self.makePlayer(for: canonical, sound: sound)
            self.enqueueIdle(player, canonical: canonical)
            loaded += 1
          } catch {
            self.lastFailures.append([
              "asset": assetKey,
              "canonical": canonical,
              "reason": "\(error)"
            ])
            NSLog("[PrimerAudioEngine] Failed to load primer \(canonical): \(error)")
          }
        }

        let status: String
        if manifest.isEmpty {
          status = "empty"
        } else if loaded == 0 {
          status = "failed"
        } else if self.lastFailures.isEmpty {
          status = "ok"
        } else {
          status = "partial"
        }

        self.initialised = status != "failed"
        self.currentStatus = status
        self.lastInitialisationMs = Date().timeIntervalSince(startWall) * 1000.0

        var payload = self.diagnosticsPayloadLocked()
        payload["count"] = loaded
        payload["requested"] = manifest.count
        payload["failed"] = self.lastFailures
        payload["failedCount"] = self.lastFailures.count
        payload["status"] = status
        DispatchQueue.main.async {
          completion(.success(payload))
        }
      } catch {
        self.initialised = false
        self.currentStatus = "failed"
        self.sessionConfigured = false
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func handleAppWillResignActive() {
    queue.async {
      self.sessionConfigured = false
      self.stopActivePlayersLocked()
    }
  }

  func handleAppDidBecomeActive() {
    queue.async {
      do {
        try self.configureSession()
        self.stopActivePlayersLocked()
        self.preparePlayersLocked()
      } catch {
        NSLog("[PrimerAudioEngine] Failed to reactivate audio session: \(error)")
      }
    }
  }

  func play(canonicalName: String, gain: Double) {
    let capped = max(0.0, min(gain, 1.0))
    queue.async {
      let canonical = PrimerAudioEngine.canonicalFileName(from: canonicalName)
      guard self.sounds[canonical] != nil else {
        NSLog("[PrimerAudioEngine] Unknown primer: \(canonicalName)")
        return
      }

      do {
        if !self.sessionConfigured {
          try self.configureSession()
        }
        let player = try self.dequeuePlayer(for: canonical)
        let identifier = ObjectIdentifier(player)
        self.activePlayers[identifier] = player
        self.playerCanonical[identifier] = canonical
        self.currentCanonical = canonical
        self.lastCanonical = canonical
        self.lastPlaybackStartedAtMs = Date().timeIntervalSince1970 * 1000.0

        DispatchQueue.main.async {
          player.currentTime = 0
          player.volume = Float(capped)
          if !player.isPlaying {
            player.play()
          } else {
            player.stop()
            player.currentTime = 0
            player.play()
          }
        }
      } catch {
        NSLog("[PrimerAudioEngine] Playback failed for \(canonical): \(error)")
      }
    }
  }

  func stopAll() {
    queue.async {
      self.stopActivePlayersLocked()
      self.lastCanonical = nil
      self.lastPlaybackStartedAtMs = 0

      for (_, players) in self.idlePlayers {
        for player in players {
          player.stop()
          player.currentTime = 0
        }
      }
    }
  }

  func diagnosticsPayload() -> [String: Any] {
    var payload: [String: Any] = [:]
    queue.sync {
      payload = self.diagnosticsPayloadLocked()
    }
    return payload
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    queue.async {
      let identifier = ObjectIdentifier(player)
      self.activePlayers.removeValue(forKey: identifier)
      let canonical = self.playerCanonical[identifier] ?? ""
      player.currentTime = 0
      player.prepareToPlay()
      if !canonical.isEmpty {
        self.enqueueIdle(player, canonical: canonical)
      }
      if self.activePlayers.isEmpty {
        self.currentCanonical = nil
      }
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    queue.async {
      let identifier = ObjectIdentifier(player)
      let canonical = self.playerCanonical[identifier] ?? "unknown"
      self.activePlayers.removeValue(forKey: identifier)
      self.playerCanonical.removeValue(forKey: identifier)
      NSLog("[PrimerAudioEngine] Decode error for \(canonical): \(String(describing: error))")
      if self.activePlayers.isEmpty {
        self.currentCanonical = nil
      }
    }
  }

  private func diagnosticsPayloadLocked() -> [String: Any] {
    let idleCount = idlePlayers.values.reduce(0) { $0 + $1.count }
    var payload: [String: Any] = [
      "status": currentStatus,
      "initialised": initialised,
      "playersActive": activePlayers.count,
      "playersIdle": idleCount,
      "sounds": sounds.count,
      "bufferDurationSec": totalBufferDuration,
      "bufferBytes": totalBufferBytes,
      "initialiseDurationMs": lastInitialisationMs,
      "requested": requestedAssets,
      "failedCount": lastFailures.count,
      "currentCanonical": currentCanonical ?? NSNull(),
      "lastCanonical": lastCanonical ?? NSNull(),
      "lastPlaybackStartedAtMs": lastPlaybackStartedAtMs
    ]
    if !lastFailures.isEmpty {
      payload["failed"] = lastFailures
    }
    return payload
  }

  private func configureSession() throws {
    let configure: () throws -> Void = {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .mixWithOthers]
      )
      try session.setActive(true, options: [])
      try? session.overrideOutputAudioPort(.speaker)
    }

    do {
      if Thread.isMainThread {
        try configure()
      } else {
        var thrownError: Error?
        DispatchQueue.main.sync {
          do {
            try configure()
          } catch {
            thrownError = error
          }
        }
        if let thrownError {
          throw thrownError
        }
      }
      sessionConfigured = true
    } catch {
      sessionConfigured = false
      throw error
    }
  }

  private func preparePlayersLocked() {
    if idlePlayers.isEmpty { return }
    let players = idlePlayers.values.flatMap { $0 }
    DispatchQueue.main.async {
      for player in players {
        player.stop()
        player.currentTime = 0
        player.prepareToPlay()
      }
    }
  }

  @objc private func handleSessionInterruption(_ notification: Notification) {
    guard
      let info = notification.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    switch type {
    case .began:
      queue.async {
        self.sessionConfigured = false
        self.stopActivePlayersLocked()
      }
    case .ended:
      let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      queue.async {
        do {
          try self.configureSession()
          if options.contains(.shouldResume) {
            self.stopActivePlayersLocked()
          }
          self.preparePlayersLocked()
        } catch {
          NSLog("[PrimerAudioEngine] Interruption resume failed: \(error)")
        }
      }
    @unknown default:
      break
    }
  }

  private func loadSound(from url: URL) throws -> PrimerSound {
    let data = try Data(contentsOf: url)
    let probe = try AVAudioPlayer(data: data)
    return PrimerSound(
      data: data,
      duration: probe.duration,
      byteCount: data.count
    )
  }

  private func makePlayer(for canonical: String, sound: PrimerSound? = nil) throws -> AVAudioPlayer {
    let tone: PrimerSound
    if let sound {
      tone = sound
    } else if let stored = sounds[canonical] {
      tone = stored
    } else {
      throw NSError(
        domain: "ai.keex.flashlights",
        code: -5,
        userInfo: [NSLocalizedDescriptionKey: "No sound cached for \(canonical)"]
      )
    }

    let player = try AVAudioPlayer(data: tone.data)
    player.delegate = self
    player.numberOfLoops = 0
    player.currentTime = 0
    player.prepareToPlay()
    let identifier = ObjectIdentifier(player)
    playerCanonical[identifier] = canonical
    return player
  }

  private func dequeuePlayer(for canonical: String) throws -> AVAudioPlayer {
    if var players = idlePlayers[canonical], let player = players.popLast() {
      idlePlayers[canonical] = players
      playerCanonical[ObjectIdentifier(player)] = canonical
      return player
    }
    let player = try makePlayer(for: canonical)
    return player
  }

  private func enqueueIdle(_ player: AVAudioPlayer, canonical: String) {
    if !player.isPlaying {
      player.currentTime = 0
    }
    playerCanonical[ObjectIdentifier(player)] = canonical
    var players = idlePlayers[canonical, default: []]
    players.append(player)
    idlePlayers[canonical] = players
  }

  /// Stops any active players and returns them to the idle pool. Must be called on `queue`.
  private func stopActivePlayersLocked() {
    if activePlayers.isEmpty { return }
    for (identifier, player) in activePlayers {
      player.stop()
      player.currentTime = 0
      player.prepareToPlay()
      if let canonical = playerCanonical[identifier] {
        enqueueIdle(player, canonical: canonical)
      }
    }
    activePlayers.removeAll(keepingCapacity: true)
    currentCanonical = nil
  }

  private func locateAssetURL(assetKey: String, canonical: String) -> URL? {
    var candidates: [URL] = []
    func addCandidate(_ url: URL?) {
      guard let url else { return }
      candidates.append(url)
    }

    if let controller = flutterController {
      let lookupKey = controller.lookupKey(forAsset: assetKey)
      addCandidate(Bundle.main.bundleURL.appendingPathComponent(lookupKey))
      if let frameworks = Bundle.main.privateFrameworksURL?
        .appendingPathComponent("App.framework/flutter_assets") {
        addCandidate(frameworks.appendingPathComponent(lookupKey))
      }
    }

    if let frameworks = Bundle.main.privateFrameworksURL?
      .appendingPathComponent("App.framework/flutter_assets") {
      addCandidate(frameworks.appendingPathComponent(assetKey))
      addCandidate(frameworks.appendingPathComponent(canonical))
    }

    addCandidate(Bundle.main.bundleURL
      .appendingPathComponent("flutter_assets/\(assetKey)"))
    addCandidate(Bundle.main.bundleURL
      .appendingPathComponent("available-sounds/primerTones/\(canonical)"))

    let fm = FileManager.default
    var seen = Set<String>()
    for url in candidates {
      let path = url.path
      if seen.contains(path) { continue }
      seen.insert(path)
      if fm.fileExists(atPath: path) {
        return url
      }
    }
    NSLog("[PrimerAudioEngine] Asset not found for \(canonical) (asset: \(assetKey))")
    return nil
  }

  static func canonicalFileName(from raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let slash = trimmed.lastIndex(of: "/") {
      trimmed = String(trimmed[trimmed.index(after: slash)...])
    }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("short") {
      trimmed = "Short" + trimmed.dropFirst(5)
    } else if lower.hasPrefix("long") {
      trimmed = "Long" + trimmed.dropFirst(4)
    }
    if !trimmed.lowercased().hasSuffix(".mp3") {
      trimmed += ".mp3"
    }
    return trimmed
  }
}
