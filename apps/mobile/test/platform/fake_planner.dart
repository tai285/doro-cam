import 'package:doro_cam/platform/background_sync.dart';

class PlannedWork {
  PlannedWork(this.kind, this.name, this.when, this.unmeteredOnly);
  final String kind;
  final String name;
  final Duration? when;
  final bool unmeteredOnly;
}

/// Records what would have been handed to the OS.
class FakePlanner implements WorkPlanner {
  final List<PlannedWork> work = [];
  final List<String> cancelled = [];
  Function? dispatcher;
  Object? failNext;

  @override
  Future<void> initialize(Function dispatcher) async => this.dispatcher = dispatcher;

  @override
  Future<void> oneOff({required String name, required Duration delay, required bool unmeteredOnly}) async =>
      work.add(PlannedWork('oneOff', name, delay, unmeteredOnly));

  @override
  Future<void> periodic({required String name, required Duration every, required bool unmeteredOnly}) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    work.add(PlannedWork('periodic', name, every, unmeteredOnly));
  }

  @override
  Future<void> cancel(String name) async => cancelled.add(name);
}
