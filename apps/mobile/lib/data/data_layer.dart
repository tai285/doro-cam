// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:doro_cam/data/preset_repository.dart';
import 'package:doro_cam/data/settings_repository.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/outbox_pusher.dart';
import 'package:doro_cam/sync/pull_sync.dart';
import 'package:doro_cam/sync/storage_uploader.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

/// The wired-up data layer: database, repositories, API client, auth and synchronization.
/// The app creates one at start (see `providers.dart`); tests create their own with fakes.
class DataLayer {
  DataLayer._({
    required this.db,
    required this.settings,
    required this.account,
    required this.media,
    required this.memories,
    required this.presets,
    required this.api,
    required this.auth,
    required this.uploads,
    required this.outbox,
    required this.pull,
    required this.sync,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final AccountContext account;
  final MediaStore media;
  final MemoryRepository memories;
  final PresetRepository presets;
  final DoroApiClient api;
  final AuthService auth;
  final UploadEngine uploads;
  final OutboxPusher outbox;
  final PullSync pull;
  final SyncCoordinator sync;

  /// Opens (or creates) the local database and builds every service.
  ///
  /// * [executor] — the drift executor, for example `NativeDatabase.createInBackground(file)`.
  /// * [mediaRoot] — where originals live on this device.
  /// * [apiBase] — base URL of services/api.
  /// * [tokens] — secure storage for the session token.
  /// * [connectivity] — platform connectivity (and optionally [power]).
  static Future<DataLayer> open({
    required QueryExecutor executor,
    required Directory mediaRoot,
    required Uri apiBase,
    required TokenStore tokens,
    required ConnectivityMonitor connectivity,
    PowerMonitor power = const UnlimitedPower(),
    BackgroundScheduler background = const NoBackgroundScheduler(),
    http.Client? httpClient,
    Clock clock = systemClock,
  }) async {
    final db = AppDatabase(executor);
    final settings = SettingsRepository(db);
    final account = await AccountContext.restore(settings);
    final media = MediaStore(mediaRoot);
    final memories = MemoryRepository(db: db, account: account, media: media, clock: clock);
    final presets = PresetRepository(db: db, account: account, clock: clock);
    final client = httpClient ?? http.Client();
    final api = DoroApiClient(baseUrl: apiBase, httpClient: client, token: tokens.read);
    final auth = AuthService(client: api, tokens: tokens, account: account, memories: memories);
    final uploads = UploadEngine(
      db: db,
      api: api,
      storage: StorageUploader(client),
      connectivity: connectivity,
      account: account,
      settings: settings,
      power: power,
      clock: clock,
    );
    final outbox = OutboxPusher(db: db, api: api, account: account);
    final pull = PullSync(db: db, api: api, account: account, clock: clock);
    final sync = SyncCoordinator(
      uploads: uploads,
      outbox: outbox,
      pull: pull,
      connectivity: connectivity,
      account: account,
      background: background,
    );
    return DataLayer._(
      db: db,
      settings: settings,
      account: account,
      media: media,
      memories: memories,
      presets: presets,
      api: api,
      auth: auth,
      uploads: uploads,
      outbox: outbox,
      pull: pull,
      sync: sync,
    );
  }

  Future<void> close() async {
    await sync.stop();
    await auth.dispose();
    await uploads.dispose();
    await account.dispose();
    api.close();
    await db.close();
  }
}
