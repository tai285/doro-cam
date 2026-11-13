/// Assisted-mode scenarios (EXP-004): a recommended intent plus a plain-language reason for each setting.
library;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';

enum ScenarioId { portrait, street, landscape, night, sunset, indoor, brightDay, film, instant, cinema }

class Scenario {
  const Scenario({
    required this.id,
    required this.name,
    required this.summary,
    required this.intent,
    required this.explanations,
  });

  final ScenarioId id;
  final String name;
  final String summary;

  /// The recommendation (a partial intent that sits between the Experience defaults and the user's overrides).
  final CaptureIntent intent;

  /// Why each recommended field was chosen, shown next to the setting ("this came from the Night scenario").
  final Map<IntentField, String> explanations;

  /// Every recommended field has an explanation, and vice versa.
  bool get isConsistent => explanations.keys.toSet().containsAll(intent.specifiedFields) && intent.specifiedFields.containsAll(explanations.keys);
}

/// The ten scenarios of EXP-004. Values are recommendations only: the resolver adapts them to the camera and
/// tells the user when something could not be applied.
abstract final class Scenarios {
  static const Scenario portrait = Scenario(
    id: ScenarioId.portrait,
    name: 'Portrait',
    summary: 'Flattering skin tones with the face in focus.',
    intent: CaptureIntent(
      focus: FocusRequest.continuous,
      exposureBiasEv: 0.3,
      whiteBalance: WbRequest.preset(WbPreset.auto),
      flash: FlashMode.off,
      profileId: 'soft-film',
      aspect: '4:3',
    ),
    explanations: <IntentField, String>{
      IntentField.focusMode: 'Continuous focus keeps a moving face sharp.',
      IntentField.exposureBias: 'A touch brighter (+0.3 EV) keeps skin from looking dull.',
      IntentField.whiteBalance: 'Automatic white balance follows the light on the face.',
      IntentField.flash: 'Flash off avoids harsh shadows; turn it on for dark rooms.',
      IntentField.profile: 'Soft Film softens contrast for gentler skin.',
      IntentField.aspect: '4:3 is the sensor’s full frame with room above the head.',
    },
  );

  static const Scenario street = Scenario(
    id: ScenarioId.street,
    name: 'Street',
    summary: 'Quick, candid shots in changing light.',
    intent: CaptureIntent(
      focus: FocusRequest.continuous,
      flash: FlashMode.off,
      profileId: 'natural',
      aspect: '3:2',
      timerSeconds: 0,
      grid: true,
    ),
    explanations: <IntentField, String>{
      IntentField.focusMode: 'Continuous focus so you can shoot without waiting.',
      IntentField.flash: 'No flash: it draws attention and spoils the mood.',
      IntentField.profile: 'Natural keeps colors honest.',
      IntentField.aspect: '3:2 is the classic street frame.',
      IntentField.timer: 'No timer, so the shutter fires the moment you press.',
      IntentField.grid: 'The grid helps you keep horizons level on the move.',
    },
  );

  static const Scenario landscape = Scenario(
    id: ScenarioId.landscape,
    name: 'Landscape',
    summary: 'Wide, sharp scenes with rich color.',
    intent: CaptureIntent(
      focus: FocusRequest.auto,
      zoom: 1,
      flash: FlashMode.off,
      whiteBalance: WbRequest.preset(WbPreset.daylight),
      profileId: 'natural',
      aspect: '16:9',
      grid: true,
    ),
    explanations: <IntentField, String>{
      IntentField.focusMode: 'Single autofocus locks on the scene.',
      IntentField.zoom: 'Stay at 1× for the widest view and best quality.',
      IntentField.flash: 'Flash cannot reach distant scenery.',
      IntentField.whiteBalance: 'Daylight white balance keeps skies and foliage consistent.',
      IntentField.profile: 'Natural keeps colors true.',
      IntentField.aspect: '16:9 suits wide panoramas.',
      IntentField.grid: 'The grid helps place the horizon on a third.',
    },
  );

  static const Scenario night = Scenario(
    id: ScenarioId.night,
    name: 'Night',
    summary: 'Low light without flash.',
    intent: CaptureIntent(
      exposureBiasEv: 1,
      flash: FlashMode.off,
      timerSeconds: 3,
      whiteBalance: WbRequest.preset(WbPreset.auto),
      profileId: 'natural',
      focus: FocusRequest.auto,
    ),
    explanations: <IntentField, String>{
      IntentField.exposureBias: 'Brighter exposure (+1 EV) gathers more light.',
      IntentField.flash: 'Flash flattens a night scene and only lights what is nearby.',
      IntentField.timer: 'A 3-second timer lets the phone settle so longer exposures stay sharp.',
      IntentField.whiteBalance: 'Automatic balance copes with mixed street lighting.',
      IntentField.profile: 'Natural avoids crushing shadows further.',
      IntentField.focusMode: 'Single autofocus is steadier than continuous in the dark.',
    },
  );

  static const Scenario sunset = Scenario(
    id: ScenarioId.sunset,
    name: 'Sunset',
    summary: 'Keep the warm glow instead of washing it out.',
    intent: CaptureIntent(
      exposureBiasEv: -0.7,
      whiteBalance: WbRequest.preset(WbPreset.cloudy),
      flash: FlashMode.off,
      profileId: 'warm-film',
      aspect: '16:9',
    ),
    explanations: <IntentField, String>{
      IntentField.exposureBias: 'Slightly darker (-0.7 EV) protects the bright sky.',
      IntentField.whiteBalance: 'Cloudy white balance keeps the sky warm instead of neutralizing it.',
      IntentField.flash: 'Flash would light the foreground and flatten the sky.',
      IntentField.profile: 'Warm Film adds a golden cast.',
      IntentField.aspect: '16:9 shows more sky and horizon.',
    },
  );

  static const Scenario indoor = Scenario(
    id: ScenarioId.indoor,
    name: 'Indoor',
    summary: 'Dim rooms and artificial light.',
    intent: CaptureIntent(
      whiteBalance: WbRequest.preset(WbPreset.tungsten),
      exposureBiasEv: 0.3,
      flash: FlashMode.auto,
      profileId: 'natural',
      focus: FocusRequest.continuous,
    ),
    explanations: <IntentField, String>{
      IntentField.whiteBalance: 'Tungsten balance cancels the orange of room bulbs.',
      IntentField.exposureBias: 'A little brighter (+0.3 EV) for dim rooms.',
      IntentField.flash: 'Auto flash helps only when it is really dark.',
      IntentField.profile: 'Natural keeps colors honest under artificial light.',
      IntentField.focusMode: 'Continuous focus for people who keep moving.',
    },
  );

  static const Scenario brightDay = Scenario(
    id: ScenarioId.brightDay,
    name: 'Bright Day',
    summary: 'Harsh sun and strong contrast.',
    intent: CaptureIntent(
      exposureBiasEv: -0.3,
      whiteBalance: WbRequest.preset(WbPreset.daylight),
      flash: FlashMode.off,
      profileId: 'natural',
      focus: FocusRequest.continuous,
    ),
    explanations: <IntentField, String>{
      IntentField.exposureBias: 'Slightly darker (-0.3 EV) keeps highlights from clipping.',
      IntentField.whiteBalance: 'Daylight balance matches the sun.',
      IntentField.flash: 'No flash needed in bright light.',
      IntentField.profile: 'Natural keeps the contrast honest.',
      IntentField.focusMode: 'Continuous focus for active scenes.',
    },
  );

  static const Scenario film = Scenario(
    id: ScenarioId.film,
    name: 'Film',
    summary: 'A warm, grainy, film-inspired look.',
    intent: CaptureIntent(
      whiteBalance: WbRequest.preset(WbPreset.daylight),
      flash: FlashMode.off,
      profileId: 'warm-film',
      aspect: '3:2',
      grid: false,
    ),
    explanations: <IntentField, String>{
      IntentField.whiteBalance: 'Daylight balance gives the warm film cast room to show.',
      IntentField.flash: 'Film looks are about available light.',
      IntentField.profile: 'Warm Film brings lifted blacks, soft highlights and grain.',
      IntentField.aspect: '3:2 matches a 35 mm frame.',
      IntentField.grid: 'No grid: fewer distractions.',
    },
  );

  static const Scenario instant = Scenario(
    id: ScenarioId.instant,
    name: 'Instant',
    summary: 'A square, sun-faded print look.',
    intent: CaptureIntent(
      aspect: '1:1',
      flash: FlashMode.auto,
      profileId: 'instant-warm',
      grid: false,
    ),
    explanations: <IntentField, String>{
      IntentField.aspect: 'A square frame like an instant print.',
      IntentField.flash: 'Auto flash gives the on-camera-flash look.',
      IntentField.profile: 'Instant Warm adds faded warm tones.',
      IntentField.grid: 'No grid: fewer distractions.',
    },
  );

  static const Scenario cinema = Scenario(
    id: ScenarioId.cinema,
    name: 'Cinema',
    summary: 'A wide, moody frame.',
    intent: CaptureIntent(
      aspect: '16:9',
      exposureBiasEv: -0.3,
      flash: FlashMode.off,
      profileId: 'soft-film',
      whiteBalance: WbRequest.preset(WbPreset.auto),
    ),
    explanations: <IntentField, String>{
      IntentField.aspect: '16:9 is the wide screen shape of films.',
      IntentField.exposureBias: 'A touch darker (-0.3 EV) deepens the mood.',
      IntentField.flash: 'Flash breaks the cinematic light.',
      IntentField.profile: 'Soft Film adds low-contrast, filmic tones.',
      IntentField.whiteBalance: 'Automatic balance follows the scene.',
    },
  );

  static const List<Scenario> all = <Scenario>[portrait, street, landscape, night, sunset, indoor, brightDay, film, instant, cinema];

  static Scenario byId(ScenarioId id) => all.firstWhere((scenario) => scenario.id == id);

  static Scenario? fromName(String? name) {
    for (final scenario in all) {
      if (scenario.id.name == name) {
        return scenario;
      }
    }
    return null;
  }
}
