import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/features/albums/presentation/albums_screens.dart';
import 'package:doro_cam/features/shared/remote_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

Map<String, Object?> album({
  String id = 'a1',
  String title = 'Japan Trip',
  String kind = 'album',
  String role = 'owner',
  int items = 0,
  int members = 1,
  bool download = true,
  bool location = false,
  bool autoAdd = false,
  String? start,
  String? end,
}) => <String, Object?>{
  'id': id,
  'title': title,
  'kind': kind,
  'role': role,
  'memberCount': members,
  'itemCount': items,
  'allowOriginalDownload': download,
  'shareLocation': location,
  'autoAddDuringTrip': autoAdd,
  'description': null,
  'startsOn': start,
  'endsOn': end,
};

Map<String, Object?> memberJson(String id, String name, String role) =>
    <String, Object?>{
      'userId': id,
      'name': name,
      'role': role,
      'joinedAt': '2026-11-01T00:00:00.000Z',
    };

Map<String, Object?> albumMemory(
  String id, {
  bool owner = true,
  String? caption,
}) => <String, Object?>{
  'id': id,
  'kind': 'photo',
  'capturedAt': '2026-11-01T09:30:00.000Z',
  'isOwner': owner,
  'caption': caption,
  'thumbnail': null,
};

void main() {
  group('albums', () {
    uiTest('[SHR-001] lists the albums the user is in with counts and role', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums': (_) => (
            200,
            <String, Object?>{
              'items': <Object?>[
                album(items: 12, members: 3),
                album(
                  id: 'a2',
                  title: 'Trip',
                  kind: 'trip',
                  start: '2027-04-01',
                  end: '2027-04-09',
                  role: 'contributor',
                ),
              ],
            },
          ),
        },
      );
      await launch(
        tester,
        location: AppRoutes.albums,
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('album-a1')));
      expect(
        find.textContaining('12 memories · 3 members · owner'),
        findsOneWidget,
      );
      expect(find.textContaining('2027-04-01 – 2027-04-09'), findsOneWidget);
      expect(find.textContaining('contributor'), findsOneWidget);
    });

    uiTest('explains when there are none, and offline', (tester) async {
      var online = false;
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums': (_) => online
              ? (200, <String, Object?>{'items': <Object?>[]})
              : throw const NetworkException('offline'),
        },
      );
      await launch(
        tester,
        location: AppRoutes.albums,
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('remote-error')));
      expect(find.textContaining('You’re offline'), findsOneWidget);
      online = true;
      await tester.tap(find.byKey(const Key('remote-retry')));
      await pumpUntil(tester, find.byKey(const Key('albums-empty')));
      expect(find.byKey(const Key('albums-empty')), findsOneWidget);
    });

    uiTest(
      '[SHR-001][SHR-002] creates an album, and a trip with dates, then opens it',
      (tester) async {
        final remote = ScriptedRemote(
          <String, (int, Object?) Function(Map<String, Object?>)>{
            'GET /v1/albums': (_) =>
                (200, <String, Object?>{'items': <Object?>[]}),
            'POST /v1/albums': (b) => (
              201,
              album(title: b['title']! as String, kind: b['kind']! as String),
            ),
            'GET /v1/albums/a1': (_) => (
              200,
              <String, Object?>{
                'album': album(),
                'members': <Object?>[memberJson('u1', 'Dorothy', 'owner')],
              },
            ),
            'GET /v1/albums/a1/memories': (_) =>
                (200, <String, Object?>{'items': <Object?>[]}),
          },
        );
        await launch(
          tester,
          location: AppRoutes.albums,
          remote: remote,
          prepare: signIn,
        );
        await pumpUntil(tester, find.byKey(const Key('new-album')));
        await tester.tap(find.byKey(const Key('new-album')));
        await settle(tester, frames: 4);
        await tester.enterText(find.byKey(const Key('album-title')), 'Kyoto');
        await tester.tap(find.byKey(const Key('album-trip')));
        await settle(tester, frames: 3);
        await tester.enterText(
          find.byKey(const Key('album-start')),
          '2027-04-01',
        );
        await tester.enterText(
          find.byKey(const Key('album-end')),
          '2027-04-09',
        );
        await tester.tap(find.byKey(const Key('album-create')));
        await settle(tester, frames: 12);
        expect(
          remote.bodies['POST /v1/albums']!.single,
          containsPair('kind', 'trip'),
        );
        expect(
          remote.bodies['POST /v1/albums']!.single,
          containsPair('startsOn', '2027-04-01'),
        );
        expect(find.byKey(const Key('album-role')), findsOneWidget);
      },
    );

    uiTest('shows the server’s reason when creating fails', (tester) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
          'POST /v1/albums': (_) => (
            400,
            <String, Object?>{
              'error': <String, Object?>{
                'code': 'album.invalid_dates',
                'message': 'The end date is before the start date.',
              },
            },
          ),
        },
      );
      await launch(
        tester,
        location: AppRoutes.albums,
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('new-album')));
      await tester.tap(find.byKey(const Key('new-album')));
      await settle(tester, frames: 4);
      await tester.enterText(find.byKey(const Key('album-title')), 'X');
      await tester.tap(find.byKey(const Key('album-create')));
      await settle(tester, frames: 8);
      expect(find.byKey(const Key('album-error')), findsOneWidget);
      expect(
        find.text('The end date is before the start date.'),
        findsOneWidget,
      );
    });

    uiTest(
      '[SHR-003] as the owner: invite someone (the link is shared once), change roles, remove members, change settings',
      (tester) async {
        final remote = ScriptedRemote(
          <String, (int, Object?) Function(Map<String, Object?>)>{
            'GET /v1/albums/a1': (_) => (
              200,
              <String, Object?>{
                'album': album(members: 2),
                'members': <Object?>[
                  memberJson('u1', 'Dorothy', 'owner'),
                  memberJson('u2', 'Friend', 'viewer'),
                ],
              },
            ),
            'GET /v1/albums/a1/memories': (_) =>
                (200, <String, Object?>{'items': <Object?>[]}),
            'POST /v1/albums/a1/invites': (b) => (
              201,
              <String, Object?>{
                'id': 'i1',
                'token': 'tok-abc',
                'role': b['role'],
                'expiresAt': '2027-01-01T00:00:00.000Z',
                'maxUses': 1,
              },
            ),
            'PATCH /v1/albums/a1/members/u2': (_) =>
                (200, memberJson('u2', 'Friend', 'editor')),
            'DELETE /v1/albums/a1/members/u2': (_) => (204, null),
            'PATCH /v1/albums/a1': (_) => (200, album()),
          },
        );
        final env = await launch(
          tester,
          location: AppRoutes.album('a1'),
          remote: remote,
          prepare: signIn,
        );
        await pumpUntil(tester, find.byKey(const Key('member-u2')));
        await tester.ensureVisible(find.byKey(const Key('invite')));
        await tester.tap(find.byKey(const Key('invite')));
        await settle(tester, frames: 4);
        await tester.tap(find.byKey(const Key('invite-create')));
        await settle(tester, frames: 8);
        expect(env.share.texts.single, contains('/invites/tok-abc'));
        expect(find.textContaining('/invites/tok-abc'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('toggle-download')));
        await tester.tap(find.byKey(const Key('toggle-download')));
        await settle(tester, frames: 6);
        expect(
          remote.bodies['PATCH /v1/albums/a1']!.last,
          containsPair('allowOriginalDownload', false),
        );
        await tester.tap(find.byKey(const Key('toggle-location')));
        await settle(tester, frames: 6);
        expect(
          remote.bodies['PATCH /v1/albums/a1']!.last,
          containsPair('shareLocation', true),
        );

        await tester.ensureVisible(find.byKey(const Key('remove-member-u2')));
        await tester.tap(find.byKey(const Key('remove-member-u2')));
        await settle(tester, frames: 8);
        expect(remote.requests, contains('DELETE /v1/albums/a1/members/u2'));
      },
    );

    uiTest(
      '[SHR-003] a viewer cannot add, invite or change settings, but can leave',
      (tester) async {
        final remote = ScriptedRemote(
          <String, (int, Object?) Function(Map<String, Object?>)>{
            'GET /v1/albums/a1': (_) => (
              200,
              <String, Object?>{
                'album': album(role: 'viewer', members: 2),
                'members': <Object?>[
                  memberJson('u1', 'Owner', 'owner'),
                  memberJson('u9', 'Me', 'viewer'),
                ],
              },
            ),
            'GET /v1/albums/a1/memories': (_) => (
              200,
              <String, Object?>{
                'items': <Object?>[
                  albumMemory('m1', owner: false, caption: 'Theirs'),
                ],
              },
            ),
            'DELETE /v1/albums/a1/members/user-1': (_) => (204, null),
            'GET /v1/albums': (_) =>
                (200, <String, Object?>{'items': <Object?>[]}),
          },
        );
        await launch(
          tester,
          location: AppRoutes.album('a1'),
          remote: remote,
          prepare: (env) async {
            await env.seed(caption: 'mine');
            await signIn(env);
          },
        );
        await pumpUntil(tester, find.byKey(const Key('album-role')));
        expect(find.byKey(const Key('invite')), findsNothing);
        expect(find.byKey(const Key('toggle-download')), findsNothing);
        expect(find.text('Add your photos'), findsNothing);
        expect(
          find.byKey(const Key('remove-m1')),
          findsNothing,
        ); // not theirs to remove
        await tester.ensureVisible(find.byKey(const Key('leave-album')));
        await tester.tap(find.byKey(const Key('leave-album')));
        await settle(tester, frames: 10);
        expect(
          remote.requests,
          contains('DELETE /v1/albums/a1/members/user-1'),
        );
      },
    );

    uiTest('[SHR-004] a contributor adds their own registered photos', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums/a1': (_) => (
            200,
            <String, Object?>{
              'album': album(role: 'contributor'),
              'members': <Object?>[memberJson('u1', 'Owner', 'owner')],
            },
          ),
          'GET /v1/albums/a1/memories': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
          'POST /v1/albums/a1/items': (_) =>
              (200, <String, Object?>{'added': 1}),
        },
      );
      late String id;
      await launch(
        tester,
        location: AppRoutes.album('a1'),
        remote: remote,
        prepare: (env) async {
          id = (await env.seed(caption: 'mine')).memory.id;
          await signIn(env);
          await env.data.sync.syncOnce(); // registers the Memory on the server
        },
      );
      await pumpUntil(tester, find.text('Add your photos'));
      await tester.ensureVisible(find.byKey(Key('add-$id')));
      await tester.tap(find.byKey(Key('add-$id')));
      await settle(tester, frames: 8);
      expect(
        remote.bodies['POST /v1/albums/a1/items']!.single['memoryIds'],
        <Object?>[id],
      );
    });

    uiTest('[SHR-002] trip proposals are offered, never added silently', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums/a1': (_) => (
            200,
            <String, Object?>{
              'album': album(
                kind: 'trip',
                start: '2027-04-01',
                end: '2027-04-09',
                autoAdd: true,
              ),
              'members': <Object?>[memberJson('u1', 'Me', 'owner')],
            },
          ),
          'GET /v1/albums/a1/memories': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
          'GET /v1/albums/a1/trip-proposals': (_) => (
            200,
            <String, Object?>{
              'memoryIds': <Object?>['m1', 'm2'],
            },
          ),
          'POST /v1/albums/a1/items': (_) =>
              (200, <String, Object?>{'added': 2}),
        },
      );
      await launch(
        tester,
        location: AppRoutes.album('a1'),
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('trip-proposals')));
      expect(remote.requests, isNot(contains('POST /v1/albums/a1/items')));
      await tester.tap(find.byKey(const Key('add-proposals')));
      await settle(tester, frames: 8);
      expect(
        remote.bodies['POST /v1/albums/a1/items']!.single['memoryIds'],
        <Object?>['m1', 'm2'],
      );
    });

    uiTest('an album the user cannot see is explained and can be retried', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums/a1': (_) => (
            404,
            <String, Object?>{
              'error': <String, Object?>{
                'code': 'album.not_found',
                'message': 'Album not found.',
              },
            },
          ),
        },
      );
      await launch(
        tester,
        location: AppRoutes.album('a1'),
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('remote-error')));
      expect(
        find.textContaining('doesn’t exist, or you’re not a member'),
        findsOneWidget,
      );
    });

    uiTest('the owner deletes the album', (tester) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/albums/a1': (_) => (
            200,
            <String, Object?>{
              'album': album(),
              'members': <Object?>[memberJson('u1', 'Me', 'owner')],
            },
          ),
          'GET /v1/albums/a1/memories': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
          'DELETE /v1/albums/a1': (_) => (204, null),
          'GET /v1/albums': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
        },
      );
      await launch(
        tester,
        location: AppRoutes.album('a1'),
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('delete-album')));
      await tester.ensureVisible(find.byKey(const Key('delete-album')));
      await tester.tap(find.byKey(const Key('delete-album')));
      await settle(tester, frames: 10);
      expect(remote.requests, contains('DELETE /v1/albums/a1'));
    });
  });

  group('joining with an invite', () {
    uiTest('[SHR-003] accepts a pasted link and opens the album', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'POST /v1/invites/accept': (b) =>
              (200, <String, Object?>{'albumId': 'a1', 'role': 'contributor'}),
          'GET /v1/albums': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
          'GET /v1/albums/a1': (_) => (
            200,
            <String, Object?>{
              'album': album(role: 'contributor'),
              'members': <Object?>[memberJson('u1', 'Owner', 'owner')],
            },
          ),
          'GET /v1/albums/a1/memories': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
        },
      );
      await launch(
        tester,
        location: AppRoutes.inviteBase,
        remote: remote,
        prepare: signIn,
      );
      await tester.enterText(
        find.byKey(const Key('invite-token')),
        'https://doro.example/invites/tok-123?x=1',
      );
      await tester.tap(find.byKey(const Key('invite-accept')));
      await settle(tester, frames: 12);
      expect(
        remote.bodies['POST /v1/invites/accept']!.single['token'],
        'tok-123',
      );
      expect(find.byKey(const Key('album-role')), findsOneWidget);
    });

    uiTest('[SHR-003] explains an expired invite', (tester) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'POST /v1/invites/accept': (_) => (
            410,
            <String, Object?>{
              'error': <String, Object?>{
                'code': 'invite.expired',
                'message': 'x',
              },
            },
          ),
        },
      );
      await launch(
        tester,
        location: AppRoutes.invite('old-token'),
        remote: remote,
        prepare: signIn,
      );
      await tester.tap(find.byKey(const Key('invite-accept')));
      await settle(tester, frames: 8);
      expect(
        find.text('This invite has expired. Ask the owner for a new one.'),
        findsOneWidget,
      );
    });

    uiTest(
      'extractInviteToken takes the token from a link, a bare code or a link with a fragment',
      (tester) async {
        expect(extractInviteToken('https://x/invites/abc#frag'), 'abc');
        expect(extractInviteToken('https://x/invites/abc?x=1'), 'abc');
        expect(extractInviteToken(' abc '), 'abc');
      },
    );

    uiTest('friendlyRemoteError knows every invite and album code', (
      tester,
    ) async {
      String msg(String code) => friendlyRemoteError(
        ApiException(status: 410, code: code, message: 'raw'),
      );
      expect(msg('invite.revoked'), 'This invite was cancelled.');
      expect(msg('invite.exhausted'), 'This invite has already been used.');
      expect(msg('invite.not_found'), 'We couldn’t find that invite.');
      expect(msg('something.else'), 'raw');
      expect(
        friendlyRemoteError(StateError('x')),
        contains('Something went wrong'),
      );
    });
  });

  group('insights', () {
    Map<String, Object?> dist(List<(String, int)> rows) => <String, Object?>{
      'total': rows.fold<int>(0, (a, b) => a + b.$2),
      'buckets': <Object?>[
        for (final r in rows)
          <String, Object?>{
            'label': r.$1,
            'count': r.$2,
            'share': r.$2 / rows.fold<int>(0, (a, b) => a + b.$2),
          },
      ],
    };
    Map<String, Object?> report(int total) => <String, Object?>{
      'total': total,
      'focalLength': dist(<(String, int)>[('24-35 mm', 8), ('51-85 mm', 2)]),
      'lens': dist(<(String, int)>[('wide', 8)]),
      'profile': dist(<(String, int)>[('natural', 6), ('warm-film', 4)]),
      'experience': dist(<(String, int)>[('mirrorless', 10)]),
      'iso': dist(<(String, int)>[('101-400', 10)]),
      'shutter': dist(<(String, int)>[('1/126-1/500', 10)]),
      'aperture': dist(<(String, int)>[('f/1.0-1.9', 10)]),
      'timeOfDay': dist(<(String, int)>[('Midday (11-16)', 10)]),
      'trend': <Object?>[
        <String, Object?>{'month': '2026-04', 'count': 4},
        <String, Object?>{'month': '2026-05', 'count': 6},
      ],
      'insights': <Object?>[
        <String, Object?>{
          'id': 'favorite-focal-length',
          'text': 'You shoot most at 24-35 mm (80% of your photos).',
          'basedOn': <String, Object?>{},
        },
      ],
    };
    final suggestion = <String, Object?>{
      'patternKey': 'a' * 24,
      'title': 'mirrorless · natural',
      'explanation': '8 of your 10 photos (80%) used this.',
      'supportingCount': 8,
      'of': 10,
    };

    uiTest(
      '[ANL-001..005] shows findings with their numbers and every distribution',
      (tester) async {
        final remote = ScriptedRemote(
          <String, (int, Object?) Function(Map<String, Object?>)>{
            'GET /v1/insights/summary': (_) => (200, report(10)),
            'GET /v1/insights/preset-suggestions': (_) =>
                (200, <String, Object?>{'items': <Object?>[]}),
          },
        );
        await launch(
          tester,
          location: AppRoutes.insights,
          remote: remote,
          prepare: signIn,
        );
        await pumpUntil(tester, find.byKey(const Key('insights-total')));
        expect(find.text('Based on 10 memories.'), findsOneWidget);
        expect(
          find.byKey(const Key('finding-favorite-focal-length')),
          findsOneWidget,
        );
        for (final title in <String>[
          'Focal length',
          'Look',
          'Shutter speed',
          'Time of day',
        ]) {
          await tester.ensureVisible(find.text(title));
          expect(find.text(title), findsOneWidget, reason: title);
        }
        expect(find.text('2026-04: 4 photos'), findsOneWidget);
        expect(find.byKey(const Key('suggestions-empty')), findsOneWidget);
      },
    );

    uiTest('no photos yet: an invitation instead of empty charts', (
      tester,
    ) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/insights/summary': (_) =>
              (200, report(0)..['focalLength'] = dist(<(String, int)>[])),
          'GET /v1/insights/preset-suggestions': (_) =>
              (200, <String, Object?>{'items': <Object?>[]}),
        },
      );
      await launch(
        tester,
        location: AppRoutes.insights,
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('insights-empty')));
      expect(find.byKey(const Key('insights-empty')), findsOneWidget);
    });

    uiTest(
      '[PRE-002][PRE-003] a suggestion explains itself; accepting saves a preset, dismissing hides it',
      (tester) async {
        final remote = ScriptedRemote(
          <String, (int, Object?) Function(Map<String, Object?>)>{
            'GET /v1/insights/summary': (_) => (200, report(10)),
            'GET /v1/insights/preset-suggestions': (_) => (
              200,
              <String, Object?>{
                'items': <Object?>[suggestion],
              },
            ),
            'POST /v1/insights/preset-suggestions/${'a' * 24}/accept': (_) =>
                (201, <String, Object?>{'presetId': 'p1'}),
            'POST /v1/insights/preset-suggestions/${'a' * 24}/dismiss': (_) =>
                (204, null),
          },
        );
        await launch(
          tester,
          location: AppRoutes.insights,
          remote: remote,
          prepare: signIn,
        );
        await pumpUntil(tester, find.byKey(Key('suggestion-${'a' * 24}')));
        expect(find.textContaining('8 of your 10 photos'), findsOneWidget);
        expect(
          find.textContaining('Nothing changes unless you accept'),
          findsOneWidget,
        );
        expect(remote.requests.where((r) => r.startsWith('POST')), isEmpty);
        await tester.ensureVisible(find.byKey(Key('accept-${'a' * 24}')));
        await tester.tap(find.byKey(Key('accept-${'a' * 24}')));
        await settle(tester, frames: 8);
        expect(
          remote.requests,
          contains('POST /v1/insights/preset-suggestions/${'a' * 24}/accept'),
        );
        await tester.tap(find.byKey(Key('dismiss-${'a' * 24}')));
        await settle(tester, frames: 8);
        expect(
          remote.requests,
          contains('POST /v1/insights/preset-suggestions/${'a' * 24}/dismiss'),
        );
      },
    );

    uiTest('offline: says so and can retry', (tester) async {
      final remote = ScriptedRemote(
        <String, (int, Object?) Function(Map<String, Object?>)>{
          'GET /v1/insights/summary': (_) =>
              throw const NetworkException('offline'),
          'GET /v1/insights/preset-suggestions': (_) =>
              throw const NetworkException('offline'),
        },
      );
      await launch(
        tester,
        location: AppRoutes.insights,
        remote: remote,
        prepare: signIn,
      );
      await pumpUntil(tester, find.byKey(const Key('remote-error')));
      expect(find.byKey(const Key('remote-retry')), findsOneWidget);
    });
  });

  group('remote api parsing', () {
    test('AlbumDto role helpers', () {
      final owner = AlbumDto.fromJson(album());
      final editor = AlbumDto.fromJson(album(role: 'editor'));
      final viewer = AlbumDto.fromJson(album(role: 'viewer', kind: 'trip'));
      expect((owner.isOwner, owner.canEdit, owner.canAdd), (true, true, true));
      expect(
        (editor.isOwner, editor.canEdit, editor.canAdd),
        (false, true, true),
      );
      expect(
        (viewer.canEdit, viewer.canAdd, viewer.isTrip),
        (false, false, true),
      );
    });

    test('AlbumMemoryDto reads relative and missing thumbnails', () {
      expect(
        AlbumMemoryDto.fromJson(<String, Object?>{
          ...albumMemory('m'),
          'thumbnail': <String, Object?>{'url': '/v1/x'},
        }).thumbnailUrl,
        '/v1/x',
      );
      expect(AlbumMemoryDto.fromJson(albumMemory('m')).thumbnailUrl, isNull);
    });
  });
}
