import 'package:flutter/material.dart';

/// Design tokens as a ThemeExtension (docs/design/ux-principles.md). Components read tokens,
/// never raw colors. Experience themes (Mirrorless, Instant, ...) later provide override sets.
/// The values below are placeholders: final colors and type are chosen during P2 design work.
@immutable
class DoroTokens extends ThemeExtension<DoroTokens> {
  const DoroTokens({
    required this.readout,
    required this.warning,
    required this.recording,
    required this.accent,
  });

  /// Numeric camera values (ISO, shutter, ...).
  final Color readout;

  /// Clamped or unsupported values (never the only signal: always paired with an icon and text).
  final Color warning;

  /// LIVE and video active.
  final Color recording;

  final Color accent;

  static const DoroTokens dark = DoroTokens(
    readout: Color(0xFFF2F2F2),
    warning: Color(0xFFFFB74D),
    recording: Color(0xFFFF5252),
    accent: Color(0xFF80CBC4),
  );

  static const DoroTokens light = DoroTokens(
    readout: Color(0xFF1A1A1A),
    warning: Color(0xFF9A5B00),
    recording: Color(0xFFB71C1C),
    accent: Color(0xFF00695C),
  );

  @override
  DoroTokens copyWith({Color? readout, Color? warning, Color? recording, Color? accent}) {
    return DoroTokens(
      readout: readout ?? this.readout,
      warning: warning ?? this.warning,
      recording: recording ?? this.recording,
      accent: accent ?? this.accent,
    );
  }

  @override
  DoroTokens lerp(ThemeExtension<DoroTokens>? other, double t) {
    if (other is! DoroTokens) {
      return this;
    }
    return DoroTokens(
      readout: Color.lerp(readout, other.readout, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      recording: Color.lerp(recording, other.recording, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension DoroTokensContext on BuildContext {
  DoroTokens get tokens => Theme.of(this).extension<DoroTokens>() ?? DoroTokens.dark;
}
