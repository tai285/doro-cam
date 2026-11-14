import 'dart:async';

import 'package:doro_cam/data/data_layer.dart';
import 'package:doro_cam/sync/sync_coordinator.dart';
import 'package:workmanager/workmanager.dart';

/// Unique names and task name used with the OS scheduler. One task kind exists: "run one sync pass".
const String wakeUpWorkName = 'doro.sync.wakeup';
const String periodicWorkName = 'doro.sync.periodic';
const String syncTaskName = 'doro.sync.pass';

/// How often the safety-net pass runs. WorkManager's minimum is 15 minutes; the upload backoff cap is 30.
const Duration periodicSyncInterval = Duration(minutes: 30);

/// The few OS scheduling calls the background sync needs, so the policy in [WorkmanagerBackgroundScheduler] is
/// testable with a fake and only [WorkmanagerPlanner] touches the plugin.
abstract interface class WorkPlanner {
  /// Wires the headless entry point the OS starts when work is due.
  Future<void> initialize(Function dispatcher);

  /// One pass after [delay]. Replaces a pending one with the same [name]. [unmeteredOnly] asks the OS to hold
  /// the work until an unmetered (Wi-Fi) network is available, otherwise any connection will do.
  /// The OS also holds it back while the battery is low.
  Future<void> oneOff({required String name, required Duration delay, required bool unmeteredOnly});

  /// A recurring pass, updated in place when it already exists. Same constraints as [oneOff].
  Future<void> periodic({required String name, required Duration every, required bool unmeteredOnly});

  Future<void> cancel(String name);
}

Constraints _constraints({required bool unmeteredOnly}) => Constraints(
  networkType: unmeteredOnly ? NetworkType.unmetered : NetworkType.connected,
  requiresBatteryNotLow: true,
);

/// [WorkPlanner] on WorkManager (Android) and BGTaskScheduler (iOS) through the `workmanager` plugin.
class WorkmanagerPlanner implements WorkPlanner {
  const WorkmanagerPlanner();

  @override
  Future<void> initialize(Function dispatcher) => Workmanager().initialize(dispatcher);

  @override
  Future<void> oneOff({required String name, required Duration delay, required bool unmeteredOnly}) =>
      Workmanager().registerOneOffTask(
        name,
        syncTaskName,
        initialDelay: delay,
        constraints: _constraints(unmeteredOnly: unmeteredOnly),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

  @override
  Future<void> periodic({required String name, required Duration every, required bool unmeteredOnly}) =>
      Workmanager().registerPeriodicTask(
        name,
        syncTaskName,
        frequency: every,
        constraints: _constraints(unmeteredOnly: unmeteredOnly),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );

  @override
  Future<void> cancel(String name) => Workmanager().cancelByUniqueName(name);
}

/// Asks the OS to run a sync pass while the app is not in the foreground (SYNC-002). Best effort: the OS decides
/// when, and correctness never depends on it (docs/architecture/sync.md). The pass itself enforces the sync
/// policy again (Wi-Fi only, battery), so these OS constraints only avoid pointless wake-ups.
///
/// * the wake-up from [SyncCoordinator] is a one-off at the next time a backed-off job is due;
/// * a periodic pass is the safety net that also picks up work after a reboot or an app kill.
class WorkmanagerBackgroundScheduler implements BackgroundScheduler {
  WorkmanagerBackgroundScheduler({
    required this._planner,
    required this._wifiOnly,
    this._now = _utcNow,
  });

  final WorkPlanner _planner;
  final Future<bool> Function() _wifiOnly;
  final DateTime Function() _now;
  StreamSubscription<bool>? _settingSubscription;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Registers the headless entry point and the periodic pass. When [wifiOnlyChanges] emits a new value (the
  /// "Upload on Wi-Fi only" setting changed) the periodic pass is registered again so the OS constraint follows.
  Future<void> start({required Function dispatcher, Stream<bool>? wifiOnlyChanges}) async {
    await _planner.initialize(dispatcher);
    await refresh();
    await _settingSubscription?.cancel();
    _settingSubscription = wifiOnlyChanges?.distinct().skip(1).listen((_) => unawaited(_safeRefresh()));
  }

  /// (Re-)registers the periodic pass with the current Wi-Fi-only setting.
  Future<void> refresh() async => _planner.periodic(
    name: periodicWorkName,
    every: periodicSyncInterval,
    unmeteredOnly: await _wifiOnly(),
  );

  Future<void> _safeRefresh() async {
    try {
      await refresh();
    } on Object {
      // Best effort: the next start registers again.
    }
  }

  @override
  Future<void> scheduleWakeUp(DateTime at) async {
    final wait = at.difference(_now());
    await _planner.oneOff(
      name: wakeUpWorkName,
      delay: wait.isNegative ? Duration.zero : wait,
      unmeteredOnly: await _wifiOnly(),
    );
  }

  /// Cancels the one-off wake-up (the queue is empty). The periodic pass stays: new captures need it.
  @override
  Future<void> cancel() => _planner.cancel(wakeUpWorkName);

  Future<void> dispose() async {
    await _settingSubscription?.cancel();
    _settingSubscription = null;
  }
}

/// One headless sync pass: open the data layer, run [SyncCoordinator.syncOnce], always close. Returns whether the
/// pass ran without an unexpected error (Android retries the work with backoff when it returns false). Network
/// and server failures are not errors here: the upload engine records them and backs off.
Future<bool> runBackgroundSyncPass(Future<DataLayer> Function() open) async {
  DataLayer? data;
  try {
    data = await open();
    await data.sync.syncOnce();
    return true;
  } on Object {
    return false;
  } finally {
    await data?.close();
  }
}
