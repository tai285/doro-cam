import 'dart:math' as math;

import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/experience/preset.dart';
import 'package:doro_cam/domain/memory/memory.dart';
import 'package:flutter_test/flutter_test.dart';

const String memId = '0192a7c0-1b2c-7d3e-8f4a-5b6c7d8e9f01';
const String handle = 'aB3dE5gH7jK9mN1pQ3sT5u';
final String sha = 'a' * 64;

Asset asset(AssetRole role, {String id = 'a1', AssetStatus status = AssetStatus.pending, String? hash, int bytes = 100}) =>
    Asset(id: '$id-${role.wire}', memoryId: memId, role: role, mime: 'image/jpeg', bytes: bytes, sha256: hash, status: status);

Memory memory({
  MemoryKind kind = MemoryKind.photo,
  List<Asset>? assets,
  String id = memId,
  String handleValue = handle,
  String tz = 'Asia/Kuala_Lumpur',
  String? caption,
  MemoryLocation? location,
}) {
  return Memory(
    id: id,
    kind: kind,
    capturedAt: DateTime.utc(2026, 11, 1, 9, 30),
    capturedTz: tz,
    experienceId: 'mirrorless',
    capture: const CaptureMetadata(isoApplied: 200),
    publicHandle: handleValue,
    caption: caption,
    location: location,
    assets: assets ??
        <Asset>[
          if (kind != MemoryKind.video) asset(AssetRole.photoOriginal),
          if (kind == MemoryKind.motion) asset(AssetRole.motionClip),
          if (kind == MemoryKind.video) asset(AssetRole.videoOriginal),
        ],
  );
}

void main() {
  group('Memory invariants (memory-domain.md)', () {
    test('[MEM-002] a valid photo, motion and video Memory construct', () {
      expect(memory().kind, MemoryKind.photo);
      expect(memory(kind: MemoryKind.motion).assets.length, 2);
      expect(memory(kind: MemoryKind.video).assets.single.role, AssetRole.videoOriginal);
    });

    test('invariant 1: exactly one photo_original (or video_original for video)', () {
      expect(() => memory(assets: <Asset>[]), throwsA(isA<InvariantViolation>()));
      expect(() => memory(assets: <Asset>[asset(AssetRole.photoRendered)]), throwsA(isA<InvariantViolation>()));
      expect(() => memory(kind: MemoryKind.video, assets: <Asset>[asset(AssetRole.photoOriginal)]), throwsA(isA<InvariantViolation>()));
      expect(() => memory(assets: <Asset>[asset(AssetRole.photoOriginal), asset(AssetRole.videoOriginal)]), throwsA(isA<InvariantViolation>()));
      expect(() => memory(kind: MemoryKind.video, assets: <Asset>[asset(AssetRole.videoOriginal), asset(AssetRole.photoOriginal)]), throwsA(isA<InvariantViolation>()));
    });

    test('invariant 1: at most one asset per role', () {
      expect(
        () => memory(assets: <Asset>[asset(AssetRole.photoOriginal), asset(AssetRole.photoOriginal, id: 'a2')]),
        throwsA(isA<InvariantViolation>().having((e) => e.message, 'message', contains('one asset per role'))),
      );
    });

    test('invariant 2: motion ⇔ exactly one motion_clip', () {
      expect(() => memory(kind: MemoryKind.motion, assets: <Asset>[asset(AssetRole.photoOriginal)]), throwsA(isA<InvariantViolation>()));
      expect(() => memory(assets: <Asset>[asset(AssetRole.photoOriginal), asset(AssetRole.motionClip)]), throwsA(isA<InvariantViolation>()));
      expect(memory(kind: MemoryKind.motion).assetFor(AssetRole.motionClip), isNotNull);
    });

    test('invariant 3: an uploaded asset cannot be modified, but a pending one can', () {
      final pending = asset(AssetRole.photoOriginal);
      final changed = pending.withNewContent(bytes: 200, sha256: 'b' * 64);
      expect(changed.bytes, 200);
      expect(changed.sha256, 'b' * 64);
      for (final status in <AssetStatus>[AssetStatus.uploaded, AssetStatus.verified, AssetStatus.ready]) {
        final frozen = Asset(id: 'x', memoryId: memId, role: AssetRole.photoOriginal, mime: 'image/jpeg', bytes: 1, sha256: sha, status: status);
        expect(() => frozen.withNewContent(bytes: 2, sha256: 'c' * 64), throwsA(isA<InvariantViolation>()), reason: status.name);
        expect(status.isImmutable, isTrue);
      }
      expect(AssetStatus.pending.isImmutable, isFalse);
      expect(AssetStatus.failed.isImmutable, isFalse);
    });

    test('invariant 3: the Memory refuses to alter the contents of an uploaded asset but allows status changes', () {
      final original = Asset(id: 'orig', memoryId: memId, role: AssetRole.photoOriginal, mime: 'image/jpeg', bytes: 10, sha256: sha, status: AssetStatus.uploaded);
      final m = memory(assets: <Asset>[original]);
      final verified = m.withUpdatedAsset(original.withStatus(AssetStatus.verified));
      expect(verified.assetFor(AssetRole.photoOriginal)!.status, AssetStatus.verified);
      final tampered = Asset(id: 'orig', memoryId: memId, role: AssetRole.photoOriginal, mime: 'image/jpeg', bytes: 11, sha256: 'd' * 64, status: AssetStatus.uploaded);
      expect(() => m.withUpdatedAsset(tampered), throwsA(isA<InvariantViolation>()));
      expect(() => m.withUpdatedAsset(asset(AssetRole.photoRendered)), throwsA(isA<InvariantViolation>()));
    });

    test('invariant 7: location latitude and longitude are both present or both absent', () {
      expect(MemoryLocation.fromNullable(), isNull);
      expect(MemoryLocation.fromNullable(lat: 3.1, lon: 101.6)!.lat, 3.1);
      expect(() => MemoryLocation.fromNullable(lat: 3.1), throwsA(isA<InvariantViolation>()));
      expect(() => MemoryLocation.fromNullable(lon: 3.1), throwsA(isA<InvariantViolation>()));
      for (final bad in <List<double>>[[91, 0], [-91, 0], [0, 181], [0, -181], [double.nan, 0], [0, double.infinity]]) {
        expect(() => MemoryLocation(lat: bad[0], lon: bad[1]), throwsA(isA<InvariantViolation>()), reason: '$bad');
      }
      expect(MemoryLocation(lat: 90, lon: -180), MemoryLocation(lat: 90, lon: -180));
    });

    test('[PRIV-001] removing the location clears it as a whole and bumps the version', () {
      final m = memory(location: MemoryLocation(lat: 1, lon: 2, accuracyM: 5));
      final cleared = m.withoutLocation();
      expect(cleared.location, isNull);
      expect(cleared.version, 2);
      expect(cleared.toRegisterJson().containsKey('location'), isFalse);
    });

    test('ids, handles, time zone and caption are validated', () {
      expect(() => memory(id: 'not-a-uuid'), throwsA(isA<InvariantViolation>()));
      expect(() => memory(handleValue: 'short'), throwsA(isA<InvariantViolation>()));
      expect(() => memory(handleValue: '!' * 22), throwsA(isA<InvariantViolation>()));
      expect(() => memory(tz: '  '), throwsA(isA<InvariantViolation>()));
      expect(() => memory(caption: 'x' * 2001), throwsA(isA<InvariantViolation>()));
      expect(memory(caption: 'x' * 2000).caption!.length, 2000);
      expect(() => memory(assets: <Asset>[Asset(id: 'o', memoryId: 'other', role: AssetRole.photoOriginal, mime: 'a/b', bytes: 1)]), throwsA(isA<InvariantViolation>()));
    });

    test('validate() lists every problem at once', () {
      try {
        memory(id: 'bad', handleValue: 'bad', assets: <Asset>[]);
        fail('should throw');
      } on InvariantViolation catch (e) {
        expect(e.message, allOf(contains('UUID'), contains('22 base62'), contains('photo_original')));
      }
    });
  });

  group('Memory edits', () {
    test('[MEM-004] captions are trimmed, blank clears, version increments each time', () {
      final m = memory();
      expect(m.withCaption('  Golden hour  ').caption, 'Golden hour');
      expect(m.withCaption('  ').caption, isNull);
      expect(m.withCaption(null).caption, isNull);
      expect(m.withCaption('x').version, 2);
      expect(m.withCaption('x').withCaption('y').version, 3);
    });

    test('[MEM-006] favorite toggles', () {
      expect(memory().withFavorite(true).favorite, isTrue);
      expect(memory().withFavorite(true).withFavorite(false).favorite, isFalse);
    });

    test('[MEM-007] trash and restore', () {
      final trashed = memory().trashed(DateTime.utc(2026, 11, 2));
      expect(trashed.isTrashed, isTrue);
      expect(trashed.restored().isTrashed, isFalse);
      expect(trashed.deletedAt, DateTime.utc(2026, 11, 2));
    });

    test('ownership is set when the first upload registers the Memory', () {
      expect(memory().ownerId, isNull);
      expect(memory().withOwner('user-1').ownerId, 'user-1');
    });

    test('equality is by id and version', () {
      expect(memory(), memory());
      expect(memory().hashCode, memory().hashCode);
      expect(memory(), isNot(memory().withFavorite(true)));
    });
  });

  group('sync state (LIB-004)', () {
    Memory withStatuses(List<AssetStatus> statuses) => memory(assets: <Asset>[
          for (var i = 0; i < statuses.length; i++)
            Asset(
              id: 'a$i',
              memoryId: memId,
              role: <AssetRole>[AssetRole.photoOriginal, AssetRole.photoRendered, AssetRole.thumbnail][i],
              mime: 'image/jpeg',
              bytes: 1,
              status: statuses[i],
            ),
        ]);

    test('local only, uploading, synced and failed', () {
      expect(withStatuses(<AssetStatus>[AssetStatus.pending, AssetStatus.pending]).syncState, SyncState.localOnly);
      expect(withStatuses(<AssetStatus>[AssetStatus.uploading, AssetStatus.pending]).syncState, SyncState.uploading);
      expect(withStatuses(<AssetStatus>[AssetStatus.uploaded, AssetStatus.verified]).syncState, SyncState.uploading);
      expect(withStatuses(<AssetStatus>[AssetStatus.verified, AssetStatus.ready]).syncState, SyncState.synced);
      expect(withStatuses(<AssetStatus>[AssetStatus.verified, AssetStatus.failed]).syncState, SyncState.failed);
    });
  });

  group('Asset lifecycle', () {
    test('moves forward through the legal transitions', () {
      var a = asset(AssetRole.photoOriginal);
      for (final next in <AssetStatus>[AssetStatus.uploading, AssetStatus.uploaded, AssetStatus.verified, AssetStatus.ready]) {
        a = a.withStatus(next);
        expect(a.status, next);
      }
    });

    test('illegal transitions throw; failed can be retried', () {
      final a = asset(AssetRole.photoOriginal);
      expect(() => a.withStatus(AssetStatus.uploaded), throwsA(isA<InvariantViolation>()));
      final ready = a.withStatus(AssetStatus.verified).withStatus(AssetStatus.ready);
      expect(() => ready.withStatus(AssetStatus.pending), throwsA(isA<InvariantViolation>()));
      final failed = a.withStatus(AssetStatus.uploading).withStatus(AssetStatus.failed);
      expect(failed.withStatus(AssetStatus.pending).status, AssetStatus.pending);
      expect(() => failed.withStatus(AssetStatus.verified), throwsA(isA<InvariantViolation>()));
      expect(a.withStatus(AssetStatus.uploading).withStatus(AssetStatus.pending).status, AssetStatus.pending);
    });

    test('a dedupe hit can go straight from pending to verified', () {
      expect(asset(AssetRole.photoOriginal).withStatus(AssetStatus.verified).status, AssetStatus.verified);
    });

    test('validates ids, sizes and checksums, and serializes', () {
      expect(() => Asset(id: '', memoryId: memId, role: AssetRole.photoOriginal, mime: 'a/b', bytes: 1), throwsA(isA<InvariantViolation>()));
      expect(() => Asset(id: 'x', memoryId: memId, role: AssetRole.photoOriginal, mime: 'a/b', bytes: -1), throwsA(isA<InvariantViolation>()));
      expect(() => Asset(id: 'x', memoryId: memId, role: AssetRole.photoOriginal, mime: 'a/b', bytes: 1, sha256: 'XYZ'), throwsA(isA<InvariantViolation>()));
      final a = Asset(id: 'x', memoryId: memId, role: AssetRole.motionClip, mime: 'video/mp4', bytes: 5, sha256: sha, width: 1, height: 2, durationMs: 3000, status: AssetStatus.verified, localPath: '/tmp/x');
      expect(a.toJson(), <String, Object?>{'id': 'x', 'memoryId': memId, 'role': 'motion_clip', 'mime': 'video/mp4', 'bytes': 5, 'sha256': sha, 'width': 1, 'height': 2, 'durationMs': 3000, 'status': 'verified'});
      expect(a, a);
      expect(a.hashCode, a.hashCode);
    });

    test('roles map to the API wire names and back', () {
      for (final role in AssetRole.values) {
        expect(AssetRole.fromWire(role.wire), role);
      }
      expect(AssetRole.fromWire('nope'), isNull);
      expect(AssetRole.photoOriginal.wire, 'photo_original');
    });
  });

  group('server contract', () {
    test('[SYNC-004] toRegisterJson matches the PUT /v1/memories body (immutable fields + metadata)', () {
      final m = Memory(
        id: memId,
        kind: MemoryKind.motion,
        capturedAt: DateTime.utc(2026, 11, 1, 9, 30, 15, 250),
        capturedTz: 'Asia/Kuala_Lumpur',
        experienceId: 'mirrorless',
        profile: const ProfileRef('warm-film', 1),
        scenario: 'street',
        presetId: '0192a7c0-1b2c-7d3e-8f4a-5b6c7d8e9f02',
        capture: const CaptureMetadata(lensKind: LensKind.wide, focalLength35mmEq: 26, aperture: 1.8, isoApplied: 200, exposureTimeNsApplied: 8000000, widthPx: 4000, heightPx: 3000),
        location: MemoryLocation(lat: 3.139, lon: 101.6869, accuracyM: 8),
        caption: 'Hello',
        favorite: true,
        aspectRatio: '3:2',
        publicHandle: handle,
        assets: <Asset>[asset(AssetRole.photoOriginal), asset(AssetRole.motionClip)],
      );
      final json = m.toRegisterJson();
      expect(json['kind'], 'motion');
      expect(json['capturedAt'], '2026-11-01T09:30:15.250Z');
      expect(json['capturedTz'], 'Asia/Kuala_Lumpur');
      expect(json['experienceId'], 'mirrorless');
      expect(json['profile'], <String, Object?>{'id': 'warm-film', 'version': 1});
      expect(json['presetId'], isNotNull);
      expect(json['location'], <String, Object?>{'lat': 3.139, 'lon': 101.6869, 'accuracyM': 8.0});
      expect(json['caption'], 'Hello');
      expect(json['favorite'], true);
      expect(json['aspectRatio'], '3:2');
      final capture = json['capture']! as Map<String, Object?>;
      // the names the server extracts analytics columns from (services/api memories/routes.ts analyticsColumns)
      expect(capture['lensKind'], 'wide');
      expect(capture['focalLength35mmEq'], 26.0);
      expect(capture['aperture'], 1.8);
      expect(capture['isoApplied'], 200);
      expect(capture['exposureTimeNsApplied'], 8000000);
      expect(json.containsKey('publicHandle'), isFalse); // the handle is server-visible only to the owner, never registered
    });

    test('a minimal Memory registers without optional keys', () {
      final json = memory().toRegisterJson();
      for (final key in <String>['profile', 'presetId', 'scenario', 'location', 'caption', 'aspectRatio']) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json['favorite'], false);
    });
  });

  group('CaptureMetadata', () {
    test('[CAM-050] JSON round trip keeps applied settings, white balance, focus and the requested intent', () {
      final metadata = CaptureMetadata(
        deviceMake: 'Honor',
        deviceModel: 'X9c',
        platform: 'android',
        osVersion: '15',
        appVersion: '1.0.0',
        cameraId: '0',
        lensKind: LensKind.tele,
        focalLengthMm: 6.2,
        focalLength35mmEq: 70,
        aperture: 2.4,
        isoApplied: 400,
        exposureTimeNsApplied: 16000000,
        exposureBiasEv: -0.5,
        whiteBalance: const ResolvedWhiteBalance(preset: WbPreset.auto, kelvin: 5200),
        focusMode: FocusMode.manual,
        focusDistanceDiopters: 2.5,
        flash: FlashMode.off,
        zoomFactor: 3,
        digitalZoom: true,
        hdr: true,
        format: PhotoFormat.heif,
        widthPx: 4000,
        heightPx: 3000,
        requested: const CaptureIntent(iso: 6400),
        adjustments: const <Adjustment>[Adjustment(field: IntentField.iso, requested: 6400, applied: 3200, reason: AdjustmentReason.outOfRange, message: 'm')],
        synthetic: true,
      );
      final json = metadata.toJson();
      expect((json['adjustments']! as List<Object?>).single, <String, Object?>{'field': 'iso', 'requested': '6400', 'applied': '3200', 'reason': 'outOfRange'});
      final copy = CaptureMetadata.fromJson(json);
      expect(copy.deviceModel, 'X9c');
      expect(copy.lensKind, LensKind.tele);
      expect(copy.focalLength35mmEq, 70);
      expect(copy.isoApplied, 400);
      expect(copy.exposureTimeNsApplied, 16000000);
      expect(copy.whiteBalance, const ResolvedWhiteBalance(preset: WbPreset.auto, kelvin: 5200));
      expect(copy.focusMode, FocusMode.manual);
      expect(copy.focusDistanceDiopters, 2.5);
      expect(copy.digitalZoom, isTrue);
      expect(copy.format, PhotoFormat.heif);
      expect(copy.requested!.iso, 6400);
      expect(copy.synthetic, isTrue);
    });

    test('[ADR-0013] synthetic captures are flagged, real ones are not', () {
      expect(const CaptureMetadata().toJson().containsKey('synthetic'), isFalse);
      expect(const CaptureMetadata(synthetic: true).toJson()['synthetic'], isTrue);
    });

    test('fromJson tolerates missing and mistyped fields', () {
      final copy = CaptureMetadata.fromJson(const <String, Object?>{'isoApplied': 'lots', 'lensKind': 'x', 'whiteBalance': 3, 'focus': 'x', 'zoomFactor': '2', 'widthPx': 1.5});
      expect(copy.isoApplied, isNull);
      expect(copy.lensKind, isNull);
      expect(copy.whiteBalance, isNull);
      expect(copy.focusMode, isNull);
      expect(copy.zoomFactor, isNull);
      expect(copy.widthPx, isNull);
      final partialWb = CaptureMetadata.fromJson(const <String, Object?>{'whiteBalance': <String, Object?>{'mode': 'weird'}});
      expect(partialWb.whiteBalance, const ResolvedWhiteBalance(preset: WbPreset.auto));
    });
  });

  group('ids', () {
    test('[MEM-008] public handles are 22 base62 characters and unique', () {
      final rng = math.Random(1);
      final handles = <String>{for (var i = 0; i < 500; i++) generatePublicHandle(random: rng)};
      expect(handles.length, 500);
      for (final h in handles) {
        expect(RegExp(r'^[0-9A-Za-z]{22}$').hasMatch(h), isTrue);
      }
      expect(generatePublicHandle().length, 22);
    });

    test('UUIDv7: version/variant bits, embedded time, and time ordering', () {
      final rng = math.Random(7);
      final a = generateUuidV7(now: DateTime.utc(2026, 1, 1), random: rng);
      final b = generateUuidV7(now: DateTime.utc(2026, 1, 2), random: rng);
      expect(isUuid(a), isTrue);
      expect(a[14], '7');
      expect('89ab'.contains(a[19]), isTrue);
      expect(a.compareTo(b), lessThan(0));
      final ms = int.parse(a.replaceAll('-', '').substring(0, 12), radix: 16);
      expect(ms, DateTime.utc(2026, 1, 1).millisecondsSinceEpoch);
      expect(isUuid(generateUuidV7()), isTrue);
      expect(isUuid('nope'), isFalse);
    });
  });
}
