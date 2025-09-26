import 'package:flutter/foundation.dart';

import 'package:flashlights_client/model/event_recipe.dart';
import 'package:flashlights_client/network/osc_packet.dart';

class PrimerColorPlacement {
  const PrimerColorPlacement({required this.staffIndex, required this.slots});

  final int staffIndex;
  final List<int> slots;
}

const Map<PrimerColor, PrimerColorPlacement> kPrimerColorPlacements = {
  PrimerColor.green: PrimerColorPlacement(staffIndex: 4, slots: [16, 29, 44]),
  PrimerColor.magenta: PrimerColorPlacement(staffIndex: 5, slots: [12, 24, 25]),
  PrimerColor.orange: PrimerColorPlacement(staffIndex: 6, slots: [23, 38, 51]),
  PrimerColor.blue: PrimerColorPlacement(staffIndex: 7, slots: [27, 41, 42]),
  PrimerColor.red: PrimerColorPlacement(staffIndex: 8, slots: [1, 14, 15]),
  PrimerColor.cyan: PrimerColorPlacement(staffIndex: 9, slots: [40, 53, 54]),
  PrimerColor.yellow: PrimerColorPlacement(staffIndex: 10, slots: [7, 19, 34]),
  PrimerColor.pink: PrimerColorPlacement(staffIndex: 11, slots: [9, 20, 21]),
  PrimerColor.purple: PrimerColorPlacement(staffIndex: 12, slots: [3, 4, 18]),
};

/// Global client state, holds the dynamic slot and clock offset.
class ClientState {
  ClientState()
    : myIndex = ValueNotifier<int>(_initialSlot),
      myColor = ValueNotifier<PrimerColor?>(_slotColorMap[_initialSlot]),
      udid = const String.fromEnvironment('UDID', defaultValue: 'unknown'),
      clockOffsetMs = ValueNotifier<double>(0.0),
      flashOn = ValueNotifier<bool>(false),
      audioPlaying = ValueNotifier<bool>(false),
      recording = ValueNotifier<bool>(false),
      brightness = ValueNotifier<double>(0.0),
      recentMessages = ValueNotifier<List<OSCMessage>>(<OSCMessage>[]),
      eventRecipes = ValueNotifier<List<EventRecipe>>(<EventRecipe>[]),
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

  /// Unique device identifier used for slot verification.
  final String udid;

  /// Rolling average clock offset from /sync (ms).
  final ValueNotifier<double> clockOffsetMs;

  /// Whether the flashlight is currently on.
  final ValueNotifier<bool> flashOn;

  /// Current screen brightness (0–1).
  final ValueNotifier<double> brightness;

  /// Whether audio is currently playing.
  final ValueNotifier<bool> audioPlaying;

  /// Whether the microphone is currently recording.
  final ValueNotifier<bool> recording;

  /// Whether the client is connected to the server.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Most recent OSC messages (capped at 10 entries).
  final ValueNotifier<List<OSCMessage>> recentMessages;

  /// Cached list of 192 event recipes used for practice browsing.
  final ValueNotifier<List<EventRecipe>> eventRecipes;

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
    final slotSet = <int>{};
    for (final slots in defaultGroups.values) {
      slotSet.addAll(slots);
    }
    final ordered = slotSet.toList()..sort();
    return List.unmodifiable(ordered);
  }

  static final Map<int, PrimerColor> _slotColorMap = _buildSlotColorMap();
  static final List<int> _availableSlots = _buildAvailableSlots();

  /// Public accessor for known seating slots.
  List<int> get availableSlots => _availableSlots;

  PrimerColor? colorForSlot(int slot) => _slotColorMap[slot];

  PrimerColorPlacement? practicePlacementForColor(PrimerColor color) =>
      kPrimerColorPlacements[color];

  List<int> practiceSlotsForColor(PrimerColor color) {
    final placement = kPrimerColorPlacements[color];
    if (placement == null) {
      return const [];
    }
    return List<int>.unmodifiable(placement.slots);
  }

  int? practiceStaffIndexForColor(PrimerColor color) =>
      kPrimerColorPlacements[color]?.staffIndex;

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

  PrimerAssignment? assignmentForSlot(EventRecipe event, int slot) {
    final color = colorForSlot(slot);
    if (color != null) {
      return event.primerAssignments[color];
    }
    return null;
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
}

/// Singleton client state
final client = ClientState();
