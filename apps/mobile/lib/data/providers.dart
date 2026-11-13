// ignore_for_file: prefer_initializing_formals
import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/preset_repository.dart';
import 'package:doro_cam/data/settings_repository.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The data layer. Override it at app start with the opened [DataLayer]:
///
/// ```dart
/// ProviderScope(overrides: [dataLayerProvider.overrideWithValue(layer)], child: ...)
/// ```
final dataLayerProvider = Provider<DataLayer>((ref) => throw UnimplementedError('Override dataLayerProvider with an opened DataLayer.'));

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) => ref.watch(dataLayerProvider).memories);
final presetRepositoryProvider = Provider<PresetRepository>((ref) => ref.watch(dataLayerProvider).presets);
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => ref.watch(dataLayerProvider).settings);
final authServiceProvider = Provider<AuthService>((ref) => ref.watch(dataLayerProvider).auth);
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) => ref.watch(dataLayerProvider).sync);
final appDatabaseProvider = Provider<AppDatabase>((ref) => ref.watch(dataLayerProvider).db);

/// What the library screen asks for.
class LibraryQuery {
  const LibraryQuery({this.kind, this.favoritesOnly = false, this.trashed = false});
  final String? kind;
  final bool favoritesOnly;
  final bool trashed;

  @override
  bool operator ==(Object other) => other is LibraryQuery && other.kind == kind && other.favoritesOnly == favoritesOnly && other.trashed == trashed;

  @override
  int get hashCode => Object.hash(kind, favoritesOnly, trashed);
}

/// Memories newest first, read from the local database only (LIB-001), live-updating with sync status (LIB-004).
final libraryProvider = StreamProvider.family<List<MemoryView>, LibraryQuery>(
  (ref, query) => ref.watch(memoryRepositoryProvider).watchLibrary(kind: query.kind, favoritesOnly: query.favoritesOnly, trashed: query.trashed),
);

/// One Memory, live.
final memoryProvider = StreamProvider.family<MemoryView?, String>((ref, id) => ref.watch(memoryRepositoryProvider).watchMemory(id));

final presetsProvider = StreamProvider<List<PresetRow>>((ref) => ref.watch(presetRepositoryProvider).watch());

/// SYNC-005: Wi-Fi-only uploads (default on).
final wifiOnlyProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepositoryProvider).watchWifiOnly());

/// PRIV-001: location capture (default off).
final captureLocationProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepositoryProvider).watchCaptureLocation());

/// Upload events: asset synced / failed, sign-in needed, quota exceeded.
final uploadEventsProvider = StreamProvider<UploadEvent>((ref) => ref.watch(dataLayerProvider).uploads.events);

/// The signed-in account id, or null while anonymous (AUTH-005).
final accountIdProvider = StreamProvider<String?>((ref) async* {
  final layer = ref.watch(dataLayerProvider);
  yield layer.account.accountId;
  yield* layer.account.changes;
});
