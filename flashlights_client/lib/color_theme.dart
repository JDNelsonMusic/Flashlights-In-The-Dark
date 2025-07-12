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
  27: SlotColors.royalBlue,
  41: SlotColors.royalBlue,
  42: SlotColors.royalBlue,
  1: SlotColors.brightRed,
  14: SlotColors.brightRed,
  15: SlotColors.brightRed,
  16: SlotColors.slotGreen,
  29: SlotColors.slotGreen,
  44: SlotColors.slotGreen,
  3: SlotColors.slotPurple,
  4: SlotColors.slotPurple,
  18: SlotColors.slotPurple,
  7: SlotColors.slotYellow,
  19: SlotColors.slotYellow,
  34: SlotColors.slotYellow,
  9: SlotColors.lightRose,
  20: SlotColors.lightRose,
  21: SlotColors.lightRose,
  23: SlotColors.slotOrange,
  38: SlotColors.slotOrange,
  51: SlotColors.slotOrange,
  12: SlotColors.hotMagenta,
  24: SlotColors.hotMagenta,
  25: SlotColors.hotMagenta,
  40: SlotColors.skyBlue,
  53: SlotColors.skyBlue,
  54: SlotColors.skyBlue,
  5: Colors.white,
};
