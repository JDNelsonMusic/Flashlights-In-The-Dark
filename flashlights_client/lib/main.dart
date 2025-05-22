import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'network/osc_listener.dart';
// import 'dart:io';
// import 'dart:convert';
// removed discovery code
import 'model/client_state.dart';
import 'version.dart';

/// Native bootstrap that must finish **before** the widget tree is built.
Future<void> _bootstrapNative() async {
  if (Platform.isIOS || Platform.isAndroid) {
    // 1. Ask for runtime permissions (camera + microphone).
    await [Permission.camera, Permission.microphone].request();
  }

  // 2. On Android, spin up the foreground service so we survive backgrounding.
  if (Platform.isAndroid) {
    const MethodChannel ch = MethodChannel('ai.keex.flashlights/client');
    try {
      await ch.invokeMethod('startService');
    } on PlatformException catch (e) {
      debugPrint('[KeepAliveService] start failed: $e');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapNative();
  runApp(const FlashlightsApp());
}

class FlashlightsApp extends StatelessWidget {
  const FlashlightsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flashlights Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: const Color(0xFF160016)),
      home: const Bootstrap(),
    );
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {

  @override
  void initState() {
    super.initState();
    OscListener.instance.start();
  }

  @override
  void dispose() {
    OscListener.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isIOS
        ? 'iOS'
        : Platform.isAndroid
            ? 'Android'
            : 'Unknown';
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Column(
                children: [
                  const Text(
                    'Flashlights In The Dark',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: client.connected,
                    builder: (context, connected, _) {
                      final status = connected ? 'Connected' : 'Searching…';
                      return Text(
                        '$kAppVersion – $platform – $status',
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: client.myIndex,
                      builder: (context, myIndex, _) {
                        return Text(
                          'Singer #$myIndex',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Override slot dropdown
                    ValueListenableBuilder<int>(
                      valueListenable: client.myIndex,
                      builder: (context, myIndex, _) {
                        return DropdownButton<int>(
                          value: myIndex,
                          items: List.generate(
                            32,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('Slot ${i + 1}'),
                            ),
                          ),
                          onChanged: (newSlot) {
                            if (newSlot != null) {
                              client.myIndex.value = newSlot;
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<bool>(
                      valueListenable: client.flashOn,
                      builder: (context, flashOn, _) {
                        return Icon(
                          flashOn ? Icons.flash_on : Icons.flash_off,
                          color: flashOn ? Colors.yellow : Colors.grey,
                          size: 48,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: client.audioPlaying,
                      builder: (context, playing, _) {
                        return Icon(
                          playing ? Icons.music_note : Icons.music_off,
                          color: playing ? Colors.green : Colors.grey,
                          size: 48,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'By Jon D. Nelson\nIn collaboration with the Philharmonic Chorus of Madison',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
