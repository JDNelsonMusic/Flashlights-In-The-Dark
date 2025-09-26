import 'dart:io' show Platform;
import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

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
// Removed PrimerToneLibrary; native audio handles asset lookup.
import 'native_audio.dart';
import 'widgets/event_practice_osmd.dart';

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
    final iosOptions =
        audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker |
        audio_session.AVAudioSessionCategoryOptions.mixWithOthers;
    await session.configure(
      audio_session.AudioSessionConfiguration(
        avAudioSessionCategory:
            audio_session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: iosOptions,
        avAudioSessionMode: audio_session.AVAudioSessionMode.defaultMode,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.sonification,
          usage: audio_session.AndroidAudioUsage.assistanceSonification,
        ),
        androidAudioFocusGainType:
            audio_session.AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);
  } catch (e) {
    debugPrint('[AudioSession] configuration failed: $e');
  }

  // 4. Warm up primer tone library so all audio buffers are ready before use.
  try {
    await NativeAudio.ensureInitialized();
  } catch (e) {
    debugPrint('[Bootstrap] primer preload failed: $e');
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.platform,
    required this.onTitleTap,
    required this.onSlotSelected,
  });

  final String platform;
  final VoidCallback onTitleTap;
  final Future<void> Function(int) onSlotSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      valueListenable: client.myIndex,
      builder: (context, myIndex, _) {
        final slotColor = kSlotOutlineColors[myIndex] ?? Colors.white70;
        return _GlassPanel(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTitleTap,
                child: Text(
                  'Flashlights In The Dark',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<bool>(
                valueListenable: client.connected,
                builder: (context, connected, _) {
                  final status = connected ? 'Connected' : 'Searching…';
                  return Text(
                    '$kAppVersion · $platform · $status',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 0.2,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<bool>(
                valueListenable: client.connected,
                builder: (context, connected, _) {
                  final statusAccent =
                      connected
                          ? const Color(0xFF06D6A0)
                          : const Color(0xFFFFA630);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _InfoPill(
                        icon: Icons.person_rounded,
                        label: 'Singer #$myIndex',
                        accent: slotColor,
                      ),
                      _SlotSelectorPill(
                        currentSlot: myIndex,
                        accent: slotColor,
                        onSelect: onSlotSelected,
                      ),
                      _InfoPill(
                        icon:
                            connected
                                ? Icons.check_circle_rounded
                                : Icons.wifi_tethering_error_rounded,
                        label: connected ? 'Connected' : 'Searching…',
                        accent: statusAccent,
                        muted: !connected,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlotSelectorPill extends StatelessWidget {
  const _SlotSelectorPill({
    required this.currentSlot,
    required this.accent,
    required this.onSelect,
  });

  final int currentSlot;
  final Color accent;
  final Future<void> Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final slots = client.availableSlots;
    final slotLabel =
        client.colorForSlot(currentSlot)?.displayName ?? 'Unassigned';
    return PopupMenuButton<int>(
      onSelected: (slot) => unawaited(onSelect(slot)),
      color: Colors.black.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) {
        return slots
            .map(
              (slot) => PopupMenuItem<int>(
                value: slot,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: kSlotOutlineColors[slot] ?? Colors.white54,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Slot $slot · ${client.colorForSlot(slot)?.displayName ?? 'Unassigned'}',
                    ),
                  ],
                ),
              ),
            )
            .toList();
      },
      child: _InfoPill(
        icon: Icons.apps_rounded,
        label: 'Slot $currentSlot · $slotLabel',
        accent: accent,
        trailing: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final displayColor = muted ? Colors.white70 : Colors.white;
    final highlight = accent.withValues(alpha: muted ? 0.35 : 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: muted ? 0.04 : 0.08),
        border: Border.all(color: highlight),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: displayColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: displayColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.activeColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final iconBackground =
        active
            ? activeColor.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.08);
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconBackground,
              boxShadow:
                  active
                      ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ]
                      : null,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'By Jon D. Nelson',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 4),
        Text(
          'In collaboration with the Philharmonic Chorus of Madison',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: Colors.white38),
        ),
      ],
    );
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
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Flashlights Client',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8053FF),
          brightness: Brightness.dark,
        ),
        textTheme: baseTheme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        sliderTheme: baseTheme.sliderTheme.copyWith(
          activeTrackColor: const Color(0xFFB987FF),
          thumbColor: const Color(0xFFB987FF),
          overlayColor: const Color(0xFFB987FF).withValues(alpha: 0.18),
          trackHeight: 4.5,
        ),
      ),
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

  Future<void> _setBrightness(double target) async {
    final current = client.brightness.value;
    final clamped = target.clamp(0.0, 1.0).toDouble();
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

  Future<void> _updateBrightness(double delta) {
    final target = (client.brightness.value + delta).clamp(0.0, 1.0).toDouble();
    return _setBrightness(target);
  }

  Future<void> _handleSlotSelected(int newSlot) async {
    client.myIndex.value = newSlot;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSlot', newSlot);
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
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1C0531), Color(0xFF0B0626), Color(0xFF011734)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                  children: [
                    _HeaderSection(
                      platform: platform,
                      onTitleTap: _handleTitleTap,
                      onSlotSelected: _handleSlotSelected,
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<bool>(
                      valueListenable: client.flashOn,
                      builder: (context, flashOn, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: client.audioPlaying,
                          builder: (context, playing, _) {
                            return Row(
                              children: [
                                Expanded(
                                  child: _StatusTile(
                                    icon:
                                        flashOn
                                            ? Icons.bolt_rounded
                                            : Icons.bolt_outlined,
                                    title: 'Flashlight',
                                    subtitle:
                                        flashOn
                                            ? 'Torch active'
                                            : 'Awaiting cue',
                                    active: flashOn,
                                    activeColor: const Color(0xFFFFD166),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _StatusTile(
                                    icon:
                                        playing
                                            ? Icons.music_note_rounded
                                            : Icons.music_off_rounded,
                                    title: 'Primer',
                                    subtitle:
                                        playing
                                            ? 'Playing locally'
                                            : 'Standing by',
                                    active: playing,
                                    activeColor: const Color(0xFF06D6A0),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    ValueListenableBuilder<int>(
                      valueListenable: client.myIndex,
                      builder: (context, myIndex, _) {
                        if (myIndex != 5) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [
                            _GlassPanel(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tap Trigger',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () {
                                        flosc.OscListener.instance.sendCustom(
                                          '/tap',
                                          [],
                                        );
                                      },
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      child: const Text('TAP'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        );
                      },
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: client.brightness,
                      builder: (context, brightness, _) {
                        final slotColor =
                            kSlotOutlineColors[client.myIndex.value] ??
                            Colors.white70;
                        return _GlassPanel(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Torch Brightness',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: slotColor,
                                  thumbColor: slotColor,
                                  overlayColor: slotColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  inactiveTrackColor: Colors.white24,
                                ),
                                child: Slider(
                                  value: brightness.clamp(0.0, 1.0),
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (value) {
                                    client.brightness.value = value;
                                  },
                                  onChangeEnd:
                                      (value) =>
                                          unawaited(_setBrightness(value)),
                                ),
                              ),
                              Text(
                                '${(brightness * 100).round()}% intensity',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    const PracticeEventStrip(),
                    const SizedBox(height: 36),
                    const _FooterNote(),
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
                          () => flosc.OscListener.instance.sendCustom(
                            '/hello',
                            [],
                          ),
                    ),
                  ),
              ],
            ),
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
  static const double _kListHeight = 280.0;
  static const double _kScoreHeight = 220.0;

  final ScrollController _controller = ScrollController();
  final GlobalKey<EventPracticeOSMDState> _osmdKey =
      GlobalKey<EventPracticeOSMDState>();
  int? _lastRenderedMeasure;
  PrimerColor? _lastRenderedColor;
  String? _lastRenderedNote;

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
    final padding = math.max(0.0, (viewport - _kCurrentWidth) / 2);
    final target = (beforeWidth - padding).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );

    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handlePlayRequest(List<EventRecipe> events, int index) async {
    if (events.isEmpty) return;
    final clampedIndex = index.clamp(0, events.length - 1);
    if (client.practiceEventIndex.value != clampedIndex) {
      client.setPracticeEventIndex(clampedIndex);
    }

    final event = events[clampedIndex];
    final slot = client.myIndex.value;
    final assignment = client.assignmentForSlot(event, slot);
    if (assignment != null) {
      try {
        await flosc.OscListener.instance.playLocalPrimer(
          assignment.sample,
          1.0,
        );
      } catch (e) {
        debugPrint('[Practice] primer playback failed: $e');
      }
    }

    if (clampedIndex < events.length - 1) {
      client.movePracticeEvent(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<EventRecipe>>(
      valueListenable: client.eventRecipes,
      builder: (context, events, _) {
        if (events.isEmpty) {
          return _GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading event timeline…'),
              ],
            ),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: client.practiceEventIndex,
          builder: (context, index, _) {
            final clampedIndex = index.clamp(0, events.length - 1);
            final mediaHeight = MediaQuery.of(context).size.height;
            final listHeight = math.min(_kListHeight, mediaHeight * 0.4);
            final slotForScore = client.myIndex.value;
            final primerColorForScore = client.colorForSlot(slotForScore);
            final currentEvent = events[clampedIndex];
            final assignmentForScore =
                client.assignmentForSlot(currentEvent, slotForScore);
            final rawNoteForScore = assignmentForScore?.note?.trim();
            final noteForScore =
                rawNoteForScore == null || rawNoteForScore.isEmpty
                    ? null
                    : rawNoteForScore;
            final measure = currentEvent.measure;
            if (measure != null && measure > 0) {
              final shouldUpdateScore =
                  measure != _lastRenderedMeasure ||
                  primerColorForScore != _lastRenderedColor ||
                  noteForScore != _lastRenderedNote;
              if (shouldUpdateScore) {
                _lastRenderedMeasure = measure;
                _lastRenderedColor = primerColorForScore;
                _lastRenderedNote = noteForScore;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final color = primerColorForScore;
                  if (color != null) {
                    _osmdKey.currentState?.updatePracticeContext(
                      color: color,
                      measure: measure,
                      note: noteForScore,
                    );
                  } else {
                    _osmdKey.currentState?.clearScore();
                  }
                });
              }
            } else if (_lastRenderedMeasure != null || _lastRenderedColor != null) {
              _lastRenderedMeasure = null;
              _lastRenderedColor = null;
              _lastRenderedNote = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _osmdKey.currentState?.clearScore();
              });
            }
            return _GlassPanel(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Event Practice',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        'Slide or tap · Trigger plays locally',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontalPadding = math.max(
                        0.0,
                        (constraints.maxWidth - _kCurrentWidth) / 2,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: listHeight,
                            child: ListView.separated(
                              controller: _controller,
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: events.length,
                              clipBehavior: Clip.none,
                              separatorBuilder:
                                  (_, _) => const SizedBox(width: _kSpacing),
                              itemBuilder: (context, i) {
                                final event = events[i];
                                final isCurrent = i == clampedIndex;
                                final slot = slotForScore;
                                final assignment = client.assignmentForSlot(
                                  event,
                                  slot,
                                );
                                final primerColor = primerColorForScore;
                                final practiceSlots = primerColor == null
                                    ? const <int>[]
                                    : client.practiceSlotsForColor(primerColor);
                                final staffIndex = primerColor == null
                                    ? null
                                    : client.practiceStaffIndexForColor(primerColor);
                                final practiceSlotNumber =
                                    client.practiceSlotNumberForSlot(slot);
                                return SizedBox(
                                  width: isCurrent ? _kCurrentWidth : _kItemWidth,
                                  child: _PracticeEventCard(
                                    event: event,
                                    isCurrent: isCurrent,
                                    assignment: assignment,
                                    primerColor: primerColor,
                                    practiceSlots: practiceSlots,
                                    practiceStaffIndex: staffIndex,
                                    practiceSlotNumber: practiceSlotNumber,
                                    onTap: () => client.setPracticeEventIndex(i),
                                    onPlay:
                                        () => unawaited(
                                          _handlePlayRequest(events, i),
                                        ),
                                    onPrev: () => client.movePracticeEvent(-1),
                                    onNext: () => client.movePracticeEvent(1),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: constraints.maxWidth,
                            child: _GlassPanel(
                              padding: const EdgeInsets.all(12),
                              child: SizedBox(
                                height: math.min(_kScoreHeight, mediaHeight * 0.3),
                                width: double.infinity,
                                child: EventPracticeOSMD(key: _osmdKey),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
    required this.practiceSlots,
    this.primerColor,
    this.practiceStaffIndex,
    this.practiceSlotNumber,
    required this.onTap,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
  });

  final EventRecipe event;
  final bool isCurrent;
  final PrimerAssignment? assignment;
  final PrimerColor? primerColor;
  final List<int> practiceSlots;
  final int? practiceStaffIndex;
  final int? practiceSlotNumber;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const double _previewWidth = 110.0;
  static const double _currentWidth = 220.0;
  static const double _previewHeight = 220.0;
  static const double _currentHeight = 340.0;

  static Color _colorForPrimer(PrimerColor color) {
    switch (color) {
      case PrimerColor.blue:
        return SlotColors.royalBlue;
      case PrimerColor.red:
        return SlotColors.brightRed;
      case PrimerColor.green:
        return SlotColors.slotGreen;
      case PrimerColor.purple:
        return SlotColors.slotPurple;
      case PrimerColor.yellow:
        return SlotColors.slotYellow;
      case PrimerColor.pink:
        return SlotColors.lightRose;
      case PrimerColor.orange:
        return SlotColors.slotOrange;
      case PrimerColor.magenta:
        return SlotColors.hotMagenta;
      case PrimerColor.cyan:
        return SlotColors.skyBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final measureText = event.measure?.toString() ?? '—';
    final position = event.position ?? '';
    final sampleName = assignment?.normalizedSample ?? '';
    final primerLabel = sampleName.isEmpty ? '—' : sampleName.split('/').last;
    final noteLabel = assignment?.note ?? '—';

    final beatText = _normalisedBeat(position);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final hasPrimer = sampleName.isNotEmpty;
    final primerAccent =
        primerColor != null ? _colorForPrimer(primerColor!) : null;

    final width = isCurrent ? _currentWidth : _previewWidth;
    final targetHeight = isCurrent ? _currentHeight : _previewHeight;
    final gradientColors =
        isCurrent
            ? [
              Colors.white.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.06),
            ]
            : [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.02),
            ];

    Widget buildPlayButton() {
      if (isCurrent) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(hasPrimer ? 'Play primer' : 'Advance'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  hasPrimer
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(hasPrimer ? 'Play' : 'Next'),
          style: FilledButton.styleFrom(
            backgroundColor:
                hasPrimer
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      constraints: BoxConstraints(minHeight: targetHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isCurrent ? 0.42 : 0.14),
          width: isCurrent ? 1.3 : 1.0,
        ),
        boxShadow:
            isCurrent
                ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ]
                : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Event #${event.id}',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (isCurrent) ...[
                  IconButton.filledTonal(
                    onPressed: onPrev,
                    icon: const Icon(Icons.chevron_left_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Measure $measureText',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Beat $beatText',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (isCurrent) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _EventDetailChip(label: 'Note: $noteLabel'),
                  _EventDetailChip(label: 'Primer: $primerLabel'),
                ],
              ),
              const SizedBox(height: 8),
              _PrimerInfoSection(
                primerColor: primerColor,
                practiceSlots: practiceSlots,
                practiceStaffIndex: practiceStaffIndex,
                practiceSlotNumber: practiceSlotNumber,
                accent: primerAccent,
              ),
              const SizedBox(height: 8),
            ] else if (!hasPrimer) ...[
              Text(
                'No primer for your slot',
                style: textTheme.labelSmall?.copyWith(color: Colors.white38),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            buildPlayButton(),
          ],
        ),
      ),
    );
  }
}

class _PrimerInfoSection extends StatelessWidget {
  const _PrimerInfoSection({
    required this.primerColor,
    required this.practiceSlots,
    required this.practiceStaffIndex,
    required this.practiceSlotNumber,
    required this.accent,
  });

  final PrimerColor? primerColor;
  final List<int> practiceSlots;
  final int? practiceStaffIndex;
  final int? practiceSlotNumber;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final groupIndex = primerColor?.groupIndex;
    final colorName = primerColor?.displayName ?? 'Unassigned';
    final groupLabel =
        groupIndex != null ? 'Group $groupIndex · $colorName' : colorName;
    final staffLabel =
        practiceStaffIndex != null ? 'Staff $practiceStaffIndex' : 'Staff —';
    final slotsLabel =
        practiceSlots.isEmpty ? 'Slots —' : 'Slots ${practiceSlots.join(', ')}';
    final youLabel =
        practiceSlotNumber != null ? 'You → ${practiceSlotNumber!.toString().padLeft(2, '0')}' : null;
    final swatchColor = accent ?? Colors.white.withValues(alpha: 0.3);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatchColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  groupLabel,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(staffLabel, style: textTheme.bodySmall),
                    Text(slotsLabel, style: textTheme.bodySmall),
                    if (youLabel != null)
                      Text(
                        youLabel,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailChip extends StatelessWidget {
  const _EventDetailChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _normalisedBeat(String rawPosition) {
  if (rawPosition.isEmpty) {
    return '—';
  }
  final match = RegExp(r'(\d+)').firstMatch(rawPosition);
  if (match != null) {
    return match.group(1) ?? rawPosition;
  }
  return rawPosition;
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
      color: Colors.black.withValues(alpha: 0.85),
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
              Builder(
                builder: (context) {
                  final ready = NativeAudio.isReady;
                  final error = NativeAudio.lastInitError;
                  final snapshot = NativeAudio.lastInitSnapshot;
                  final status =
                      snapshot != null
                          ? (snapshot['status'] ?? (ready ? 'ok' : 'pending'))
                          : (ready ? 'ok' : 'pending');
                  final bufferCount =
                      snapshot != null
                          ? (snapshot['count'] ?? snapshot['sounds'])
                          : null;
                  final failed = snapshot?['failed'];
                  final failedCountRaw = snapshot?['failedCount'];
                  final failedCount =
                      failedCountRaw is num
                          ? failedCountRaw.toInt()
                          : failed is List
                          ? failed.length
                          : 0;
                  final detail =
                      error != null
                          ? 'error: $error'
                          : 'status: $status, buffers: ${bufferCount ?? 'n/a'}, failed: $failedCount';
                  return Text(
                    'Audio engine: ${ready ? 'ready' : 'not ready'} ($detail)',
                    style: TextStyle(
                      color: error != null ? Colors.redAccent : Colors.white70,
                    ),
                  );
                },
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
