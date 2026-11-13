import 'dart:async';
import 'dart:io';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/support.dart';

/// Waits for the first data value of a stream provider. A listener is needed: Riverpod pauses providers nobody listens to.
Future<T> firstValue<T>(
  ProviderSubscription<AsyncValue<T>> Function(void Function(AsyncValue<T>? previous, AsyncValue<T> next) listener) subscribe, {
  bool Function(T value)? where,
}) {
  final completer = Completer<T>();
  late final ProviderSubscription<AsyncValue<T>> subscription;
  subscription = subscribe((_, next) {
    if (next.hasValue && !completer.isCompleted && (where == null || where(next.requireValue))) {
      completer.complete(next.requireValue);
    }
  });
  return completer.future.whenComplete(subscription.close);
}

void main() {
  late Scratch scratch;
  late FakeBackend backend;
  late DataLayer layer;
  late ProviderContainer container;

  setUp(() async {
    scratch = Scratch();
    backend = FakeBackend();
    layer = await DataLayer.open(
      executor: NativeDatabase.memory(),
      mediaRoot: scratch.sub('media'),
      apiBase: Uri.parse('https://api.test'),
      tokens: InMemoryTokenStore(),
      connectivity: FakeConnectivity(),
      httpClient: backend,
    );
    container = ProviderContainer(overrides: [dataLayerProvider.overrideWithValue(layer)]);
  });
  tearDown(() async {
    container.dispose();
    await layer.close();
    scratch.dispose();
  });

  test('open wires every service and starts anonymous', () {
    expect(layer.account.isSignedIn, isFalse);
    expect(container.read(memoryRepositoryProvider), same(layer.memories));
    expect(container.read(presetRepositoryProvider), same(layer.presets));
    expect(container.read(settingsRepositoryProvider), same(layer.settings));
    expect(container.read(authServiceProvider), same(layer.auth));
    expect(container.read(syncCoordinatorProvider), same(layer.sync));
    expect(container.read(appDatabaseProvider), same(layer.db));
  });

  test('without an override the data layer provider fails loudly', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(dataLayerProvider), throwsA(anything));
  });

  test('[LIB-001] libraryProvider streams Memories from the local database and follows edits', () async {
    final seen = <List<String?>>[];
    final sub = container.listen(libraryProvider(const LibraryQuery()), (_, next) => next.whenData((views) => seen.add([for (final v in views) v.memory.caption])), fireImmediately: true);
    final view = await layer.memories.commitCapture(photoDraft(scratch));
    await pumpEventQueue(times: 30);
    await layer.memories.setCaption(view.memory.id, 'Hello');
    await pumpEventQueue(times: 30);
    sub.close();
    expect(seen.last, ['Hello']);
    final single = await firstValue<MemoryView?>((l) => container.listen(memoryProvider(view.memory.id), l, fireImmediately: true));
    expect(single!.memory.caption, 'Hello');
  });

  test('library queries compare by value and filter', () async {
    expect(const LibraryQuery(kind: 'photo', favoritesOnly: true), const LibraryQuery(kind: 'photo', favoritesOnly: true));
    expect(const LibraryQuery(kind: 'photo').hashCode, const LibraryQuery(kind: 'photo').hashCode);
    expect(const LibraryQuery(trashed: true) == const LibraryQuery(), isFalse);
    await layer.memories.commitCapture(photoDraft(scratch, kind: MemoryKinds.motion));
    await layer.memories.commitCapture(photoDraft(scratch));
    expect(await firstValue<List<MemoryView>>((l) => container.listen(libraryProvider(const LibraryQuery(kind: MemoryKinds.motion)), l, fireImmediately: true)), hasLength(1));
  });

  test('[SYNC-005][PRIV-001] settings providers expose the defaults and changes', () async {
    expect(await firstValue<bool>((l) => container.listen(wifiOnlyProvider, l, fireImmediately: true)), isTrue);
    expect(await firstValue<bool>((l) => container.listen(captureLocationProvider, l, fireImmediately: true)), isFalse);
    await layer.settings.setWifiOnly(value: false);
    await layer.settings.setCaptureLocation(value: true);
    expect(await firstValue<bool>((l) => container.listen(wifiOnlyProvider, l, fireImmediately: true), where: (v) => !v), isFalse);
    expect(await firstValue<bool>((l) => container.listen(captureLocationProvider, l, fireImmediately: true), where: (v) => v), isTrue);
  });

  test('[EXP-007] presetsProvider streams the saved presets', () async {
    await layer.presets.save(name: 'Street', experienceId: 'mirrorless', intent: const {});
    expect((await firstValue<List<PresetRow>>((l) => container.listen(presetsProvider, l, fireImmediately: true))).single.name, 'Street');
  });

  test('[AUTH-005] accountIdProvider starts null and follows sign-in; upload events are exposed', () async {
    final ids = <String?>[];
    final sub = container.listen(accountIdProvider, (_, next) => next.whenData(ids.add), fireImmediately: true);
    await pumpEventQueue(times: 20);
    await layer.auth.signIn(email: 'd@example.test', password: 'correct-password');
    await pumpEventQueue(times: 20);
    sub.close();
    expect(ids, [null, 'user-1']);

    final events = <UploadEvent>[];
    final eventSub = container.listen(uploadEventsProvider, (_, next) => next.whenData(events.add));
    await layer.memories.commitCapture(photoDraft(scratch, withThumbnail: false));
    await layer.uploads.drain();
    await pumpEventQueue(times: 20);
    eventSub.close();
    expect(events.whereType<NeedsSignIn>(), isEmpty); // the fake backend accepts the token
  });

  test('close releases the database and is safe to call once', () async {
    final other = await DataLayer.open(
      executor: NativeDatabase.memory(),
      mediaRoot: Directory('${scratch.dir.path}/other'),
      apiBase: Uri.parse('https://api.test'),
      tokens: InMemoryTokenStore(),
      connectivity: FakeConnectivity(),
      httpClient: backend,
    );
    await other.close();
    await expectLater(other.memories.library(), throwsA(anything));
  });
}
