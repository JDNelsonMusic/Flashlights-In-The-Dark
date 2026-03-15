// Copyright © 2025.  MIT-licensed.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';

import '../model/client_state.dart';
import '../model/event_recipe.dart';
import '../native_audio.dart';
import '../services/mic_input.dart';
import 'osc_messages.dart';
import 'osc_packet.dart';

const MethodChannel _torchChannel = MethodChannel('ai.keex.flashlights/torch');
const bool kEnableMic = false;
const int _oscPort = 9000;
const Duration _fastHelloInterval = Duration(seconds: 2);
const Duration _slowHelloInterval = Duration(seconds: 10);
const Duration _conductorTimeout = Duration(seconds: 8);
const Duration _watchdogTick = Duration(seconds: 1);
const int _legacySoundEventCount = 32;
const bool kPrimerPlaybackEnabled = false;
const Duration _lightSequenceTick = Duration(milliseconds: 40);

@visibleForTesting
Duration playbackDelayForStartAtMs(double? startAtMs, {DateTime? now}) {
  if (startAtMs == null) {
    return Duration.zero;
  }
  final reference = now ?? DateTime.now();
  final delayMs =
      (startAtMs - reference.millisecondsSinceEpoch)
          .clamp(0, double.infinity)
          .toInt();
  return Duration(milliseconds: delayMs);
}

@visibleForTesting
double interpolateLightLevel(
  List<LightingKeyframe> keyframes,
  double elapsedMs,
) {
  if (keyframes.isEmpty) {
    return 0.0;
  }

  final clampedElapsed = elapsedMs.clamp(0.0, double.infinity);
  if (clampedElapsed <= keyframes.first.atMs) {
    return keyframes.first.level;
  }
  for (var index = 1; index < keyframes.length; index += 1) {
    final previous = keyframes[index - 1];
    final current = keyframes[index];
    if (clampedElapsed <= current.atMs) {
      if (previous.interpolation == 'step') {
        return previous.level;
      }
      final span = current.atMs - previous.atMs;
      if (span <= 0) {
        return current.level;
      }
      final t = (clampedElapsed - previous.atMs) / span;
      return previous.level + (current.level - previous.level) * t;
    }
  }
  return keyframes.last.level;
}

String? _normaliseAudioPlayToken(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (value.contains('/')) {
    value = value.split('/').last;
  }
  return value;
}

@visibleForTesting
String? resolvePrimerAudioPlayFile(String raw) {
  final token = _normaliseAudioPlayToken(raw);
  if (token == null || token.isEmpty) {
    return null;
  }

  final lower = token.toLowerCase();
  if (lower.startsWith('short') || lower.startsWith('long')) {
    return token;
  }

  final legacyPrimer = RegExp(r'^a(\d+)(?:\.mp3)?$', caseSensitive: false);
  final match = legacyPrimer.firstMatch(token);
  if (match == null) {
    return null;
  }

  final value = int.tryParse(match.group(1) ?? '');
  if (value == null) {
    return null;
  }
  if (value >= 0 && value <= 48) {
    return 'Short$value.mp3';
  }
  if (value >= 50 && value <= 98) {
    return 'Long$value.mp3';
  }
  return null;
}

@visibleForTesting
String? resolveBundledAudioPlayAssetKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  var value = trimmed;
  if (value.startsWith('./')) {
    value = value.substring(2);
  }

  if (value.startsWith('available-sounds/')) {
    if (!value.toLowerCase().endsWith('.mp3')) {
      value = '$value.mp3';
    }
    return value;
  }

  final token = _normaliseAudioPlayToken(value);
  if (token == null || token.isEmpty) {
    return null;
  }

  String? prefixedAsset(String folder, String stem, int number) {
    if (number < 1 || number > _legacySoundEventCount) {
      return null;
    }
    return 'available-sounds/$folder/$stem$number.mp3';
  }

  final directBank = RegExp(r'^([bcd])(\d+)(?:\.mp3)?$', caseSensitive: false);
  final directMatch = directBank.firstMatch(token);
  if (directMatch != null) {
    final stem = directMatch.group(1)!.toLowerCase();
    final number = int.tryParse(directMatch.group(2) ?? '');
    if (number == null) {
      return null;
    }
    switch (stem) {
      case 'b':
        return prefixedAsset('sound-events-LEFT', 'b', number);
      case 'c':
        return prefixedAsset('sound-events-CENTER', 'c', number);
      case 'd':
        return prefixedAsset('sound-events-RIGHT', 'd', number);
    }
  }

  final familyBank = RegExp(
    r'^(se[clr])-(\d+)(?:\.mp3)?$',
    caseSensitive: false,
  );
  final familyMatch = familyBank.firstMatch(token);
  if (familyMatch == null) {
    return null;
  }

  final family = familyMatch.group(1)!.toLowerCase();
  final zeroBasedIndex = int.tryParse(familyMatch.group(2) ?? '');
  if (zeroBasedIndex == null) {
    return null;
  }

  // The repo currently ships 32 legacy left/center/right sound-event MP3s
  // per family. Map the 0-based transport vocabulary onto those bundled files.
  final assetNumber = zeroBasedIndex + 1;
  switch (family) {
    case 'sel':
      return prefixedAsset('sound-events-LEFT', 'b', assetNumber);
    case 'sec':
      return prefixedAsset('sound-events-CENTER', 'c', assetNumber);
    case 'ser':
      return prefixedAsset('sound-events-RIGHT', 'd', assetNumber);
    default:
      return null;
  }
}

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

class _InboundDatagram {
  const _InboundDatagram({
    required this.message,
    required this.address,
    required this.port,
  });

  final OSCMessage message;
  final InternetAddress address;
  final int port;
}

class _CueEnvelope {
  const _CueEnvelope({
    required this.slot,
    required this.protocolVersion,
    required this.showSessionId,
    required this.seq,
    required this.cueId,
    required this.sentAtMs,
    required this.payload,
  });

  final int slot;
  final int protocolVersion;
  final String showSessionId;
  final int seq;
  final String cueId;
  final int sentAtMs;
  final List<Object> payload;

  static _CueEnvelope? fromOsc(OSCMessage message) {
    final args = message.arguments;
    if (args.length < 6) return null;

    final slot = args[0];
    final protocolVersion = args[1];
    final showSessionId = args[2];
    final seq = args[3];
    final cueId = args[4];
    final sentAtMs = args[5];

    if (slot is! int ||
        protocolVersion is! int ||
        showSessionId is! String ||
        seq is! int ||
        cueId is! String ||
        sentAtMs is! int) {
      return null;
    }

    return _CueEnvelope(
      slot: slot,
      protocolVersion: protocolVersion,
      showSessionId: showSessionId,
      seq: seq,
      cueId: cueId,
      sentAtMs: sentAtMs,
      payload: args.length > 6 ? args.sublist(6) : const <Object>[],
    );
  }
}

OSCSocket _createBroadcastSocket({
  required InternetAddress serverAddress,
  required int serverPort,
}) {
  final socket = OSCSocket(
    serverAddress: serverAddress,
    // Use an ephemeral source port for outbound traffic so the dedicated
    // receive socket remains the sole owner of UDP/9000.
    serverPort: 0,
    destination: InternetAddress('255.255.255.255'),
    destinationPort: serverPort,
  );
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

class OscListener {
  OscListener._();
  static final OscListener instance = OscListener._();

  OSCSocket? _socket;
  RawDatagramSocket? _recvSocket;
  StreamSubscription<RawSocketEvent>? _recvSubscription;
  StreamSubscription<List<int>>? _micSubscription;

  final MicInput _mic = MicInputStub();
  bool _running = false;

  Timer? _helloTimer;
  Duration _currentHelloInterval = _fastHelloInterval;
  Timer? _disconnectTimer;
  Timer? _conductorWatchdog;

  Completer<void>? _rebindCompleter;
  DateTime? _lastRebindTime;

  Future<void> _dispatchQueue = Future<void>.value();
  int _playbackToken = 0;
  int _lightSequenceToken = 0;
  final Map<String, Timer> _primerDedupTimers = <String, Timer>{};
  Timer? _lightSequenceTimer;
  static const Duration _primerDedupHold = Duration(seconds: 5);
  double _lastAppliedLightLevel = -1.0;
  String? _activeLightingSummary;
  String? _activeLightingPart;
  int? _activeLightingEventId;

  final List<_NetworkEvent> _eventLog = <_NetworkEvent>[];
  static const int _maxLogEntries = 600;

  InternetAddress? _trustedConductorAddress;
  int? _trustedConductorPort;
  String? _lockedShowSessionId;
  DateTime? _lastConductorHeartbeat;

  int _unknownSenderCount = 0;
  int _protocolMismatchCount = 0;
  int _duplicatesDropped = 0;
  int _outOfOrderDropped = 0;
  int _slotMismatchCount = 0;

  int _lastProcessedSeq = -1;
  String? _lastAcceptedCueAddress;
  String? _lastAcceptedCueId;
  final LinkedHashMap<String, DateTime> _recentCueIds =
      LinkedHashMap<String, DateTime>();
  static const Duration _cueIdTtl = Duration(minutes: 3);
  static const int _maxCueIdCacheSize = 4096;

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

  void _resetCueOrderingState() {
    _lastProcessedSeq = -1;
    _recentCueIds.clear();
  }

  void _setCueRoutingIssue(String? issue) {
    if (client.cueRoutingIssue.value == issue) {
      return;
    }
    client.cueRoutingIssue.value = issue;
  }

  void _unlockConductor({required String reason}) {
    final hadLock = _trustedConductorAddress != null;
    _trustedConductorAddress = null;
    _trustedConductorPort = null;
    _lockedShowSessionId = null;
    _lastConductorHeartbeat = null;
    _resetCueOrderingState();

    if (hadLock) {
      _record('pairing', 'Unlocked conductor', <String, Object?>{
        'reason': reason,
      });
    }

    _setCueRoutingIssue(null);
    client.connected.value = false;
    if (_running) {
      _restartHelloTimer(_fastHelloInterval);
    }
  }

  void _lockConductor(InternetAddress address, int port, String showSessionId) {
    _trustedConductorAddress = address;
    _trustedConductorPort = port;
    _lockedShowSessionId = showSessionId;
    _resetCueOrderingState();
    _setCueRoutingIssue(null);
    _record('pairing', 'Locked conductor endpoint', <String, Object?>{
      'ip': address.address,
      'port': port,
      'showSessionId': showSessionId,
    });
    _markConductorHeartbeat();
  }

  bool _isTrustedSender(_InboundDatagram datagram) {
    final trustedAddress = _trustedConductorAddress;
    final trustedPort = _trustedConductorPort;
    if (trustedAddress == null || trustedPort == null) return false;
    return datagram.address.address == trustedAddress.address &&
        datagram.port == trustedPort;
  }

  bool _recordUnknownSender(_InboundDatagram datagram, String reason) {
    _unknownSenderCount += 1;
    _record(
      'security',
      'Dropped message from untrusted sender',
      <String, Object?>{
        'reason': reason,
        'ip': datagram.address.address,
        'port': datagram.port,
        'address': datagram.message.address,
      },
    );
    return false;
  }

  void _markConductorHeartbeat() {
    _lastConductorHeartbeat = DateTime.now().toUtc();
    if (!client.connected.value) {
      client.connected.value = true;
      _record('connectivity', 'Connected to trusted conductor');
    }
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer(_conductorTimeout, () {
      _unlockConductor(reason: 'conductor heartbeat timeout');
    });

    if (_currentHelloInterval != _slowHelloInterval) {
      _restartHelloTimer(_slowHelloInterval);
    }
  }

  void _startConductorWatchdog() {
    _conductorWatchdog?.cancel();
    _conductorWatchdog = Timer.periodic(_watchdogTick, (_) {
      final last = _lastConductorHeartbeat;
      if (last == null) return;
      if (DateTime.now().toUtc().difference(last) > _conductorTimeout) {
        _unlockConductor(reason: 'watchdog timeout');
      }
    });
  }

  Future<void> _rebindSockets() async {
    await _recvSubscription?.cancel();
    _recvSubscription = null;
    _socket?.close();
    _socket = null;
    _recvSocket?.close();
    _recvSocket = null;

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
          if (dg == null) return;
          final parsed = _parseMessage(dg.data);
          if (parsed == null) return;
          _enqueueDispatch(
            _InboundDatagram(
              message: parsed,
              address: dg.address,
              port: dg.port,
            ),
          );
          return;
        }

        if (event == RawSocketEvent.closed ||
            event == RawSocketEvent.readClosed) {
          _record('socket', 'Receive socket closed', <String, Object?>{
            'event': '$event',
          });
          unawaited(_scheduleRebind(reason: 'recv socket closed'));
        }
      },
      onError: (Object error, StackTrace stack) {
        _record('socket', 'Receive socket error', <String, Object?>{
          'error': error.toString(),
        });
        unawaited(_scheduleRebind(reason: 'recv socket error'));
      },
      onDone: () {
        _record('socket', 'Receive socket done');
        unawaited(_scheduleRebind(reason: 'recv socket done'));
      },
    );
    _recvSocket = recv;
  }

  Future<void> _scheduleRebind({required String reason}) {
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
          const minSpacing = Duration(milliseconds: 600);
          final diff = now.difference(last);
          if (diff < minSpacing) {
            await Future<void>.delayed(minSpacing - diff);
          }
        }

        _record('rebind', 'Rebinding sockets', <String, Object?>{
          'reason': reason,
        });
        await _rebindSockets();
        _lastRebindTime = DateTime.now();
        _record('rebind', 'Rebind complete', <String, Object?>{
          'reason': reason,
        });

        if (_running) {
          _sendHello();
        }

        completer.complete();
      } catch (e, st) {
        _record('rebind', 'Rebind failed', <String, Object?>{
          'reason': reason,
          'error': e.toString(),
        });
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        _rebindCompleter = null;
      }
    }();

    return completer.future;
  }

  void _sendBestEffort(
    OSCMessage msg, {
    InternetAddress? destination,
    int port = _oscPort,
    required String category,
  }) {
    final socket = _socket;
    if (socket == null) return;

    Future<int> sendFuture;
    if (destination == null) {
      sendFuture = socket.send(msg);
    } else {
      sendFuture = socket.sendTo(msg, dest: destination, port: port);
    }

    unawaited(
      sendFuture.catchError((Object error) {
        _record(category, 'Send failed', <String, Object?>{
          'error': error.toString(),
        });
        return 0;
      }),
    );
  }

  void _enqueueDispatch(_InboundDatagram datagram) {
    _dispatchQueue = _dispatchQueue.then((_) => _dispatch(datagram)).catchError(
      (Object error, StackTrace stack) {
        _record('dispatch', 'Dispatch error', <String, Object?>{
          'error': error.toString(),
        });
      },
    );
  }

  void _registerPrimerKey(String key) {
    _primerDedupTimers[key]?.cancel();
    _primerDedupTimers[key] = Timer(_primerDedupHold, () {
      _primerDedupTimers.remove(key);
    });
  }

  bool _shouldSkipPrimer(String? key) {
    if (key == null) return false;

    _primerDedupTimers.removeWhere((entryKey, timer) {
      final active = timer.isActive;
      if (!active) timer.cancel();
      return !active;
    });

    final existing = _primerDedupTimers[key];
    if (existing != null && existing.isActive) {
      return true;
    }
    return false;
  }

  bool _isDuplicateCueId(String cueId, DateTime now) {
    _recentCueIds.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _cueIdTtl,
    );

    if (_recentCueIds.containsKey(cueId)) {
      return true;
    }

    _recentCueIds[cueId] = now;
    while (_recentCueIds.length > _maxCueIdCacheSize) {
      _recentCueIds.remove(_recentCueIds.keys.first);
    }
    return false;
  }

  bool _validateEnvelope(
    _CueEnvelope envelope,
    _InboundDatagram datagram, {
    required bool requiresSlot,
  }) {
    if (envelope.protocolVersion != kConcertProtocolVersion) {
      _protocolMismatchCount += 1;
      _setCueRoutingIssue(
        'Protocol mismatch: expected v$kConcertProtocolVersion, got v${envelope.protocolVersion}',
      );
      _record(
        'protocol',
        'Dropped cue due to protocol mismatch',
        <String, Object?>{
          'expected': kConcertProtocolVersion,
          'received': envelope.protocolVersion,
          'cueId': envelope.cueId,
        },
      );
      return false;
    }

    final lockedSession = _lockedShowSessionId;
    if (lockedSession == null || lockedSession != envelope.showSessionId) {
      _setCueRoutingIssue(
        lockedSession == null
            ? 'Cue arrived before session lock completed'
            : 'Session mismatch: expected $lockedSession',
      );
      _record(
        'protocol',
        'Dropped cue due to showSessionId mismatch',
        <String, Object?>{
          'expected': lockedSession,
          'received': envelope.showSessionId,
          'cueId': envelope.cueId,
        },
      );
      return false;
    }

    if (requiresSlot && envelope.slot != client.myIndex.value) {
      _slotMismatchCount += 1;
      _setCueRoutingIssue(
        'Cue for slot ${envelope.slot}, phone is slot ${client.myIndex.value}',
      );
      _record('routing', 'Dropped cue due to slot mismatch', <String, Object?>{
        'address': datagram.message.address,
        'cueId': envelope.cueId,
        'cueSlot': envelope.slot,
        'currentSlot': client.myIndex.value,
      });
      return false;
    }

    final now = DateTime.now().toUtc();
    if (_isDuplicateCueId(envelope.cueId, now)) {
      _duplicatesDropped += 1;
      _record('dedupe', 'Dropped duplicate cue', <String, Object?>{
        'cueId': envelope.cueId,
        'seq': envelope.seq,
      });
      return false;
    }

    if (_lastProcessedSeq >= 0 && envelope.seq <= _lastProcessedSeq) {
      _outOfOrderDropped += 1;
      _record('ordering', 'Dropped out-of-order cue', <String, Object?>{
        'cueId': envelope.cueId,
        'seq': envelope.seq,
        'lastSeq': _lastProcessedSeq,
      });
      return false;
    }

    _lastProcessedSeq = envelope.seq;
    _lastAcceptedCueAddress = datagram.message.address;
    _lastAcceptedCueId = envelope.cueId;
    _markConductorHeartbeat();
    _setCueRoutingIssue(null);

    _record('cue', 'Accepted cue', <String, Object?>{
      'address': datagram.message.address,
      'cueId': envelope.cueId,
      'seq': envelope.seq,
    });
    return true;
  }

  Future<void> _playPrimer(
    String fileName,
    double gain, {
    bool sendAck = false,
    String? dedupeKey,
    String? cueId,
    int? seq,
  }) async {
    if (!kPrimerPlaybackEnabled) {
      _record('audio', 'Ignoring primer playback request', <String, Object?>{
        'file': fileName,
      });
      if (sendAck) {
        _sendAck(cueId: cueId, seq: seq);
      }
      return;
    }

    if (_shouldSkipPrimer(dedupeKey)) {
      _record('dedupe', 'Skipping duplicate primer request', <String, Object?>{
        'key': dedupeKey,
      });
      if (sendAck) {
        _sendAck(cueId: cueId, seq: seq);
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

      client.audioPlaying.value = true;
      _scheduleAudioPlayingReset(playbackToken, const Duration(seconds: 2));
    } catch (e) {
      _record('audio', 'Native playback failed', <String, Object?>{
        'error': e.toString(),
      });
      client.audioPlaying.value = false;
    }

    if (sendAck) {
      _sendAck(cueId: cueId, seq: seq);
    }
  }

  void _scheduleAudioPlayingReset(int playbackToken, Duration duration) {
    unawaited(
      Future<void>.delayed(duration, () {
        if (_playbackToken == playbackToken) {
          client.audioPlaying.value = false;
        }
      }),
    );
  }

  void _cancelLightSequence({bool turnOff = false, String? reason}) {
    _lightSequenceToken += 1;
    _lightSequenceTimer?.cancel();
    _lightSequenceTimer = null;
    _activeLightingSummary = null;
    _activeLightingPart = null;
    _activeLightingEventId = null;
    if (reason != null) {
      _record('lighting', 'Cancelled light sequence', <String, Object?>{
        'reason': reason,
      });
    }
    if (turnOff) {
      _lastAppliedLightLevel = -1.0;
      unawaited(_applyLightLevel(0.0, force: true));
    }
  }

  Future<void> _applyLightLevel(double level, {bool force = false}) async {
    final clamped = level.clamp(0.0, 1.0).toDouble();
    if (!force && (_lastAppliedLightLevel - clamped).abs() < 0.015) {
      return;
    }
    _lastAppliedLightLevel = clamped;
    client.brightness.value = clamped;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(clamped);
    } catch (_) {
      // best-effort
    }
    await _setTorchLevel(clamped);
  }

  void _startLightSequence(
    LightingAssignment assignment, {
    required int eventId,
    required int slot,
  }) {
    _cancelLightSequence(reason: 'starting Trigger #$eventId');
    _activeLightingSummary = assignment.summary;
    _activeLightingPart = assignment.label;
    _activeLightingEventId = eventId;
    final token = _lightSequenceToken;
    final start = DateTime.now();

    Future<void> tick({bool force = false}) async {
      if (token != _lightSequenceToken) {
        return;
      }
      final elapsedMs =
          DateTime.now().difference(start).inMilliseconds.toDouble();
      final level = interpolateLightLevel(assignment.keyframes, elapsedMs);
      await _applyLightLevel(level, force: force);
      if (elapsedMs >= assignment.durationMs) {
        _lightSequenceTimer?.cancel();
        _lightSequenceTimer = null;
        _activeLightingSummary = null;
        _activeLightingPart = null;
        _activeLightingEventId = null;
      }
    }

    _record('lighting', 'Starting light sequence', <String, Object?>{
      'eventId': eventId,
      'slot': slot,
      'part': assignment.label,
      'summary': assignment.summary,
      'durationMs': assignment.durationMs.round(),
      'peakLevel': assignment.peakLevel,
    });

    unawaited(tick(force: true));
    _lightSequenceTimer = Timer.periodic(_lightSequenceTick, (_) {
      unawaited(tick());
    });
  }

  Future<void> _playEventMedia({
    String? primerFile,
    String? electronicsAssetKey,
    double? electronicsDurationMs,
    bool sendAck = false,
    String? dedupeKey,
    String? cueId,
    int? seq,
  }) async {
    if (_shouldSkipPrimer(dedupeKey)) {
      _record(
        'dedupe',
        'Skipping duplicate event media request',
        <String, Object?>{'key': dedupeKey},
      );
      if (sendAck) {
        _sendAck(cueId: cueId, seq: seq);
      }
      return;
    }

    if (primerFile == null && electronicsAssetKey == null) {
      if (sendAck) {
        _sendAck(cueId: cueId, seq: seq);
      }
      return;
    }

    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);

      final playbackToken = ++_playbackToken;

      if (kPrimerPlaybackEnabled && primerFile != null) {
        await NativeAudio.playPrimerTone(primerFile, 1.0);
      }
      if (electronicsAssetKey != null) {
        await NativeAudio.playElectronicsClip(electronicsAssetKey, 1.0);
      }

      if (dedupeKey != null) {
        _registerPrimerKey(dedupeKey);
      }

      client.audioPlaying.value = true;
      final resetMs = (electronicsDurationMs ?? 2000.0).round().clamp(
        2000,
        45000,
      );
      _scheduleAudioPlayingReset(
        playbackToken,
        Duration(milliseconds: resetMs),
      );
    } catch (e) {
      _record('audio', 'Event media playback failed', <String, Object?>{
        'error': e.toString(),
        if (primerFile != null) 'primer': primerFile,
        if (electronicsAssetKey != null) 'electronics': electronicsAssetKey,
      });
      client.audioPlaying.value = false;
    }

    if (sendAck) {
      _sendAck(cueId: cueId, seq: seq);
    }
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _record('lifecycle', 'OSC listener starting');

    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      _record('audio', 'Failed to activate audio session', <String, Object?>{
        'error': e.toString(),
      });
    }

    try {
      await _scheduleRebind(reason: 'startup');
    } catch (e) {
      _running = false;
      rethrow;
    }

    _startConductorWatchdog();
    _restartHelloTimer(_fastHelloInterval);
    _sendHello();
    _record('lifecycle', 'Listening on 0.0.0.0:$_oscPort');
  }

  OSCMessage? _parseMessage(Uint8List data) {
    int idx = 0;
    final zero = data.indexOf(0, idx);
    if (zero == -1) return null;

    final address = utf8.decode(data.sublist(0, zero));
    idx = (zero + 4) & ~3;
    if (idx >= data.length || data[idx] != 44) return null;

    final tagEnd = data.indexOf(0, idx);
    if (tagEnd == -1) return null;

    final tags = utf8.decode(data.sublist(idx + 1, tagEnd));
    idx = (tagEnd + 4) & ~3;

    final args = <Object>[];
    final byteData = ByteData.sublistView(data);
    for (final tag in tags.split('')) {
      switch (tag) {
        case 'i':
          if (idx + 4 > data.length) return null;
          args.add(byteData.getInt32(idx, Endian.big));
          idx += 4;
          break;
        case 'h':
          if (idx + 8 > data.length) return null;
          args.add(byteData.getInt64(idx, Endian.big));
          idx += 8;
          break;
        case 'f':
          if (idx + 4 > data.length) return null;
          args.add(byteData.getFloat32(idx, Endian.big));
          idx += 4;
          break;
        case 'd':
          if (idx + 8 > data.length) return null;
          args.add(byteData.getFloat64(idx, Endian.big));
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
          final hi = byteData.getUint32(idx, Endian.big);
          final lo = byteData.getUint32(idx + 4, Endian.big);
          args.add((BigInt.from(hi) << 32) | BigInt.from(lo));
          idx += 8;
          break;
        default:
          return null;
      }
    }

    return OSCMessage(address, arguments: List<Object>.from(args));
  }

  Future<void> _setTorchLevel(double level) async {
    try {
      await _torchChannel.invokeMethod('setTorchLevel', level);
      client.flashOn.value = level > 0;
    } on MissingPluginException {
      if (level > 0) {
        await TorchLight.enableTorch();
        client.flashOn.value = true;
      } else {
        await TorchLight.disableTorch();
        client.flashOn.value = false;
      }
    } catch (e) {
      _record('torch', 'Torch command failed', <String, Object?>{
        'error': e.toString(),
      });
      client.flashOn.value = false;
    }
  }

  Future<void> setTorchLevel(double level) async {
    _cancelLightSequence(reason: 'manual torch control');
    await _applyLightLevel(level, force: true);
  }

  bool _tryHandleConductorHello(_InboundDatagram datagram) {
    final message = datagram.message;
    if (message.address != '/hello') return false;

    final args = message.arguments;
    if (args.length < 3) return false;
    if (args[0] != 'conductor') return false;

    final protocol = args[1];
    final showSessionId = args[2];
    if (protocol is! int || showSessionId is! String || showSessionId.isEmpty) {
      return false;
    }

    if (protocol != kConcertProtocolVersion) {
      _protocolMismatchCount += 1;
      _record(
        'protocol',
        'Ignored conductor hello due to protocol mismatch',
        <String, Object?>{
          'expected': kConcertProtocolVersion,
          'received': protocol,
          'ip': datagram.address.address,
        },
      );
      return true;
    }

    final trusted = _trustedConductorAddress;
    final trustedPort = _trustedConductorPort;
    final isCurrentTrusted =
        trusted != null &&
        trustedPort != null &&
        trusted.address == datagram.address.address &&
        trustedPort == datagram.port;

    if (trusted == null || trustedPort == null) {
      _lockConductor(datagram.address, datagram.port, showSessionId);
      _sendHello();
      return true;
    }

    if (!isCurrentTrusted) {
      _recordUnknownSender(
        datagram,
        'different conductor endpoint while locked',
      );
      return true;
    }

    if (_lockedShowSessionId != showSessionId) {
      _record(
        'pairing',
        'Trusted conductor started new session; relocking',
        <String, Object?>{
          'oldSessionId': _lockedShowSessionId,
          'newSessionId': showSessionId,
        },
      );
      _lockConductor(datagram.address, datagram.port, showSessionId);
    } else {
      _markConductorHeartbeat();
    }

    return true;
  }

  Future<void> _dispatch(_InboundDatagram datagram) async {
    final message = datagram.message;

    final updatedMessages = List<OSCMessage>.from(client.recentMessages.value)
      ..add(message);
    if (updatedMessages.length > 20) {
      updatedMessages.removeRange(0, updatedMessages.length - 20);
    }
    client.recentMessages.value = updatedMessages;

    if (_tryHandleConductorHello(datagram)) {
      return;
    }

    final trustedSender = _isTrustedSender(datagram);
    if (!trustedSender) {
      _recordUnknownSender(datagram, 'sender is not trusted conductor');
      return;
    }

    if (message.address == '/discover' || message.address == '/ping') {
      _markConductorHeartbeat();
      _sendHello();
      return;
    }

    if (message.address == '/sync') {
      _markConductorHeartbeat();
      if (client.clockOffsetMs.value != 0) {
        client.clockOffsetMs.value = 0;
      }
      return;
    }

    if (message.address == OscAddress.panicAllStop.value) {
      final envelope = _CueEnvelope.fromOsc(message);
      if (envelope != null) {
        if (!_validateEnvelope(envelope, datagram, requiresSlot: false)) {
          return;
        }
        _sendAck(cueId: envelope.cueId, seq: envelope.seq);
      } else {
        _markConductorHeartbeat();
      }

      _cancelLightSequence(turnOff: false, reason: 'panic/all-stop');
      await _setTorchLevel(0);
      client.brightness.value = 0;
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(0);
      } catch (_) {
        // best-effort
      }
      _playbackToken++;
      try {
        await NativeAudio.stopPrimerTone();
      } catch (_) {
        // best-effort
      }
      client.audioPlaying.value = false;
      return;
    }

    switch (message.address) {
      case '/flash/on':
        await _handleFlashOn(datagram);
        break;
      case '/flash/off':
        await _handleFlashOff(datagram);
        break;
      case '/event/trigger':
        await _handleEventTrigger(datagram);
        break;
      case '/audio/play':
        await _handleAudioPlay(datagram);
        break;
      case '/audio/stop':
        await _handleAudioStop(datagram);
        break;
      case '/set-slot':
        await _handleSetSlot(datagram);
        break;
      case '/mic/record':
        await _handleMicRecord(datagram);
        break;
      default:
        _record('dispatch', 'Ignored unsupported address', <String, Object?>{
          'address': message.address,
        });
        break;
    }
  }

  Future<void> _handleFlashOn(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }
    if (envelope.payload.isEmpty || envelope.payload[0] is! num) {
      return;
    }

    final intensity = (envelope.payload[0] as num).toDouble();
    try {
      _cancelLightSequence(reason: 'direct /flash/on');
      final clamped = intensity.clamp(0.0, 1.0).toDouble();
      await _applyLightLevel(clamped, force: true);
      _sendAck(cueId: envelope.cueId, seq: envelope.seq);
    } catch (e) {
      _record('torch', 'Torch cue failed', <String, Object?>{
        'error': e.toString(),
      });
      client.flashOn.value = false;
    }
  }

  Future<void> _handleFlashOff(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }

    try {
      _cancelLightSequence(reason: 'direct /flash/off');
      await _applyLightLevel(0.0, force: true);
      _sendAck(cueId: envelope.cueId, seq: envelope.seq);
    } catch (e) {
      _record('torch', 'Torch off cue failed', <String, Object?>{
        'error': e.toString(),
      });
      client.flashOn.value = true;
    }
  }

  Future<void> _handleEventTrigger(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }

    if (envelope.payload.isEmpty || envelope.payload[0] is! int) {
      return;
    }

    final eventId = envelope.payload[0] as int;
    double? startAtMs;
    if (envelope.payload.length >= 2 && envelope.payload[1] is num) {
      startAtMs = (envelope.payload[1] as num).toDouble();
    }

    await client.ensureEventRecipesLoaded();
    final events = client.eventRecipes.value;

    EventRecipe? event;
    for (final candidate in events) {
      if (candidate.id == eventId) {
        event = candidate;
        break;
      }
    }

    if (event == null) {
      _record('event', 'Unknown event ID', <String, Object?>{
        'eventId': eventId,
      });
      return;
    }

    final slot = client.myIndex.value;
    final primerAssignment =
        kPrimerPlaybackEnabled ? client.assignmentForSlot(event, slot) : null;
    final electronicsAssignment = client.electronicsForSlot(event, slot);
    final lightingAssignment = client.lightingForSlot(event, slot);
    if (primerAssignment == null &&
        electronicsAssignment == null &&
        lightingAssignment == null) {
      _record('event', 'No event media for slot', <String, Object?>{
        'eventId': eventId,
        'slot': slot,
      });
      return;
    }

    _record('event', 'Resolved event media', <String, Object?>{
      'eventId': eventId,
      'slot': slot,
      if (primerAssignment != null) 'primer': primerAssignment.sample,
      if (electronicsAssignment != null)
        'electronics': electronicsAssignment.sample,
      if (lightingAssignment != null) 'lighting': lightingAssignment.summary,
    });

    final delay = playbackDelayForStartAtMs(startAtMs);
    final dedupeKey = 'event:$eventId:slot=$slot';

    unawaited(
      Future<void>.delayed(delay, () async {
        if (lightingAssignment != null) {
          _startLightSequence(lightingAssignment, eventId: eventId, slot: slot);
        }
        await _playEventMedia(
          primerFile: primerAssignment?.sample,
          electronicsAssetKey: electronicsAssignment?.sample,
          electronicsDurationMs: electronicsAssignment?.durationMs,
          sendAck: true,
          dedupeKey: dedupeKey,
          cueId: envelope.cueId,
          seq: envelope.seq,
        );
      }),
    );
  }

  Future<void> _handleAudioPlay(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }

    if (envelope.payload.length < 2) {
      return;
    }

    final file = envelope.payload[0];
    final gain = envelope.payload[1];
    if (file is! String || gain is! num) {
      return;
    }

    double? startAtMs;
    if (envelope.payload.length >= 3 && envelope.payload[2] is num) {
      startAtMs = (envelope.payload[2] as num).toDouble();
    }

    final delay = playbackDelayForStartAtMs(startAtMs);
    final primerFile = resolvePrimerAudioPlayFile(file);
    final bundledAssetKey =
        primerFile == null ? resolveBundledAudioPlayAssetKey(file) : null;

    if (primerFile != null && !kPrimerPlaybackEnabled) {
      _record('audio', 'Ignoring direct primer cue', <String, Object?>{
        'file': file,
        'slot': envelope.slot,
      });
      _sendAck(cueId: envelope.cueId, seq: envelope.seq);
      return;
    }

    if (primerFile == null && bundledAssetKey == null) {
      _record('audio', 'Unsupported /audio/play request', <String, Object?>{
        'file': file,
        'slot': envelope.slot,
      });
      _sendAck(cueId: envelope.cueId, seq: envelope.seq);
      return;
    }

    unawaited(
      Future<void>.delayed(delay, () async {
        if (primerFile != null) {
          await _playPrimer(
            primerFile,
            gain.toDouble(),
            sendAck: true,
            cueId: envelope.cueId,
            seq: envelope.seq,
          );
          return;
        }

        await _playEventMedia(
          electronicsAssetKey: bundledAssetKey,
          sendAck: true,
          cueId: envelope.cueId,
          seq: envelope.seq,
        );
      }),
    );
  }

  Future<void> _handleAudioStop(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }

    _playbackToken++;
    _cancelLightSequence(turnOff: true, reason: 'audio/stop');
    try {
      await NativeAudio.stopPrimerTone();
    } catch (e) {
      _record('audio', 'Native stop failed', <String, Object?>{
        'error': e.toString(),
      });
    }
    client.audioPlaying.value = false;
    _sendAck(cueId: envelope.cueId, seq: envelope.seq);
  }

  Future<void> _handleSetSlot(_InboundDatagram datagram) async {
    final args = datagram.message.arguments;
    if (args.isEmpty || args[0] is! int) {
      return;
    }

    final newSlot = args[0] as int;
    if (newSlot != client.myIndex.value) {
      client.myIndex.value = newSlot;
      _setCueRoutingIssue(null);
      _record('slot', 'Updated listening slot', <String, Object?>{
        'slot': newSlot,
      });
      _sendAck();
      _sendHello();
    }
  }

  Future<void> _handleMicRecord(_InboundDatagram datagram) async {
    final envelope = _CueEnvelope.fromOsc(datagram.message);
    if (envelope == null) {
      return;
    }
    if (!_validateEnvelope(envelope, datagram, requiresSlot: true)) {
      return;
    }

    if (envelope.payload.isEmpty || envelope.payload[0] is! num) {
      return;
    }

    final durationSec = (envelope.payload[0] as num).toDouble();
    if (!kEnableMic) {
      _record('mic', 'Mic disabled (stub)');
      _sendAck(cueId: envelope.cueId, seq: envelope.seq);
      return;
    }

    final audioStream = _mic.start(sampleRate: 44100);
    await _micSubscription?.cancel();
    _micSubscription = audioStream.listen((_) {});
    client.recording.value = true;

    Timer(Duration(milliseconds: (durationSec * 1000).toInt()), () async {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _mic.stop();
      client.recording.value = false;
    });

    _sendAck(cueId: envelope.cueId, seq: envelope.seq);
  }

  Future<void> playLocalPrimer(String fileName, double gain) async {
    await _playPrimer(fileName, gain, sendAck: false);
  }

  Future<void> playLocalLightingPreview(
    LightingAssignment assignment, {
    required int eventId,
  }) async {
    _startLightSequence(
      assignment,
      eventId: eventId,
      slot: client.myIndex.value,
    );
  }

  Future<void> playLocalElectronicsPreview(
    String assetKey, {
    double? durationMs,
  }) async {
    await _playEventMedia(
      electronicsAssetKey: assetKey,
      electronicsDurationMs: durationMs,
      sendAck: false,
    );
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
    final socket = _socket;
    if (socket == null) return;

    final msg = OSCMessage(
      '/hello',
      arguments: <Object>[
        client.myIndex.value,
        client.deviceId.value,
        kConcertProtocolVersion,
        _lockedShowSessionId ?? '',
      ],
    );

    final conductor = _trustedConductorAddress;
    final conductorPort = _trustedConductorPort;
    if (conductor != null && conductorPort != null) {
      _sendBestEffort(
        msg,
        destination: conductor,
        port: conductorPort,
        category: 'hello',
      );
      _record('hello', 'Sent /hello to trusted conductor', <String, Object?>{
        'ip': conductor.address,
        'port': conductorPort,
      });
      return;
    }

    _sendBestEffort(msg, category: 'hello');
    _record('hello', 'Broadcasting /hello while unpaired');
  }

  void _sendAck({String? cueId, int? seq}) {
    final msg = OSCMessage(
      '/ack',
      arguments: <Object>[
        client.myIndex.value,
        client.deviceId.value,
        cueId ?? '',
        seq ?? -1,
        _lockedShowSessionId ?? '',
        kConcertProtocolVersion,
      ],
    );

    final conductor = _trustedConductorAddress;
    final conductorPort = _trustedConductorPort;
    if (conductor != null && conductorPort != null) {
      _sendBestEffort(
        msg,
        destination: conductor,
        port: conductorPort,
        category: 'ack',
      );
    } else {
      _sendBestEffort(msg, category: 'ack');
    }
  }

  void sendCustom(String address, List<Object> args) {
    final msg = OSCMessage(address, arguments: args);
    final conductor = _trustedConductorAddress;
    final conductorPort = _trustedConductorPort;

    if (conductor != null && conductorPort != null) {
      _sendBestEffort(
        msg,
        destination: conductor,
        port: conductorPort,
        category: 'custom',
      );
      return;
    }

    _sendBestEffort(msg, category: 'custom');
  }

  Future<void> refreshConnection() async {
    if (!_running) {
      await start();
      return;
    }

    _record('manual', 'Manual refresh requested');
    _unlockConductor(reason: 'manual refresh');
    await _scheduleRebind(reason: 'manual refresh');
    _sendHello();
  }

  Future<void> announcePresence() async {
    if (!_running) {
      await start();
      return;
    }
    _sendHello();
  }

  void send(OscCodable message) {
    final osc = message.toOsc();
    final conductor = _trustedConductorAddress;
    final conductorPort = _trustedConductorPort;

    if (conductor != null && conductorPort != null) {
      _sendBestEffort(
        osc,
        destination: conductor,
        port: conductorPort,
        category: 'typed-send',
      );
      return;
    }

    _sendBestEffort(osc, category: 'typed-send');
  }

  Map<String, Object?> networkDiagnosticsSnapshot() {
    return <String, Object?>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'trustedConductorIp': _trustedConductorAddress?.address,
      'trustedConductorPort': _trustedConductorPort,
      'showSessionId': _lockedShowSessionId,
      'protocolVersion': kConcertProtocolVersion,
      'unknownSenderCount': _unknownSenderCount,
      'protocolMismatchCount': _protocolMismatchCount,
      'slotMismatchCount': _slotMismatchCount,
      'duplicatesDropped': _duplicatesDropped,
      'outOfOrderDropped': _outOfOrderDropped,
      'lastProcessedSeq': _lastProcessedSeq,
      'currentSlot': client.myIndex.value,
      'cueRoutingIssue': client.cueRoutingIssue.value,
      'lastAcceptedCueAddress': _lastAcceptedCueAddress,
      'lastAcceptedCueId': _lastAcceptedCueId,
      'activeLightingEventId': _activeLightingEventId,
      'activeLightingPart': _activeLightingPart,
      'activeLightingSummary': _activeLightingSummary,
      'helloIntervalSeconds': _currentHelloInterval.inSeconds,
      'events': _eventLog.map((e) => e.toJson()).toList(growable: false),
    };
  }

  String exportNetworkLogJson() {
    return jsonEncode(networkDiagnosticsSnapshot());
  }

  Future<void> stop() async {
    await _recvSubscription?.cancel();
    _recvSubscription = null;

    _socket?.close();
    _socket = null;
    _recvSocket?.close();
    _recvSocket = null;

    await _micSubscription?.cancel();
    _micSubscription = null;
    client.recording.value = false;

    try {
      await NativeAudio.stopPrimerTone();
    } catch (_) {
      // best-effort
    }
    _cancelLightSequence(turnOff: false, reason: 'listener stop');
    _lastAppliedLightLevel = -1.0;
    client.audioPlaying.value = false;
    _running = false;

    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
      client.brightness.value = 0;
    } catch (_) {
      // best-effort
    }

    _disconnectTimer?.cancel();
    _helloTimer?.cancel();
    _conductorWatchdog?.cancel();
    _unlockConductor(reason: 'listener stopped');

    _record('lifecycle', 'Listener stopped');
  }
}
