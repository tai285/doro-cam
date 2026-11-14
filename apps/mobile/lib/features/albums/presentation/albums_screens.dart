import 'dart:async';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:doro_cam/features/shared/remote_api.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String friendlyRemoteError(Object error) {
  if (error is NetworkException) {
    return 'You’re offline. Connect to the internet and try again.';
  }
  if (error is ApiException) {
    return switch (error.code) {
      'invite.expired' =>
        'This invite has expired. Ask the owner for a new one.',
      'invite.revoked' => 'This invite was cancelled.',
      'invite.exhausted' => 'This invite has already been used.',
      'invite.not_found' => 'We couldn’t find that invite.',
      'album.not_found' => 'That album doesn’t exist, or you’re not a member.',
      _ => error.message,
    };
  }
  return 'Something went wrong. Please try again.';
}

final albumsProvider = FutureProvider.autoDispose<List<AlbumDto>>(
  (ref) => ref.watch(remoteApiProvider).albums(),
);
final albumDetailProvider = FutureProvider.autoDispose
    .family<AlbumDetail, String>(
      (ref, id) => ref.watch(remoteApiProvider).album(id),
    );
final albumMemoriesProvider = FutureProvider.autoDispose
    .family<List<AlbumMemoryDto>, String>(
      (ref, id) => ref.watch(remoteApiProvider).albumMemories(id),
    );
final tripProposalsProvider = FutureProvider.autoDispose
    .family<List<String>, String>(
      (ref, id) => ref.watch(remoteApiProvider).tripProposals(id),
    );

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            friendlyRemoteError(error),
            key: const Key('remote-error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('remote-retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

/// Pulls the token out of a pasted invite link, or returns a bare code unchanged.
String extractInviteToken(String input) {
  final trimmed = input.trim();
  final marker = trimmed.lastIndexOf('/invites/');
  return marker >= 0
      ? trimmed.substring(marker + 9).split(RegExp('[?#]')).first
      : trimmed;
}

class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  Future<void> _create() async {
    final created = await showDialog<AlbumDto>(
      context: context,
      builder: (dialogContext) => const _NewAlbumDialog(),
    );
    if (created != null && mounted) {
      ref.invalidate(albumsProvider);
      unawaited(context.push(AppRoutes.album(created.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to settings',
          location: AppRoutes.settings,
        ),
        title: const Text('Albums and trips'),
        actions: <Widget>[
          IconButton(
            key: const Key('join-album'),
            tooltip: 'Join with an invite',
            icon: const Icon(Icons.link),
            onPressed: () => context.push(AppRoutes.invite('')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-album'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New album'),
      ),
      body: albums.when(
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading albums'),
        ),
        error: (e, _) => _ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(albumsProvider),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'You aren’t in any albums yet. Create one, or join with an invite link.',
                    key: Key('albums-empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                children: <Widget>[
                  for (final album in items)
                    ListTile(
                      key: Key('album-${album.id}'),
                      leading: Icon(
                        album.isTrip
                            ? Icons.luggage_outlined
                            : Icons.photo_album_outlined,
                      ),
                      title: Text(album.title),
                      subtitle: Text(
                        '${album.isTrip && album.startsOn != null ? '${album.startsOn} – ${album.endsOn} · ' : ''}${album.itemCount} memories · ${album.memberCount} members · ${album.isOwner ? 'owner' : album.role}',
                      ),
                      onTap: () => context.push(AppRoutes.album(album.id)),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Owns its controllers, so they are disposed only after the dialog has fully left the screen.
class _NewAlbumDialog extends ConsumerStatefulWidget {
  const _NewAlbumDialog();

  @override
  ConsumerState<_NewAlbumDialog> createState() => _NewAlbumDialogState();
}

class _NewAlbumDialogState extends ConsumerState<_NewAlbumDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _start = TextEditingController();
  final TextEditingController _end = TextEditingController();
  bool _trip = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    try {
      final album = await ref
          .read(remoteApiProvider)
          .createAlbum(
            title: _title.text.trim(),
            trip: _trip,
            startsOn: _start.text.trim(),
            endsOn: _end.text.trim(),
          );
      navigator.pop(album);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyRemoteError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New album'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('album-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: true,
            ),
            SwitchListTile(
              key: const Key('album-trip'),
              contentPadding: EdgeInsets.zero,
              title: const Text('This is a trip'),
              value: _trip,
              onChanged: (v) => setState(() => _trip = v),
            ),
            if (_trip) ...<Widget>[
              TextField(
                key: const Key('album-start'),
                controller: _start,
                decoration: const InputDecoration(
                  labelText: 'Starts on',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              TextField(
                key: const Key('album-end'),
                controller: _end,
                decoration: const InputDecoration(
                  labelText: 'Ends on',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
            ],
            if (_error != null) Text(_error!, key: const Key('album-error')),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('album-create'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({required this.albumId, super.key});

  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  String? _message;

  Future<void> _refresh() async {
    ref
      ..invalidate(albumDetailProvider(widget.albumId))
      ..invalidate(albumMemoriesProvider(widget.albumId))
      ..invalidate(tripProposalsProvider(widget.albumId))
      ..invalidate(albumsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      await _refresh();
      if (mounted) setState(() => _message = done);
    } on Object catch (error) {
      if (mounted) setState(() => _message = friendlyRemoteError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(albumDetailProvider(widget.albumId));
    final api = ref.read(remoteApiProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to albums',
          location: AppRoutes.albums,
        ),
        title: Text(detail.value?.album.title ?? 'Album'),
      ),
      body: detail.when(
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading album'),
        ),
        error: (e, _) => _ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(albumDetailProvider(widget.albumId)),
        ),
        data: (d) => _content(context, d, api),
      ),
    );
  }

  Widget _content(BuildContext context, AlbumDetail d, RemoteApi api) {
    final router = GoRouter.of(context);
    final album = d.album;
    final memories = ref.watch(albumMemoriesProvider(widget.albumId));
    final proposals = album.isTrip && album.autoAddDuringTrip
        ? ref.watch(tripProposalsProvider(widget.albumId)).value ??
              const <String>[]
        : const <String>[];
    final mine =
        ref.watch(libraryProvider(const LibraryQuery())).value ??
        const <MemoryView>[];
    final inAlbum =
        memories.value?.map((m) => m.id).toSet() ?? const <String>{};
    final candidates = mine
        .where((m) => m.memory.registered && !inAlbum.contains(m.memory.id))
        .toList();
    final base = ref.read(apiBaseProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (album.description != null) Text(album.description!),
          Text(
            'You are ${album.isOwner ? 'the owner' : 'a ${album.role}'}.',
            key: const Key('album-role'),
          ),
          const SizedBox(height: 12),
          Text('Memories', style: Theme.of(context).textTheme.titleMedium),
          memories.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text(friendlyRemoteError(e)),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No memories in this album yet.',
                      key: Key('album-empty'),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final m = items[i];
                      final url = m.thumbnailUrl == null
                          ? null
                          : (m.thumbnailUrl!.startsWith('/')
                                ? base.replace(path: m.thumbnailUrl).toString()
                                : m.thumbnailUrl!);
                      return Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          if (url == null)
                            const ColoredBox(color: Colors.black12)
                          else
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              semanticLabel: m.caption ?? 'Photo',
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Colors.black12),
                            ),
                          if (album.canEdit || m.isOwner)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                key: Key('remove-${m.id}'),
                                tooltip: 'Remove from album',
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  shadows: <Shadow>[Shadow(blurRadius: 4)],
                                ),
                                onPressed: () => _run(
                                  () => api.removeFromAlbum(album.id, m.id),
                                  done: 'Removed from the album.',
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (proposals.isNotEmpty)
            Card(
              key: const Key('trip-proposals'),
              child: ListTile(
                title: Text(
                  '${proposals.length} of your photos were taken during this trip',
                ),
                subtitle: const Text('Nothing is added until you say so.'),
                trailing: FilledButton(
                  key: const Key('add-proposals'),
                  onPressed: () => _run(
                    () => api.addToAlbum(album.id, proposals),
                    done: 'Added.',
                  ),
                  child: Text('Add all ${proposals.length}'),
                ),
              ),
            ),
          if (album.canAdd && candidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Add your photos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final view in candidates.take(30))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        key: Key('add-${view.memory.id}'),
                        onTap: () => _run(
                          () => api.addToAlbum(album.id, <String>[
                            view.memory.id,
                          ]),
                          done: 'Added to the album.',
                        ),
                        child: Semantics(
                          label: 'Add ${memoryTitle(view)}',
                          button: true,
                          excludeSemantics: true,
                          child: SizedBox(
                            width: 84,
                            height: 84,
                            child: LocalImage(
                              path: view.thumbnail?.localPath,
                              cacheWidth: 200,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Members', style: Theme.of(context).textTheme.titleMedium),
          for (final member in d.members)
            ListTile(
              key: Key('member-${member.userId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(member.name),
              subtitle: Text(member.role),
              trailing: album.isOwner && member.role != 'owner'
                  ? Wrap(
                      children: <Widget>[
                        PopupMenuButton<String>(
                          key: Key('role-${member.userId}'),
                          tooltip: 'Change role of ${member.name}',
                          onSelected: (role) => _run(
                            () => api.changeRole(album.id, member.userId, role),
                          ),
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem(
                              value: 'editor',
                              child: Text('Editor'),
                            ),
                            PopupMenuItem(
                              value: 'contributor',
                              child: Text('Contributor'),
                            ),
                            PopupMenuItem(
                              value: 'viewer',
                              child: Text('Viewer'),
                            ),
                          ],
                        ),
                        IconButton(
                          key: Key('remove-member-${member.userId}'),
                          tooltip: 'Remove ${member.name}',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _run(
                            () => api.removeMember(album.id, member.userId),
                            done: 'Removed.',
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          if (album.isOwner) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('invite'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invite someone'),
              onPressed: () => _invite(context, api, album),
            ),
            SwitchListTile(
              key: const Key('toggle-download'),
              title: const Text('Members may download originals'),
              value: album.allowOriginalDownload,
              onChanged: (v) => _run(
                () => api.patchAlbum(album.id, <String, Object?>{
                  'allowOriginalDownload': v,
                }),
              ),
            ),
            SwitchListTile(
              key: const Key('toggle-location'),
              title: const Text('Show location to members'),
              subtitle: const Text(
                'A photo also needs its own location sharing switched on.',
              ),
              value: album.shareLocation,
              onChanged: (v) => _run(
                () => api.patchAlbum(album.id, <String, Object?>{
                  'shareLocation': v,
                }),
              ),
            ),
            if (album.isTrip)
              SwitchListTile(
                key: const Key('toggle-autoadd'),
                title: const Text('Suggest my photos taken during the trip'),
                value: album.autoAddDuringTrip,
                onChanged: (v) => _run(
                  () => api.patchAlbum(album.id, <String, Object?>{
                    'autoAddDuringTrip': v,
                  }),
                ),
              ),
          ],
          if (!album.isOwner)
            OutlinedButton(
              key: const Key('leave-album'),
              onPressed: () async {
                final id = ref.read(dataLayerProvider).account.accountId;
                if (id == null) return;
                await _run(() => api.removeMember(album.id, id));
                router.go(AppRoutes.albums);
              },
              child: const Text('Leave album'),
            ),
          if (album.isOwner)
            TextButton(
              key: const Key('delete-album'),
              onPressed: () async {
                await _run(() => api.deleteAlbum(album.id));
                router.go(AppRoutes.albums);
              },
              child: const Text('Delete album'),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, key: const Key('album-message')),
            ),
        ],
      ),
    );
  }

  Future<void> _invite(
    BuildContext context,
    RemoteApi api,
    AlbumDto album,
  ) async {
    var role = 'contributor';
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Invite someone'),
          content: DropdownButtonFormField<String>(
            key: const Key('invite-role'),
            isExpanded: true,
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'contributor',
                child: Text(
                  'Contributor (adds own photos)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(value: 'editor', child: Text('Editor')),
              DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
            ],
            onChanged: (v) => setLocal(() => role = v ?? role),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('invite-create'),
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                navigator.pop(await api.createInvite(album.id, role: role));
              },
              child: const Text('Create link'),
            ),
          ],
        ),
      ),
    );
    if (token == null) return;
    final link =
        '${ref.read(apiBaseProvider).replace(path: '/invites/$token')}';
    await ref
        .read(shareServiceProvider)
        .shareText('Join my Doro Cam album “${album.title}”: $link');
    if (mounted) setState(() => _message = 'Invite link: $link');
  }
}

/// Accept an invite from a link or pasted code (SHR-003).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({this.token = '', super.key});

  final String token;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  late final TextEditingController _token = TextEditingController(
    text: widget.token,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(remoteApiProvider)
          .acceptInvite(extractInviteToken(_token.text));
      ref.invalidate(albumsProvider);
      if (mounted) context.go(AppRoutes.album(id));
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyRemoteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(
        label: 'Back to albums',
        location: AppRoutes.albums,
      ),
      title: const Text('Join an album'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('Paste the invite link you were sent.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('invite-token'),
          controller: _token,
          decoration: const InputDecoration(
            labelText: 'Invite link or code',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('invite-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('invite-accept'),
          onPressed: _busy ? null : _accept,
          child: Text(_busy ? 'Joining…' : 'Join album'),
        ),
      ],
    ),
  );
}
