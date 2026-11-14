import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum LibraryFilter { all, photos, motion, video, favorites, trash }

LibraryQuery queryFor(LibraryFilter filter) => switch (filter) {
  LibraryFilter.all => const LibraryQuery(),
  LibraryFilter.photos => const LibraryQuery(kind: MemoryKinds.photo),
  LibraryFilter.motion => const LibraryQuery(kind: MemoryKinds.motion),
  LibraryFilter.video => const LibraryQuery(kind: MemoryKinds.video),
  LibraryFilter.favorites => const LibraryQuery(favoritesOnly: true),
  LibraryFilter.trash => const LibraryQuery(trashed: true),
};

String filterLabel(LibraryFilter filter) => switch (filter) {
  LibraryFilter.all => 'All',
  LibraryFilter.photos => 'Photos',
  LibraryFilter.motion => 'Motion',
  LibraryFilter.video => 'Video',
  LibraryFilter.favorites => 'Favorites',
  LibraryFilter.trash => 'Trash',
};

/// The local library: newest first, read from the device database, so it works offline (LIB-001, NFR-001).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialFilter = LibraryFilter.all});

  final LibraryFilter initialFilter;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late LibraryFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider(queryFor(_filter)));
    final signedIn = ref.watch(accountIdProvider).value != null;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to camera',
          location: AppRoutes.camera,
        ),
        title: const Text('Library'),
        actions: <Widget>[
          if (_filter == LibraryFilter.trash &&
              (library.value?.isNotEmpty ?? false))
            TextButton(
              key: const Key('empty-trash'),
              onPressed: () => _confirmEmptyTrash(context),
              child: const Text('Empty trash'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 56,
            child: SingleChildScrollView(
              key: const Key('library-filters'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  for (final filter in LibraryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('filter-${filter.name}'),
                        label: Text(filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!signedIn && _filter != LibraryFilter.trash)
            MaterialBanner(
              key: const Key('backup-banner'),
              content: const Text(
                'Your photos are only on this phone. Sign in to back them up.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => context.push(AppRoutes.signIn),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          if (_filter == LibraryFilter.trash)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Memories in the trash are deleted for good after 30 days.',
              ),
            ),
          Expanded(
            child: library.when(
              data: (items) =>
                  items.isEmpty ? _Empty(filter: _filter) : _Grid(items: items),
              error: (error, _) => Center(
                child: Text('The library could not be loaded: $error'),
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading your library',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty the trash?'),
        content: const Text(
          'Everything in the trash is deleted permanently, here and in your cloud backup. This can’t be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-empty-trash'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(memoryRepositoryProvider).emptyTrash();
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final text = switch (filter) {
      LibraryFilter.trash => 'The trash is empty.',
      LibraryFilter.favorites =>
        'No favorites yet. Open a photo and tap the star.',
      LibraryFilter.all => 'No memories yet',
      _ => 'Nothing here yet.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          key: const Key('library-empty'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<MemoryView> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('library-grid'),
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _Tile(view: items[index]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.view});

  final MemoryView view;

  @override
  Widget build(BuildContext context) {
    final badge = syncBadge(view.status);
    final isVideo = view.memory.kind == MemoryKinds.video;
    return Semantics(
      button: true,
      label:
          '${memoryTitle(view)}. ${badge.label}.${view.memory.favorite ? ' Favorite.' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('tile-${view.memory.id}'),
        onTap: () => context.push(AppRoutes.memory(view.memory.id)),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            LocalImage(
              path: view.thumbnail?.localPath,
              cacheWidth: 280,
              placeholderIcon: isVideo
                  ? Icons.videocam_outlined
                  : Icons.image_outlined,
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Row(
                children: <Widget>[
                  if (view.memory.kind == MemoryKinds.motion)
                    const _Pill(label: 'LIVE'),
                  if (isVideo) const _Pill(label: 'VIDEO'),
                  if (view.memory.favorite) const _Pill(label: '★'),
                ],
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Icon(
                badge.icon,
                size: 18,
                color: Colors.white,
                shadows: const <Shadow>[Shadow(blurRadius: 4)],
                key: Key('sync-${view.memory.id}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );
}
