// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:doro_cam/sync/outbox_pusher.dart';
import 'package:doro_cam/sync/pull_sync.dart';
import 'package:doro_cam/sync/upload_engine.dart';

/// Hands work to the operating system when the app is not in the foreground. The platform adapter
/// (WorkManager on Android, background URLSession on iOS; docs/architecture/sync.md "Background
/// execution") implements this; correctness never depends on it (best effort).
abstract interface class BackgroundScheduler {
  /// Asks the OS to wake the app around [at] to run the queue.
  Future<void> scheduleWakeUp(DateTime at);
  Future<void> cancel();
}

/// Does nothing. Used where there is no background support (tests, desktop).
class NoBackgroundScheduler implements BackgroundScheduler {
  const NoBackgroundScheduler();

  @override
  Future<void> scheduleWakeUp(DateTime at) async {}

  @override
  Future<void> cancel() async {}
}

/// Totals of one synchronization round.
class SyncReport {
  const SyncReport({this.uploaded = 0, this.push = const PushResult(), this.pull = const PullResult()});
  final int uploaded;
  final PushResult push;
  final PullResult pull;
}

/// Runs the three halves of synchronization in order: push local edits, upload media, pull remote
/// changes (docs/architecture/sync.md). In the foreground it re-runs when connectivity returns, the
/// account changes, or a backed-off job becomes due.
class SyncCoordinator {
  SyncCoordinator({
    required UploadEngine uploads,
    required OutboxPusher outbox,
    required PullSync pull,
    required ConnectivityMonitor connectivity,
    required AccountContext account,
    BackgroundScheduler background = const NoBackgroundScheduler(),
  }) : _uploads = uploads,
       _outbox = outbox,
       _pull = pull,
       _connectivity = connectivity,
       _account = account,
       _background = background;

  final UploadEngine _uploads;
  final OutboxPusher _outbox;
  final PullSync _pull;
  final ConnectivityMonitor _connectivity;
  final AccountContext _account;
  final BackgroundScheduler _background;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _timer;
  Future<SyncReport>? _running;
  bool _started = false;

  /// One full round. Concurrent calls share a run.
  Future<SyncReport> syncOnce() => _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    if (!_account.isSignedIn) {
      return const SyncReport();
    }
    final push = await _outbox.push();
    final uploaded = await _uploads.drain();
    // Uploads register Memories, which unblocks edits that were waiting for them.
    final push2 = push.waiting > 0 ? await _outbox.push() : push;
    final pull = await _pull.pull();
    await _scheduleNext();
    return SyncReport(uploaded: uploaded, push: push2, pull: pull);
  }

  Future<void> _scheduleNext() async {
    final due = await _uploads.nextDueAt();
    _timer?.cancel();
    if (due == null) {
      await _background.cancel();
      return;
    }
    final wait = due.difference(DateTime.now().toUtc());
    _timer = Timer(wait.isNegative ? const Duration(seconds: 1) : wait, () => unawaited(_safeSync()));
    await _background.scheduleWakeUp(due);
  }

  Future<void> _safeSync() async {
    try {
      await syncOnce();
    } on Object {
      // Network and server errors are handled inside the engine; anything else is retried on the next trigger.
    }
  }

  /// Starts reacting to connectivity and account changes.
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _subscriptions
      ..add(_connectivity.changes.listen((kind) {
        if (kind != NetworkKind.none) {
          unawaited(_safeSync());
        }
      }))
      ..add(_account.changes.listen((account) {
        if (account != null) {
          unawaited(_safeSync());
        }
      }));
    unawaited(_safeSync());
  }

  Future<void> stop() async {
    _started = false;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
