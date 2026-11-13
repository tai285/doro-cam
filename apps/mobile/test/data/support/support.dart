import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:doro_cam/data/preset_repository.dart';
import 'package:doro_cam/data/settings_repository.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/outbox_pusher.dart';
import 'package:doro_cam/sync/pull_sync.dart';
import 'package:doro_cam/sync/storage_uploader.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;

import 'fake_backend.dart';

/// A clock tests move by hand.
class TestClock {
  TestClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 11, 13, 12);
  DateTime _now;

  DateTime call() => _now;
  void advance(Duration by) => _now = _now.add(by);
  set now(DateTime value) => _now = value;
}

class FakeConnectivity implements ConnectivityMonitor {
  FakeConnectivity([this.kind = NetworkKind.wifi]);
  NetworkKind kind;
  final StreamController<NetworkKind> _controller = StreamController<NetworkKind>.broadcast();

  void set(NetworkKind value) {
    kind = value;
    _controller.add(value);
  }

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _controller.stream;
}

class FakePower implements PowerMonitor {
  int percent = 100;
  bool charging = false;

  @override
  Future<({int percent, bool charging})> current() async => (percent: percent, charging: charging);
}

/// A scratch directory removed by [dispose].
class Scratch {
  Scratch() : dir = Directory.systemTemp.createTempSync('doro_data_test_');
  final Directory dir;
  int _n = 0;

  Directory sub(String name) => Directory('${dir.path}/$name')..createSync(recursive: true);

  /// Creates a file with [size] deterministic pseudo-random bytes.
  File file(String name, {int size = 4096, int seed = 1}) {
    final file = File('${dir.path}/${_n++}_$name');
    final random = Random(seed);
    final bytes = List<int>.generate(size, (_) => random.nextInt(256));
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// A large file made of 1 MiB blocks that each differ, written in chunks (so 200 MB is cheap).
  File bigFile(String name, int size, {int seed = 1}) {
    final file = File('${dir.path}/${_n++}_$name');
    final random = Random(seed);
    final block = Uint8List.fromList(List<int>.generate(1024 * 1024, (_) => random.nextInt(256)));
    final handle = file.openSync(mode: FileMode.write);
    var written = 0;
    var index = 0;
    while (written < size) {
      final length = min(block.length, size - written);
      block[0] = index & 0xff;
      block[1] = (index >> 8) & 0xff;
      handle.writeFromSync(block, 0, length);
      written += length;
      index++;
    }
    handle.closeSync();
    return file;
  }

  void dispose() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// Everything the data layer needs, wired against an in-memory SQLite database and a [FakeBackend].
class Env {
  Env._(this.scratch, this.db, this.clock, this.account, this.settings, this.media, this.memories, this.presets, this.backend, this.api, this.tokens, this.auth, this.connectivity, this.power, this.engine, this.outbox, this.pull, this.sync);

  final Scratch scratch;
  final AppDatabase db;
  final TestClock clock;
  final AccountContext account;
  final SettingsRepository settings;
  final MediaStore media;
  final MemoryRepository memories;
  final PresetRepository presets;
  final FakeBackend backend;
  final DoroApiClient api;
  final InMemoryTokenStore tokens;
  final AuthService auth;
  final FakeConnectivity connectivity;
  final FakePower power;
  UploadEngine engine;
  final OutboxPusher outbox;
  final PullSync pull;
  final SyncCoordinator sync;

  static Future<Env> create({
    FakeBackend? backend,
    http.Client? httpClient,
    Uri? baseUrl,
    UploadEngineConfig config = const UploadEngineConfig(),
    FutureOr<void> Function(String point)? checkpoint,
    AppDatabase? database,
    Scratch? scratch,
    String? signedInAs,
    int randomSeed = 7,
  }) async {
    // Tests open several short-lived databases in one isolate on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final scratch0 = scratch ?? Scratch();
    final db = database ?? AppDatabase(NativeDatabase.memory());
    final clock = TestClock();
    final settings = SettingsRepository(db);
    final account = AccountContext(settings);
    final media = MediaStore(scratch0.sub('media'));
    final memories = MemoryRepository(db: db, account: account, media: media, clock: clock.call);
    final presets = PresetRepository(db: db, account: account, clock: clock.call);
    final fake = backend ?? FakeBackend();
    final client = httpClient ?? fake;
    final tokens = InMemoryTokenStore(signedInAs == null ? null : fake.signInToken);
    final api = DoroApiClient(baseUrl: baseUrl ?? Uri.parse('https://api.test'), httpClient: client, token: tokens.read);
    final auth = AuthService(client: api, tokens: tokens, account: account, memories: memories);
    final connectivity = FakeConnectivity();
    final power = FakePower();
    final engine = UploadEngine(
      db: db,
      api: api,
      storage: StorageUploader(client),
      connectivity: connectivity,
      account: account,
      settings: settings,
      power: power,
      config: config,
      clock: clock.call,
      random: Random(randomSeed),
      sleeper: (_) async {},
      checkpoint: checkpoint,
    );
    final outbox = OutboxPusher(db: db, api: api, account: account);
    final pull = PullSync(db: db, api: api, account: account, clock: clock.call);
    final sync = SyncCoordinator(uploads: engine, outbox: outbox, pull: pull, connectivity: connectivity, account: account);
    if (signedInAs != null) {
      await account.setAccount(signedInAs);
    }
    return Env._(scratch0, db, clock, account, settings, media, memories, presets, fake, api, tokens, auth, connectivity, power, engine, outbox, pull, sync);
  }

  /// A second engine on the same database, as after the app was killed and restarted.
  UploadEngine restartEngine({FutureOr<void> Function(String point)? checkpoint, UploadEngineConfig config = const UploadEngineConfig(), http.Client? httpClient}) {
    final client = httpClient ?? backend;
    final api2 = DoroApiClient(baseUrl: api.baseUrl, httpClient: client, token: tokens.read);
    return UploadEngine(
      db: db,
      api: api2,
      storage: StorageUploader(client),
      connectivity: connectivity,
      account: account,
      settings: settings,
      power: power,
      config: config,
      clock: clock.call,
      random: Random(11),
      sleeper: (_) async {},
      checkpoint: checkpoint,
    );
  }

  Future<void> close() async {
    await sync.stop();
    await auth.dispose();
    await account.dispose();
    await db.close();
    scratch.dispose();
  }
}

int _draftCounter = 0;

/// A valid photo capture draft whose files live in [scratch].
CaptureDraft photoDraft(
  Scratch scratch, {
  String? id,
  String kind = MemoryKinds.photo,
  DateTime? capturedAt,
  int originalSize = 4096,
  int seed = 1,
  bool withThumbnail = true,
  bool withClip = false,
  String? caption,
  double? lat,
  double? lon,
  Map<String, Object?>? capture,
}) {
  _draftCounter++;
  final memoryId = id ?? IdGenerator().newId();
  final assets = <DraftAsset>[
    DraftAsset(role: AssetRoles.photoOriginal, path: scratch.file('orig.jpg', size: originalSize, seed: seed + _draftCounter).path, mime: 'image/jpeg', width: 4000, height: 3000),
    if (withThumbnail) DraftAsset(role: AssetRoles.thumbnail, path: scratch.file('thumb.jpg', size: 512, seed: seed + 100 + _draftCounter).path, mime: 'image/jpeg', width: 512, height: 384),
    if (withClip || kind == MemoryKinds.motion) DraftAsset(role: AssetRoles.motionClip, path: scratch.file('clip.mp4', size: 2048, seed: seed + 200 + _draftCounter).path, mime: 'video/mp4', durationMs: 3000),
  ];
  return CaptureDraft(
    id: memoryId,
    kind: kind,
    capturedAt: capturedAt ?? DateTime.utc(2026, 11, 1, 9, 30),
    capturedTz: 'Asia/Kuala_Lumpur',
    experienceId: 'mirrorless',
    profileId: 'natural',
    profileVersion: 1,
    scenario: 'street',
    capture: capture ?? {'lensKind': 'wide', 'focalLength35mmEq': 26, 'aperture': 1.8, 'isoApplied': 200, 'exposureTimeNsApplied': 8000000, 'widthPx': 4000, 'heightPx': 3000},
    assets: assets,
    lat: lat,
    lon: lon,
    caption: caption,
  );
}
