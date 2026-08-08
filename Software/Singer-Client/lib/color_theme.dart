import 'package:flutter/material.dart';

/// Slot outline colors matching the macOS console view.
class SlotColors {
  static const royalBlue = Color(0xFF0800F0);
  static const brightRed = Color(0xFFF00800);
  static const slotGreen = Color(0xFF29F000);
  static const slotPurple = Color(0xFF6E00F0);
  static const slotYellow = Color(0xFFF0AD00);
  static const lightRose = Color(0xFFFFB8D9);
  static const slotOrange = Color(0xFFF05100);
  static const hotMagenta = Color(0xFFFF00D7);
  static const skyBlue = Color(0xFF9EE4FF);
}

/// Mapping from real slot number to its outline color.
const Map<int, Color> kSlotOutlineColors = {
  1: SlotColors.slotGreen,
  2: SlotColors.slotGreen,
  3: SlotColors.slotGreen,
  4: SlotColors.slotGreen,
  5: SlotColors.slotGreen,
  6: SlotColors.slotGreen,
  7: SlotColors.hotMagenta,
  8: SlotColors.hotMagenta,
  9: SlotColors.hotMagenta,
  10: SlotColors.hotMagenta,
  11: SlotColors.hotMagenta,
  12: SlotColors.hotMagenta,
  13: SlotColors.slotYellow,
  14: SlotColors.slotYellow,
  15: SlotColors.slotYellow,
  16: SlotColors.slotYellow,
  17: SlotColors.slotYellow,
  18: SlotColors.slotYellow,
  19: SlotColors.lightRose,
  20: SlotColors.lightRose,
  21: SlotColors.lightRose,
  22: SlotColors.lightRose,
  23: SlotColors.lightRose,
  24: SlotColors.lightRose,
  25: SlotColors.brightRed,
  26: SlotColors.brightRed,
  27: SlotColors.brightRed,
  28: SlotColors.brightRed,
  29: SlotColors.brightRed,
  30: SlotColors.brightRed,
  31: SlotColors.royalBlue,
  32: SlotColors.royalBlue,
  33: SlotColors.royalBlue,
  34: SlotColors.royalBlue,
  35: SlotColors.royalBlue,
  36: SlotColors.royalBlue,
};
