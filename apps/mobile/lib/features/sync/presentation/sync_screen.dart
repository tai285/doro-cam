import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:doro_cam/sync/upload_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String describeEvent(UploadEvent event) => switch (event) {
  AssetSynced() => 'An upload finished.',
  AssetFailed(:final code) =>
    'An upload failed ($code). Open the photo to retry.',
  NeedsSignIn() => 'Your session ended. Sign in again to continue backing up.',
  QuotaExceeded() =>
    'Your cloud storage is full. Free up space on the web to continue.',
};

/// Backup status (LIB-004): counts, what is waiting, why uploads are paused, and a "sync now" (SYNC-002).
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _running = false;
  String? _result;

  Future<void> _syncNow() async {
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final report = await ref.read(syncCoordinatorProvider).syncOnce();
      if (mounted) {
        setState(
          () => _result =
              'Uploaded ${report.uploaded}, sent ${report.push.sent} changes, received ${report.pull.memoriesUpdated + report.pull.presetsChanged}.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _result = 'Backup could not run: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all =
        ref.watch(libraryProvider(const LibraryQuery())).value ??
        const <MemoryView>[];
    final signedIn = ref.watch(accountIdProvider).value != null;
    final event = ref.watch(uploadEventsProvider).value;
    int count(SyncStatus s) => all.where((m) => m.status == s).length;
    final waiting = all.where((m) => m.status != SyncStatus.synced).toList();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to settings',
          location: AppRoutes.settings,
        ),
        title: const Text('Backup status'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!signedIn)
            Card(
              key: const Key('sync-signed-out'),
              child: ListTile(
                title: const Text('Sign in to back up'),
                subtitle: const Text(
                  'Nothing is uploaded while you are signed out. Your photos stay safe on this phone.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push(AppRoutes.signIn),
                  child: const Text('Sign in'),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              Chip(
                key: const Key('count-synced'),
                label: Text('Backed up: ${count(SyncStatus.synced)}'),
              ),
              Chip(
                key: const Key('count-uploading'),
                label: Text('Uploading: ${count(SyncStatus.uploading)}'),
              ),
              Chip(
                key: const Key('count-local'),
                label: Text(
                  'Only on this phone: ${count(SyncStatus.localOnly)}',
                ),
              ),
              Chip(
                key: const Key('count-failed'),
                label: Text('Failed: ${count(SyncStatus.failed)}'),
              ),
            ],
          ),
          if (event != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(describeEvent(event), key: const Key('sync-event')),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('sync-now'),
            onPressed: signedIn && !_running ? _syncNow : null,
            icon: const Icon(Icons.sync),
            label: Text(_running ? 'Syncing…' : 'Sync now'),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_result!, key: const Key('sync-result')),
            ),
          const SizedBox(height: 16),
          Text('Waiting', style: Theme.of(context).textTheme.titleSmall),
          if (waiting.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Everything is backed up.',
                key: Key('sync-all-done'),
              ),
            ),
          for (final view in waiting)
            ListTile(
              key: Key('waiting-${view.memory.id}'),
              leading: SizedBox(
                width: 48,
                height: 48,
                child: LocalImage(
                  path: view.thumbnail?.localPath,
                  cacheWidth: 120,
                ),
              ),
              title: Text(
                memoryTitle(view),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(syncBadge(view.status).label),
              onTap: () => context.push(AppRoutes.memory(view.memory.id)),
            ),
        ],
      ),
    );
  }
}
