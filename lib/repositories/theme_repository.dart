import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/theme_service.dart';

class ThemeRepository extends ChangeNotifier {
  final ThemeService _service;
  ThemeRepository({required ThemeService service}) : _service = service;

  Color _primary   = AppTheme.primary;
  Color _secondary = AppTheme.secondary;

  ThemeData themeFor(Brightness brightness) {
    final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
    if (_primary == AppTheme.primary && _secondary == AppTheme.secondary) {
      return base;
    }
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _primary),
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: _secondary),
    );
  }

  Future<void> fetchTheme(String company) async {
    final palette = await _service.fetchTheme(company);
    if (palette.isEmpty) return;
    _primary   = _parseHex(palette['primary'])   ?? AppTheme.primary;
    _secondary = _parseHex(palette['secondary']) ?? AppTheme.secondary;
    notifyListeners();
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }
}
