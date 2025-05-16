import 'dart:async';
import 'dart:io';
import 'package:osc/osc.dart';
import 'package:torch_light/torch_light.dart';
import 'package:just_audio/just_audio.dart';

/// Singleton OSC listener for flash/audio/mic/sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  final _oscParser = OSCParser();
  final _player = AudioPlayer();
  bool _running = false;

  /// Starts listening on UDP port 9000.  Idempotent.
  Future<void> start(int myIndex) async {
    if (_running) return;
    _running = true;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      9000,
      reuseAddress: true,
      reusePort: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.joinMulticast(InternetAddress('255.255.255.255'));

    _sub = _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = _socket!.receive();
      if (packet == null) return;

      final decoded = _oscParser.parse(packet.data);
      if (decoded is OSCMessage) {
        _dispatch(decoded, myIndex);
      }
    });

    print('[OSC] Listener started on 0.0.0.0:9000');
  }

  void _dispatch(OSCMessage m, int myIndex) async {
    print('OSC ▸ ${m.address} ${m.arguments}');
    switch (m.address) {
      case '/flash/on':
        final id = m.arguments[0] as int;
        final intensity = m.arguments[1] as double;
        if (id == myIndex) {
          await TorchLight.enableTorch(intensity: intensity);
        }
        break;

      case '/flash/off':
        if (m.arguments[0] as int == myIndex) {
          await TorchLight.disableTorch();
        }
        break;

      case '/audio/play':
        if (m.arguments[0] as int == myIndex) {
          final url = m.arguments[1] as String;
          final gain = m.arguments[2] as double;
          await _player.setUrl(url);
          await _player.setVolume(gain);
          await _player.play();
        }
        break;

      case '/audio/stop':
        if (m.arguments[0] as int == myIndex) {
          await _player.stop();
        }
        break;

      case '/mic/record':
        // TODO: integrate mic_stream once decided.
        break;

      case '/sync':
        // TODO: rolling offset (CNMAT method).
        break;
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