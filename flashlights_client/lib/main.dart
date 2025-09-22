import 'dart:io' show Platform;
import 'dart:async' show Timer, unawaited;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'package:flashlights_client/network/osc_listener.dart' as flosc;
import 'package:flashlights_client/network/osc_packet.dart';
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

    const MethodChannel networkChannel = MethodChannel(
      'ai.keex.flashlights/network',
    );
    try {
      await networkChannel.invokeMethod('acquireMulticastLock');
    } on PlatformException catch (e) {
      debugPrint('[MulticastLock] acquire failed: $e');
    }
  }

  // 3. Configure the audio session so primer tones play even in silent mode.
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
    await session.setActive(true);
  } catch (e) {
    debugPrint('[AudioSession] configuration failed: $e');
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
  WakelockPlus.enable();
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
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _showDebugOverlay = false;
  int _titleTapCount = 0;
  Timer? _tapResetTimer;

  @override
  void initState() {
    super.initState();
    flosc.OscListener.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    unawaited(flosc.OscListener.instance.stop());
    _tapResetTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleTitleTap() {
    _tapResetTimer?.cancel();
    _titleTapCount += 1;
    _tapResetTimer = Timer(const Duration(milliseconds: 600), () {
      _titleTapCount = 0;
    });
    if (_titleTapCount >= 3) {
      _titleTapCount = 0;
      setState(() {
        _showDebugOverlay = !_showDebugOverlay;
      });
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.audioVolumeUp) {
      unawaited(_updateBrightness(0.1));
    } else if (key == LogicalKeyboardKey.audioVolumeDown) {
      unawaited(_updateBrightness(-0.1));
    }
  }

  Future<void> _updateBrightness(double delta) async {
    final current = client.brightness.value;
    final clamped = (current + delta).clamp(0.0, 1.0).toDouble();
    if ((clamped - current).abs() < 0.001) {
      return;
    }
    client.brightness.value = clamped;
    try {
      await ScreenBrightness.instance.setScreenBrightness(clamped);
    } catch (e) {
      debugPrint('[UI] Screen brightness set failed: $e');
    }
    try {
      await flosc.OscListener.instance.setTorchLevel(clamped);
    } catch (e) {
      debugPrint('[UI] Torch level set failed: $e');
    }
    flosc.OscListener.instance.sendCustom('/flash/on', [
      client.myIndex.value,
      clamped,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final platform =
        Platform.isIOS
            ? 'iOS'
            : Platform.isAndroid
            ? 'Android'
            : 'Unknown';
    return RawKeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKey: _handleKeyEvent,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _handleTitleTap,
                          child: const Text(
                            'Flashlights In The Dark',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: client.connected,
                          builder: (context, connected, _) {
                            final status =
                                connected ? 'Connected' : 'Searching…';
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
                                  vertical: 4,
                                  horizontal: 8,
                                ),
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
                              final realSlots = {
                                ...List<int>.generate(9, (i) => i + 1),
                                3,
                                4,
                                5,
                                7,
                                9,
                                12,
                                14,
                                15,
                                16,
                                18,
                                19,
                                20,
                                21,
                                23,
                                24,
                                25,
                                27,
                                29,
                                34,
                                38,
                                40,
                                41,
                                42,
                                44,
                                51,
                                53,
                                54,
                              }.toList()
                                ..sort();
                              return DropdownButton<int>(
                                value: myIndex,
                                items:
                                    realSlots
                                        .map(
                                          (slot) => DropdownMenuItem(
                                            value: slot,
                                            child: Text('Slot $slot'),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (newSlot) async {
                                  if (newSlot != null) {
                                    client.myIndex.value = newSlot;
                                    final prefs =
                                        await SharedPreferences.getInstance();
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
                                    flosc.OscListener.instance.sendCustom(
                                      '/tap',
                                      [],
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 12.0,
                                      horizontal: 32.0,
                                    ),
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
              if (_showDebugOverlay)
                Positioned.fill(
                  child: DebugOverlay(
                    onClose: () {
                      setState(() {
                        _showDebugOverlay = false;
                      });
                    },
                    onSendHello:
                        () =>
                            flosc.OscListener.instance.sendCustom('/hello', []),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DebugOverlay extends StatelessWidget {
  const DebugOverlay({
    super.key,
    required this.onClose,
    required this.onSendHello,
  });

  final VoidCallback onClose;
  final VoidCallback onSendHello;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Debug Overlay',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: client.myIndex,
                builder:
                    (context, slot, _) => Text(
                      'Slot: $slot',
                      style: const TextStyle(color: Colors.white70),
                    ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: client.connected,
                builder:
                    (context, connected, _) => Text(
                      'Connected: $connected',
                      style: const TextStyle(color: Colors.white70),
                    ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: client.brightness,
                builder:
                    (context, brightness, _) => Text(
                      'Brightness: ${brightness.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: client.audioPlaying,
                builder:
                    (context, playing, _) => Text(
                      'Audio playing: $playing',
                      style: const TextStyle(color: Colors.white70),
                    ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: client.clockOffsetMs,
                builder:
                    (context, offset, _) => Text(
                      'Clock offset (ms): ${offset.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onSendHello,
                child: const Text('Send /hello'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recent OSC Messages',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<List<OSCMessage>>(
                  valueListenable: client.recentMessages,
                  builder: (context, messages, _) {
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'No OSC messages yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    final entries = messages.reversed.toList();
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final msg = entries[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            '${msg.address}  ${msg.arguments}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
