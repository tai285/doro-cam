// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Source of "now". Injected so tests are deterministic.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();

/// Creates the client-generated IDs of Memories and assets: UUIDv7, so they sort by creation time
/// and offline-created entities never need re-keying (docs/architecture/sync.md).
class IdGenerator {
  IdGenerator([Uuid? uuid]) : _uuid = uuid ?? const Uuid();
  final Uuid _uuid;

  String newId() => _uuid.v7();
}

/// SHA-256 of a file, streamed so a large video never sits in memory.
Future<String> sha256OfFile(File file) async {
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Where a Memory's original files live on this device: `<root>/<memoryId>/<role>.<ext>`.
/// Files are written here (and fsynced) before the Memory row exists, so a crash leaves at worst
/// an orphan directory that [MediaStore.orphans] finds, never a Memory without its file.
class MediaStore {
  MediaStore(this.root);

  final Directory root;

  Directory directoryFor(String memoryId) => Directory(p.join(root.path, memoryId));

  String pathFor(String memoryId, String role, String mime) =>
      p.join(root.path, memoryId, '$role.${extensionFor(mime)}');

  static String extensionFor(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    'image/x-adobe-dng' => 'dng',
    'image/png' => 'png',
    'video/mp4' => 'mp4',
    'video/quicktime' => 'mov',
    _ => 'bin',
  };

  /// Moves [source] to [destination], durably. Falls back to copy + delete across file systems.
  Future<void> adopt(File source, File destination) async {
    await destination.parent.create(recursive: true);
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      await source.copy(destination.path);
      await source.delete();
    }
    final handle = await destination.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<void> deleteMemoryFiles(String memoryId) async {
    final dir = directoryFor(memoryId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Directory names under [root] that no Memory claims (left by a capture that crashed between
  /// moving its files and committing the row). Only directories older than [grace] are returned.
  Future<List<String>> orphans(Set<String> knownMemoryIds, {required DateTime now, Duration grace = const Duration(hours: 1)}) async {
    if (!root.existsSync()) {
      return const [];
    }
    final found = <String>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      if (knownMemoryIds.contains(name)) {
        continue;
      }
      final modified = (await entity.stat()).modified;
      if (now.difference(modified.toUtc()) >= grace) {
        found.add(name);
      }
    }
    return found;
  }
}

/// Exponential backoff with full jitter: a random delay in [0, min(cap, base * 2^attempt)]
/// (docs/architecture/sync.md: 5 s base, 30 min cap).
Duration backoffDelay(int attempt, Random random, {Duration base = const Duration(seconds: 5), Duration cap = const Duration(minutes: 30)}) {
  final exponent = min(attempt, 20);
  final ceilingMs = min(cap.inMilliseconds, base.inMilliseconds * (1 << exponent));
  return Duration(milliseconds: (random.nextDouble() * ceilingMs).round());
}

/// Delay used by the engine between checks. Replaced in tests so they do not sleep.
typedef Sleeper = Future<void> Function(Duration duration);

Future<void> realSleep(Duration duration) => Future<void>.delayed(duration);
