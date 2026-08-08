import 'package:flutter/foundation.dart';

import 'package:flashlights_client/model/event_recipe.dart';
import 'package:flashlights_client/model/show_profile.dart';
import 'package:flashlights_client/network/osc_packet.dart';

class PrimerColorPlacement {
  const PrimerColorPlacement({required this.partLabel, required this.slots});

  final String partLabel;
  final List<int> slots;
}

class LightChorusSeat {
  const LightChorusSeat({
    required this.part,
    required this.seatNumber,
    required this.slot,
  });

  final LightChorusPart part;
  final int seatNumber;
  final int slot;

  String get label => '${part.label} · Seat $seatNumber';
}

enum LightChorusPart { sopranoL1, sopranoL2, tenorL, bassL, altoL2, altoL1 }

extension LightChorusPartDisplay on LightChorusPart {
  String get label {
    switch (this) {
      case LightChorusPart.sopranoL1:
        return 'Sop-L1';
      case LightChorusPart.sopranoL2:
        return 'Sop-L2';
      case LightChorusPart.tenorL:
        return 'Ten-L';
      case LightChorusPart.bassL:
        return 'Bass-L';
      case LightChorusPart.altoL2:
        return 'Alto-L2';
      case LightChorusPart.altoL1:
        return 'Alto-L1';
    }
  }

  int get defaultSlot {
    switch (this) {
      case LightChorusPart.sopranoL1:
        return 1;
      case LightChorusPart.sopranoL2:
        return 7;
      case LightChorusPart.tenorL:
        return 13;
      case LightChorusPart.bassL:
        return 19;
      case LightChorusPart.altoL2:
        return 25;
      case LightChorusPart.altoL1:
        return 31;
    }
  }

  List<int> get slots {
    switch (this) {
      case LightChorusPart.sopranoL1:
        return const <int>[1, 2, 3, 4, 5, 6];
      case LightChorusPart.sopranoL2:
        return const <int>[7, 8, 9, 10, 11, 12];
      case LightChorusPart.tenorL:
        return const <int>[13, 14, 15, 16, 17, 18];
      case LightChorusPart.bassL:
        return const <int>[19, 20, 21, 22, 23, 24];
      case LightChorusPart.altoL2:
        return const <int>[25, 26, 27, 28, 29, 30];
      case LightChorusPart.altoL1:
        return const <int>[31, 32, 33, 34, 35, 36];
    }
  }

  List<LightChorusSeat> get seats =>
      List<LightChorusSeat>.generate(slots.length, (index) {
        return LightChorusSeat(
          part: this,
          seatNumber: index + 1,
          slot: slots[index],
        );
      });

  String get recipeKey {
    switch (this) {
      case LightChorusPart.sopranoL1:
        return 'soprano_l1';
      case LightChorusPart.sopranoL2:
        return 'soprano_l2';
      case LightChorusPart.tenorL:
        return 'tenor_l';
      case LightChorusPart.bassL:
        return 'bass_l';
      case LightChorusPart.altoL2:
        return 'alto_l2';
      case LightChorusPart.altoL1:
        return 'alto_l1';
    }
  }
}

const Map<PrimerColor, PrimerColorPlacement> kPrimerColorPlacements = {
  PrimerColor.blue: PrimerColorPlacement(
    partLabel: 'Alto-L1',
    slots: [31, 32, 33, 34],
  ),
  PrimerColor.red: PrimerColorPlacement(
    partLabel: 'Alto-L2',
    slots: [25, 26, 27, 28],
  ),
  PrimerColor.green: PrimerColorPlacement(
    partLabel: 'Sop-L1',
    slots: [1, 2, 3, 4],
  ),
  PrimerColor.purple: PrimerColorPlacement(
    partLabel: 'Bass-L',
    slots: [19, 20, 21, 22],
  ),
  PrimerColor.yellow: PrimerColorPlacement(
    partLabel: 'Ten-L',
    slots: [13, 14, 15, 16],
  ),
  PrimerColor.pink: PrimerColorPlacement(
    partLabel: 'Ten/Bass Bridge',
    slots: [17, 18, 23, 24],
  ),
  PrimerColor.orange: PrimerColorPlacement(
    partLabel: 'Upper Chorus Bridge',
    slots: [5, 6, 11, 12],
  ),
  PrimerColor.magenta: PrimerColorPlacement(
    partLabel: 'Sop-L2',
    slots: [7, 8, 9, 10],
  ),
  PrimerColor.cyan: PrimerColorPlacement(
    partLabel: 'Alto Bridge',
    slots: [29, 30, 35, 36],
  ),
};

/// Global client state, holds the dynamic slot and clock offset.
class ClientState {
  ClientState()
    : myIndex = ValueNotifier<int>(_normalizedInitialSlot),
      myColor = ValueNotifier<PrimerColor?>(
        _slotColorMap[_normalizedInitialSlot],
      ),
      deviceId = ValueNotifier<String>('unknown'),
      clockOffsetMs = ValueNotifier<double>(0.0),
      cueRoutingIssue = ValueNotifier<String?>(null),
      flashOn = ValueNotifier<bool>(false),
      audioPlaying = ValueNotifier<bool>(false),
      recording = ValueNotifier<bool>(false),
      brightness = ValueNotifier<double>(0.0),
      recentMessages = ValueNotifier<List<OSCMessage>>(<OSCMessage>[]),
      eventRecipes = ValueNotifier<List<EventRecipe>>(<EventRecipe>[]),
      showProfiles = ValueNotifier<ShowProfileManifest?>(null),
      practiceEventIndex = ValueNotifier<int>(0) {
    myIndex.addListener(() {
      final slot = myIndex.value;
      myColor.value = colorForSlot(slot);
    });
  }

  /// Singer slot (uses the real slot number). Notifier so UI can react to changes at runtime.
  final ValueNotifier<int> myIndex;

  /// Convenience notifier for the currently selected colour group.
  final ValueNotifier<PrimerColor?> myColor;

  /// Persistent app-generated device identity used at runtime.
  final ValueNotifier<String> deviceId;

  /// Rolling average clock offset from /sync (ms).
  final ValueNotifier<double> clockOffsetMs;

  /// Non-null when incoming cues are being rejected for routing/session reasons.
  final ValueNotifier<String?> cueRoutingIssue;

  /// Whether the flashlight is currently on.
  final ValueNotifier<bool> flashOn;

  /// Current torch brightness (0–1).
  final ValueNotifier<double> brightness;

  /// Whether audio is currently playing.
  final ValueNotifier<bool> audioPlaying;

  /// Whether the microphone is currently recording.
  final ValueNotifier<bool> recording;

  /// Whether the client is connected to the server.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Most recent OSC messages (capped at 10 entries).
  final ValueNotifier<List<OSCMessage>> recentMessages;

  /// Cached list of trigger-point recipes used for local practice browsing.
  final ValueNotifier<List<EventRecipe>> eventRecipes;

  /// Profile metadata for the currently bundled runtime.
  final ValueNotifier<ShowProfileManifest?> showProfiles;

  /// Current event index highlighted in the practice strip.
  final ValueNotifier<int> practiceEventIndex;

  static const Map<PrimerColor, List<int>> defaultGroups = {
    PrimerColor.blue: [31, 32, 33, 34],
    PrimerColor.red: [25, 26, 27, 28],
    PrimerColor.green: [1, 2, 3, 4],
    PrimerColor.purple: [19, 20, 21, 22],
    PrimerColor.yellow: [13, 14, 15, 16],
    PrimerColor.pink: [17, 18, 23, 24],
    PrimerColor.orange: [5, 6, 11, 12],
    PrimerColor.magenta: [7, 8, 9, 10],
    PrimerColor.cyan: [29, 30, 35, 36],
  };

  static const int _initialSlot = int.fromEnvironment('SLOT', defaultValue: 1);

  // One source of truth for the expected live-performance slots.
  static const List<int> performanceSlots = <int>[
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
  ];
  static final int _normalizedInitialSlot =
      performanceSlots.contains(_initialSlot)
          ? _initialSlot
          : performanceSlots.first;

  static Map<int, PrimerColor> _buildSlotColorMap() {
    final slots = <int, PrimerColor>{};
    for (final entry in defaultGroups.entries) {
      for (final slot in entry.value) {
        slots[slot] = entry.key;
      }
    }
    return Map.unmodifiable(slots);
  }

  static List<int> _buildAvailableSlots() {
    final ordered = performanceSlots.toList()..sort();
    return List.unmodifiable(ordered);
  }

  static final Map<int, PrimerColor> _slotColorMap = _buildSlotColorMap();
  static final List<int> _availableSlots = _buildAvailableSlots();
  static const List<LightChorusPart> _availableParts = <LightChorusPart>[
    LightChorusPart.sopranoL1,
    LightChorusPart.sopranoL2,
    LightChorusPart.tenorL,
    LightChorusPart.bassL,
    LightChorusPart.altoL2,
    LightChorusPart.altoL1,
  ];
  static final List<LightChorusSeat> _availableSeats = _availableParts
      .expand((part) => part.seats)
      .toList(growable: false);
  static final Map<int, LightChorusSeat> _seatBySlot =
      Map<int, LightChorusSeat>.unmodifiable(<int, LightChorusSeat>{
        for (final seat in _availableSeats) seat.slot: seat,
      });

  /// Public accessor for known seating slots.
  List<int> get availableSlots => _availableSlots;
  List<LightChorusSeat> get availableSeats => _availableSeats;
  List<LightChorusPart> get availableParts => _availableParts;

  PrimerColor? colorForSlot(int slot) => _slotColorMap[slot];

  LightChorusSeat? seatForSlot(int slot) => _seatBySlot[slot];

  bool isAvailableSlot(int slot) => _seatBySlot.containsKey(slot);

  LightChorusPart? partForSlot(int slot) {
    return seatForSlot(slot)?.part;
  }

  PrimerColorPlacement? practicePlacementForColor(PrimerColor color) =>
      kPrimerColorPlacements[color];

  List<int> practiceSlotsForColor(PrimerColor color) {
    final placement = kPrimerColorPlacements[color];
    if (placement == null) {
      return const [];
    }
    return List<int>.unmodifiable(placement.slots);
  }

  String? practicePartLabelForColor(PrimerColor color) =>
      kPrimerColorPlacements[color]?.partLabel;

  int? practiceSlotNumberForSlot(int slot) {
    return seatForSlot(slot)?.slot;
  }

  PrimerColor? colorForGroupIndex(int index) {
    if (index < 1 || index > PrimerColor.values.length) {
      return null;
    }
    return PrimerColor.values[index - 1];
  }

  Future<void> ensureEventRecipesLoaded() async {
    if (eventRecipes.value.isNotEmpty) return;
    final recipes = await loadEventRecipesAsset();
    eventRecipes.value = recipes;
    if (practiceEventIndex.value >= recipes.length) {
      practiceEventIndex.value = 0;
    }
  }

  Future<void> ensureShowProfilesLoaded() async {
    if (showProfiles.value != null) return;
    showProfiles.value = await loadShowProfileManifestAsset();
  }

  PrimerAssignment? assignmentForSlot(EventRecipe event, int slot) {
    final color = colorForSlot(slot);
    if (color != null) {
      return event.primerAssignments[color];
    }
    return null;
  }

  ChoirFamily? choirFamilyForSlot(int slot) {
    final part = partForSlot(slot);
    if (part == null) {
      return null;
    }
    switch (part) {
      case LightChorusPart.sopranoL1:
      case LightChorusPart.sopranoL2:
        return ChoirFamily.soprano;
      case LightChorusPart.altoL2:
      case LightChorusPart.altoL1:
        return ChoirFamily.alto;
      case LightChorusPart.tenorL:
      case LightChorusPart.bassL:
        return ChoirFamily.tenorBass;
    }
  }

  ElectronicsAssignment? electronicsForSlot(EventRecipe event, int slot) {
    final part = partForSlot(slot);
    if (part != null) {
      final partSpecific = event.electronicsByPart[part.recipeKey];
      if (partSpecific != null) {
        return partSpecific;
      }
    }
    final family = choirFamilyForSlot(slot);
    if (family == null) {
      return null;
    }
    return event.electronicsAssignments[family];
  }

  LightingAssignment? lightingForSlot(EventRecipe event, int slot) {
    final part = partForSlot(slot);
    if (part == null) {
      return null;
    }
    return event.lighting?.parts[part.recipeKey];
  }

  bool shouldHandleIndex(int messageIndex, {int? slotOverride}) {
    final slot = slotOverride ?? myIndex.value;
    return messageIndex == slot;
  }

  void movePracticeEvent(int delta) {
    final events = eventRecipes.value;
    if (events.isEmpty) return;
    final nextIndex = (practiceEventIndex.value + delta).clamp(
      0,
      events.length - 1,
    );
    practiceEventIndex.value = nextIndex;
  }

  void setPracticeEventIndex(int index) {
    final events = eventRecipes.value;
    if (events.isEmpty) return;
    final nextIndex = index.clamp(0, events.length - 1);
    practiceEventIndex.value = nextIndex;
  }

  EventRecipe? practiceEventAt(int index) {
    final events = eventRecipes.value;
    if (index < 0 || index >= events.length) return null;
    return events[index];
  }

  void setDeviceId(String id) {
    if (id.trim().isEmpty) return;
    deviceId.value = id.trim();
  }
}

/// Singleton client state
final client = ClientState();
