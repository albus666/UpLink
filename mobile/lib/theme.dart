import 'package:flutter/material.dart';

class PilotColors {
  static const bg = Color(0xFF0B0E13);
  static const surface = Color(0xFF141A22);
  static const card = Color(0xFF1B2330);
  static const line = Color(0xFF2A3342);
  static const text = Color(0xFFE8EEF6);
  static const muted = Color(0xFF93A0B3);
  static const accent = Color(0xFFF0B429);
  static const accentDim = Color(0xFF3A2F12);
  static const userBubble = Color(0xFF3B3354);
  static const good = Color(0xFF3DDC97);
  static const goodDim = Color(0xFF163528);
  static const bad = Color(0xFFFF6B6B);
  static const info = Color(0xFF7C9CFF);
  static const selected = Color(0xFF1C3354);
}

ThemeData buildPilotTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: PilotColors.accent,
      onPrimary: Color(0xFF1A1400),
      surface: PilotColors.surface,
      onSurface: PilotColors.text,
    ),
    scaffoldBackgroundColor: PilotColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: PilotColors.bg,
      foregroundColor: PilotColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: PilotColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PilotColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PilotColors.surface,
      hintStyle: const TextStyle(color: PilotColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PilotColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PilotColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PilotColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PilotColors.accent,
        foregroundColor: const Color(0xFF1A1400),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: PilotColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      textStyle: const TextStyle(color: PilotColors.text, fontSize: 13, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PilotColors.line),
      ),
    ),
  );
}
