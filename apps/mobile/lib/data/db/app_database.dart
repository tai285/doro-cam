// ignore_for_file: prefer_initializing_formals
import 'package:doro_cam/data/db/tables.dart';
import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// One schema migration step: brings a database from version `to - 1` to `to`.
typedef MigrationStep = Future<void> Function(Migrator migrator, AppDatabase db);

/// Thrown when an on-disk database is newer than this app understands. Opening it would risk
/// corrupting data written by a newer version, so the app refuses instead.
class DatabaseDowngradeError extends StateError {
  DatabaseDowngradeError(int found, int supported)
    : super('The local database is version $found but this app supports up to $supported.');
}

/// The device database (docs/architecture/sync.md). Version 1 is the first release; every later
/// schema change adds one entry to [migrationSteps], and `test/data/db/migration_test.dart` covers
/// each step.
@DriftDatabase(tables: [Memories, Assets, UploadJobs, UploadParts, Outbox, SyncState, Presets, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {this.extraSteps = const []});

  /// Steps after version 1, in order. Production passes none until a schema change ships; tests
  /// inject steps to exercise the upgrade mechanism.
  final List<MigrationStep> extraSteps;

  @override
  int get schemaVersion => 1 + extraSteps.length;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from > to) {
        throw DatabaseDowngradeError(from, to);
      }
      for (var version = from + 1; version <= to; version++) {
        await extraSteps[version - 2](m, this);
      }
    },
    beforeOpen: (details) async {
      if (details.hadUpgrade && details.versionBefore != null && details.versionBefore! > details.versionNow) {
        throw DatabaseDowngradeError(details.versionBefore!, details.versionNow);
      }
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
