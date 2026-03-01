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

class _NetworkEvent {
  const _NetworkEvent({
    required this.timestamp,
    required this.category,
    required this.message,
    this.data,
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp.toIso8601String(),
      'category': category,
      'message': message,
      if (data != null) 'data': data,
    };
  }
}

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

Future<RawDatagramSocket> _bindReceiveSocket() {
  return RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    _oscPort,
    reuseAddress: true,
    reusePort: true,
  );
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
  final Map<String, Timer> _primerDedupTimers = {};
  static const Duration _primerDedupHold = Duration(seconds: 5);
  StreamSubscription<List<int>>? _micSubscription;
  final MicInput _mic = MicInputStub();
  bool _running = false;
  Timer? _disconnectTimer;
  final Map<String, InternetAddress> _serverAddresses = {};
  StreamSubscription<RawSocketEvent>? _recvSubscription;
  final List<_NetworkEvent> _eventLog = <_NetworkEvent>[];
  static const int _maxLogEntries = 600;
  final Set<String> _everSeenServers = <String>{};
  Completer<void>? _rebindCompleter;
  DateTime? _lastRebindTime;

  void _record(String category, String message, [Map<String, Object?>? data]) {
    final event = _NetworkEvent(
      timestamp: DateTime.now().toUtc(),
      category: category,
      message: message,
      data: data == null ? null : Map<String, Object?>.unmodifiable(data),
    );
    _eventLog.add(event);
    if (_eventLog.length > _maxLogEntries) {
      _eventLog.removeRange(0, _eventLog.length - _maxLogEntries);
    }
    if (kDebugMode) {
      final suffix = data == null ? '' : ' $data';
      debugPrint('[OSC][$category] $message$suffix');
    }
  }

  Future<void> _rebindSockets({bool clearServerCache = false}) async {
    _recvSubscription?.cancel();
    _recvSubscription = null;
    _socket?.close();
    _socket = null;
    _recvSocket?.close();
    _recvSocket = null;

    if (clearServerCache) {
      _serverAddresses.clear();
    }

    _socket = _createBroadcastSocket(
      serverAddress: InternetAddress.anyIPv4,
      serverPort: _oscPort,
    );

    final recv = await _bindReceiveSocket();
    recv.broadcastEnabled = true;
    _recvSubscription = recv.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          final dg = recv.receive();
          if (dg != null) {
            _rememberServer(dg.address);
            final msg = _parseMessage(dg.data);
            if (msg != null) {
              _dispatch(msg);
            }
          }
        } else if (event == RawSocketEvent.closed ||
            event == RawSocketEvent.readClosed) {
          _record('socket', 'Receive socket closed', <String, Object?>{'event': '$event'});
          unawaited(
            _scheduleRebind(reason: 'recv socket closed', clearServerCache: false),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        _record(
          'socket',
          'Receive socket error',
          <String, Object?>{'error': error.toString()},
        );
        unawaited(
          _scheduleRebind(reason: 'recv socket error', clearServerCache: false),
        );
      },
      onDone: () {
        _record('socket', 'Receive socket done');
        unawaited(
          _scheduleRebind(reason: 'recv socket done', clearServerCache: false),
        );
      },
    );
    _recvSocket = recv;
  }

  Future<void> _scheduleRebind({
    required String reason,
    bool clearServerCache = false,
  }) {
    if (_rebindCompleter != null) {
      _record('rebind', 'Rebind already in flight ($reason)');
      return _rebindCompleter!.future;
    }
    final completer = Completer<void>();
    _rebindCompleter = completer;

    () async {
      try {
        final now = DateTime.now();
        final last = _lastRebindTime;
        if (last != null) {
          final diff = now.difference(last);
          const minSpacing = Duration(milliseconds: 600);
          if (diff < minSpacing) {
            await Future<void>.delayed(minSpacing - diff);
          }
        }
        _record(
          'rebind',
          'Rebinding sockets',
          <String, Object?>{'reason': reason, 'clearCache': clearServerCache},
        );
        await _rebindSockets(clearServerCache: clearServerCache);
        _lastRebindTime = DateTime.now();
        _record('rebind', 'Rebind complete', <String, Object?>{'reason': reason});
        if (_running) {
          _sendHello();
        }
        completer.complete();
      } catch (e, st) {
        _record(
          'rebind',
          'Rebind failed',
          <String, Object?>{'reason': reason, 'error': e.toString()},
        );
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        _rebindCompleter = null;
      }
    }();

    return completer.future;
  }

  void _registerPrimerKey(String key) {
    _primerDedupTimers[key]?.cancel();
    _primerDedupTimers[key] = Timer(_primerDedupHold, () {
      _primerDedupTimers.remove(key);
    });
  }

  bool _shouldSkipPrimer(String? key) {
    if (key == null) {
      return false;
    }
    _primerDedupTimers.removeWhere((k, timer) {
      final active = timer.isActive;
      if (!active) {
        timer.cancel();
      }
      return !active;
    });
    final existing = _primerDedupTimers[key];
    if (existing != null && existing.isActive) {
      return true;
    }
    return false;
  }

  Future<void> _playPrimer(
    String fileName,
    double gain, {
    bool sendAck = false,
    String? dedupeKey,
  }) async {
    if (_shouldSkipPrimer(dedupeKey)) {
      debugPrint('[OSC] Skipping duplicate primer request for $dedupeKey');
      if (sendAck) {
        _sendAck();
      }
      return;
    }
    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);

      final volume = gain.clamp(0.0, 1.0).toDouble();
      final playbackToken = ++_playbackToken;

      await NativeAudio.playPrimerTone(fileName, volume);

      if (dedupeKey != null) {
        _registerPrimerKey(dedupeKey);
      }

      debugPrint(
        '[OSC] Native playback invoked: ${fileName.trim()} @ vol=$volume',
      );
      client.audioPlaying.value = true;
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (_playbackToken == playbackToken) {
            client.audioPlaying.value = false;
          }
        }),
      );
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
    _record('lifecycle', 'OSC listener starting');

    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('[OSC] Failed to activate audio session: $e');
    }

    try {
      await _scheduleRebind(reason: 'startup', clearServerCache: true);
    } catch (e) {
      _running = false;
      rethrow;
    }

    // Periodically announce our presence so servers can discover us.
    _restartHelloTimer(_fastHelloInterval);
    _sendHello();

    _record('lifecycle', 'Listening on 0.0.0.0:$_oscPort');
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
    final isSelfHello =
        m.address == '/hello' &&
        m.arguments.isNotEmpty &&
        m.arguments[0] is int &&
        m.arguments[0] == myIndex &&
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
              final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
              final startAt = msg.startAtMs ?? nowMs;
              final delayMs =
                  (startAt - nowMs).clamp(0, double.infinity).toInt();
              final dedupeKey = 'event:${msg.eventId}:slot=$myIndex';
              unawaited(
                Future.delayed(Duration(milliseconds: delayMs), () async {
                  await _playPrimer(
                    sample,
                    gain,
                    sendAck: true,
                    dedupeKey: dedupeKey,
                  );
                }),
              );
            } else {
              debugPrint(
                '[OSC] No primer assignment for event ${msg.eventId} slot $myIndex',
              );
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
    final existing = _serverAddresses[key];
    _serverAddresses[key] = address;
    if (existing == null) {
      _everSeenServers.add(key);
      _record('server', 'Discovered console', <String, Object?>{'ip': key});
    }
  }

  Future<void> _sendToServers(OSCMessage msg) async {
    if (_socket == null || _serverAddresses.isEmpty) return;
    for (final entry in _serverAddresses.values) {
      try {
        await _socket!.sendTo(msg, dest: entry, port: _oscPort);
      } catch (e) {
        debugPrint('[OSC] Unicast send error to ${entry.address}: $e');
        _record(
          'send',
          'Unicast send error',
          <String, Object?>{'ip': entry.address, 'error': e.toString()},
        );
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

    _record(
      'hello',
      'Broadcasting /hello',
      <String, Object?>{'knownServers': _serverAddresses.length},
    );
    // Primary broadcast via the socket’s predefined destination.
    try {
      _socket!.send(msg);
    } catch (e) {
      // Log but do not crash; we fall back to per‑interface broadcasts below.
      print('[OSC] Primary broadcast failed: $e');
      _record(
        'hello',
        'Primary broadcast failed',
        <String, Object?>{'error': e.toString()},
      );
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
    _record('ack', 'Sending /ack', <String, Object?>{'slot': client.myIndex.value});
    try {
      _socket!.send(msg);
      unawaited(_sendToServers(msg));
    } catch (e) {
      print('[OSC] Ack send error: $e');
      _record(
        'ack',
        'Ack send error',
        <String, Object?>{'error': e.toString()},
      );
    }
  }

  void _markConnected() {
    final wasConnected = client.connected.value;
    client.connected.value = true;
    if (!wasConnected) {
      _record('connectivity', 'Connected');
    }
    _disconnectTimer?.cancel();
    if (_currentHelloInterval != _slowHelloInterval) {
      _restartHelloTimer(_slowHelloInterval);
    }
    _disconnectTimer = Timer(const Duration(seconds: 2), () {
      client.connected.value = false;
      if (_currentHelloInterval != _fastHelloInterval) {
        _restartHelloTimer(_fastHelloInterval);
      }
      _record('connectivity', 'Connection timed out');
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

  /// Rebinds sockets and rebroadcasts presence so the console rediscovers us.
  Future<void> refreshConnection() async {
    if (!_running) {
      await start();
      return;
    }
    _record('manual', 'Manual refresh requested');
    await _scheduleRebind(reason: 'manual refresh', clearServerCache: false);
    _disconnectTimer?.cancel();
    client.connected.value = false;
    _restartHelloTimer(_fastHelloInterval);
    _sendHello();
    debugPrint('[OSC] Connection refresh triggered by user');
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

  Map<String, Object?> networkDiagnosticsSnapshot() {
    return <String, Object?>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'knownServers': _serverAddresses.keys.toList(growable: false),
      'everSeenServers': _everSeenServers.toList(growable: false),
      'helloIntervalSeconds': _currentHelloInterval.inSeconds,
      'events': _eventLog.map((e) => e.toJson()).toList(growable: false),
    };
  }

  String exportNetworkLogJson() {
    return jsonEncode(networkDiagnosticsSnapshot());
  }

  /* -------------------------------------------------------------------- */
  /*                               Teardown                                */
  /* -------------------------------------------------------------------- */

  /// Stops listening and cleans up resources.
  Future<void> stop() async {
    await _recvSubscription?.cancel();
    _recvSubscription = null;
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
    _record('lifecycle', 'Listener stopped');
  }
}
