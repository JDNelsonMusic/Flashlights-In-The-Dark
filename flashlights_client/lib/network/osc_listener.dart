import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:osc/osc.dart';
// Import client state to update slot dynamically
import '../model/client_state.dart';
import 'package:torch_light/torch_light.dart';

/// Singleton OSC listener for flash/audio/mic/sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  late final AudioPlayer _player = AudioPlayer();
  bool _running = false;

  /// Starts listening on UDP port 9000 (idempotent).
  Future<void> start() async {
    if (_running) return;
    _running = true;

    _socket = OSCSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: 9000,
    );
    // Listen and dispatch using the current slot
    await _socket!.listen((OSCMessage msg) => _dispatch(msg));

    print('[OSC] Listening on 0.0.0.0:9000');
  }

  Future<void> _dispatch(OSCMessage m) async {
    // Always use the latest listening slot
    final myIndex = client.myIndex.value;
    print('OSC ↳ ${m.address} ${m.arguments}');
    switch (m.address) {
      case '/flash/on':
        final id = m.arguments[0] as int;
        // Intensity argument is ignored – torch_light has no such API.
        if (id == myIndex) {
          client.flashOn.value = true;
          await TorchLight.enableTorch();
        }
        break;

      case '/flash/off':
        if (m.arguments[0] as int == myIndex) {
          client.flashOn.value = false;
          await TorchLight.disableTorch();
        }
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
          client.audioPlaying.value = true;
        }
        break;

      case '/audio/stop':
        if (m.arguments[0] as int == myIndex) {
          await _player.stop();
          client.audioPlaying.value = false;
        }
        break;

      // Dynamic slot assignment
      case '/set-slot':
        final newSlot =
            m.arguments.isNotEmpty ? (m.arguments[0] as int) : myIndex;
        if (newSlot != client.myIndex.value) {
          client.myIndex.value = newSlot;
          print('[OSC] Updated listening slot to $newSlot');
        }
        break;

      // TODO: implement /mic/record and /sync handling.
    }
  }

  /// Stops listening and cleans up resources.
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    await _player.dispose();
    _running = false;
    print('[OSC] Listener stopped');
  }
}
