import 'dart:io' show Platform;
import 'dart:async' show Timer, unawaited;

import 'package:audio_session/audio_session.dart' as audio_session;
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
import 'color_theme.dart';
import 'version.dart';
import 'model/client_state.dart';
import 'model/event_recipe.dart';
import 'services/primer_tone_library.dart';

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
    final session = await audio_session.AudioSession.instance;
    final iosOptions = audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker |
        audio_session.AVAudioSessionCategoryOptions.mixWithOthers;
    await session.configure(
      audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: iosOptions,
        avAudioSessionMode: audio_session.AVAudioSessionMode.defaultMode,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.music,
          usage: audio_session.AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);
  } catch (e) {
    debugPrint('[AudioSession] configuration failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapNative();
  await PrimerToneLibrary.instance.warmUp();
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
    unawaited(client.ensureEventRecipesLoaded());
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
                              final slots = client.availableSlots;
                              if (slots.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final hasSlot = slots.contains(myIndex);
                              final currentValue =
                                  hasSlot ? myIndex : slots.first;
                              final dropdownItems =
                                  slots.map((slot) {
                                    final color = client.colorForSlot(slot);
                                    final label =
                                        color?.displayName ?? 'Unassigned';
                                    return DropdownMenuItem<int>(
                                      value: slot,
                                      child: Text('Slot $slot · $label'),
                                    );
                                  }).toList();
                              return DropdownButton<int>(
                                value: currentValue,
                                items: dropdownItems,
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
                          const SizedBox(height: 32),
                          const PracticeEventStrip(),
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

class PracticeEventStrip extends StatefulWidget {
  const PracticeEventStrip({super.key});

  @override
  State<PracticeEventStrip> createState() => _PracticeEventStripState();
}

class _PracticeEventStripState extends State<PracticeEventStrip> {
  static const double _kItemWidth = 120.0;
  static const double _kCurrentWidth = 240.0;
  static const double _kSpacing = 12.0;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    client.practiceEventIndex.addListener(_autoCenter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCenter());
  }

  @override
  void dispose() {
    client.practiceEventIndex.removeListener(_autoCenter);
    _controller.dispose();
    super.dispose();
  }

  void _autoCenter() {
    if (!_controller.hasClients) return;
    final events = client.eventRecipes.value;
    if (events.isEmpty) return;
    final i = client.practiceEventIndex.value.clamp(0, events.length - 1);

    final beforeWidth = i * (_kItemWidth + _kSpacing);
    final viewport = _controller.position.viewportDimension;
    final target = (beforeWidth - (viewport - _kCurrentWidth) / 2)
        .clamp(0.0, _controller.position.maxScrollExtent);

    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<EventRecipe>>(
      valueListenable: client.eventRecipes,
      builder: (context, events, _) {
        if (events.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Loading event timeline…'),
              ],
            ),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: client.practiceEventIndex,
          builder: (context, index, __) {
            final clampedIndex = index.clamp(0, events.length - 1);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white.withOpacity(0.08),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Event Practice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('Slide or tap · Trigger plays locally', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(width: _kSpacing),
                      itemBuilder: (context, i) {
                        final event = events[i];
                        final isCurrent = i == clampedIndex;
                        final slot = client.myIndex.value;
                        final assignment = client.assignmentForSlot(event, slot);
                        return SizedBox(
                          width: isCurrent ? _kCurrentWidth : _kItemWidth,
                          child: _PracticeEventCard(
                            event: event,
                            isCurrent: isCurrent,
                            assignment: assignment,
                            onTap: () => client.setPracticeEventIndex(i),
                            onPlay: assignment == null
                                ? null
                                : () => unawaited(
                                      flosc.OscListener.instance.playLocalPrimer(
                                        assignment.sample,
                                        1.0,
                                      ),
                                    ),
                            onPrev: () => client.movePracticeEvent(-1),
                            onNext: () => client.movePracticeEvent(1),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PracticeEventCard extends StatelessWidget {
  const _PracticeEventCard({
    required this.event,
    required this.isCurrent,
    required this.assignment,
    required this.onTap,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
  });

  final EventRecipe event;
  final bool isCurrent;
  final PrimerAssignment? assignment;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const double _previewWidth = 120.0;
  static const double _currentWidth = 240.0;
  static const double _currentHeight = 228.0;

  @override
  Widget build(BuildContext context) {
    final measureText = event.measure?.toString() ?? '—';
    final position = event.position ?? '';
    final sampleName = assignment?.normalizedSample ?? '';
    final primerLabel = sampleName.isEmpty ? '—' : sampleName.split('/').last;
    final noteLabel = assignment?.note ?? '—';

    final width = isCurrent ? _currentWidth : _previewWidth;
    final height = isCurrent ? _currentHeight : null;
    final background = isCurrent
        ? Colors.white.withOpacity(0.16)
        : Colors.white.withOpacity(0.08);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: background,
        border: Border.all(
          color: Colors.white.withOpacity(isCurrent ? 0.35 : 0.12),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${event.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isCurrent) ...[
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text('M$measureText', style: Theme.of(context).textTheme.bodySmall),
            Text(position, style: Theme.of(context).textTheme.bodySmall),
            if (isCurrent) ...[
              const SizedBox(height: 12),
              Text('Note: $noteLabel'),
              Text('Primer: $primerLabel'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  assignment == null ? 'No primer available' : 'Trigger $primerLabel',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  minimumSize: const Size.fromHeight(36),
                ),
              ),
            ],
          ],
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
