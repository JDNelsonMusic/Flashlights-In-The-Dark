// Copyright © 2025.  MIT‑licensed.
// Improved version generated 2025‑07‑11.
// This file supersedes the former merge‑conflicted osc_listener.dart.

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'osc_packet.dart';
import 'osc_messages.dart';
import 'package:torch_light/torch_light.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../services/mic_input.dart';
import '../native_audio.dart';

import '../model/client_state.dart';
import '../model/event_recipe.dart';

/// Native channel to control torch brightness.
const MethodChannel _torchChannel = MethodChannel('ai.keex.flashlights/torch');
const bool kEnableMic = false;

/// Helper that creates a UDP‑broadcast‑enabled [OSCSocket].
const int _oscPort = 9000;
const Duration _fastHelloInterval = Duration(seconds: 2);
const Duration _slowHelloInterval = Duration(seconds: 10);

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
  // Best‑effort: create the socket immediately and allow broadcasting.
  socket.bind().then((_) {
    socket.rawSocket?.broadcastEnabled = true;
  });
  return socket;
}

/// Singleton OSC listener handling flash / audio / mic / sync cues.
class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  RawDatagramSocket? _recvSocket;
  Timer? _helloTimer;
  Duration _currentHelloInterval = _fastHelloInterval;
  int _playbackToken = 0;
  StreamSubscription<List<int>>? _micSubscription;
  final MicInput _mic = MicInputStub();
  bool _running = false;
  Timer? _disconnectTimer;
  final Map<String, InternetAddress> _serverAddresses = {};

  Future<void> _playPrimer(
    String fileName,
    double gain, {
    bool sendAck = false,
  }) async {
    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);

      final volume = gain.clamp(0.0, 1.0).toDouble();
      final playbackToken = ++_playbackToken;

      await NativeAudio.playPrimerTone(fileName, volume);

      debugPrint('[OSC] Native playback invoked: ${fileName.trim()} @ vol=$volume');
      client.audioPlaying.value = true;
      unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
        if (_playbackToken == playbackToken) {
          client.audioPlaying.value = false;
        }
      }));
    } catch (e) {
      debugPrint('[OSC] Native playback failed for $fileName: $e');
      client.audioPlaying.value = false;
    }
    if (sendAck) {
      _sendAck();
    }
  }

  /// Starts listening on UDP port 9000 (idempotent).
  Future<void> start() async {
    if (_running) return;
    _running = true;

    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('[OSC] Failed to activate audio session: $e');
    }

    _socket = _createBroadcastSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: _oscPort,
    );

    _recvSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _oscPort,
      reuseAddress: true,
      reusePort: true,
    );
    _recvSocket!.broadcastEnabled = true;
    _recvSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _recvSocket!.receive();
        if (dg != null) {
          _rememberServer(dg.address);
          final msg = _parseMessage(dg.data);
          if (msg != null) {
            _dispatch(msg);
          }
        }
      }
    });

    // Periodically announce our presence so servers can discover us.
    _restartHelloTimer(_fastHelloInterval);
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
        case 'd':
          if (idx + 8 > data.length) return null;
          args.add(bd.getFloat64(idx, Endian.big));
          idx += 8;
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

  /// Public helper so UI elements can adjust the torch directly.
  Future<void> setTorchLevel(double level) => _setTorchLevel(level);

  /* -------------------------------------------------------------------- */
  /*                               Dispatcher                             */
  /* -------------------------------------------------------------------- */

  Future<void> _dispatch(OSCMessage m) async {
    final myIndex = client.myIndex.value;
    final isSelfHello = m.address == '/hello' && m.arguments.isNotEmpty &&
        m.arguments[0] is int && m.arguments[0] == myIndex &&
        (m.arguments.length < 2 ||
            (m.arguments[1] is String && m.arguments[1] == client.udid));
    if (!isSelfHello) {
      debugPrint('📲 OSC <<< ${m.address}  ${m.arguments}');
    }

    final List<OSCMessage> updatedMessages = List<OSCMessage>.from(
      client.recentMessages.value,
    )..add(m);
    if (updatedMessages.length > 10) {
      updatedMessages.removeRange(0, updatedMessages.length - 10);
    }
    client.recentMessages.value = updatedMessages;

    switch (m.address) {
      case '/flash/on':
        final msg = FlashOn.fromOsc(m);
        if (msg != null && msg.index == myIndex) {
          final intensity = msg.intensity;
          try {
            final clamped = intensity.clamp(0.0, 1.0).toDouble();
            if ((client.brightness.value - clamped).abs() > 0.01) {
              client.brightness.value = clamped;
              await ScreenBrightness.instance.setScreenBrightness(clamped);
            }
            await _setTorchLevel(clamped);
            _sendAck();
          } catch (e) {
            print('[OSC] Torch error: $e');
            client.flashOn.value = false;
          }
        }
        break;

      case '/flash/off':
        final msg = FlashOff.fromOsc(m);
        if (msg != null && msg.index == myIndex) {
          try {
            await _setTorchLevel(0);
            client.brightness.value = 0;
            await ScreenBrightness.instance.setScreenBrightness(0);
            _sendAck();
          } catch (e) {
            print('[OSC] Torch error: $e');
            client.flashOn.value = true;
          }
        }
        break;

      case '/event/trigger':
        final msg = EventTrigger.fromOsc(m);
        if (msg != null && msg.index == myIndex) {
          await client.ensureEventRecipesLoaded();
          final events = client.eventRecipes.value;
          EventRecipe? event;
          for (final candidate in events) {
            if (candidate.id == msg.eventId) {
              event = candidate;
              break;
            }
          }
          if (event != null) {
            final assignment = client.assignmentForSlot(event, myIndex);
            if (assignment != null) {
              final sample = assignment.sample;
              const gain = 1.0;
              final nowMs =
                  DateTime.now().millisecondsSinceEpoch.toDouble();
              final startAt = msg.startAtMs ?? nowMs;
              final delayMs =
                  (startAt - nowMs).clamp(0, double.infinity).toInt();
              unawaited(Future.delayed(Duration(milliseconds: delayMs), () async {
                await _playPrimer(sample, gain, sendAck: true);
              }));
            } else {
              debugPrint(
                  '[OSC] No primer assignment for event ${msg.eventId} slot $myIndex');
            }
          } else {
            debugPrint('[OSC] Unknown event ID ${msg.eventId}');
          }
        }
        break;

      case '/audio/play':
        final msg = AudioPlay.fromOsc(m);
        if (msg != null &&
            client.shouldHandleIndex(msg.index, slotOverride: myIndex)) {
          final fileName = msg.file;
          final gain = msg.gain;
          await _playPrimer(fileName, gain, sendAck: true);
        }
        break;

      case '/audio/stop':
        final msg = AudioStop.fromOsc(m);
        if (msg != null &&
            client.shouldHandleIndex(msg.index, slotOverride: myIndex)) {
          _playbackToken++;
          try {
            await NativeAudio.stopPrimerTone();
          } catch (e) {
            debugPrint('[OSC] Native stop failed: $e');
          }
          client.audioPlaying.value = false;
          _sendAck();
        }
        break;

      // Dynamic slot assignment.
      case '/set-slot':
        final newSlot =
            m.arguments.isNotEmpty ? (m.arguments[0] as int) : myIndex;
        if (newSlot != client.myIndex.value) {
          client.myIndex.value = newSlot;
          print('[OSC] Updated listening slot to $newSlot');
          _sendAck();
          _sendHello();
        }
        break;

      case '/sync':
        // Clock syncing disabled: acknowledge reachability but ignore timestamp data.
        _markConnected();
        if (client.clockOffsetMs.value != 0) {
          client.clockOffsetMs.value = 0;
        }
        break;

      case '/hello':
        _markConnected();
        break;

      case '/discover':
      case '/ping':
        _markConnected();
        _sendHello();
        break;

      case '/mic/record':
        final msg = MicRecord.fromOsc(m);
        if (msg != null && msg.index == myIndex) {
          if (!kEnableMic) {
            print('[OSC] Mic disabled (stub).');
            _sendAck();
            break;
          }
          final durationSec = msg.maxDuration;
          print('[OSC] Starting mic recording (stub) for $durationSec s');
          final audioStream = _mic.start(sampleRate: 44100);
          _micSubscription?.cancel();
          _micSubscription = audioStream.listen((_) {});
          client.recording.value = true;
          Timer(Duration(milliseconds: (durationSec * 1000).toInt()), () async {
            await _micSubscription?.cancel();
            _micSubscription = null;
            await _mic.stop();
            client.recording.value = false;
            print('[OSC] Mic recording of $durationSec s completed (stub)');
          });
          _sendAck();
        }
        break;
    }

    // Close the dispatcher function after handling all cases.
  }

  Future<void> playLocalPrimer(String fileName, double gain) async {
    await _playPrimer(fileName, gain, sendAck: false);
  }

  /* -------------------------------------------------------------------- */
  /*                         Discovery / Heart‑beat                        */
  /* -------------------------------------------------------------------- */

  /// Broadcast a `/hello` so servers can discover this client.
  void _rememberServer(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return;
    if (address.isLoopback) return;
    final key = address.address;
    if (key.isEmpty) return;
    _serverAddresses[key] = address;
  }

  Future<void> _sendToServers(OSCMessage msg) async {
    if (_socket == null || _serverAddresses.isEmpty) return;
    for (final entry in _serverAddresses.values) {
      try {
        await _socket!.sendTo(msg, dest: entry, port: _oscPort);
      } catch (e) {
        debugPrint('[OSC] Unicast send error to ${entry.address}: $e');
      }
    }
  }

  void _restartHelloTimer(Duration interval) {
    if (_currentHelloInterval == interval && _helloTimer?.isActive == true) {
      return;
    }
    _helloTimer?.cancel();
    _currentHelloInterval = interval;
    _helloTimer = Timer.periodic(interval, (_) => _sendHello());
  }

  void _sendHello() {
    if (_socket == null) return;

    final msg = OSCMessage(
      '/hello',
      arguments: [client.myIndex.value, client.udid],
    );

    // Primary broadcast via the socket’s predefined destination.
    try {
      _socket!.send(msg);
    } catch (e) {
      // Log but do not crash; we fall back to per‑interface broadcasts below.
      print('[OSC] Primary broadcast failed: $e');
    }

    // Target any known servers directly first so they hear us even if broadcasts
    // are filtered by the network.
    unawaited(_sendToServers(msg));

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
                  raw.send(msg.toBytes(), bcast, _oscPort);
                  raw.close();
                })
                .catchError((_) {
                  /* ignore */
                });
          }
        }
      }
    });
  }

  void _sendAck() {
    if (_socket == null) return;
    final msg = OSCMessage('/ack', arguments: [client.myIndex.value]);
    try {
      _socket!.send(msg);
      unawaited(_sendToServers(msg));
    } catch (e) {
      print('[OSC] Ack send error: $e');
    }
  }

  void _markConnected() {
    client.connected.value = true;
    _disconnectTimer?.cancel();
    if (_currentHelloInterval != _slowHelloInterval) {
      _restartHelloTimer(_slowHelloInterval);
    }
    _disconnectTimer = Timer(const Duration(seconds: 2), () {
      client.connected.value = false;
      if (_currentHelloInterval != _fastHelloInterval) {
        _restartHelloTimer(_fastHelloInterval);
      }
    });
  }

  /// Send a custom OSC message to the server. Best effort only.
  void sendCustom(String address, List<Object> args) {
    if (_socket == null) return;
    final msg = OSCMessage(address, arguments: args);
    try {
      _socket!.send(msg);
      unawaited(_sendToServers(msg));
    } catch (e) {
      print('[OSC] sendCustom error: $e');
    }
  }

  /// Send a typed OSC message using [OscCodable].
  void send(OscCodable message) {
    if (_socket == null) return;
    try {
      final osc = message.toOsc();
      _socket!.send(osc);
      unawaited(_sendToServers(osc));
    } catch (e) {
      print('[OSC] send error: $e');
    }
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

    // Cancel any mic recording.
    await _micSubscription?.cancel();
    _micSubscription = null;
    client.recording.value = false;

    try {
      await NativeAudio.stopPrimerTone();
    } catch (e) {
      debugPrint('[OSC] Failed to stop native primer playback: $e');
    }
    client.audioPlaying.value = false;
    _running = false;

    // Reset screen brightness to default and clear brightness state.
    try {
      await ScreenBrightness.instance.resetScreenBrightness();
      client.brightness.value = 0;
    } catch (_) {
      // Ignore if the platform doesn’t support brightness reset.
    }

    // Cancel timers and update connection state.
    _disconnectTimer?.cancel();
    _helloTimer?.cancel();
    client.connected.value = false;

    print('[OSC] Listener stopped');
  }
}
