class ClientState {
  ClientState();
  /// Singer slot (1-32). Injected at build time:
  ///     flutter run --dart-define=SLOT=<N>
  /// Falls back to 1 so the app still runs on simulators.
  int myIndex = const int.fromEnvironment('SLOT', defaultValue: 1);
  double clockOffsetMs = 0.0;  // rolling average from /sync
}

final client = ClientState();