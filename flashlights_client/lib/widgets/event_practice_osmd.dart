import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:flashlights_client/model/event_recipe.dart';
import 'package:flashlights_client/utils/music_xml_utils.dart';

class EventPracticeOSMD extends StatefulWidget {
  const EventPracticeOSMD({super.key});

  @override
  EventPracticeOSMDState createState() => EventPracticeOSMDState();
}

class EventPracticeOSMDState extends State<EventPracticeOSMD> {
  WebViewController? _controller;
  bool _controllerReady = false;
  bool _initialised = false;
  bool _applyingContext = false;
  bool _contextUpdateQueued = false;
  String? _error;
  Map<String, dynamic>? _lastInitMessage;

  PrimerColor? _currentColor;
  PrimerColor? _pendingColor;
  int? _pendingMeasure;
  String? _pendingNote;
  String? _currentContextKey;
  String? _svgMarkup;

  void _markReady() {
    debugPrint('[EventPracticeOSMD] markReady()');
    if (!mounted) {
      return;
    }
    setState(() {
      _initialised = true;
      _error = null;
    });
  }

  String _sanitizeSvgMarkup(String raw) {
    var output = raw.trim();
    if (!output.startsWith('<svg')) {
      return output;
    }
    if (!output.contains('xmlns=')) {
      output = output.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }
    if (!output.contains('xmlns:xlink')) {
      output = output.replaceFirst(
        '<svg',
        '<svg xmlns:xlink="http://www.w3.org/1999/xlink"',
      );
    }
    if (!output.startsWith('<?xml')) {
      output = '<?xml version="1.0" encoding="UTF-8"?>' + output;
    }
    return output;
  }

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
            ..enableZoom(false);

      try {
        controller.setBackgroundColor(const Color(0x00000000));
      } on UnimplementedError catch (error, stackTrace) {
        debugPrint(
          '[EventPracticeOSMD] transparent background unsupported: $error\n$stackTrace',
        );
      }

      controller.addJavaScriptChannel(
        'FlutterOSMD',
        onMessageReceived: (message) {
          dynamic decoded;
          try {
            decoded = jsonDecode(message.message);
          } catch (_) {
            decoded = message.message;
          }

          if (decoded is String) {
            if (decoded == 'ready') {
              _markReady();
            }
            return;
          }

          if (decoded is Map<String, dynamic>) {
            final type = decoded['type'];
            if (type == 'rendered') {
              final svg = decoded['svg'];
              if (svg is String && svg.isNotEmpty) {
                final previewLength = svg.length > 120 ? 120 : svg.length;
                final preview = svg.substring(0, previewLength);
                debugPrint(
                  '[EventPracticeOSMD] received svg snippet len=${svg.length} preview=$preview',
                );
                final sanitized = _sanitizeSvgMarkup(svg);
                setState(() {
                  _svgMarkup = sanitized;
                });
              }
              _markReady();
              return;
            }
            if (type == 'error') {
              final detail = decoded['detail'] ?? decoded['message'];
              final detailText = detail == null ? 'unknown' : detail.toString();
              debugPrint('[EventPracticeOSMD][JS][error] $detailText');
              if (mounted) {
                setState(() {
                  _initialised = false;
                  _error = detailText;
                });
              }
            } else if (type == 'log') {
              final logMessage = decoded['message'];
              if (logMessage != null) {
                debugPrint('[EventPracticeOSMD][JS] $logMessage');
              }
            }
          }
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
            debugPrint(
              '[EventPracticeOSMD] web error: code=${error.errorCode} type=${error.errorType} description=${error.description}',
            );
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
    debugPrint(
      '[EventPracticeOSMD] updatePracticeContext color=${color?.name ?? 'null'} measure=${measure ?? 'null'} note=${note ?? 'null'}',
    );
    _pendingColor = color;
    _pendingMeasure = measure;
    if (note != null) {
      final trimmed = note.trim();
      _pendingNote = trimmed.isEmpty ? null : trimmed;
    } else {
      _pendingNote = null;
    }
    await _applyPendingContext();
  }

  Future<void> clearScore({String? message}) async {
    _pendingColor = null;
    _currentColor = null;
    _pendingMeasure = null;
    _pendingNote = null;
    _currentContextKey = null;
    _svgMarkup = null;
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
    final contextKey = _composeContextKey(measure, note);

    if (color == null) {
      _currentContextKey = null;
      _svgMarkup = null;
      if (mounted) {
        setState(() {
          _initialised = false;
          _error = 'Select a slot to view the score';
        });
      }
      return;
    }

    if (measure == null || measure <= 0) {
      _currentContextKey = null;
      _svgMarkup = null;
      if (mounted) {
        setState(() {
          _initialised = false;
          _error = 'Score unavailable for this event';
        });
      }
      return;
    }

    _applyingContext = true;
    try {
      if (_currentColor != color ||
          _currentContextKey != contextKey ||
          !_initialised) {
        final trimmed = await loadTrimmedMusicXML(
          forColor: color,
          highlightMeasure: measure,
          highlightNote: note,
        );
        debugPrint(
          '[EventPracticeOSMD] sending init payload ${trimmed.windowStart}-${trimmed.windowEnd}',
        );
        if (mounted) {
          setState(() {
            _initialised = false;
            _error = null;
            _svgMarkup = null;
          });
        } else {
          _initialised = false;
          _error = null;
          _svgMarkup = null;
        }
        await _sendInit(trimmed);
        _currentColor = color;
        _currentContextKey = contextKey;
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
      } else {
        _initialised = false;
        _error = error.toString();
      }
    } finally {
      _applyingContext = false;
    }
  }

  String _composeContextKey(int? measure, String? note) {
    final measurePart = measure == null ? 'null' : measure.toString();
    final notePart = note == null ? '' : note.trim().toUpperCase();
    return '$measurePart|$notePart';
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

  Future<void> _sendInit(TrimmedMusicXmlResult payload) async {
    final message = {
      'type': 'init',
      'xml': payload.xml,
      'meta': payload.toMetaJson(),
    };
    _lastInitMessage = Map<String, dynamic>.from(message);
    await _sendPayload(message);
  }

  Future<void> reload() async {
    final message = _lastInitMessage;
    if (message == null) {
      return;
    }
    await _sendPayload(message);
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
        Offstage(
          offstage: true,
          child: SizedBox(
            width: 1,
            height: 1,
            child: WebViewWidget(controller: controller),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.transparent),
            child:
                _svgMarkup != null
                    ? SvgPicture.string(
                      _svgMarkup!,
                      key: ValueKey(_svgMarkup),
                      fit: BoxFit.contain,
                      allowDrawingOutsideViewBox: true,
                    )
                    : const SizedBox.expand(),
          ),
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
