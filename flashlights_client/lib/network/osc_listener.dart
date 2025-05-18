import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:osc/osc.dart';
import 'package:torch_light/torch_light.dart';

/// Singleton OSC listener for flash/audio/mic/sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  late final AudioPlayer _player = AudioPlayer();
  bool _running = false;
  StreamSubscription<OSCMessage>? _sub;

  /// Starts listening on UDP port 9000 (idempotent).
  Future<void> start(int myIndex) async {
    if (_running) return;
    _running = true;

    _socket = OSCSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: 9000,
    );
    await _socket!.listen((msg) => _dispatch(msg, myIndex));

    print('[OSC] Listening on 0.0.0.0:9000');
  }

  Future<void> _dispatch(OSCMessage m, int myIndex) async {
    print('OSC ↳ ${m.address} ${m.arguments}');
    switch (m.address) {
      case '/flash/on':
        final id = m.arguments[0] as int;
        // Intensity argument is ignored – torch_light has no such API.
        if (id == myIndex) await TorchLight.enableTorch();
        break;

      case '/flash/off':
        if (m.arguments[0] as int == myIndex) await TorchLight.disableTorch();
        break;

      case '/audio/play':
        if (m.arguments[0] as int == myIndex) {
          final fileName = m.arguments[1] as String;
          final gain = (m.arguments[2] as num).toDouble();
          final assetPath = 'available-sounds/$fileName';
          try {
            await _player.setAsset(assetPath);
          } catch (e) {
            print('[OSC] Failed to load asset $assetPath: $e');
            await _player.setUrl(fileName);
          }
          await _player.setVolume(gain.clamp(0, 1));
          await _player.play();
        }
        break;

      case '/audio/stop':
        if (m.arguments[0] as int == myIndex) await _player.stop();
        break;

      // TODO: implement /mic/record and /sync handling.
    }
  }

  /// Stops listening and cleans up resources.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    await _player.dispose();
    _running = false;
    print('[OSC] Listener stopped');
  }
}
