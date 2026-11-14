import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/domain/camera/capabilities.dart' as dom;
import 'package:doro_cam/domain/camera/capture_intent.dart' as dom;
import 'package:doro_cam/features/camera/application/camera_mapping.dart';
import 'package:doro_cam/features/camera/application/stops.dart';
import 'package:doro_cam/features/presets/preset_mapping.dart';
import 'package:doro_cam/profiles/builtin_profiles.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/lut.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:doro_camera/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plugin capabilities → domain capabilities (CAM-004)', () {
    test('a fully capable camera maps every field', () {
      final plugin = FakeCameraPlatform.fullCapabilities('x');
      final domain = toDomainCapabilities(plugin);
      expect(domain.iso, const dom.IntRange(50, 3200));
      expect(domain.exposureTimeNs, const dom.IntRange(100000, 1000000000));
      expect(domain.exposureBias!.step, closeTo(1 / 3, 1e-9));
      expect(
        domain.focus.manual!.calibration,
        dom.FocusCalibration.approximate,
      );
      expect(
        domain.whiteBalance.presets,
        containsAll(<dom.WbPreset>[
          dom.WbPreset.tungsten,
          dom.WbPreset.fluorescent,
        ]),
      );
      expect(domain.whiteBalance.kelvin, const dom.IntRange(2000, 10000));
      expect(domain.zoom.max, 8);
      expect(domain.flash, <dom.FlashMode>{
        dom.FlashMode.off,
        dom.FlashMode.auto,
        dom.FlashMode.on,
      });
      expect(domain.torch, isTrue);
      expect(domain.photoSizes.first, const dom.PixelSize(4000, 3000));
      expect(domain.live.supported, isTrue);
      expect(domain.apertures, <double>[1.8]);
      expect(domain.hardwareLevel, 'FULL');
    });

    test('a bare camera maps to "nothing optional"', () {
      const bare = cam.CameraCapabilities(
        cameraId: 'bare',
        apertures: <double>[],
        focus: cam.FocusCapabilities(
          auto: false,
          continuous: false,
          tapToFocus: false,
        ),
        whiteBalance: cam.WhiteBalanceCapabilities(presets: <cam.WbPreset>[]),
        zoom: cam.ZoomCapabilities(min: 1, max: 1, opticalSteps: <double>[1]),
        flash: <cam.FlashMode>[],
        torch: false,
        photoFormats: <cam.PhotoFormat>[cam.PhotoFormat.jpeg],
        photoSizes: <cam.CameraSize>[],
        stabilization: cam.StabilizationCapabilities(
          photo: <cam.StabilizationMode>[],
          video: <cam.StabilizationMode>[],
        ),
        video: cam.VideoCapabilities(
          options: <cam.VideoSizeOption>[],
          audio: false,
        ),
        hdr: false,
        live: cam.LiveCapabilities(
          supported: false,
          maxPreBufferMs: 0,
          audio: false,
        ),
        hardwareLevel: 'LEGACY',
      );
      final domain = toDomainCapabilities(bare);
      expect(domain.hasManualIso, isFalse);
      expect(domain.hasManualShutter, isFalse);
      expect(domain.exposureBias, isNull);
      expect(domain.focus.manual, isNull);
      expect(domain.flash, isEmpty);
      expect(domain.live.supported, isFalse);
    });
  });

  group('resolved settings → plugin settings', () {
    cam.ResolvedCaptureSettings map(dom.ResolvedCaptureSettings s) =>
        toPluginSettings(s);

    test('manual exposure, focus lock, zoom, flash and torch pass through', () {
      final out = map(
        const dom.ResolvedCaptureSettings(
          iso: 400,
          exposureTimeNs: 8000000,
          exposureBiasEv: 0.7,
          exposureLocked: true,
          focusMode: dom.FocusMode.manual,
          manualFocusDiopters: 3,
          zoom: 2.5,
          flash: dom.FlashMode.auto,
          torch: true,
        ),
      );
      expect(
        (out.iso, out.exposureTimeNs, out.exposureBiasEv, out.aeLock),
        (400, 8000000, 0.7, true),
      );
      expect(
        (out.focusMode, out.focusDistanceDiopters),
        (cam.FocusMode.manual, 3.0),
      );
      expect(
        (out.zoomRatio, out.flash, out.torch),
        (2.5, cam.FlashMode.auto, true),
      );
    });

    test('automatic white balance becomes "no preset", a preset stays one, Kelvin wins', () {
      expect(
        map(const dom.ResolvedCaptureSettings()).whiteBalancePreset,
        isNull,
      );
      final preset = map(
        const dom.ResolvedCaptureSettings(
          whiteBalance: dom.ResolvedWhiteBalance(preset: dom.WbPreset.shade),
        ),
      );
      expect(preset.whiteBalancePreset, cam.WbPreset.shade);
      final kelvin = map(
        const dom.ResolvedCaptureSettings(
          whiteBalance: dom.ResolvedWhiteBalance(
            preset: dom.WbPreset.daylight,
            kelvin: 4300,
          ),
        ),
      );
      expect(kelvin.kelvin, 4300);
      expect(kelvin.whiteBalancePreset, isNull);
    });

    test('every domain focus mode has a plugin counterpart', () {
      expect(
        <cam.FocusMode>[
          for (final mode in dom.FocusMode.values)
            map(dom.ResolvedCaptureSettings(focusMode: mode)).focusMode,
        ],
        <cam.FocusMode>[
          cam.FocusMode.auto,
          cam.FocusMode.auto,
          cam.FocusMode.continuous,
          cam.FocusMode.manual,
        ],
      );
    });
  });

  group('look → render spec (PRF-003)', () {
    test('the LUT is packed as RGB bytes, R fastest, 3 per entry, and carries grain and vignette', () {
      final profile = BuiltInProfiles.warmFilm;
      final lut = compileProfile(profile);
      final spec = renderSpecFor(profile, lut, aspect: '1:1', crop: true);
      expect(spec.lutSize, lut.size);
      expect(spec.lut!.length, lut.size * lut.size * lut.size * 3);
      expect(spec.lut![0], (lut.data[0].clamp(0.0, 1.0) * 255).round());
      expect(spec.grain, profile.effects.grain.amount);
      expect(spec.vignette, profile.effects.vignette.amount);
      expect(spec.aspectRatio, '1:1');
      expect(spec.profileId, 'warm-film');
      expect(
        renderSpecFor(profile, lut).aspectRatio,
        isNull,
      ); // native aspect: nothing to crop
    });

    test('packLut clamps out-of-range values', () {
      final lut = Lut3d.identity(size: 2);
      lut.data[0] = -0.5;
      lut.data[1] = 1.7;
      final packed = packLut(lut);
      expect((packed[0], packed[1]), (0, 255));
    });
  });

  group('capture metadata (CAM-050, MEM-002)', () {
    final descriptor = FakeCameraPlatform.defaultDescriptor;
    cam.CaptureResult result({
      cam.AppliedSettings applied = const cam.AppliedSettings(
        iso: 200,
        exposureTimeNs: 8000000,
        aperture: 1.8,
        zoomRatio: 2,
        flash: cam.FlashMode.auto,
      ),
    }) => cam.CaptureResult(
      memoryId: 'm',
      originalPath: '/o.jpg',
      originalMime: 'image/jpeg',
      width: 4000,
      height: 3000,
      orientationDegrees: 90,
      applied: applied,
      capturedAtEpochMs: 1,
      source: cam.CameraSource.hardware,
      liveIncluded: true,
      mirrored: false,
      renderFailed: false,
    );

    test('records what the device reported, the requested values, and the adjustments shown to the user', () {
      final metadata = buildCaptureMetadata(
        camera: descriptor,
        result: result(),
        requested: const dom.ResolvedCaptureSettings(
          iso: 100,
          exposureTimeNs: 4000000,
          zoom: 2,
          digitalZoom: true,
        ),
        adjustments: const <dom.Adjustment>[
          dom.Adjustment(
            field: dom.IntentField.iso,
            requested: 99999,
            applied: 3200,
            reason: dom.AdjustmentReason.outOfRange,
            message: 'm',
          ),
        ],
        platform: 'android',
        osVersion: '15',
        appVersion: '1.0.0+1',
      );
      expect(
        metadata['isoApplied'],
        200,
      ); // what the device used, not what was asked for
      expect(metadata['exposureTimeNsApplied'], 8000000);
      expect(metadata['aperture'], 1.8);
      expect(metadata['focalLength35mmEq'], 52.0); // 26 mm × 2× zoom
      expect(metadata['zoomFactor'], 2);
      expect(metadata['digitalZoom'], isTrue);
      expect(metadata['flash'], 'auto');
      expect(metadata['widthPx'], 4000);
      expect(metadata['live'], isTrue);
      expect((metadata['requested']! as Map<String, Object?>)['iso'], 100);
      expect(
        ((metadata['adjustments']! as List<Object?>).single!
            as Map<String, Object?>)['field'],
        'iso',
      );
      expect(metadata['platform'], 'android');
      expect(metadata['osVersion'], '15');
      expect(metadata['cameraSource'], 'hardware');
    });

    test(
      'values the device did not report are left out rather than invented',
      () {
        final metadata = buildCaptureMetadata(
          camera: descriptor,
          result: result(applied: const cam.AppliedSettings()),
          requested: const dom.ResolvedCaptureSettings(),
          adjustments: const <dom.Adjustment>[],
          platform: 'ios',
          appVersion: '1',
        );
        expect(metadata.containsKey('isoApplied'), isFalse);
        expect(metadata.containsKey('exposureTimeNsApplied'), isFalse);
        expect(metadata.containsKey('aperture'), isFalse);
        expect(metadata.containsKey('osVersion'), isFalse);
        expect(metadata.containsKey('mismatches'), isFalse);
      },
    );

    test('mismatches the device reported are kept', () {
      final metadata = buildCaptureMetadata(
        camera: descriptor,
        result: result(
          applied: const cam.AppliedSettings(mismatches: <String>['iso']),
        ),
        requested: const dom.ResolvedCaptureSettings(),
        adjustments: const <dom.Adjustment>[],
        platform: 'android',
        appVersion: '1',
      );
      expect(metadata['mismatches'], <String>['iso']);
    });
  });

  group('dial stops (CAM-010, CAM-011)', () {
    test('ISO stops stay inside the reported range and include its ends', () {
      expect(isoStops(const dom.IntRange(50, 3200)), <int>[
        50,
        64,
        80,
        100,
        125,
        160,
        200,
        250,
        320,
        400,
        500,
        640,
        800,
        1000,
        1250,
        1600,
        2000,
        2500,
        3200,
      ]);
      expect(isoStops(const dom.IntRange(123, 456)), <int>[
        123,
        125,
        160,
        200,
        250,
        320,
        400,
        456,
      ]);
      expect(isoStops(const dom.IntRange(100, 100)), <int>[100]);
    });

    test('shutter stops run from the fastest the camera allows to the slowest, in order', () {
      final stops = shutterStops(const dom.IntRange(100000, 1000000000));
      expect(stops.first, 100000);
      expect(stops.last, 1000000000);
      expect(stops, orderedEquals(<int>[...stops]..sort()));
      expect(stops, contains(8000000)); // 1/125
    });

    test('formatters', () {
      expect(formatShutterNs(8000000), '1/125');
      expect(formatShutterNs(1000000000), '1 s');
      expect(formatShutterNs(2500000000), '2.5 s');
      expect(formatEv(0), '0 EV');
      expect(formatEv(1), '+1 EV');
      expect(formatEv(-0.7), '−0.7 EV');
      expect(formatZoom(2), '2×');
      expect(formatZoom(2.5), '2.5×');
      expect(formatFocusDistance(0), '∞');
      expect(formatFocusDistance(2), '50 cm');
      expect(formatFocusDistance(0.5), '2.0 m');
      expect(formatFocusDistance(0.05), '∞');
      expect(formatFocusDistance(0.08), '13 m');
    });

    test(
      'labels cover every white balance preset, flash mode and lens kind',
      () {
        expect(dom.WbPreset.values.map(presetLabel), <String>[
          'Auto',
          'Daylight',
          'Cloudy',
          'Shade',
          'Tungsten',
          'Fluorescent',
        ]);
        expect(dom.FlashMode.values.map(flashLabel), <String>[
          'Off',
          'Auto',
          'On',
        ]);
        expect(
          <String>[
            'ultraWide',
            'wide',
            'tele',
            'front',
            'other',
          ].map(lensLabel),
          <String>['Ultra-wide', 'Wide', 'Telephoto', 'Front', 'Camera'],
        );
        expect(aspectChoices, <String>['4:3', '3:2', '16:9', '1:1']);
      },
    );
  });

  group('stored presets', () {
    PresetRow row({
      String intent = '{"iso":400}',
      String source = 'user',
      String? profile = 'warm-film',
    }) => PresetRow(
      id: 'p1',
      name: 'Street',
      experienceId: 'mirrorless',
      intentJson: intent,
      profileId: profile,
      profileVersion: 2,
      live: true,
      source: source,
      dirty: false,
      createdAt: 1000,
      updatedAt: 2000,
    );

    test('a stored row becomes a domain preset with its intent, look and LIVE flag', () {
      final preset = rowToPreset(row());
      expect(preset.name, 'Street');
      expect(preset.intent.iso, 400);
      expect(preset.profile!.id, 'warm-film');
      expect(preset.profile!.version, 2);
      expect(preset.live, isTrue);
    });

    test('a suggested preset keeps its origin, and a damaged intent does not block the camera', () {
      expect(rowToPreset(row(source: 'suggested')).source.name, 'suggested');
      expect(
        rowToPreset(row(intent: 'not json')).intent,
        dom.CaptureIntent.empty,
      );
      expect(rowToPreset(row(profile: null)).profile, isNull);
    });
  });

  test('every built-in profile compiles to a LUT the plugin can use', () {
    for (final ImageProfile profile in BuiltInProfiles.all) {
      final lut = compileProfile(profile);
      expect(
        packLut(lut).length,
        lut.size * lut.size * lut.size * 3,
        reason: profile.id,
      );
    }
  });
}
