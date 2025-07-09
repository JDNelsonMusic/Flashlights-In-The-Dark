import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:osc/osc.dart';
// Import client state to update slot dynamically
import '../model/client_state.dart';
import 'package:torch_light/torch_light.dart';
import 'package:mic_stream/mic_stream.dart';

/// Helper that enables UDP broadcast on an [OSCSocket].
OSCSocket _createBroadcastSocket({
  required InternetAddress serverAddress,
  required int serverPort,
  required InternetAddress destination,
  required int destinationPort,
}) {
  final socket = OSCSocket(
    serverAddress: serverAddress,
    serverPort: serverPort,
    destination: destination,
    destinationPort: destinationPort,
  );
  // Enable UDP broadcast if the underlying OSCSocket exposes the raw socket.
  try {
    // ignore: invalid_use_of_visible_for_testing_member, avoid_dynamic_calls
    (socket as dynamic).socket?.broadcastEnabled = true;
  } catch (_) {
    // Best effort: the `osc` package may not provide access to the inner socket.
  }
  return socket;
}

/// Singleton OSC listener for flash/audio/mic/sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  Timer? _helloTimer;
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<int>>? _micSubscription;
  bool _running = false;
  Timer? _disconnectTimer;

  /// Starts listening on UDP port 9000 (idempotent).
  Future<void> start() async {
    if (_running) return;
    _running = true;

    _socket = _createBroadcastSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: 9000,
      destination: InternetAddress('255.255.255.255'),
      destinationPort: 9000,
    );
    // Listen and dispatch using the current slot
    await _socket!.listen((OSCMessage msg) async {
      await _dispatch(msg);
    });

    // Periodically announce our presence so the server can discover us.
    _helloTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _sendHello());
    _sendHello();

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
          try {
            await TorchLight.enableTorch();
            client.flashOn.value = true;
          } catch (e) {
            print('[OSC] Torch error: $e');
            client.flashOn.value = false;
          }
        }
        break;

      case '/flash/off':
        if (m.arguments[0] as int == myIndex) {
          try {
            await TorchLight.disableTorch();
            client.flashOn.value = false;
          } catch (e) {
            print('[OSC] Torch error: $e');
            client.flashOn.value = true;
          }
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

      case '/sync':
        _markConnected();
        if (m.arguments.isNotEmpty) {
          final ts = m.arguments[0];
          BigInt? ntp;
          if (ts is BigInt) {
            ntp = ts;
          } else if (ts is int) {
            ntp = BigInt.from(ts);
          }
          if (ntp != null) {
            const eraOffset = 2208988800; // Seconds between 1900 and 1970
            final serverSecs = ntp - BigInt.from(eraOffset);
            final serverMs = serverSecs.toInt() * 1000;
            final localMs = DateTime.now().millisecondsSinceEpoch;
            final offset = serverMs - localMs;
            client.clockOffsetMs =
                (client.clockOffsetMs + offset) / 2; // simple smoothing
            print('[OSC] Clock offset updated to ${client.clockOffsetMs} ms');
          }
        }
        break;

      case '/hello':
        _markConnected();
        break;

      case '/mic/record':
        final id = m.arguments[0] as int;
        final durationSec = (m.arguments[1] as num).toDouble();
        if (id == myIndex) {
          print('[OSC] Starting mic recording for $durationSec s');
          await MicStream.shouldRequestPermission(true);
          final audioStream = MicStream.microphone(
            audioSource: AudioSource.DEFAULT,
            sampleRate: 44100,
            channelConfig: ChannelConfig.CHANNEL_IN_MONO,
            audioFormat: AudioFormat.ENCODING_PCM_16BIT,
          );
          _micSubscription?.cancel();
          _micSubscription = audioStream.listen((_) {});
          client.recording.value = true;
          Timer(
            Duration(milliseconds: (durationSec * 1000).toInt()),
            () async {
              await _micSubscription?.cancel();
              _micSubscription = null;
              client.recording.value = false;
              print('[OSC] Mic recording of $durationSec s completed');
            },
          );
        }
        break;
    }
  }

  /// Broadcast a hello so servers can discover us
  void _sendHello() {
    if (_socket == null) return;
    final msg = OSCMessage('/hello', [client.myIndex.value]);
    _socket!.send(
      msg,
      address: InternetAddress('255.255.255.255'),
      port: 9000,
    );
  }

  void _markConnected() {
    client.connected.value = true;
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer(const Duration(seconds: 2), () {
      client.connected.value = false;
    });
  }

  /// Stops listening and cleans up resources.
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    await _micSubscription?.cancel();
    _micSubscription = null;
    client.recording.value = false;
    await _player.dispose();
    _running = false;
    _disconnectTimer?.cancel();
    _helloTimer?.cancel();
    client.connected.value = false;    print('[OSC] Listener stopped');
  }
}
