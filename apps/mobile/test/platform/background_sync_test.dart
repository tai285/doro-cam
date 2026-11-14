import 'dart:async';

import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/platform/background_sync.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';
import 'package:workmanager_android/workmanager_android.dart';

import '../data/support/fake_backend.dart';
import '../data/support/support.dart';
import 'fake_planner.dart';

/// Stands in for the Android implementation of the plugin; extending it keeps `Workmanager()` from replacing it.
class RecordingAndroidWorkmanager extends WorkmanagerAndroid {
  final List<String> calls = [];
  Constraints? constraints;
  Duration? delay;
  Duration? frequency;
  ExistingWorkPolicy? oneOffPolicy;
  ExistingPeriodicWorkPolicy? periodicPolicy;
  String? taskName;

  @override
  Future<void> initialize(Function callbackDispatcher, {bool isInDebugMode = false}) async => calls.add('initialize');

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    calls.add('oneOff:$uniqueName');
    this.taskName = taskName;
    this.constraints = constraints;
    delay = initialDelay;
    oneOffPolicy = existingWorkPolicy;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    calls.add('periodic:$uniqueName');
    this.taskName = taskName;
    this.constraints = constraints;
    this.frequency = frequency;
    periodicPolicy = existingWorkPolicy;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async => calls.add('cancel:$uniqueName');
}

@pragma('vm:entry-point')
void fakeDispatcher() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkmanagerBackgroundScheduler', () {
    late FakePlanner planner;
    late bool wifiOnly;
    final now = DateTime.utc(2026, 11, 14, 12);
    late WorkmanagerBackgroundScheduler scheduler;

    setUp(() {
      planner = FakePlanner();
      wifiOnly = true;
      scheduler = WorkmanagerBackgroundScheduler(planner: planner, wifiOnly: () async => wifiOnly, now: () => now);
    });
    tearDown(() => scheduler.dispose());

    test('[SYNC-002] start wires the headless entry point and registers the periodic safety-net pass', () async {
      await scheduler.start(dispatcher: fakeDispatcher);
      expect(planner.dispatcher, same(fakeDispatcher));
      expect(planner.work, hasLength(1));
      expect(planner.work.single.kind, 'periodic');
      expect(planner.work.single.name, periodicWorkName);
      expect(planner.work.single.when, periodicSyncInterval);
      expect(periodicSyncInterval, greaterThanOrEqualTo(const Duration(minutes: 15)));
    });

    test('[SYNC-002] a wake-up is a one-off after the wait until the next job is due', () async {
      await scheduler.scheduleWakeUp(now.add(const Duration(minutes: 7)));
      expect(planner.work.single.kind, 'oneOff');
      expect(planner.work.single.name, wakeUpWorkName);
      expect(planner.work.single.when, const Duration(minutes: 7));
    });

    test('[SYNC-002] a wake-up for a time already past runs without delay', () async {
      await scheduler.scheduleWakeUp(now.subtract(const Duration(minutes: 3)));
      expect(planner.work.single.when, Duration.zero);
    });

    test('[SYNC-005] with Wi-Fi only on, the OS is told to wait for an unmetered network', () async {
      wifiOnly = true;
      await scheduler.scheduleWakeUp(now);
      await scheduler.refresh();
      expect(planner.work.map((w) => w.unmeteredOnly), [true, true]);
    });

    test('[SYNC-005] with Wi-Fi only off, any connection is enough', () async {
      wifiOnly = false;
      await scheduler.scheduleWakeUp(now);
      await scheduler.refresh();
      expect(planner.work.map((w) => w.unmeteredOnly), [false, false]);
    });

    test('[SYNC-005] changing the Wi-Fi-only setting registers the periodic pass again with the new constraint', () async {
      final changes = StreamController<bool>();
      addTearDown(changes.close);
      await scheduler.start(dispatcher: fakeDispatcher, wifiOnlyChanges: changes.stream);
      expect(planner.work.map((w) => w.unmeteredOnly), [true]);

      changes.add(true); // the initial value of the setting stream: nothing changed
      await pumpEventQueue();
      expect(planner.work, hasLength(1));

      wifiOnly = false;
      changes.add(false);
      await pumpEventQueue();
      expect(planner.work.map((w) => w.unmeteredOnly), [true, false]);

      changes.add(false); // not a change
      await pumpEventQueue();
      expect(planner.work, hasLength(2));
    });

    test('a failure while re-registering is swallowed (best effort) and later changes still register', () async {
      final changes = StreamController<bool>();
      addTearDown(changes.close);
      await scheduler.start(dispatcher: fakeDispatcher, wifiOnlyChanges: changes.stream);
      changes.add(true);
      planner.failNext = StateError('os refused');
      wifiOnly = false;
      changes.add(false);
      await pumpEventQueue();
      wifiOnly = true;
      changes.add(true);
      await pumpEventQueue();
      expect(planner.work.map((w) => w.unmeteredOnly), [true, true]);
    });

    test('starting again replaces the setting subscription instead of stacking it', () async {
      final first = StreamController<bool>();
      final second = StreamController<bool>();
      addTearDown(first.close);
      addTearDown(second.close);
      await scheduler.start(dispatcher: fakeDispatcher, wifiOnlyChanges: first.stream);
      await scheduler.start(dispatcher: fakeDispatcher, wifiOnlyChanges: second.stream);
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);
      await scheduler.dispose();
      expect(second.hasListener, isFalse);
    });

    test('[SYNC-002] cancel removes the pending wake-up but keeps the periodic pass', () async {
      await scheduler.cancel();
      expect(planner.cancelled, [wakeUpWorkName]);
    });
  });

  group('WorkmanagerPlanner (against a stand-in for the Android plugin)', () {
    late RecordingAndroidWorkmanager platform;
    setUp(() {
      platform = RecordingAndroidWorkmanager();
      WorkmanagerPlatform.instance = platform;
    });

    test('[SYNC-002][SYNC-005] a one-off is replaced in place, needs the battery not low and an unmetered network when asked', () async {
      const planner = WorkmanagerPlanner();
      await planner.initialize(fakeDispatcher);
      await planner.oneOff(name: wakeUpWorkName, delay: const Duration(seconds: 90), unmeteredOnly: true);
      expect(platform.calls, ['initialize', 'oneOff:$wakeUpWorkName']);
      expect(platform.taskName, syncTaskName);
      expect(platform.delay, const Duration(seconds: 90));
      expect(platform.oneOffPolicy, ExistingWorkPolicy.replace);
      expect(platform.constraints!.networkType, NetworkType.unmetered);
      expect(platform.constraints!.requiresBatteryNotLow, isTrue);
      expect(platform.constraints!.requiresCharging, isNull);
    });

    test('[SYNC-005] any connected network is enough when Wi-Fi only is off', () async {
      await const WorkmanagerPlanner().oneOff(name: wakeUpWorkName, delay: Duration.zero, unmeteredOnly: false);
      expect(platform.constraints!.networkType, NetworkType.connected);
    });

    test('[SYNC-002] the periodic pass updates the existing registration', () async {
      await const WorkmanagerPlanner().periodic(name: periodicWorkName, every: periodicSyncInterval, unmeteredOnly: true);
      expect(platform.calls, ['periodic:$periodicWorkName']);
      expect(platform.frequency, periodicSyncInterval);
      expect(platform.periodicPolicy, ExistingPeriodicWorkPolicy.update);
      expect(platform.constraints!.networkType, NetworkType.unmetered);
      expect(platform.taskName, syncTaskName);
    });

    test('cancel goes to the unique work name', () async {
      await const WorkmanagerPlanner().cancel(wakeUpWorkName);
      expect(platform.calls, ['cancel:$wakeUpWorkName']);
    });
  });

  group('runBackgroundSyncPass', () {
    late Scratch scratch;
    late FakeBackend backend;
    late FakeConnectivity connectivity;
    late FakePower power;
    late DataLayer layer;

    setUp(() async {
      scratch = Scratch();
      backend = FakeBackend();
      connectivity = FakeConnectivity();
      power = FakePower();
      layer = await DataLayer.open(
        executor: NativeDatabase.memory(),
        mediaRoot: scratch.sub('media'),
        apiBase: Uri.parse('https://api.test'),
        tokens: InMemoryTokenStore(backend.signInToken),
        connectivity: connectivity,
        power: power,
        httpClient: backend,
      );
      await layer.account.setAccount('user-1');
      await layer.memories.commitCapture(photoDraft(scratch));
    });
    tearDown(() => scratch.dispose());

    Future<DataLayer> open() async => layer;

    test('[SYNC-002][SYNC-001] runs one sync pass over the durable queue, reports success and closes the data layer', () async {
      expect(await runBackgroundSyncPass(open), isTrue);
      expect(backend.assets.values.map((a) => a['status']), everyElement('verified'));
      expect(backend.assets, hasLength(2));
      // closed: using the database again fails
      await expectLater(layer.db.select(layer.db.uploadJobs).get(), throwsA(anything));
    });

    test('[SYNC-005] on a metered network the pass uploads nothing while Wi-Fi only is on, and still succeeds', () async {
      connectivity.kind = NetworkKind.cellular;
      expect(await runBackgroundSyncPass(open), isTrue);
      expect(backend.requests.where((r) => r.startsWith('PUT /o/')), isEmpty);
    });

    test('[SYNC-005] with Wi-Fi only switched off, the pass uploads over a metered network', () async {
      await layer.settings.setWifiOnly(value: false);
      connectivity.kind = NetworkKind.cellular;
      expect(await runBackgroundSyncPass(open), isTrue);
      expect(backend.assets.values.map((a) => a['status']), everyElement('verified'));
    });

    test('a low battery pauses the pass unless the phone is charging', () async {
      power
        ..percent = 8
        ..charging = false;
      expect(await runBackgroundSyncPass(open), isTrue);
      expect(backend.requests.where((r) => r.startsWith('PUT /o/')), isEmpty);
    });

    test('a pass that cannot open the data layer reports failure so the OS retries it', () async {
      await layer.close();
      expect(await runBackgroundSyncPass(() async => throw StateError('no database')), isFalse);
    });

    test('a pass that fails midway still closes the data layer and reports failure', () async {
      await layer.close();
      // The layer is already closed, so the sync pass itself throws; closing again must not hide that.
      expect(await runBackgroundSyncPass(open), isFalse);
    });
  });
}
