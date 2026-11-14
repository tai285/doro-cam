import 'dart:convert';
import 'dart:io';

import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/memory_repository.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/camera/application/stops.dart';
import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:doro_cam/features/memory_detail/presentation/motion_player.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Rows of capture metadata from the settings the device actually applied (CAM-050, LIB-002).
List<(String, String)> metadataRows(MemoryView view) {
  Map<String, Object?> capture;
  try {
    capture = Map<String, Object?>.from(
      jsonDecode(view.memory.captureJson) as Map<Object?, Object?>,
    );
  } on Object {
    capture = <String, Object?>{};
  }
  num? num0(String key) => capture[key] is num ? capture[key]! as num : null;
  final rows = <(String, String)>[];
  final focal = num0('focalLength35mmEq');
  if (focal != null) {
    rows.add(('Focal length (35 mm equivalent)', '${focal.round()} mm'));
  }
  if (capture['lensKind'] is String) {
    rows.add(('Lens', lensLabel(capture['lensKind']! as String)));
  }
  final aperture = num0('aperture');
  if (aperture != null) rows.add(('Aperture', 'ƒ/$aperture'));
  final shutter = num0('exposureTimeNsApplied');
  if (shutter != null) rows.add(('Shutter', formatShutterNs(shutter.round())));
  final iso = num0('isoApplied');
  if (iso != null) rows.add(('ISO', '${iso.round()}'));
  final ev = num0('exposureBiasEv');
  if (ev != null) rows.add(('Exposure compensation', formatEv(ev.toDouble())));
  final zoom = num0('zoomFactor');
  if (zoom != null && zoom != 1) {
    rows.add((
      'Zoom',
      '${formatZoom(zoom.toDouble())}${capture['digitalZoom'] == true ? ' (digital)' : ''}',
    ));
  }
  if (capture['flash'] is String) {
    rows.add(('Flash', capture['flash']! as String));
  }
  final width = num0('widthPx');
  final height = num0('heightPx');
  if (width != null && height != null) {
    rows.add(('Size', '${width.round()} × ${height.round()}'));
  }
  rows.add(('Camera style', view.memory.experienceId));
  if (view.memory.profileId != null) rows.add(('Look', view.memory.profileId!));
  if (view.memory.scenario != null) {
    rows.add(('Scenario', view.memory.scenario!));
  }
  if (view.memory.aspectRatio != null) {
    rows.add(('Aspect ratio', view.memory.aspectRatio!));
  }
  if (view.memory.lat != null && view.memory.lon != null) {
    rows.add((
      'Location',
      '${view.memory.lat!.toStringAsFixed(4)}, ${view.memory.lon!.toStringAsFixed(4)}',
    ));
  }
  return rows;
}

/// One Memory: photo or motion playback, metadata, caption, favorite, trash, export (LIB-002, MEM-004..007, MOT-004).
class MemoryDetailScreen extends ConsumerStatefulWidget {
  const MemoryDetailScreen({required this.memoryId, super.key});

  final String memoryId;

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  final TextEditingController _caption = TextEditingController();
  String? _loadedFor;
  String? _message;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(memoryProvider(widget.memoryId));
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to library',
          location: AppRoutes.library,
        ),
        title: const Text('Memory'),
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading'),
        ),
        error: (e, _) =>
            Center(child: Text('This memory could not be loaded: $e')),
        data: (view) => view == null
            ? const Center(
                child: Text(
                  'This memory no longer exists.',
                  key: Key('memory-missing'),
                ),
              )
            : _body(context, view),
      ),
    );
  }

  Widget _body(BuildContext context, MemoryView view) {
    final repo = ref.read(memoryRepositoryProvider);
    final memory = view.memory;
    if (_loadedFor != memory.id) {
      _loadedFor = memory.id;
      _caption.text = memory.caption ?? '';
    }
    final trashed = view.isTrashed;
    final badge = syncBadge(view.status);
    final display =
        view.asset(AssetRoles.photoDisplay) ??
        view.asset(AssetRoles.photoRendered) ??
        view.asset(AssetRoles.photoOriginal);
    final clip = view.asset(AssetRoles.motionClip);
    final original =
        view.asset(AssetRoles.photoOriginal) ??
        view.asset(AssetRoles.videoOriginal);
    final failed = view.assets
        .where(
          (a) =>
              a.uploadState == UploadStates.failedPermanent ||
              a.uploadState == 'failed',
        )
        .toList();
    final isVideo = memory.kind == MemoryKinds.video;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (memory.kind == MemoryKinds.motion)
            MotionPlayerView(
              stillPath: display?.localPath,
              clipPath: clip?.localPath,
              label: memoryTitle(view),
            )
          else
            AspectRatio(
              aspectRatio: 4 / 3,
              child: LocalImage(
                path: display?.localPath,
                fit: BoxFit.contain,
                semanticLabel: memoryTitle(view),
                placeholderIcon: isVideo
                    ? Icons.videocam_outlined
                    : Icons.image_outlined,
              ),
            ),
          if (display?.localPath == null && original?.localPath == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This memory is in your account but its files are not on this phone.',
                key: Key('server-only'),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(badge.icon, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(badge.label, key: const Key('detail-sync'))),
              if (failed.isNotEmpty)
                TextButton(
                  key: const Key('retry-upload'),
                  onPressed: () async {
                    for (final asset in failed) {
                      await ref.read(dataLayerProvider).uploads.retry(asset.id);
                    }
                    await ref
                        .read(syncCoordinatorProvider)
                        .syncOnce()
                        .then<void>((_) {}, onError: (Object _) {});
                  },
                  child: const Text('Retry upload'),
                ),
            ],
          ),
          if (!trashed) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              key: const Key('caption-field'),
              controller: _caption,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Caption',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => _saveCaption(repo, memory.id, value),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('save-caption'),
                onPressed: () => _saveCaption(repo, memory.id, _caption.text),
                child: const Text('Save caption'),
              ),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilterChip(
                  key: const Key('favorite-toggle'),
                  avatar: Icon(
                    memory.favorite ? Icons.star : Icons.star_border,
                  ),
                  label: Text(
                    memory.favorite ? 'Favorite' : 'Mark as favorite',
                  ),
                  selected: memory.favorite,
                  onSelected: (v) => repo.setFavorite(memory.id, favorite: v),
                ),
                if (original?.localPath != null)
                  ActionChip(
                    key: const Key('share-original'),
                    avatar: const Icon(Icons.ios_share),
                    label: const Text('Export original'),
                    onPressed: () => _share(original!),
                  ),
                if (memory.lat != null)
                  ActionChip(
                    key: const Key('remove-location'),
                    avatar: const Icon(Icons.location_off_outlined),
                    label: const Text('Remove location'),
                    onPressed: () => repo.removeLocation(memory.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Details', style: Theme.of(context).textTheme.titleMedium),
          for (final row in metadataRows(view))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(child: Text(row.$1)),
                  Flexible(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          if (_message != null)
            Text(_message!, key: const Key('detail-message')),
          if (trashed) ...<Widget>[
            const Text(
              'In the trash. It is deleted for good 30 days after it was moved here.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const Key('restore'),
                  onPressed: () => repo.restore(memory.id),
                  child: const Text('Restore'),
                ),
                OutlinedButton(
                  key: const Key('delete-forever'),
                  onPressed: () => _confirmPurge(repo, memory.id),
                  child: const Text('Delete permanently'),
                ),
              ],
            ),
          ] else
            OutlinedButton.icon(
              key: const Key('trash'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Move to trash'),
              onPressed: () async {
                final router = GoRouter.of(context);
                await repo.trash(memory.id);
                router.go(AppRoutes.library);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _saveCaption(
    MemoryRepository repo,
    String id,
    String value,
  ) async {
    final text = value.trim();
    await repo.setCaption(id, text.isEmpty ? null : text);
    if (mounted) {
      setState(() => _message = 'Caption saved.');
    }
  }

  Future<void> _share(AssetRow asset) async {
    final path = asset.localPath;
    if (path == null || !File(path).existsSync()) {
      setState(() => _message = 'The original file is not on this phone.');
      return;
    }
    await ref.read(shareServiceProvider).shareFile(path, mime: asset.mime);
  }

  Future<void> _confirmPurge(MemoryRepository repo, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'This deletes the photo from this phone and from your cloud backup. It can’t be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-purge'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await repo.purge(id);
      if (mounted) {
        context.go(AppRoutes.library);
      }
    }
  }
}
