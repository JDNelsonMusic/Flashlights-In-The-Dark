import 'package:flutter/foundation.dart';

import 'package:flashlights_client/model/event_recipe.dart';
import 'package:flashlights_client/model/show_profile.dart';
import 'package:flashlights_client/network/osc_packet.dart';

class PrimerColorPlacement {
  const PrimerColorPlacement({required this.partLabel, required this.slots});

  final String partLabel;
  final List<int> slots;
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
        return 16;
      case LightChorusPart.sopranoL2:
        return 12;
      case LightChorusPart.tenorL:
        return 7;
      case LightChorusPart.bassL:
        return 9;
      case LightChorusPart.altoL2:
        return 1;
      case LightChorusPart.altoL1:
        return 27;
    }
  }

  List<int> get slots {
    switch (this) {
      case LightChorusPart.sopranoL1:
        return const <int>[16, 29, 44];
      case LightChorusPart.sopranoL2:
        return const <int>[12, 24, 25, 23, 38, 51];
      case LightChorusPart.tenorL:
        return const <int>[7, 19, 34];
      case LightChorusPart.bassL:
        return const <int>[9, 20, 21, 3, 4, 18];
      case LightChorusPart.altoL2:
        return const <int>[1, 14, 15, 40, 53, 54];
      case LightChorusPart.altoL1:
        return const <int>[27, 41, 42];
    }
  }

  String get slotSummary => slots.join(' · ');

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
  PrimerColor.green: PrimerColorPlacement(
    partLabel: 'Sop-L1',
    slots: [16, 29, 44],
  ),
  PrimerColor.magenta: PrimerColorPlacement(
    partLabel: 'Sop-L2',
    slots: [12, 24, 25],
  ),
  PrimerColor.orange: PrimerColorPlacement(
    partLabel: 'Sop-L2',
    slots: [23, 38, 51],
  ),
  PrimerColor.blue: PrimerColorPlacement(
    partLabel: 'Alto-L1',
    slots: [27, 41, 42],
  ),
  PrimerColor.red: PrimerColorPlacement(
    partLabel: 'Alto-L2',
    slots: [1, 14, 15],
  ),
  PrimerColor.cyan: PrimerColorPlacement(
    partLabel: 'Alto-L2',
    slots: [40, 53, 54],
  ),
  PrimerColor.yellow: PrimerColorPlacement(
    partLabel: 'Ten-L',
    slots: [7, 19, 34],
  ),
  PrimerColor.pink: PrimerColorPlacement(
    partLabel: 'Bass-L',
    slots: [9, 20, 21],
  ),
  PrimerColor.purple: PrimerColorPlacement(
    partLabel: 'Bass-L',
    slots: [3, 4, 18],
  ),
};

/// Global client state, holds the dynamic slot and clock offset.
class ClientState {
  ClientState()
    : myIndex = ValueNotifier<int>(_initialSlot),
      myColor = ValueNotifier<PrimerColor?>(_slotColorMap[_initialSlot]),
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
    PrimerColor.blue: [27, 41, 42],
    PrimerColor.red: [1, 14, 15],
    PrimerColor.green: [16, 29, 44],
    PrimerColor.purple: [3, 4, 18],
    PrimerColor.yellow: [7, 19, 34],
    PrimerColor.pink: [9, 20, 21],
    PrimerColor.orange: [23, 38, 51],
    PrimerColor.magenta: [12, 24, 25],
    PrimerColor.cyan: [40, 53, 54],
  };

  static const int _initialSlot = int.fromEnvironment('SLOT', defaultValue: 1);

  // One source of truth for the expected live-performance slots.
  static const List<int> performanceSlots = <int>[
    1,
    3,
    4,
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
  ];

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

  /// Public accessor for known seating slots.
  List<int> get availableSlots => _availableSlots;
  List<LightChorusPart> get availableParts => _availableParts;

  PrimerColor? colorForSlot(int slot) => _slotColorMap[slot];

  LightChorusPart? partForSlot(int slot) {
    final color = colorForSlot(slot);
    if (color == null) {
      return null;
    }
    switch (color) {
      case PrimerColor.green:
        return LightChorusPart.sopranoL1;
      case PrimerColor.magenta:
      case PrimerColor.orange:
        return LightChorusPart.sopranoL2;
      case PrimerColor.yellow:
        return LightChorusPart.tenorL;
      case PrimerColor.pink:
      case PrimerColor.purple:
        return LightChorusPart.bassL;
      case PrimerColor.red:
      case PrimerColor.cyan:
        return LightChorusPart.altoL2;
      case PrimerColor.blue:
        return LightChorusPart.altoL1;
    }
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
    final color = colorForSlot(slot);
    if (color == null) {
      return null;
    }
    final groupSlots = defaultGroups[color];
    if (groupSlots == null) {
      return null;
    }
    final index = groupSlots.indexOf(slot);
    if (index == -1) {
      return null;
    }
    return (color.groupIndex - 1) * 3 + index + 1;
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
    final color = colorForSlot(slot);
    if (color == null) {
      return null;
    }
    switch (color) {
      case PrimerColor.green:
      case PrimerColor.magenta:
      case PrimerColor.orange:
        return ChoirFamily.soprano;
      case PrimerColor.blue:
      case PrimerColor.red:
      case PrimerColor.cyan:
        return ChoirFamily.alto;
      case PrimerColor.yellow:
      case PrimerColor.pink:
      case PrimerColor.purple:
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
