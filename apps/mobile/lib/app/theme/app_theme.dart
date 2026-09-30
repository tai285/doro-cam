import 'package:doro_cam/app/theme/doro_tokens.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, DoroTokens.dark);

  static ThemeData light() => _build(Brightness.light, DoroTokens.light);

  static ThemeData _build(Brightness brightness, DoroTokens tokens) {
    final scheme = ColorScheme.fromSeed(seedColor: tokens.accent, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [tokens],
    );
  }
}
