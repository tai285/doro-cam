import 'dart:async';
import 'dart:io';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Opens the database, wires the platform adapters and restores the session. Never blocks the camera on the
/// network: sign-in restore and sync run in the background (NFR-001).
Future<AppRuntime> bootstrap({Uri? apiBase}) async {
  final docs = await getApplicationDocumentsDirectory();
  final media = Directory(p.join(docs.path, 'media'));
  await media.create(recursive: true);
  final tokens = SecureTokenStore();
  final data = await DataLayer.open(
    executor: NativeDatabase.createInBackground(
      File(p.join(docs.path, 'doro.sqlite')),
    ),
    mediaRoot: media,
    apiBase: apiBase ?? defaultApiBase(),
    tokens: tokens,
    connectivity: PlusConnectivityMonitor(),
    power: BatteryPowerMonitor(),
  );
  unawaited(_housekeeping(data));
  return AppRuntime(data: data, tokens: tokens);
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
