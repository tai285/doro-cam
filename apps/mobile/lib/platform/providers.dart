import 'dart:io';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/platform.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/platform/adapters.dart';
import 'package:doro_camera/doro_camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Everything the UI needs from the platform, behind providers so tests replace each one.

/// The native camera. Tests override with `DoroCamera(platform: FakeCameraPlatform())`.
final doroCameraProvider = Provider<DoroCamera>((ref) => DoroCamera());

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('Override tokenStoreProvider at start-up.'),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => const SystemFeedbackService(),
);

final shareServiceProvider = Provider<ShareService>(
  (ref) => const SharePlusService(),
);

/// Where a capture is written before the repository adopts it.
final captureTempDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/captures');
    await dir.create(recursive: true);
    return dir;
  },
);

final clockProvider = Provider<Clock>((ref) => systemClock);

final idGeneratorProvider = Provider<IdGenerator>((ref) => IdGenerator());

final appVersionProvider = Provider<String>((ref) => '1.0.0+1');

/// Base URL of services/api for the remote-only features (albums, insights).
final apiBaseProvider = Provider<Uri>(
  (ref) => ref.watch(dataLayerProvider).api.baseUrl,
);

/// Riverpod 3 retries a failed provider on its own, which would keep a failed screen on its spinner. Errors are
/// shown immediately with an explicit "Try again" instead (offline is a normal state for this app).
Duration? noProviderRetry(int retryCount, Object error) => null;
