import 'package:flutter/foundation.dart';

/// Global client state, holds the dynamic slot and clock offset.
class ClientState {
  ClientState()
    : myIndex = ValueNotifier<int>(
        const int.fromEnvironment('SLOT', defaultValue: 1),
      ),
      clockOffsetMs = 0.0,
      flashOn = ValueNotifier<bool>(false),
      audioPlaying = ValueNotifier<bool>(false),
      recording = ValueNotifier<bool>(false);

  /// Singer slot (uses the real slot number). Notifier so UI can react to changes at runtime.
  final ValueNotifier<int> myIndex;

  /// Rolling average clock offset from /sync (ms).
  double clockOffsetMs;

  /// Whether the flashlight is currently on.
  final ValueNotifier<bool> flashOn;

  /// Whether audio is currently playing.
  final ValueNotifier<bool> audioPlaying;

  /// Whether the microphone is currently recording.
  final ValueNotifier<bool> recording;

  /// Whether the client is connected to the server.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
}

/// Singleton client state
final client = ClientState();
