import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:flashlights_client/utils/music_xml_utils.dart';

class EventPracticeOSMD extends StatefulWidget {
  const EventPracticeOSMD({super.key});

  @override
  EventPracticeOSMDState createState() => EventPracticeOSMDState();
}

class EventPracticeOSMDState extends State<EventPracticeOSMD> {
  WebViewController? _controller;
  bool _initialised = false;
  String? _lastInitPayload;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final trimmedXml = await loadTrimmedMusicXML();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..enableZoom(false);

      final pageLoaded = Completer<void>();
      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageLoaded.isCompleted) {
              pageLoaded.complete();
            }
          },
        ),
      );

      await controller.loadFlutterAsset('assets/osmd_view.html');
      await pageLoaded.future;

      _controller = controller;
      await _sendInit(trimmedXml);

      if (mounted) {
        setState(() {
          _initialised = true;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('[EventPracticeOSMD] init failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _initialised = false;
        });
      }
    }
  }

  Future<void> _sendInit(String xml) async {
    if (_controller == null) {
      return;
    }
    final payload = jsonEncode({'type': 'init', 'xml': xml});
    _lastInitPayload = payload;
    await _controller!.runJavaScript('window.postMessage($payload, "*");');
  }

  void setMeasure(int measureNumber) {
    if (_controller == null || measureNumber <= 0) {
      return;
    }
    final payload = jsonEncode({'type': 'window', 'measure': measureNumber});
    unawaited(_controller!.runJavaScript('window.postMessage($payload, "*");'));
  }

  /// Attempts to reload the score if the WebView loses state (e.g., app resume).
  Future<void> reload() async {
    final controller = _controller;
    final initPayload = _lastInitPayload;
    if (controller == null || initPayload == null) {
      return;
    }
    await controller.runJavaScript('window.postMessage($initPayload, "*");');
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
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54),
              child: Center(
                child: SizedBox.square(
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
