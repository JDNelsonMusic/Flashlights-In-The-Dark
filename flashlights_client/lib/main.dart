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

Future<void> _setAppScreenToMaximum() async {
  if (!(Platform.isIOS || Platform.isAndroid)) {
    return;
  }
  try {
    await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
  } catch (e) {
    debugPrint('[ScreenBrightness] max-screen set failed: $e');
  }
}

/// Native bootstrap that must finish **before** the widget tree is built.
Future<void> _bootstrapNative() async {
  if (Platform.isIOS || Platform.isAndroid) {
    // 1. Ask only for camera permission, which is required for torch control.
    await [Permission.camera].request();
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

  // 3. Configure the audio session so event-electronics clips play in silent mode.
  try {
    final session = await audio_session.AudioSession.instance;
    await session.configure(
      audio_session.AudioSessionConfiguration(
        // Mic capture is currently disabled in the concert client, so prefer a
        // straight playback session for reliable loudspeaker routing on iPhone.
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            audio_session.AVAudioSessionCategoryOptions.mixWithOthers,
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

  // 4. Warm up the native audio layer before the first cue arrives.
  try {
    await NativeAudio.ensureInitialized();
  } catch (e) {
    debugPrint('[Bootstrap] native audio init failed: $e');
  }

  // 5. Keep the singer-facing screen fully lit while the app is active.
  await _setAppScreenToMaximum();
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.platform,
    required this.compact,
    required this.dense,
    required this.onTitleTap,
    required this.onPartSelected,
    required this.onRefreshConnection,
    required this.refreshingConnection,
  });

  final String platform;
  final bool compact;
  final bool dense;
  final VoidCallback onTitleTap;
  final Future<void> Function(LightChorusPart) onPartSelected;
  final VoidCallback onRefreshConnection;
  final bool refreshingConnection;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      valueListenable: client.myIndex,
      builder: (context, myIndex, _) {
        final slotColor = kSlotOutlineColors[myIndex] ?? Colors.white70;
        final partLabel = client.partForSlot(myIndex)?.label;
        final singerLabel =
            myIndex == 0
                ? 'Unassigned'
                : partLabel == null
                ? 'Slot $myIndex'
                : '$partLabel · Slot $myIndex';
        return _GlassPanel(
          padding: EdgeInsets.fromLTRB(
            dense ? 14 : compact ? 18 : 24,
            dense ? 14 : compact ? 18 : 24,
            dense ? 14 : compact ? 18 : 24,
            dense ? 16 : compact ? 20 : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTitleTap,
                child: Text(
                  'Flashlights In The Dark',
                  style: (dense
                          ? textTheme.titleLarge
                          : textTheme.headlineSmall)
                      ?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              SizedBox(height: dense ? 2 : compact ? 4 : 6),
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
              SizedBox(height: dense ? 10 : compact ? 12 : 20),
              ValueListenableBuilder<bool>(
                valueListenable: client.connected,
                builder: (context, connected, _) {
                  final statusAccent =
                      connected
                          ? const Color(0xFF06D6A0)
                          : const Color(0xFFFFA630);
                  return Wrap(
                    spacing: compact ? 8 : 12,
                    runSpacing: compact ? 8 : 12,
                    children: [
                      _InfoPill(
                        icon: Icons.person_rounded,
                        label: 'Singer: $singerLabel',
                        accent: slotColor,
                        compact: compact || dense,
                      ),
                      _SlotSelectorPill(
                        currentSlot: myIndex,
                        accent: slotColor,
                        onSelect: onPartSelected,
                        compact: compact || dense,
                      ),
                      _InfoPill(
                        icon:
                            connected
                                ? Icons.check_circle_rounded
                                : Icons.wifi_tethering_error_rounded,
                        label: connected ? 'Connected' : 'Searching…',
                        accent: statusAccent,
                        muted: !connected,
                        compact: compact || dense,
                      ),
                      ValueListenableBuilder<String?>(
                        valueListenable: client.cueRoutingIssue,
                        builder: (context, issue, _) {
                          if (issue == null || issue.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _InfoPill(
                            icon: Icons.warning_amber_rounded,
                            label: issue,
                            accent: const Color(0xFFFFA630),
                            compact: compact || dense,
                          );
                        },
                      ),
                      FilledButton.icon(
                        key: const Key('refreshConnectionButton'),
                        onPressed:
                            refreshingConnection ? null : onRefreshConnection,
                        icon:
                            refreshingConnection
                                ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                )
                                : const Icon(Icons.refresh_rounded),
                        label: Text(
                          refreshingConnection
                              ? 'Refreshing…'
                              : 'Refresh Connection',
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity:
                              dense
                                  ? const VisualDensity(
                                    horizontal: -1,
                                    vertical: -2,
                                  )
                                  : VisualDensity.standard,
                          padding: EdgeInsets.symmetric(
                            horizontal: dense ? 12 : 16,
                            vertical: dense ? 10 : 12,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  }
}

class _SlotSelectorPill extends StatelessWidget {
  const _SlotSelectorPill({
    required this.currentSlot,
    required this.accent,
    required this.onSelect,
    required this.compact,
  });

  final int currentSlot;
  final Color accent;
  final Future<void> Function(LightChorusPart) onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parts = client.availableParts;
    final currentPart = client.partForSlot(currentSlot);
    final partLabel = currentPart?.label;
    final isUnassigned = currentSlot == 0;
    final pillLabel =
        isUnassigned
            ? 'Select part'
            : partLabel == null
            ? 'Slot $currentSlot'
            : '$partLabel · Slot $currentSlot';
    return PopupMenuButton<LightChorusPart>(
      onSelected: (part) => unawaited(onSelect(part)),
      color: Colors.black.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) {
        return parts.map((part) {
          final accentSlot = part.defaultSlot;
          final segments = <String>[part.label];
          segments.add('Slots ${part.slotSummary}');
          return PopupMenuItem<LightChorusPart>(
            value: part,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: kSlotOutlineColors[accentSlot] ?? Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(segments.join(' · ')),
              ],
            ),
          );
        }).toList();
      },
      child: _InfoPill(
        icon: Icons.apps_rounded,
        label: pillLabel,
        accent: accent,
        compact: compact,
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
    required this.compact,
    this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool compact;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final displayColor = muted ? Colors.white70 : Colors.white;
    final highlight = accent.withValues(alpha: muted ? 0.35 : 0.6);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 10,
      ),
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
          Icon(icon, size: compact ? 16 : 18, color: displayColor),
          SizedBox(width: compact ? 6 : 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: displayColor,
                fontSize: compact ? 13 : null,
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
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final Color activeColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final iconBackground =
        active
            ? activeColor.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.08);
    if (compact) {
      return _GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconBackground,
                boxShadow:
                    active
                        ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                        : null,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _GlassPanel(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        compact ? 16 : 24,
        compact ? 16 : 24,
        compact ? 18 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: compact ? 38 : 48,
            width: compact ? 38 : 48,
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
            child: Icon(icon, color: Colors.white, size: compact ? 20 : 24),
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            title,
            style: (compact ? textTheme.titleSmall : textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: compact ? 4 : 6),
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

String _generateDeviceId() {
  final random = math.Random.secure();
  const alphabet = '0123456789abcdef';
  String segment(int len) {
    final b = StringBuffer();
    for (var i = 0; i < len; i++) {
      b.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  return '${segment(8)}-${segment(4)}-4${segment(3)}-a${segment(3)}-${segment(12)}';
}

Future<String> _ensurePersistentDeviceId(SharedPreferences prefs) async {
  final existing = prefs.getString('deviceId')?.trim() ?? '';
  if (existing.isNotEmpty) {
    return existing;
  }
  final generated = _generateDeviceId();
  await prefs.setString('deviceId', generated);
  return generated;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapNative();
  final prefs = await SharedPreferences.getInstance();
  final deviceId = await _ensurePersistentDeviceId(prefs);
  client.setDeviceId(deviceId);
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

class _BootstrapState extends State<Bootstrap> with WidgetsBindingObserver {
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _showDebugOverlay = false;
  int _titleTapCount = 0;
  Timer? _tapResetTimer;
  bool _refreshingConnection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    flosc.OscListener.instance.start();
    unawaited(client.ensureEventRecipesLoaded());
    unawaited(_setAppScreenToMaximum());
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
    WidgetsBinding.instance.removeObserver(this);
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

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.audioVolumeUp) {
      unawaited(_updateBrightness(0.1));
    } else if (key == LogicalKeyboardKey.audioVolumeDown) {
      unawaited(_updateBrightness(-0.1));
    }
  }

  Future<void> _refreshConnection() async {
    if (_refreshingConnection) return;
    setState(() {
      _refreshingConnection = true;
    });
    try {
      await flosc.OscListener.instance.refreshConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-sent network hello to the console.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingConnection = false;
        });
      } else {
        _refreshingConnection = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      client.audioPlaying.value = false;
    }
  }

  Future<void> _handleAppResumed() async {
    await _setAppScreenToMaximum();
    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('[Lifecycle] Failed to reactivate AudioSession: $e');
    }
    try {
      await NativeAudio.ensureInitialized();
    } catch (e) {
      debugPrint('[Lifecycle] Native audio reinitialisation failed: $e');
    }
    try {
      await flosc.OscListener.instance.refreshConnection();
    } catch (e) {
      debugPrint('[Lifecycle] OSC refresh failed: $e');
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
      await flosc.OscListener.instance.setTorchLevel(clamped);
    } catch (e) {
      debugPrint('[UI] Torch level set failed: $e');
    }
  }

  Future<void> _updateBrightness(double delta) {
    final target = (client.brightness.value + delta).clamp(0.0, 1.0).toDouble();
    return _setBrightness(target);
  }

  Future<void> _handlePartSelected(LightChorusPart part) async {
    final currentSlot = client.myIndex.value;
    final nextSlot =
        client.partForSlot(currentSlot) == part
            ? currentSlot
            : part.defaultSlot;
    client.myIndex.value = nextSlot;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSlot', nextSlot);
    await prefs.setString('lastPart', part.name);
    try {
      await flosc.OscListener.instance.announcePresence();
    } catch (e) {
      debugPrint('[PartSelect] Failed to announce updated part: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform =
        Platform.isIOS
            ? 'iOS'
            : Platform.isAndroid
            ? 'Android'
            : 'Unknown';
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 760;
                      final dense = constraints.maxHeight < 700;
                      final gap = dense ? 8.0 : compact ? 10.0 : 12.0;
                      final statusHeight = dense ? 92.0 : compact ? 104.0 : 124.0;
                      final sliderHeight = dense ? 92.0 : compact ? 100.0 : 124.0;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderSection(
                            platform: platform,
                            compact: compact,
                            dense: dense,
                            onTitleTap: _handleTitleTap,
                            onPartSelected: _handlePartSelected,
                            onRefreshConnection:
                                () => unawaited(_refreshConnection()),
                            refreshingConnection: _refreshingConnection,
                          ),
                          SizedBox(height: gap),
                          SizedBox(
                            height: statusHeight,
                            child: ValueListenableBuilder<bool>(
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
                                            activeColor: const Color(
                                              0xFFFFD166,
                                            ),
                                            compact: compact || dense,
                                          ),
                                        ),
                                        SizedBox(width: dense ? 8 : 10),
                                        Expanded(
                                          child: _StatusTile(
                                            icon:
                                                playing
                                                    ? Icons.music_note_rounded
                                                    : Icons.music_off_rounded,
                                            title: 'Electronics',
                                            subtitle:
                                                playing
                                                    ? 'Clip playing'
                                                    : 'Standing by',
                                            active: playing,
                                            activeColor: const Color(
                                              0xFF06D6A0,
                                            ),
                                            compact: compact || dense,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          SizedBox(height: gap),
                          SizedBox(
                            height: sliderHeight,
                            child: ValueListenableBuilder<double>(
                              valueListenable: client.brightness,
                              builder: (context, brightness, _) {
                                final slotColor =
                                    kSlotOutlineColors[client.myIndex.value] ??
                                    Colors.white70;
                                return _GlassPanel(
                                  padding: EdgeInsets.fromLTRB(
                                    dense ? 12 : compact ? 14 : 20,
                                    dense ? 8 : compact ? 10 : 18,
                                    dense ? 12 : compact ? 14 : 20,
                                    dense ? 8 : compact ? 10 : 18,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Torch Level',
                                            style: (compact
                                                    ? Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                    : Theme.of(context)
                                                        .textTheme
                                                        .titleMedium)
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${(brightness * 100).round()}% torch · screen 100%',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontSize: dense ? 11 : null,
                                                  color: Colors.white70,
                                                ),
                                          ),
                                        ],
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: SliderTheme(
                                            data: SliderTheme.of(
                                              context,
                                            ).copyWith(
                                              activeTrackColor: slotColor,
                                              thumbColor: slotColor,
                                              overlayColor:
                                                  slotColor.withValues(
                                                    alpha: 0.12,
                                                  ),
                                              inactiveTrackColor:
                                                  Colors.white24,
                                            ),
                                            child: Slider(
                                              value: brightness.clamp(0.0, 1.0),
                                              min: 0.0,
                                              max: 1.0,
                                              onChanged: (value) {
                                                client.brightness.value = value;
                                              },
                                              onChangeEnd:
                                                  (value) => unawaited(
                                                    _setBrightness(value),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(height: gap),
                          Expanded(
                            child: PracticeEventStrip(
                              compact: compact,
                              dense: dense,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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
  const PracticeEventStrip({
    super.key,
    required this.compact,
    required this.dense,
  });

  final bool compact;
  final bool dense;

  @override
  State<PracticeEventStrip> createState() => _PracticeEventStripState();
}

class _PracticeEventStripState extends State<PracticeEventStrip> {
  final ScrollController _controller = ScrollController();

  double get _itemWidth => widget.dense ? 76.0 : widget.compact ? 84.0 : 92.0;
  double get _itemSpacing => widget.dense ? 8.0 : 12.0;

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

    final beforeWidth = i * (_itemWidth + _itemSpacing);
    final viewport = _controller.position.viewportDimension;
    final padding = math.max(0.0, (viewport - _itemWidth) / 2);
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
    final assignment = client.electronicsForSlot(event, slot);
    final lightingAssignment = client.lightingForSlot(event, slot);
    if (assignment != null) {
      try {
        await flosc.OscListener.instance.playLocalElectronicsPreview(
          assignment.sample,
          durationMs: assignment.durationMs,
        );
      } catch (e) {
        debugPrint('[Practice] electronics preview failed: $e');
      }
    }
    if (lightingAssignment != null) {
      await flosc.OscListener.instance.playLocalLightingPreview(
        lightingAssignment,
        eventId: event.id,
      );
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
                Text('Loading trigger points…'),
              ],
            ),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: client.practiceEventIndex,
          builder: (context, index, _) {
            final clampedIndex = index.clamp(0, events.length - 1);
            final slotForPreview = client.myIndex.value;
            final selectedPart = client.partForSlot(slotForPreview);
            final partAccent =
                kSlotOutlineColors[slotForPreview] ?? Colors.white70;
            final currentEvent = events[clampedIndex];
            final currentAssignment = client.electronicsForSlot(
              currentEvent,
              slotForPreview,
            );
            final currentLightingAssignment = client.lightingForSlot(
              currentEvent,
              slotForPreview,
            );
            final detailSummary =
                currentLightingAssignment?.summary ??
                currentEvent.lighting?.summary ??
                (currentAssignment == null
                    ? 'No cue assigned for this slot.'
                    : currentAssignment.sample.split('/').last);
            final compact = widget.compact;
            final dense = widget.dense;
            final detailChips = <String>[
              if (!dense)
                '${selectedPart?.label ?? 'Unassigned'} · Slot $slotForPreview',
              _routeLabel(currentAssignment),
              'Clip ${_durationLabel(currentAssignment?.durationMs)}',
              currentLightingAssignment == null
                  ? 'No torch cue'
                  : 'Torch ${_lightLabel(currentLightingAssignment.peakLevel)}',
            ];

            return _GlassPanel(
              padding: EdgeInsets.fromLTRB(
                dense ? 12 : compact ? 16 : 18,
                dense ? 12 : compact ? 14 : 18,
                dense ? 12 : compact ? 16 : 18,
                dense ? 12 : compact ? 14 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Trigger Practice',
                        style: (compact
                                ? Theme.of(context).textTheme.titleSmall
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '8 triggers',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: dense ? 11 : null,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: dense ? 4 : compact ? 6 : 8),
                  Text(
                    'TP ${currentEvent.id} · M${currentEvent.displayMeasureText} · ${_normalisedBeat(currentEvent.position ?? '')}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: dense ? 12 : null,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: dense ? 6 : compact ? 8 : 10),
                  Text(
                    detailSummary,
                    maxLines: dense ? 1 : compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: dense ? 11.5 : null,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: dense ? 6 : compact ? 8 : 10),
                  SizedBox(
                    height: dense ? 28 : 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: detailChips.length,
                      separatorBuilder:
                          (_, _) => SizedBox(width: dense ? 6 : 8),
                      itemBuilder:
                          (context, chipIndex) => _EventDetailChip(
                            label: detailChips[chipIndex],
                            compact: dense,
                          ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (dense) ...[
                        _PracticeNavButton(
                          icon: Icons.chevron_left_rounded,
                          onPressed:
                              clampedIndex > 0
                                  ? () => client.movePracticeEvent(-1)
                                  : null,
                        ),
                      ] else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                clampedIndex > 0
                                    ? () => client.movePracticeEvent(-1)
                                    : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: const Text('Prev'),
                          ),
                        ),
                      ],
                      SizedBox(width: dense ? 6 : 8),
                      Expanded(
                        flex: dense ? 1 : 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: Size.fromHeight(dense ? 40 : 48),
                            visualDensity:
                                dense
                                    ? const VisualDensity(
                                      horizontal: -1,
                                      vertical: -2,
                                    )
                                    : VisualDensity.standard,
                            padding: EdgeInsets.symmetric(
                              horizontal: dense ? 10 : 16,
                              vertical: dense ? 10 : 14,
                            ),
                          ),
                          onPressed:
                              () => unawaited(
                                _handlePlayRequest(events, clampedIndex),
                              ),
                          icon: Icon(
                            Icons.play_arrow_rounded,
                            size: dense ? 20 : 24,
                          ),
                          label: Text(
                            currentAssignment != null ||
                                    currentLightingAssignment != null
                                ? 'Play Cue'
                                : 'Advance',
                          ),
                        ),
                      ),
                      SizedBox(width: dense ? 6 : 8),
                      if (dense) ...[
                        _PracticeNavButton(
                          icon: Icons.chevron_right_rounded,
                          onPressed:
                              clampedIndex < events.length - 1
                                  ? () => client.movePracticeEvent(1)
                                  : null,
                        ),
                      ] else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                clampedIndex < events.length - 1
                                    ? () => client.movePracticeEvent(1)
                                    : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('Next'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: dense ? 8 : compact ? 10 : 12),
                  SizedBox(
                    height: dense ? 50 : compact ? 58 : 64,
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: events.length,
                      separatorBuilder:
                          (_, _) => SizedBox(width: _itemSpacing),
                      itemBuilder: (context, i) {
                        final event = events[i];
                        final isCurrent = i == clampedIndex;
                        return _PracticeTriggerChip(
                          event: event,
                          isCurrent: isCurrent,
                          accent: partAccent,
                          dense: dense,
                          onTap: () => client.setPracticeEventIndex(i),
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

class _PracticeNavButton extends StatelessWidget {
  const _PracticeNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

String _routeLabel(ElectronicsAssignment? assignment) {
  switch (assignment?.channelMode) {
    case 'left':
      return 'Left channel';
    case 'right':
      return 'Right channel';
    case 'mono_sum':
      return 'Mono sum';
    default:
      return 'No route';
  }
}

String _durationLabel(double? durationMs) {
  if (durationMs == null) {
    return '—';
  }
  return '${(durationMs / 1000).toStringAsFixed(1)}s';
}

String _lightLabel(double? peakLevel) {
  if (peakLevel == null) {
    return '—';
  }
  return '${(peakLevel * 100).round()}%';
}

class _PracticeTriggerChip extends StatelessWidget {
  const _PracticeTriggerChip({
    required this.event,
    required this.isCurrent,
    required this.accent,
    required this.dense,
    required this.onTap,
  });

  final EventRecipe event;
  final bool isCurrent;
  final Color accent;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: dense ? 76 : 92,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 6 : 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              isCurrent
                  ? accent.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color:
                isCurrent
                    ? accent.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'TP ${event.id}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: dense ? 12 : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'M${event.displayMeasureText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: dense ? 10.5 : null,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventDetailChip extends StatelessWidget {
  const _EventDetailChip({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontSize: compact ? 11 : null),
      ),
    );
  }
}

String _normalisedBeat(String rawPosition) {
  if (rawPosition.isEmpty) {
    return '—';
  }
  final beatMatch = RegExp(
    r'beat\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(rawPosition);
  if (beatMatch != null) {
    return 'Beat ${beatMatch.group(1)}';
  }
  final match = RegExp(r'(\d+)').firstMatch(rawPosition);
  if (match != null) {
    return 'Beat ${match.group(1)}';
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
              ValueListenableBuilder<String>(
                valueListenable: client.deviceId,
                builder:
                    (context, deviceId, _) => Text(
                      'Device ID: $deviceId',
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
                      'Torch level: ${brightness.toStringAsFixed(2)}',
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
              FutureBuilder<Map<String, dynamic>?>(
                future: NativeAudio.diagnostics(),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  final players = data?['electronicsPlayers'];
                  final assetKey = data?['lastElectronicsAssetKey'];
                  final lastError = data?['lastElectronicsError'];
                  final resolvedPath = data?['lastElectronicsResolvedPath'];
                  return Text(
                    'Electronics: players=${players ?? 'n/a'} · asset=${assetKey ?? 'none'} · '
                    'error=${lastError ?? 'none'}${resolvedPath == null ? '' : '\\nResolved path: $resolvedPath'}',
                    style: TextStyle(
                      color:
                          lastError == null || lastError == 'null'
                              ? Colors.white70
                              : Colors.redAccent,
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
              Builder(
                builder: (context) {
                  final snapshot =
                      flosc.OscListener.instance.networkDiagnosticsSnapshot();
                  final trustedIp = snapshot['trustedConductorIp'] as String?;
                  final showSessionId = snapshot['showSessionId'] as String?;
                  final protocolVersion = snapshot['protocolVersion'];
                  final cueRoutingIssue =
                      snapshot['cueRoutingIssue'] as String?;
                  final currentSlot = snapshot['currentSlot'];
                  final activeLightingEventId =
                      snapshot['activeLightingEventId'];
                  final activeLightingPart =
                      snapshot['activeLightingPart'] as String?;
                  final activeLightingSummary =
                      snapshot['activeLightingSummary'] as String?;
                  final unknown = snapshot['unknownSenderCount'];
                  final duplicates = snapshot['duplicatesDropped'];
                  final outOfOrder = snapshot['outOfOrderDropped'];
                  final mismatches = snapshot['protocolMismatchCount'];
                  final slotMismatches = snapshot['slotMismatchCount'];
                  final lastAcceptedCueAddress =
                      snapshot['lastAcceptedCueAddress'] as String?;
                  return Text(
                    'Trusted: ${trustedIp ?? 'none'} · Session: ${showSessionId ?? 'none'} · v$protocolVersion\\n'
                    'Slot: $currentSlot · Cue routing: ${cueRoutingIssue ?? 'ok'}\\n'
                    'Active light cue: ${activeLightingEventId == null ? 'none' : 'TP$activeLightingEventId'}'
                    '${activeLightingPart == null ? '' : ' · $activeLightingPart'}'
                    '${activeLightingSummary == null ? '' : '\\n$activeLightingSummary'}\\n'
                    'Unknown senders: $unknown · Duplicates dropped: $duplicates · '
                    'Out-of-order dropped: $outOfOrder · Protocol mismatches: $mismatches · '
                    'Slot mismatches: $slotMismatches\\n'
                    'Last accepted cue: ${lastAcceptedCueAddress ?? 'none'}',
                    style: const TextStyle(color: Colors.white70),
                  );
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onSendHello,
                child: const Text('Send /hello'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final logJson =
                      flosc.OscListener.instance.exportNetworkLogJson();
                  await Clipboard.setData(ClipboardData(text: logJson));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Network log copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: const Text('Copy Network Log'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recent Network Events',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: Builder(
                  builder: (context) {
                    final snapshot =
                        flosc.OscListener.instance.networkDiagnosticsSnapshot();
                    final rawEvents =
                        (snapshot['events'] as List<dynamic>? ??
                                const <dynamic>[])
                            .cast<Map<String, dynamic>>();
                    if (rawEvents.isEmpty) {
                      return const Center(
                        child: Text(
                          'No network events yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    final events = rawEvents.reversed.take(20).toList();
                    return ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final category = event['category'] ?? 'event';
                        final message = event['message'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            '[$category] $message',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    );
                  },
                ),
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
