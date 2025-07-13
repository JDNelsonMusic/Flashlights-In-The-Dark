// Copyright © 2025.  MIT‑licensed.
// Improved version generated 2025‑07‑11.
// This file supersedes the former merge‑conflicted osc_listener.dart.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:osc/osc.dart';
import 'package:torch_light/torch_light.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:mic_stream/mic_stream.dart' as mic;

import '../model/client_state.dart';

/// Native channel to control torch brightness.
const MethodChannel _torchChannel = MethodChannel('ai.keex.flashlights/torch');

/// Helper that creates a UDP‑broadcast‑enabled [OSCSocket].
OSCSocket _createBroadcastSocket({
  required InternetAddress serverAddress,
  required int serverPort,
}) {
  // Pre‑define the broadcast target so [OSCSocket.send] can be called with
  // *only* the OSC message (send(msg)).
  final socket = OSCSocket(
    serverAddress: serverAddress,
    serverPort: serverPort,
    destination: InternetAddress('255.255.255.255'),
    destinationPort: serverPort,
  );

  // Best‑effort: ask the wrapped RawDatagramSocket to allow broadcasting.
  try {
    // ignore: invalid_use_of_visible_for_testing_member, avoid_dynamic_calls
    (socket as dynamic).rawSocket?.broadcastEnabled = true;
  } catch (_) {
    try {
      // ignore: invalid_use_of_visible_for_testing_member, avoid_dynamic_calls
      (socket as dynamic).socket?.broadcastEnabled = true;
    } catch (_) {
      // Some builds of the osc package don’t expose the inner socket.
    }
  }
  return socket;
}

/// Singleton OSC listener handling flash / audio / mic / sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  RawDatagramSocket? _recvSocket;
  Timer? _helloTimer;
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<int>>? _micSubscription;
  bool _running = false;
  Timer? _disconnectTimer;

  /// Starts listening on UDP port 9000 (idempotent).
  Future<void> start() async {
    if (_running) return;
    _running = true;

    _socket = _createBroadcastSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: 9000,
    );

    _recvSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      9000,
      reuseAddress: true,
      reusePort: true,
    );
    _recvSocket!.broadcastEnabled = true;
  _recvSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _recvSocket!.receive();
        if (dg != null) {
          final msg = _parseMessage(dg.data);
          if (msg != null) {
            _dispatch(msg);
          }
        }
      }
    });

    // Periodically announce our presence so servers can discover us.
    _helloTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _sendHello());
    _sendHello();

    print('[OSC] Listening on 0.0.0.0:9000');
  }

  /// Minimal OSC parser for the small subset of messages we use.
  OSCMessage? _parseMessage(Uint8List data) {
    int idx = 0;
    final zero = data.indexOf(0, idx);
    if (zero == -1) return null;
    final address = utf8.decode(data.sublist(0, zero));
    idx = (zero + 4) & ~3;
    if (idx >= data.length || data[idx] != 44) return null; // ','
    final tagEnd = data.indexOf(0, idx);
    if (tagEnd == -1) return null;
    final tags = utf8.decode(data.sublist(idx + 1, tagEnd));
    idx = (tagEnd + 4) & ~3;
    final args = <Object>[];
    final bd = ByteData.sublistView(data);
    for (final t in tags.split('')) {
      switch (t) {
        case 'i':
          if (idx + 4 > data.length) return null;
          args.add(bd.getInt32(idx, Endian.big));
          idx += 4;
          break;
        case 'h':
          if (idx + 8 > data.length) return null;
          args.add(bd.getInt64(idx, Endian.big));
          idx += 8;
          break;
        case 'f':
          if (idx + 4 > data.length) return null;
          args.add(bd.getFloat32(idx, Endian.big));
          idx += 4;
          break;
        case 's':
          final end = data.indexOf(0, idx);
          if (end == -1) return null;
          args.add(utf8.decode(data.sublist(idx, end)));
          idx = (end + 4) & ~3;
          break;
        case 't':
          if (idx + 8 > data.length) return null;
          final hi = bd.getUint32(idx, Endian.big);
          final lo = bd.getUint32(idx + 4, Endian.big);
          args.add((BigInt.from(hi) << 32) | BigInt.from(lo));
          idx += 8;
          break;
        default:
          return null; // unsupported
      }
    }
    // Explicitly cast the dynamic list to the non-nullable
    // type expected by the OSCMessage constructor.
    return OSCMessage(address, arguments: List<Object>.from(args));
  }

  /// Sets the torch brightness on the native side. Falls back to
  /// [TorchLight.enableTorch]/[TorchLight.disableTorch] if the platform
  /// channel isn't implemented (older Android versions).
  Future<void> _setTorchLevel(double level) async {
    try {
      await _torchChannel.invokeMethod('setTorchLevel', level);
      client.flashOn.value = level > 0;
    } on MissingPluginException {
      // Older Android versions: only on/off available via TorchLight.
      if (level > 0) {
        await TorchLight.enableTorch();
        client.flashOn.value = true;
      } else {
        await TorchLight.disableTorch();
        client.flashOn.value = false;
      }
    } catch (e) {
      print('[OSC] Torch error: $e');
      client.flashOn.value = false;
    }
  }

  /* -------------------------------------------------------------------- */
  /*                               Dispatcher                             */
  /* -------------------------------------------------------------------- */

  Future<void> _dispatch(OSCMessage m) async {
    final myIndex = client.myIndex.value;
    print('OSC ↳ ${m.address} ${m.arguments}');

    switch (m.address) {
      case '/flash/on':
        final id = m.arguments[0] as int;
        final intensity = m.arguments.length > 1
            ? (m.arguments[1] as num).toDouble()
            : 1.0;
        if (id == myIndex) {
          try {
            final clamped = intensity.clamp(0.0, 1.0) as double;
            if ((client.brightness.value - clamped).abs() > 0.01) {
              client.brightness.value = clamped;
              await ScreenBrightness.instance.setScreenBrightness(clamped);
            }
            await _setTorchLevel(clamped);
          } catch (e) {
            print('[OSC] Torch error: $e');
            client.flashOn.value = false;
          }
        }
        break;

      case '/flash/off':
        if (m.arguments[0] as int == myIndex) {
          try {
            await _setTorchLevel(0);
            client.brightness.value = 0;
            await ScreenBrightness.instance.setScreenBrightness(0);
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
            await _player.setVolume(gain.clamp(0.0, 1.0) as double);
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

      // Dynamic slot assignment.
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
            const eraOffset = 2208988800; // Seconds between 1900 and 1970.
            final serverSecs = ntp - BigInt.from(eraOffset);
            final serverMs = serverSecs.toInt() * 1000;
            final localMs = DateTime.now().millisecondsSinceEpoch;
            final offset = serverMs - localMs;
            client.clockOffsetMs =
                (client.clockOffsetMs + offset) / 2; // Simple smoothing.
            print('[OSC] Clock offset updated to ${client.clockOffsetMs} ms');
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
          print('[OSC] Starting mic recording for $durationSec s');
          await mic.MicStream.shouldRequestPermission(true);
          final audioStream = mic.MicStream.microphone(
            audioSource: mic.AudioSource.DEFAULT,
            sampleRate: 44100,
            channelConfig: mic.ChannelConfig.CHANNEL_IN_MONO,
            audioFormat: mic.AudioFormat.ENCODING_PCM_16BIT,
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
              print('[OSC] Mic recording of $durationSec s completed');
            },
          );
        }
        break;
    }
  }

  /* -------------------------------------------------------------------- */
  /*                         Discovery / Heart‑beat                        */
  /* -------------------------------------------------------------------- */

  /// Broadcast a `/hello` so servers can discover this client.
  void _sendHello() {
    if (_socket == null) return;

    final msg = OSCMessage('/hello', arguments: [client.myIndex.value]);

    // Primary broadcast via the socket’s predefined destination.
    try {
      _socket!.send(msg);
    } catch (e) {
      // Log but do not crash; we fall back to per‑interface broadcasts below.
      print('[OSC] Primary broadcast failed: $e');
    }

    // Secondary: per‑interface subnet broadcast for routers that
    // ignore 255.255.255.255. Best‑effort only – errors intentionally ignored.
    NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    ).then((interfaces) {
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            parts[3] = '255';
            final bcast = InternetAddress(parts.join('.'));

            RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
                .then((raw) {
              raw.broadcastEnabled = true;
              raw.send(msg.toBytes(), bcast, 9000);
              raw.close();
            }).catchError((_) {/* ignore */});
          }
        }
      }
    });
  }

  void _markConnected() {
    client.connected.value = true;
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer(const Duration(seconds: 2), () {
      client.connected.value = false;
    });
  }

  /* -------------------------------------------------------------------- */
  /*                               Teardown                                */
  /* -------------------------------------------------------------------- */

  /// Stops listening and cleans up resources.
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _recvSocket?.close();
    _recvSocket = null;

    await _micSubscription?.cancel();
    _micSubscription = null;
    client.recording.value = false;

    await _player.dispose();
    _running = false;

    try {
      await ScreenBrightness.instance.resetScreenBrightness();
      client.brightness.value = 0;
    } catch (_) {}

    _disconnectTimer?.cancel();
    _helloTimer?.cancel();
    client.connected.value = false;

    print('[OSC] Listener stopped');
  }
}