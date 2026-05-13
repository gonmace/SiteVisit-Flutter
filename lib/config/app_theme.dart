import 'package:flutter/material.dart';

class AppTheme {
  // ── Paleta — espejo exacto de la DaisyUI "dark" del backend Django ──────────
  static const primary   = Color(0xFFFF3B30); // --color-primary
  static const secondary = Color(0xFF8E8E93); // --color-secondary
  static const accent    = Color(0xFF818CF8); // --color-accent
  static const neutral   = Color(0xFF636366); // --color-neutral
  static const success   = Color(0xFF34D399); // --color-success
  static const error     = Color(0xFFF87171); // --color-error
  static const warning   = Color(0xFFFBBF24); // --color-warning
  static const info      = Color(0xFF38BDF8); // --color-info
  static const edit      = Color(0xFFFACC15); // --color-edit
  static const delete    = Color(0xFFFB923C); // --color-delete
  static const view      = Color(0xFF60A5FA); // --color-view

  // ── Colores semánticos light ────────────────────────────────────────────────
  static const textPrimary     = Color(0xFF1C1C1E);
  static const textSecondary   = Color(0xFF8E8E93);
  static const textPlaceholder = Color(0xFFC7C7CC);
  static const separator       = Color(0xFFE5E5EA);

  // ── Helpers adaptativos (llamar en build()) ────────────────────────────────
  // base-100 / base-200 / base-300 de DaisyUI para dark mode
  static Color bg(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFF1C1C1E) // base-100
      : const Color(0xFFF2F2F7);
  static Color surf(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFF2C2C2E) // base-200
      : const Color(0xFFFFFFFF);
  static Color surfSec(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFF3A3A3C) // base-300
      : const Color(0xFFF2F2F7);
  static Color text(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFFF2F2F7) // base-content
      : const Color(0xFF1C1C1E);
  static Color textSec(BuildContext ctx) => const Color(0xFF8E8E93);
  static Color placeholder(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFF48484A)
      : const Color(0xFFC7C7CC);
  static Color sep(BuildContext ctx) => _dark(ctx)
      ? const Color(0xFF3A3A3C) // base-300
      : const Color(0xFFE5E5EA);

  static bool _dark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  // ── Temas ───────────────────────────────────────────────────────────────────
  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: b,
        primary: primary,
        secondary: secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(
          color: dark ? const Color(0xFF636366) : const Color(0xFFAEAEB2),
          fontSize: 15,
        ),
      ),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFF2C2C2E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      useMaterial3: true,
    );
  }

  static final light = _build(Brightness.light);
  static final dark  = _build(Brightness.dark);

  static Color tintBg(Color c)     => c.withValues(alpha: 0.12);
  static Color tintBorder(Color c) => c.withValues(alpha: 0.25);
}
