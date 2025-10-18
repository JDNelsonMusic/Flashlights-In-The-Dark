import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:flashlights_client/model/event_recipe.dart';
import 'package:flashlights_client/utils/music_xml_utils.dart';

class EventPracticeOSMD extends StatefulWidget {
  const EventPracticeOSMD({super.key});

  @override
  EventPracticeOSMDState createState() => EventPracticeOSMDState();
}

class EventPracticeOSMDState extends State<EventPracticeOSMD> {
  static const int _kInitChunkThreshold = 60000;
  static const int _kInitChunkSize = 24000;

  WebViewController? _controller;
  bool _controllerReady = false;
  bool _initialised = false;
  bool _applyingContext = false;
  bool _contextUpdateQueued = false;
  String? _error;
  String? _lastInitXml;
  int _initSequence = 0;
  int _contextSequence = 0;
  String? _currentNoteLabel;
  int? _currentMeasure;

  PrimerColor? _currentColor;
  PrimerColor? _pendingColor;
  int? _pendingMeasure;
  String? _pendingNote;
  String? _pendingHighlightSignature;
  String? _currentHighlightSignature;
  int _windowRenderedLogCount = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final controller =
          WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0x00000000))
            ..enableZoom(false);

      controller.addJavaScriptChannel(
        'FlutterOSMD',
        onMessageReceived: (message) {
          final raw = message.message;
          dynamic decoded;
          try {
            decoded = jsonDecode(raw);
          } catch (_) {
            decoded = raw;
          }

          void markReady() {
            if (!mounted) {
              return;
            }
            setState(() {
              _initialised = true;
              _error = null;
            });
            _flushPendingWindow();
          }

          void logVerbose(String text) {
            if (kDebugMode) {
              debugPrint(text);
            }
          }

          if (decoded is String && decoded == 'ready') {
            logVerbose('[EventPracticeOSMD][JS] $decoded');
            markReady();
            return;
          }

          if (decoded is Map<String, dynamic>) {
            final type = decoded['type'];
            if (type == 'window-rendered') {
              _windowRenderedLogCount += 1;
              if (kDebugMode) {
                if (_windowRenderedLogCount <= 3) {
                  debugPrint('[EventPracticeOSMD][JS] $raw');
                } else if (_windowRenderedLogCount == 4) {
                  debugPrint(
                    '[EventPracticeOSMD][JS] window-rendered continuing; suppressing further logs',
                  );
                }
              }
              markReady();
              return;
            }
            if (type == 'error') {
              final detail = decoded['detail'] ?? decoded['message'];
              final detailText = detail == null ? 'unknown' : detail.toString();
              debugPrint('[EventPracticeOSMD][JS][error] $detailText');
              if (mounted) {
                setState(() {
                  _error = detailText;
                  _initialised = false;
                });
              }
              return;
            }
            logVerbose('[EventPracticeOSMD][JS] $raw');
            return;
          }

          logVerbose('[EventPracticeOSMD][JS] $raw');
        },
      );

      final pageLoaded = Completer<void>();
      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageLoaded.isCompleted) {
              pageLoaded.complete();
            }
          },
          onWebResourceError: (error) {
            debugPrint('[EventPracticeOSMD] web error: ${error.description}');
            if (mounted) {
              setState(() {
                _error = error.description;
                _initialised = false;
              });
            }
          },
        ),
      );

      await controller.loadFlutterAsset('assets/osmd_view.html');
      try {
        await pageLoaded.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        debugPrint('[EventPracticeOSMD] page load timed out; continuing');
      }

      _controller = controller;
      _controllerReady = true;
      await _applyPendingContext();
    } catch (error, stackTrace) {
      debugPrint('[EventPracticeOSMD] init failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _initialised = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> updatePracticeContext({
    PrimerColor? color,
    int? measure,
    String? note,
  }) async {
    _pendingColor = color;
    if (measure != null) {
      _pendingMeasure = measure;
    }
    if (note != null) {
      final trimmed = note.trim();
      _pendingNote = trimmed.isEmpty ? null : trimmed;
    } else {
      _pendingNote = null;
    }
    _pendingHighlightSignature = _composeHighlightSignature(
      _pendingMeasure,
      _pendingNote,
    );
    await _applyPendingContext();
  }

  Future<void> clearScore({String? message}) async {
    _pendingColor = null;
    _currentColor = null;
    _pendingMeasure = null;
    _pendingNote = null;
    _pendingHighlightSignature = null;
    _currentHighlightSignature = null;
    _windowRenderedLogCount = 0;
    _lastInitXml = null;
    _currentNoteLabel = null;
    _currentMeasure = null;
    if (mounted) {
      setState(() {
        _initialised = false;
        _error = message ?? 'No music assigned to your slot yet';
      });
    }
  }

  Future<void> _applyPendingContext() async {
    if (!_controllerReady) {
      return;
    }
    if (_applyingContext) {
      if (!_contextUpdateQueued) {
        _contextUpdateQueued = true;
        scheduleMicrotask(() {
          _contextUpdateQueued = false;
          _applyPendingContext();
        });
      }
      return;
    }
    final color = _pendingColor;
    final measure = _pendingMeasure;
    final note = _pendingNote;
    final highlightSignature = _pendingHighlightSignature;
    if (color == null) {
      _pendingHighlightSignature = null;
      _currentHighlightSignature = null;
      _pendingNote = null;
      if (mounted) {
        setState(() {
          _initialised = false;
          _error = 'Select a slot to view the score';
        });
      }
      return;
    }

    final contextSeq = ++_contextSequence;
    _applyingContext = true;
    try {
      final needsBase = _currentColor != color || _lastInitXml == null;
      if (needsBase) {
        final xml = await loadBaseTrimmedMusicXML(forColor: color);
        _initialised = false;
        await _sendBaseInit(xml, contextSeq: contextSeq);
        _currentColor = color;
        _currentHighlightSignature = null;
        _currentNoteLabel = null;
        _currentMeasure = null;
      }

      final highlightChanged =
          needsBase || !_initialised || _currentHighlightSignature != highlightSignature;

      if (highlightChanged) {
        await _sendHighlight(
          contextSeq: contextSeq,
          measure: measure,
          note: note,
        );
        _currentHighlightSignature = highlightSignature;
        _currentNoteLabel = note;
        _currentMeasure = measure;
      } else if (_initialised) {
        _flushPendingWindow();
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        '[EventPracticeOSMD] context apply failed: $error\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _initialised = false;
          _error = error.toString();
        });
      }
    } finally {
      _applyingContext = false;
    }
  }

  String? _composeHighlightSignature(int? measure, String? note) {
    if (measure == null) {
      return null;
    }
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return '$measure|${trimmed.toUpperCase()}';
  }

  void _flushPendingWindow() {
    final measure = _pendingMeasure;
    if (!_initialised || measure == null) {
      return;
    }
    setMeasure(measure);
  }

  Future<void> _sendPayload(Map<String, dynamic> message) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final payload = jsonEncode(message);
    final script = '''
      (function() {
        const message = $payload;
        try {
          if (typeof window.handleFlutterMessage === "function") {
            window.handleFlutterMessage({ data: message });
          } else if (typeof window.postMessage === "function") {
            window.postMessage(message, "*");
          }
        } catch (error) {
          console.error("Flutter->OSMD postMessage failed", error);
        }
      })();
    ''';
    await controller.runJavaScript(script);
  }

  Future<void> _sendBaseInit(
    String xml, {
    required int contextSeq,
  }) async {
    _windowRenderedLogCount = 0;
    _lastInitXml = xml;
    if (xml.length <= _kInitChunkThreshold) {
      await _sendPayload({'type': 'init', 'xml': xml, 'context': contextSeq});
      return;
    }
    await _sendChunkedInit(
      xml,
      contextSeq: contextSeq,
    );
  }

  Future<void> _sendChunkedInit(
    String xml, {
    required int contextSeq,
  }) async {
    final id = (++_initSequence).toString();
    await _sendPayload({'type': 'init-reset', 'id': id, 'context': contextSeq});
    final totalChunks = (xml.length / _kInitChunkSize).ceil();
    for (var index = 0; index < totalChunks; index += 1) {
      final start = index * _kInitChunkSize;
      final end = math.min(xml.length, start + _kInitChunkSize);
      final chunk = xml.substring(start, end);
      await _sendPayload({
        'type': 'init-chunk',
        'id': id,
        'index': index,
        'total': totalChunks,
        'chunk': chunk,
        'context': contextSeq,
      });
    }
    await _sendPayload({'type': 'init-chunk-final', 'id': id, 'context': contextSeq});
  }

  Future<void> _sendHighlight({
    required int contextSeq,
    int? measure,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'type': 'highlight',
      'context': contextSeq,
    };
    if (measure != null && measure > 0) {
      payload['measure'] = measure;
    }
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      payload['note'] = trimmedNote;
    }
    _windowRenderedLogCount = 0;
    _initialised = false;
    await _sendPayload(payload);
  }

  void setMeasure(int measureNumber) {
    if (measureNumber <= 0) {
      return;
    }
    _pendingMeasure = measureNumber;
    unawaited(_sendPayload({'type': 'window', 'measure': measureNumber}));
  }

  Future<void> reload() async {
    final xml = _lastInitXml;
    if (xml == null) {
      return;
    }
    final measure = _pendingMeasure ?? _currentMeasure;
    final note = _currentNoteLabel;
    final contextSeq = ++_contextSequence;
    await _sendBaseInit(xml, contextSeq: contextSeq);
    await _sendHighlight(
      contextSeq: contextSeq,
      measure: measure,
      note: note,
    );
    _currentHighlightSignature = _composeHighlightSignature(measure, note);
    _currentNoteLabel = note;
    _currentMeasure = measure;
    if (measure != null) {
      setMeasure(measure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: WebViewWidget(controller: controller),
        ),
        if (!_initialised)
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black54),
              child: Center(
                child:
                    _error != null
                        ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Score unavailable\n\n${_error!}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.redAccent.shade100,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        : const SizedBox.square(
                          dimension: 32,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
              ),
            ),
          ),
      ],
    );
  }
}
