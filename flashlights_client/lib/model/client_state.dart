import 'package:flutter/foundation.dart';

/// Global client state, holds the dynamic slot and clock offset.
class ClientState {
  ClientState()
      : myIndex = ValueNotifier<int>(
            const int.fromEnvironment('SLOT', defaultValue: 1)),
        clockOffsetMs = 0.0;

  /// Singer slot (1-32). Notifier so UI can react to changes at runtime.
  final ValueNotifier<int> myIndex;
  /// Rolling average clock offset from /sync (ms).
  double clockOffsetMs;
}

/// Singleton client state
final client = ClientState();