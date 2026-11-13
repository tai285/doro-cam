/// Camera Experiences (EXP-001..003, EXP-010, EXP-011, ADR-0003).
///
/// An Experience is data plus a UI skin description: defaults, optional constraints, a token theme and
/// workflow flags. It is not a separate camera implementation.
library;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';

enum ExperienceId { mirrorless, dslr, film, instant }

/// Colors for the Experience skin as ARGB ints, so the domain stays free of Flutter types.
class ExperienceTheme {
  const ExperienceTheme({
    required this.surface,
    required this.onSurface,
    required this.accent,
    required this.readout,
    required this.cornerRadius,
    required this.fontFamily,
  });

  final int surface;
  final int onSurface;
  final int accent;
  final int readout;
  final double cornerRadius;

  /// A font *family name* the UI maps to a bundled or system font.
  final String fontFamily;
}

/// How the capture flow behaves for this Experience.
class WorkflowFlags {
  const WorkflowFlags({
    this.showsHistogramSpace = false,
    this.showsExposureReadout = true,
    this.shutterSoundByDefault = false,
    this.developsAfterCapture = false,
    this.showsFrameCounter = false,
    this.manualDialsVisible = true,
    this.opensWithAssistedPicker = false,
  });

  final bool showsHistogramSpace;
  final bool showsExposureReadout;
  final bool shutterSoundByDefault;

  /// Instant: the capture is presented as a print that "develops" (EXP-010).
  final bool developsAfterCapture;

  /// Film: a frame counter (the roll constraint itself is Post, EXP-009).
  final bool showsFrameCounter;
  final bool manualDialsVisible;
  final bool opensWithAssistedPicker;
}

/// A typed refusal from the Experience constraint validator (spec rule 5).
class ConstraintRejection {
  const ConstraintRejection(this.code, this.message);

  /// `roll_finished` when a limited roll has no frames left.
  final String code;
  final String message;

  @override
  String toString() => 'ConstraintRejection($code)';
}

class Experience {
  const Experience({
    required this.id,
    required this.name,
    required this.tagline,
    required this.defaults,
    required this.defaultProfileId,
    required this.theme,
    required this.workflow,
    required this.fullyBuilt,
    this.authenticLocks = const <IntentField>{},
    this.rollSize,
  });

  final ExperienceId id;
  final String name;
  final String tagline;

  /// Defaults layer (lowest priority). Includes the aspect ratio and profile defaults (EXP-002).
  final CaptureIntent defaults;
  final String defaultProfileId;
  final ExperienceTheme theme;
  final WorkflowFlags workflow;

  /// EXP-011: Mirrorless and Instant are fully built; DSLR and Film are styled variants on the same engine.
  final bool fullyBuilt;

  /// Fields forced to the Experience default when the user opts into the "authentic" constraint (EXP-003).
  final Set<IntentField> authenticLocks;

  /// A limited roll (e.g. 24/36 frames). Null means unlimited. Enforced only when "authentic" (EXP-009 is Post).
  final int? rollSize;

  /// The profile used when the user has not chosen one.
  CaptureIntent get defaultsWithProfile => defaults.merge(CaptureIntent(profileId: defaultProfileId));

  /// Rule 5 of the resolver: may reject a capture, e.g. when an authentic roll is finished.
  ConstraintRejection? validate({required bool authentic, required int framesShot}) {
    final roll = rollSize;
    if (authentic && roll != null && framesShot >= roll) {
      return ConstraintRejection('roll_finished', 'This roll of $roll frames is finished. Load a new roll to keep shooting.');
    }
    return null;
  }
}

/// The four Experiences (EXP-001). Mirrorless and Instant are fully built (EXP-011).
abstract final class Experiences {
  static const Experience mirrorless = Experience(
    id: ExperienceId.mirrorless,
    name: 'Modern Mirrorless',
    tagline: 'Clean, precise and fully in your hands.',
    defaults: CaptureIntent(aspect: '3:2', grid: true, flash: FlashMode.off, live: false, timerSeconds: 0),
    defaultProfileId: 'natural',
    theme: ExperienceTheme(
      surface: 0xFF0F1514,
      onSurface: 0xFFE6EFED,
      accent: 0xFF80CBC4,
      readout: 0xFFF2F2F2,
      cornerRadius: 12,
      fontFamily: 'sans',
    ),
    workflow: WorkflowFlags(showsHistogramSpace: true, manualDialsVisible: true),
    fullyBuilt: true,
  );

  static const Experience dslr = Experience(
    id: ExperienceId.dslr,
    name: 'DSLR',
    tagline: 'Mode dial, exposure meter, shutter sound.',
    defaults: CaptureIntent(aspect: '3:2', grid: true, flash: FlashMode.auto, live: false),
    defaultProfileId: 'natural',
    theme: ExperienceTheme(
      surface: 0xFF111111,
      onSurface: 0xFFEDEDED,
      accent: 0xFFFFB300,
      readout: 0xFFFFD54F,
      cornerRadius: 4,
      fontFamily: 'mono',
    ),
    workflow: WorkflowFlags(shutterSoundByDefault: true, showsExposureReadout: true),
    fullyBuilt: false,
    authenticLocks: <IntentField>{IntentField.aspect},
  );

  static const Experience film = Experience(
    id: ExperienceId.film,
    name: 'Film',
    tagline: 'Fewer choices. One roll at a time.',
    defaults: CaptureIntent(aspect: '3:2', grid: false, flash: FlashMode.off, live: false),
    defaultProfileId: 'warm-film',
    theme: ExperienceTheme(
      surface: 0xFF1B1611,
      onSurface: 0xFFF0E6D8,
      accent: 0xFFD9A066,
      readout: 0xFFE8C99A,
      cornerRadius: 2,
      fontFamily: 'serif',
    ),
    workflow: WorkflowFlags(showsFrameCounter: true, manualDialsVisible: false, opensWithAssistedPicker: true),
    fullyBuilt: false,
    authenticLocks: <IntentField>{IntentField.aspect, IntentField.profile},
    rollSize: 36,
  );

  static const Experience instant = Experience(
    id: ExperienceId.instant,
    name: 'Instant',
    tagline: 'Press, and watch the print develop.',
    defaults: CaptureIntent(aspect: '1:1', grid: false, flash: FlashMode.auto, live: false),
    defaultProfileId: 'instant-warm',
    theme: ExperienceTheme(
      surface: 0xFFF6F0E4,
      onSurface: 0xFF2B2620,
      accent: 0xFFE4572E,
      readout: 0xFF2B2620,
      cornerRadius: 20,
      fontFamily: 'rounded',
    ),
    workflow: WorkflowFlags(developsAfterCapture: true, shutterSoundByDefault: true, manualDialsVisible: false, opensWithAssistedPicker: true),
    fullyBuilt: true,
    authenticLocks: <IntentField>{IntentField.aspect},
  );

  static const List<Experience> all = <Experience>[mirrorless, dslr, film, instant];

  static Experience byId(ExperienceId id) => all.firstWhere((experience) => experience.id == id);

  /// Lookup by stored string id; falls back to Mirrorless for unknown ids (an old preset must still open).
  static Experience fromName(String? name) => all.firstWhere(
        (experience) => experience.id.name == name,
        orElse: () => mirrorless,
      );
}

/// The Instant "develop" animation (EXP-010), as a pure function so it can be tested without a UI.
class InstantDevelop {
  const InstantDevelop({this.duration = const Duration(seconds: 6), this.startOpacity = 0.0});

  final Duration duration;
  final double startOpacity;

  /// Development progress in 0..1 after [elapsed], eased so the image appears slowly then settles.
  double progress(Duration elapsed) {
    if (duration <= Duration.zero) {
      return 1;
    }
    final t = (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Image opacity: from [startOpacity] to 1.
  double opacity(Duration elapsed) => startOpacity + (1 - startOpacity) * progress(elapsed);

  /// Remaining blur/greenish "chemical" tint amount: 1 at the start, 0 when developed.
  double chemicalHaze(Duration elapsed) => 1 - progress(elapsed);

  bool isDeveloped(Duration elapsed) => elapsed >= duration;
}
