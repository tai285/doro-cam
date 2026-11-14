import 'dart:io';

import 'package:doro_cam/data/models.dart';
import 'package:flutter/material.dart';

/// What a sync status means to the user (LIB-004). Never colour alone: an icon and a word go with it.
({IconData icon, String label}) syncBadge(
  SyncStatus status,
) => switch (status) {
  SyncStatus.localOnly => (
    icon: Icons.phone_android,
    label: 'On this phone only',
  ),
  SyncStatus.uploading => (
    icon: Icons.cloud_upload_outlined,
    label: 'Uploading',
  ),
  SyncStatus.synced => (icon: Icons.cloud_done_outlined, label: 'Backed up'),
  SyncStatus.failed => (icon: Icons.cloud_off_outlined, label: 'Upload failed'),
};

/// An image from a local file with a quiet placeholder when there is none (a Memory that only exists on the server).
class LocalImage extends StatelessWidget {
  const LocalImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.cacheWidth,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String? path;
  final BoxFit fit;
  final String? semanticLabel;
  final int? cacheWidth;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    if (file == null || !file.existsSync()) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(placeholderIcon, semanticLabel: semanticLabel),
        ),
      );
    }
    return Image.file(
      file,
      fit: fit,
      semanticLabel: semanticLabel,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

String memoryTitle(MemoryView view) {
  final caption = view.memory.caption;
  if (caption != null && caption.trim().isNotEmpty) {
    return caption;
  }
  final when = DateTime.fromMillisecondsSinceEpoch(
    view.memory.capturedAt,
    isUtc: true,
  ).toLocal();
  final noun = switch (view.memory.kind) {
    MemoryKinds.motion => 'Motion memory',
    MemoryKinds.video => 'Video',
    _ => 'Photo',
  };
  return '$noun from ${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
}
