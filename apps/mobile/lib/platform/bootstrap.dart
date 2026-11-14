import 'dart:async';
import 'dart:io';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:doro_cam/platform/background_sync.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

/// Where the API is. Override at build time: `--dart-define=API_URL=https://api.example.com`.
/// The Android emulator reaches the host machine at 10.0.2.2.
Uri defaultApiBase() {
  const configured = String.fromEnvironment('API_URL');
  if (configured.isNotEmpty) {
    return Uri.parse(configured);
  }
  return Uri.parse(
    !kIsWeb && Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000',
  );
}

class AppRuntime {
  const AppRuntime({required this.data, required this.tokens});
  final DataLayer data;
  final TokenStore tokens;
}

/// Opens the database and every service. [background] hands work to the OS scheduler; the headless background
/// pass passes none (it must not replace the work item it is running in).
Future<DataLayer> openDataLayer({
  TokenStore? tokens,
  Uri? apiBase,
  BackgroundScheduler background = const NoBackgroundScheduler(),
  Future<Directory> Function() documents = getApplicationDocumentsDirectory,
}) async {
  final docs = await documents();
  final media = Directory(p.join(docs.path, 'media'));
  await media.create(recursive: true);
  return DataLayer.open(
    // The app and a background pass can hold the file at the same time: wait for the lock instead of failing.
    executor: NativeDatabase.createInBackground(
      File(p.join(docs.path, 'doro.sqlite')),
      setup: (db) => db.execute('PRAGMA busy_timeout = 5000;'),
    ),
    mediaRoot: media,
    apiBase: apiBase ?? defaultApiBase(),
    tokens: tokens ?? SecureTokenStore(),
    connectivity: PlusConnectivityMonitor(),
    power: BatteryPowerMonitor(),
    background: background,
  );
}

/// Headless entry point the OS starts for background work (WorkManager / BGTaskScheduler, SYNC-002).
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask(
    (task, inputData) => runBackgroundSyncPass(openDataLayer),
  );
}

bool get _hasBackgroundSupport =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Opens the database, wires the platform adapters and restores the session. Never blocks the camera on the
/// network: sign-in restore, background registration and sync run without being awaited (NFR-001).
///
/// [planner] is the OS scheduling seam; by default the WorkManager / BGTaskScheduler plugin on Android and iOS and
/// nothing elsewhere. [documents] locates app storage.
Future<AppRuntime> bootstrap({
  Uri? apiBase,
  WorkPlanner? planner,
  Future<Directory> Function() documents = getApplicationDocumentsDirectory,
}) async {
  final tokens = SecureTokenStore();
  late final DataLayer data;
  final effectivePlanner =
      planner ?? (_hasBackgroundSupport ? const WorkmanagerPlanner() : null);
  WorkmanagerBackgroundScheduler? scheduler;
  if (effectivePlanner != null) {
    scheduler = WorkmanagerBackgroundScheduler(
      planner: effectivePlanner,
      wifiOnly: () => data.settings.wifiOnly(),
    );
  }
  data = await openDataLayer(
    tokens: tokens,
    apiBase: apiBase,
    background: scheduler ?? const NoBackgroundScheduler(),
    documents: documents,
  );
  if (scheduler != null) {
    unawaited(_registerBackground(scheduler, data));
  }
  unawaited(_housekeeping(data));
  return AppRuntime(data: data, tokens: tokens);
}

Future<void> _registerBackground(
  WorkmanagerBackgroundScheduler scheduler,
  DataLayer data,
) async {
  try {
    await scheduler.start(
      dispatcher: backgroundCallbackDispatcher,
      wifiOnlyChanges: data.settings.watchWifiOnly(),
    );
  } on Object catch (error) {
    debugPrint('Background sync not registered: $error');
  }
}

Future<void> _housekeeping(DataLayer data) async {
  try {
    await data.memories.recoverOrphans();
    await data.memories.purgeExpired();
    await data.auth.restore();
    data.sync.start();
    await data.sync.syncOnce();
  } on Object catch (error) {
    debugPrint('Start-up housekeeping skipped: $error');
  }
}
