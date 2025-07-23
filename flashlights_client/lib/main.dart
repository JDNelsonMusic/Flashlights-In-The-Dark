import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock/wakelock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashlights_client/network/osc_listener.dart' as flosc;
// import 'dart:io';
// import 'dart:convert';
// removed discovery code
import 'model/client_state.dart';
import 'color_theme.dart';
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
  final prefs = await SharedPreferences.getInstance();
  final savedSlot = prefs.getInt('lastSlot');
  if (savedSlot != null && savedSlot != 0) {
    client.myIndex.value = savedSlot;
  }
  Wakelock.enable();
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
      ).copyWith(scaffoldBackgroundColor: const Color(0xFF120012)),
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
    flosc.OscListener.instance.start();
  }

  @override
  void dispose() {
    flosc.OscListener.instance.stop();
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
                        final color = kSlotOutlineColors[myIndex];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: color ?? Colors.transparent,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Singer #$myIndex',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Override slot dropdown
                    ValueListenableBuilder<int>(
                      valueListenable: client.myIndex,
                      builder: (context, myIndex, _) {
                        const realSlots = [
                          1, 3, 4, 5, 7, 9, 12,
                          14, 15, 16, 18, 19, 20, 21, 23, 24, 25,
                          27, 29, 34, 38, 40,
                          41, 42, 44, 51, 53, 54
                        ];
                        return DropdownButton<int>(
                          value: myIndex,
                          items: realSlots
                              .map((slot) => DropdownMenuItem(
                                    value: slot,
                                    child: Text('Slot $slot'),
                                  ))
                              .toList(),
                          onChanged: (newSlot) async {
                            if (newSlot != null) {
                              client.myIndex.value = newSlot;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('lastSlot', newSlot);
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
                    const SizedBox(height: 24),
                    ValueListenableBuilder<int>(
                      valueListenable: client.myIndex,
                      builder: (context, myIndex, _) {
                        if (myIndex == 5) {
                          return ElevatedButton(
                            onPressed: () {
                              flosc.OscListener.instance.sendCustom('/tap', []);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: 12.0, horizontal: 32.0),
                              child: Text(
                                'TAP',
                                style: TextStyle(fontSize: 32),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
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
