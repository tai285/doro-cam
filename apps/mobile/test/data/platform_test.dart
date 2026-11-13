import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:doro_cam/data/platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/support.dart';

void main() {
  late Scratch scratch;
  setUp(() => scratch = Scratch());
  tearDown(() => scratch.dispose());

  group('IdGenerator', () {
    test('creates unique UUIDv7 ids that sort by creation time', () async {
      final ids = IdGenerator();
      final first = ids.newId();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      final second = ids.newId();
      expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(first.compareTo(second), lessThan(0));
      expect({for (var i = 0; i < 500; i++) ids.newId()}.length, 500);
    });
  });

  group('sha256OfFile', () {
    test('[NFR-005] matches the digest of the same bytes computed in memory', () async {
      final file = scratch.file('a.bin', size: 300000, seed: 9);
      expect(await sha256OfFile(file), crypto.sha256.convert(file.readAsBytesSync()).toString());
    });

    test('hashes an empty file', () async {
      final file = File('${scratch.dir.path}/empty')..writeAsBytesSync([]);
      expect(await sha256OfFile(file), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });

  group('MediaStore', () {
    test('maps mime types to file extensions', () {
      expect(['image/jpeg', 'image/heic', 'image/heif', 'image/x-adobe-dng', 'image/png', 'video/mp4', 'video/quicktime', 'x/unknown'].map(MediaStore.extensionFor), ['jpg', 'heic', 'heif', 'dng', 'png', 'mp4', 'mov', 'bin']);
    });

    test('builds a stable path per Memory, role and type', () {
      final store = MediaStore(scratch.sub('media'));
      expect(store.pathFor('m1', 'photo_original', 'image/jpeg'), endsWith('/media/m1/photo_original.jpg'));
    });

    test('adopt moves the file into place and leaves nothing at the source', () async {
      final store = MediaStore(scratch.sub('media'));
      final source = scratch.file('x.jpg', size: 100);
      final bytes = source.readAsBytesSync();
      final destination = File(store.pathFor('m1', 'photo_original', 'image/jpeg'));
      await store.adopt(source, destination);
      expect(source.existsSync(), isFalse);
      expect(destination.readAsBytesSync(), bytes);
    });

    test('deleteMemoryFiles removes the Memory directory and tolerates a missing one', () async {
      final store = MediaStore(scratch.sub('media'));
      final destination = File(store.pathFor('m1', 'thumbnail', 'image/jpeg'));
      await store.adopt(scratch.file('t.jpg'), destination);
      await store.deleteMemoryFiles('m1');
      expect(store.directoryFor('m1').existsSync(), isFalse);
      await store.deleteMemoryFiles('never-existed');
    });

    test('orphans lists only unknown directories older than the grace period', () async {
      final store = MediaStore(scratch.sub('media'));
      for (final id in ['known', 'old-orphan', 'fresh-orphan']) {
        await store.adopt(scratch.file('$id.jpg'), File(store.pathFor(id, 'photo_original', 'image/jpeg')));
      }
      File('${store.root.path}/stray-file.txt').writeAsStringSync('x');
      final now = DateTime.now().toUtc();
      // Age two directories; the fresh one stays recent.
      final old = now.subtract(const Duration(hours: 3));
      for (final id in ['known', 'old-orphan']) {
        // Directories cannot have their mtime set from dart:io; use touch (tests run in WSL/Linux).
        Process.runSync('touch', ['-d', old.toIso8601String(), store.directoryFor(id).path]);
      }
      expect(await store.orphans({'known'}, now: now), ['old-orphan']);
      expect(await store.orphans({'known'}, now: now.add(const Duration(hours: 2))), unorderedEquals(['old-orphan', 'fresh-orphan']));
    });

    test('orphans of a store that does not exist yet is empty', () async {
      expect(await MediaStore(Directory('${scratch.dir.path}/nope')).orphans({}, now: DateTime.now().toUtc()), isEmpty);
    });
  });

  group('backoffDelay', () {
    test('[SYNC-002] stays within the exponential ceiling and never exceeds the 30 minute cap', () {
      final random = Random(1);
      for (var attempt = 0; attempt < 40; attempt++) {
        final delay = backoffDelay(attempt, random);
        final ceiling = attempt >= 9 ? const Duration(minutes: 30) : Duration(seconds: 5 * (1 << attempt));
        expect(delay, lessThanOrEqualTo(ceiling > const Duration(minutes: 30) ? const Duration(minutes: 30) : ceiling));
        expect(delay, greaterThanOrEqualTo(Duration.zero));
      }
    });

    test('uses full jitter: delays at the same attempt differ', () {
      final random = Random(3);
      expect({for (var i = 0; i < 20; i++) backoffDelay(4, random).inMilliseconds}.length, greaterThan(10));
    });

    test('grows on average with the attempt number', () {
      double mean(int attempt) {
        final random = Random(5);
        return List.generate(400, (_) => backoffDelay(attempt, random).inMilliseconds).reduce((a, b) => a + b) / 400;
      }

      expect(mean(0), lessThan(mean(3)));
      expect(mean(3), lessThan(mean(6)));
    });
  });

  test('systemClock is UTC and realSleep waits', () async {
    expect(systemClock().isUtc, isTrue);
    final watch = Stopwatch()..start();
    await realSleep(const Duration(milliseconds: 20));
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(15));
  });
}
