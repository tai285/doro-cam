import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/app/app.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/presentation/preview.dart';
import 'package:doro_cam/features/memory_detail/presentation/motion_player.dart';
import 'package:doro_cam/features/shared/remote_api.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:doro_camera/doro_camera.dart';
import 'package:doro_camera/testing.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/support/fake_backend.dart';
import '../data/support/support.dart';

/// The fake camera, but a capture really writes its files, as the native plugin does, so the data layer can adopt them.
class FileWritingCamera extends FakeCameraPlatform {
  FileWritingCamera({super.permissions, super.cameras, super.capabilities});

  @override
  Future<CaptureResult> capture(int sessionId, CaptureRequest request) async {
    final dir = Directory(request.outputDir)..createSync(recursive: true);
    final jpeg = _tinyImage;
    for (final name in <String?>[
      request.originalName,
      request.renderedName,
      request.thumbnailName,
      request.displayName,
    ]) {
      if (name != null) {
        File('${dir.path}/$name').writeAsBytesSync(jpeg);
      }
    }
    if (request.live && request.motionName != null) {
      File('${dir.path}/${request.motionName}')
          .writeAsBytesSync(<int>[0, 0, 0, 24, 102, 116, 121, 112, 1, 2, 3]);
    }
    return super.capture(sessionId, request);
  }

  @override
  Future<VideoResult> stopVideo(int sessionId) async {
    final request = videos.isEmpty ? null : videos.last;
    if (request != null) {
      File(request.outputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[0, 0, 0, 24, 102, 116, 121, 112, 4, 5, 6]);
    }
    return super.stopVideo(sessionId);
  }
}

/// A real 1x1 image, so widgets that decode the file (the developing print, thumbnails) do not throw.
final Uint8List _tinyImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class FakeFeedback implements FeedbackService {
  final List<String> events = <String>[];

  @override
  Future<void> select() async => events.add('select');

  @override
  Future<void> shutter({required bool sound}) async =>
      events.add(sound ? 'shutter+sound' : 'shutter');

  @override
  Future<void> warn() async => events.add('warn');
}

class FakeShare implements ShareService {
  final List<String> files = <String>[];
  final List<String> texts = <String>[];

  @override
  Future<void> shareFile(String path, {String? mime, String? text}) async =>
      files.add(path);

  @override
  Future<void> shareText(String text) async => texts.add(text);
}

class FakeLocation implements LocationService {
  FakeLocation({this.permission = true, this.fix});

  bool permission;
  DeviceLocation? fix;
  int requests = 0;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<DeviceLocation?> current() async => permission ? fix : null;
}

/// A clip that "plays" instantly, for motion playback tests.
class FakeMotionClip implements MotionClip {
  final StreamController<void> _ended = StreamController<void>.broadcast();
  int plays = 0;
  int stops = 0;
  bool disposed = false;

  void finish() => _ended.add(null);

  @override
  Future<void> prepare() async {}

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<void> get ended => _ended.stream;

  @override
  Widget view() => const SizedBox(key: Key('fake-video'));

  @override
  double get aspectRatio => 16 / 9;

  @override
  void dispose() => disposed = true;
}

/// Everything a screen test needs: a real data layer on in-memory SQLite, a fake backend, and fake platform adapters.
class UiEnv {
  UiEnv._(
    this.scratch,
    this.backend,
    this.data,
    this.camera,
    this.tokens,
    this.remote,
  );

  final Scratch scratch;
  final FakeBackend backend;
  final DataLayer data;
  final FakeCameraPlatform camera;
  final InMemoryTokenStore tokens;
  http.Client remote;
  final FakeFeedback feedback = FakeFeedback();
  final FakeShare share = FakeShare();
  final FakeLocation location = FakeLocation();
  final FakeMotionClip clip = FakeMotionClip();
  late final DoroCamera doro = DoroCamera(platform: camera);

  static Future<UiEnv> create({
    FakeCameraPlatform? camera,
    http.Client? remote,
  }) async {
    final scratch = Scratch();
    final backend = FakeBackend();
    final tokens = InMemoryTokenStore();
    final data = await DataLayer.open(
      executor: NativeDatabase.memory(),
      mediaRoot: scratch.sub('media'),
      apiBase: Uri.parse('https://api.test'),
      tokens: tokens,
      connectivity: FakeConnectivity(),
      httpClient: backend,
    );
    return UiEnv._(
      scratch,
      backend,
      data,
      camera ?? FileWritingCamera(),
      tokens,
      remote ?? backend,
    );
  }

  Future<void> dispose() async {
    await data.close();
    scratch.dispose();
  }

  List<Override> overrides({List<Override> extra = const <Override>[]}) =>
      <Override>[
        dataLayerProvider.overrideWithValue(data),
        doroCameraProvider.overrideWithValue(doro),
        tokenStoreProvider.overrideWithValue(tokens),
        feedbackServiceProvider.overrideWithValue(feedback),
        shareServiceProvider.overrideWithValue(share),
        locationServiceProvider.overrideWithValue(location),
        httpClientProvider.overrideWithValue(remote),
        captureTempDirProvider.overrideWithValue(
          () async => scratch.sub('capture'),
        ),
        cameraDelayProvider.overrideWithValue((_) async {}),
        motionClipFactoryProvider.overrideWithValue((_) => clip),
        previewLookProvider.overrideWith((ref, id) async => null),
        ...extra,
      ];

  /// Saves a Memory exactly as a capture would (real files, real database), so the UI reads what production reads.
  Future<MemoryView> seed({
    String? id,
    String kind = MemoryKinds.photo,
    DateTime? capturedAt,
    String? caption,
    Map<String, Object?>? capture,
    bool withMotion = false,
    double? lat,
    double? lon,
  }) async {
    final memoryId = id ?? IdGenerator().newId();
    final jpeg = _tinyImage;
    File write(String name, {List<int>? bytes}) =>
        (File('${scratch.dir.path}/$memoryId-$name')
          ..writeAsBytesSync(bytes ?? jpeg));
    final draft = CaptureDraft(
      id: memoryId,
      kind: kind,
      capturedAt: capturedAt ?? DateTime.utc(2026, 11, 1, 9, 30),
      capturedTz: 'Etc/GMT-8',
      experienceId: 'mirrorless',
      profileId: 'natural',
      profileVersion: 1,
      caption: caption,
      lat: lat,
      lon: lon,
      aspectRatio: '3:2',
      capture:
          capture ??
          <String, Object?>{
            'lensKind': 'wide',
            'focalLength35mmEq': 26,
            'aperture': 1.8,
            'isoApplied': 200,
            'exposureTimeNsApplied': 8000000,
            'widthPx': 4000,
            'heightPx': 3000,
          },
      assets: <DraftAsset>[
        DraftAsset(
          role: AssetRoles.photoOriginal,
          path: write('orig.jpg').path,
          mime: 'image/jpeg',
          width: 4000,
          height: 3000,
        ),
        DraftAsset(
          role: AssetRoles.photoDisplay,
          path: write('display.jpg').path,
          mime: 'image/jpeg',
        ),
        DraftAsset(
          role: AssetRoles.thumbnail,
          path: write('thumb.jpg').path,
          mime: 'image/jpeg',
        ),
        if (withMotion || kind == MemoryKinds.motion)
          DraftAsset(
            role: AssetRoles.motionClip,
            path: write(
              'motion.mp4',
              bytes: <int>[
                0,
                0,
                0,
                24,
                102,
                116,
                121,
                112,
                109,
                112,
                52,
                50,
                1,
                2,
                3,
              ],
            ).path,
            mime: 'video/mp4',
            durationMs: 3000,
          ),
      ],
    );
    return data.memories.commitCapture(draft);
  }

  MemoryRepository get memories => data.memories;
}

/// The real app at [location] on top of [env]. The introduction is skipped unless [onboarded] is false.
Widget appFor(
  UiEnv env, {
  String location = AppRoutes.camera,
  bool onboarded = true,
  List<Override> extra = const <Override>[],
}) {
  final router = createRouter(
    initialLocation: location,
    isOnboarded: onboarded ? null : () async => false,
  );
  return ProviderScope(
    retry: noProviderRetry,
    overrides: <Override>[
      ...env.overrides(extra: extra),
      routerProvider.overrideWithValue(router),
    ],
    child: const DoroCamApp(),
  );
}

/// Runs real I/O (SQLite, files) outside the fake-async zone of widget tests.
Future<T> io<T>(WidgetTester tester, Future<T> Function() body) async {
  final result = await tester.runAsync(body);
  return result as T;
}

/// Pumps until [finder] matches or the budget runs out, letting real async work (database reads) land in between.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int tries = 60,
}) async {
  for (var i = 0; i < tries; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

/// Pumps until [condition] holds (real async work between frames), or the budget runs out.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  int tries = 80,
}) async {
  for (var i = 0; i < tries && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps a few frames with real async between them (no "settle": streams keep the tree alive).
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Capabilities with specific controls removed, for the "every capability permutation" tests.
CameraCapabilities capsWithout(
  CameraCapabilities full, {
  bool iso = false,
  bool shutter = false,
  bool bias = false,
  bool manualFocus = false,
  bool autoFocus = false,
  bool tapFocus = false,
  bool wbPresets = false,
  bool kelvin = false,
  bool zoom = false,
  bool flash = false,
  bool torch = false,
  bool live = false,
  bool formats = false,
}) {
  return CameraCapabilities(
    cameraId: full.cameraId,
    iso: iso ? null : full.iso,
    exposureTimeNs: shutter ? null : full.exposureTimeNs,
    exposureBias: bias ? null : full.exposureBias,
    apertures: full.apertures,
    focus: FocusCapabilities(
      auto: autoFocus ? false : full.focus.auto,
      continuous: autoFocus ? false : full.focus.continuous,
      tapToFocus: tapFocus ? false : full.focus.tapToFocus,
      manual: manualFocus ? null : full.focus.manual,
    ),
    whiteBalance: WhiteBalanceCapabilities(
      presets: wbPresets
          ? const <WbPreset>[WbPreset.auto]
          : full.whiteBalance.presets,
      kelvin: kelvin ? null : full.whiteBalance.kelvin,
    ),
    zoom: zoom
        ? const ZoomCapabilities(min: 1, max: 1, opticalSteps: <double>[1])
        : full.zoom,
    flash: flash ? const <FlashMode>[FlashMode.off] : full.flash,
    torch: torch ? false : full.torch,
    photoFormats: formats
        ? <PhotoFormat>[PhotoFormat.jpeg, PhotoFormat.heif]
        : full.photoFormats,
    photoSizes: full.photoSizes,
    stabilization: full.stabilization,
    video: full.video,
    hdr: full.hdr,
    live: live
        ? const LiveCapabilities(
            supported: false,
            maxPreBufferMs: 0,
            audio: false,
          )
        : full.live,
    hardwareLevel: full.hardwareLevel,
  );
}

/// A scripted stand-in for the remote-only endpoints (albums, insights). Unknown routes answer 404.
class ScriptedRemote extends http.BaseClient {
  ScriptedRemote(this.routes);

  /// "METHOD /path" -> (decoded JSON body) -> (status, JSON body or null).
  final Map<String, (int, Object?) Function(Map<String, Object?> body)> routes;
  final List<String> requests = <String>[];
  final Map<String, List<Map<String, Object?>>> bodies =
      <String, List<Map<String, Object?>>>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.method} ${request.url.path}';
    requests.add(key);
    var body = <String, Object?>{};
    if (request is http.Request && request.body.isNotEmpty) {
      body = Map<String, Object?>.from(
        jsonDecode(request.body) as Map<Object?, Object?>,
      );
    }
    (bodies[key] ??= <Map<String, Object?>>[]).add(body);
    final handler = routes[key];
    final (status, payload) = handler == null
        ? (
            404,
            <String, Object?>{
              'error': <String, Object?>{
                'code': 'route.not_found',
                'message': 'No route $key',
              },
            },
          )
        : handler(body);
    final bytes = utf8.encode(payload == null ? '' : jsonEncode(payload));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

/// A widget test that drains timers (stream clean-up, focus rings) before it ends, so none outlives the widget tree.
void uiTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

/// Opens the app on [location] with a fresh environment; [prepare] runs real I/O first (seeding, signing in).
Future<UiEnv> launch(
  WidgetTester tester, {
  String location = AppRoutes.camera,
  FakeCameraPlatform? camera,
  http.Client? remote,
  bool onboarded = true,
  Future<void> Function(UiEnv env)? prepare,
  Finder? waitFor,
  List<Override> extra = const <Override>[],
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final env = await io(
    tester,
    () => UiEnv.create(camera: camera, remote: remote),
  );
  addTearDown(() => tester.runAsync(env.dispose));
  if (prepare != null) {
    await io(tester, () => prepare(env));
  }
  await tester.pumpWidget(
    appFor(env, location: location, onboarded: onboarded, extra: extra),
  );
  if (waitFor != null) {
    await pumpUntil(tester, waitFor);
  }
  await settle(tester, frames: 3);
  return env;
}

/// Signs the data layer in against the fake backend, as the sign-in screen does.
Future<void> signIn(UiEnv env) async {
  await env.data.auth.signIn(
    email: 'dorothy@example.test',
    password: env.backend.currentPassword ?? 'correct-password',
  );
}
