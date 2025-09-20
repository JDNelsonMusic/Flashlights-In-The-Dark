import 'dart:async';

/// Simple microphone abstraction so the app compiles without the plugin.
abstract class MicInput {
  /// Start capturing mono PCM16 at 44.1kHz; returns a stream of byte chunks.
  Stream<List<int>> start({int sampleRate = 44100});

  /// Stop capture and close the stream.
  Future<void> stop();
}

/// No-op implementation used when mic plugin is unavailable.
class MicInputStub implements MicInput {
  StreamController<List<int>>? _ctrl;

  @override
  Stream<List<int>> start({int sampleRate = 44100}) {
    _ctrl?.close();
    _ctrl = StreamController<List<int>>.broadcast();
    // No data emitted; acts as a placeholder.
    return _ctrl!.stream;
  }

  @override
  Future<void> stop() async {
    await _ctrl?.close();
    _ctrl = null;
  }
}
