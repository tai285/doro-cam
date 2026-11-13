import 'dart:io';

import 'package:doro_cam/data/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('doro_migration_');
    file = File('${dir.path}/app.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> userVersion(AppDatabase db) async => (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');

  Future<Set<String>> tables(AppDatabase db) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").get()).map((r) => r.read<String>('name')).toSet();

  test('[MEM-001] a fresh database is created at version 1 with every table', () async {
    final db = AppDatabase(NativeDatabase(file));
    expect(await userVersion(db), 1);
    expect(await tables(db), {'memories', 'assets', 'upload_jobs', 'upload_parts', 'outbox', 'sync_state', 'presets', 'settings'});
    await db.close();
  });

  test('[NFR-001] data survives closing and reopening the database file', () async {
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.settings).insert(SettingsCompanion.insert(key: 'k', value: 'v'));
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.settings).get();
    expect(rows.single.value, 'v');
    expect(await userVersion(db), 1);
    await db.close();
  });

  test('foreign keys are enforced and deleting a Memory cascades to its assets, jobs and parts', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.into(db.memories).insert(MemoriesCompanion.insert(id: 'm1', kind: 'photo', capturedAt: 1, capturedTz: 'UTC', experienceId: 'x', captureJson: '{}', createdAt: 1, updatedAt: 1));
    await db.into(db.assets).insert(AssetsCompanion.insert(id: 'a1', memoryId: 'm1', role: 'photo_original', bytes: 1, sha256: 'ab', mime: 'image/jpeg'));
    await db.into(db.uploadJobs).insert(UploadJobsCompanion.insert(assetId: 'a1', accountId: 'u', state: 'pending', updatedAt: 1));
    await db.into(db.uploadParts).insert(UploadPartsCompanion.insert(assetId: 'a1', partNumber: 1));

    await expectLater(
      db.into(db.assets).insert(AssetsCompanion.insert(id: 'a2', memoryId: 'missing', role: 'thumbnail', bytes: 1, sha256: 'ab', mime: 'image/jpeg')),
      throwsA(anything),
    );

    await (db.delete(db.memories)..where((m) => m.id.equals('m1'))).go();
    expect(await db.select(db.assets).get(), isEmpty);
    expect(await db.select(db.uploadJobs).get(), isEmpty);
    expect(await db.select(db.uploadParts).get(), isEmpty);
    await db.close();
  });

  test('one upload job per asset, and one part row per (asset, part)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.memories).insert(MemoriesCompanion.insert(id: 'm1', kind: 'photo', capturedAt: 1, capturedTz: 'UTC', experienceId: 'x', captureJson: '{}', createdAt: 1, updatedAt: 1));
    await db.into(db.assets).insert(AssetsCompanion.insert(id: 'a1', memoryId: 'm1', role: 'photo_original', bytes: 1, sha256: 'ab', mime: 'image/jpeg'));
    await db.into(db.uploadJobs).insert(UploadJobsCompanion.insert(assetId: 'a1', accountId: 'u', state: 'pending', updatedAt: 1));
    await expectLater(db.into(db.uploadJobs).insert(UploadJobsCompanion.insert(assetId: 'a1', accountId: 'u', state: 'pending', updatedAt: 1)), throwsA(anything));
    await db.into(db.uploadParts).insert(UploadPartsCompanion.insert(assetId: 'a1', partNumber: 1));
    await expectLater(db.into(db.uploadParts).insert(UploadPartsCompanion.insert(assetId: 'a1', partNumber: 1)), throwsA(anything));
    await db.close();
  });

  test('column defaults match the documented behavior (location sharing off, favorite off, registered off)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.memories).insert(MemoriesCompanion.insert(id: 'm1', kind: 'photo', capturedAt: 1, capturedTz: 'UTC', experienceId: 'x', captureJson: '{}', createdAt: 1, updatedAt: 1));
    final row = await db.select(db.memories).getSingle();
    expect([row.locationShared, row.favorite, row.registered, row.capturedHere, row.deletedAt, row.accountId], [false, false, false, true, null, null]);
    await db.close();
  });

  group('upgrades', () {
    test('every step runs once, in order, from the stored version to the latest', () async {
      final ran = <int>[];
      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('select 1').get();
      await db.close();

      db = AppDatabase(
        NativeDatabase(file),
        extraSteps: [
          (m, db) async {
            ran.add(2);
            await db.customStatement('ALTER TABLE memories ADD COLUMN extra_a TEXT');
          },
          (m, db) async {
            ran.add(3);
            await db.customStatement('ALTER TABLE memories ADD COLUMN extra_b TEXT');
          },
        ],
      );
      expect(db.schemaVersion, 3);
      await db.customSelect('select 1').get();
      expect(ran, [2, 3]);
      expect(await userVersion(db), 3);
      final columns = (await db.customSelect('PRAGMA table_info(memories)').get()).map((r) => r.read<String>('name')).toSet();
      expect(columns, containsAll(['extra_a', 'extra_b']));
      await db.close();
    });

    test('data written before an upgrade is still there afterwards', () async {
      var db = AppDatabase(NativeDatabase(file));
      await db.into(db.memories).insert(MemoriesCompanion.insert(id: 'keep', kind: 'photo', capturedAt: 5, capturedTz: 'UTC', experienceId: 'x', captureJson: '{"a":1}', createdAt: 1, updatedAt: 1));
      await db.close();

      db = AppDatabase(NativeDatabase(file), extraSteps: [(m, db) async => db.customStatement('ALTER TABLE memories ADD COLUMN later TEXT')]);
      final row = await db.select(db.memories).getSingle();
      expect([row.id, row.capturedAt, row.captureJson], ['keep', 5, '{"a":1}']);
      await db.close();
    });

    test('a step that fails leaves the error visible instead of silently continuing', () async {
      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('select 1').get();
      await db.close();
      db = AppDatabase(NativeDatabase(file), extraSteps: [(m, db) async => throw StateError('step failed')]);
      await expectLater(db.customSelect('select 1').get(), throwsA(anything));
      await db.close();
    });

    test('a database from a newer app version is refused rather than corrupted', () async {
      var db = AppDatabase(NativeDatabase(file), extraSteps: [(m, db) async => db.customStatement('ALTER TABLE memories ADD COLUMN x TEXT')]);
      await db.customSelect('select 1').get();
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      await expectLater(db.customSelect('select 1').get(), throwsA(isA<DatabaseDowngradeError>()));
      await db.close();
    });
  });
}
