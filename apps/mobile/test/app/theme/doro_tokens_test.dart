import 'package:doro_cam/app/theme/app_theme.dart';
import 'package:doro_cam/app/theme/doro_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('DoroTokens', () {
    test('copyWith replaces only the given fields', () {
      final copy = DoroTokens.dark.copyWith(warning: const Color(0xFF123456));
      expect(copy.warning, const Color(0xFF123456));
      expect(copy.readout, DoroTokens.dark.readout);
      expect(copy.recording, DoroTokens.dark.recording);
      expect(copy.accent, DoroTokens.dark.accent);
    });

    test('copyWith with no arguments keeps every field', () {
      final copy = DoroTokens.light.copyWith();
      expect(copy.readout, DoroTokens.light.readout);
      expect(copy.warning, DoroTokens.light.warning);
      expect(copy.recording, DoroTokens.light.recording);
      expect(copy.accent, DoroTokens.light.accent);
    });

    test('lerp returns the endpoints at t=0 and t=1', () {
      final at0 = DoroTokens.dark.lerp(DoroTokens.light, 0);
      final at1 = DoroTokens.dark.lerp(DoroTokens.light, 1);
      expect(at0.readout, DoroTokens.dark.readout);
      expect(at1.readout, DoroTokens.light.readout);
      expect(at1.accent, DoroTokens.light.accent);
    });

    test('lerp interpolates every color at the midpoint', () {
      final mid = DoroTokens.dark.lerp(DoroTokens.light, 0.5);
      expect(mid.readout, Color.lerp(DoroTokens.dark.readout, DoroTokens.light.readout, 0.5));
      expect(mid.warning, Color.lerp(DoroTokens.dark.warning, DoroTokens.light.warning, 0.5));
      expect(mid.recording, Color.lerp(DoroTokens.dark.recording, DoroTokens.light.recording, 0.5));
      expect(mid.accent, Color.lerp(DoroTokens.dark.accent, DoroTokens.light.accent, 0.5));
    });

    test('lerp with a different extension type returns this unchanged', () {
      expect(identical(DoroTokens.dark.lerp(null, 0.5), DoroTokens.dark), isTrue);
    });
  });

  group('AppTheme', () {
    test('dark and light themes carry their matching token sets', () {
      expect(AppTheme.dark().extension<DoroTokens>(), DoroTokens.dark);
      expect(AppTheme.light().extension<DoroTokens>(), DoroTokens.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.light().brightness, Brightness.light);
    });

    for (final entry in {'dark': AppTheme.dark(), 'light': AppTheme.light()}.entries) {
      final theme = entry.value;
      final surface = theme.colorScheme.surface;
      final tokens = theme.extension<DoroTokens>()!;

      test('[NFR-007] ${entry.key}: readout and warning text reach 4.5:1 on the surface', () {
        expect(contrastRatio(tokens.readout, surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(tokens.warning, surface), greaterThanOrEqualTo(4.5));
      });

      test('[NFR-007] ${entry.key}: recording and accent UI colors reach 3:1 on the surface', () {
        expect(contrastRatio(tokens.recording, surface), greaterThanOrEqualTo(3));
        expect(contrastRatio(tokens.accent, surface), greaterThanOrEqualTo(3));
      });

      test('[NFR-007] ${entry.key}: body text reaches 4.5:1 on the surface', () {
        expect(contrastRatio(theme.colorScheme.onSurface, surface), greaterThanOrEqualTo(4.5));
      });
    }

    test('contrast helper matches known WCAG values', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
      expect(contrastRatio(const Color(0xFF777777), Colors.white), closeTo(4.48, 0.05));
    });
  });

  testWidgets('context.tokens reads the extension, and falls back to dark tokens without one', (tester) async {
    late DoroTokens withExtension;
    late DoroTokens withoutExtension;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            withExtension = context.tokens;
            return Theme(
              data: ThemeData(),
              child: Builder(
                builder: (inner) {
                  withoutExtension = inner.tokens;
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(withExtension, DoroTokens.light);
    expect(withoutExtension, DoroTokens.dark);
  });
}
