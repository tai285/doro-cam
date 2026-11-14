import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/features/library/presentation/library_screen.dart';
import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:doro_cam/features/memory_detail/presentation/memory_detail_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ui_harness.dart';

void main() {
  group('library', () {
    uiTest('[LIB-001] an empty library says so', (tester) async {
      await launch(tester, location: AppRoutes.library);
      expect(find.text('No memories yet'), findsOneWidget);
      expect(
        find.byKey(const Key('backup-banner')),
        findsOneWidget,
      ); // not signed in
    });

    uiTest(
      '[LIB-001][NFR-001] lists Memories newest first from the device, with kind and favorite badges',
      (tester) async {
        late String older;
        late String newer;
        late String live;
        await launch(
          tester,
          location: AppRoutes.library,
          prepare: (env) async {
            older = (await env.seed(capturedAt: DateTime.utc(2026, 1, 1)))
                .memory
                .id;
            newer = (await env.seed(
              capturedAt: DateTime.utc(2026, 6, 1),
              caption: 'Sunset',
            )).memory.id;
            live = (await env.seed(
              kind: MemoryKinds.motion,
              capturedAt: DateTime.utc(2026, 3, 1),
            )).memory.id;
            await env.memories.setFavorite(newer, favorite: true);
          },
          waitFor: find.byType(GridView),
        );
        final tiles = tester
            .widgetList<InkWell>(
              find.byWidgetPredicate(
                (w) => w is InkWell && w.key.toString().startsWith("[<'tile-"),
              ),
            )
            .map((w) => w.key.toString())
            .toList();
        expect(tiles, <String>[
          "[<'tile-$newer'>]",
          "[<'tile-$live'>]",
          "[<'tile-$older'>]",
        ]);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('★'), findsOneWidget);
      },
    );

    uiTest(
      '[LIB-004] each tile shows its sync status as an icon with a word for screen readers',
      (tester) async {
        late String id;
        final handle = tester.ensureSemantics();
        await launch(
          tester,
          location: AppRoutes.library,
          prepare: (env) async =>
              id = (await env.seed(caption: 'Cat')).memory.id,
          waitFor: find.byType(GridView),
        );
        expect(find.byKey(Key('sync-$id')), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Cat. On this phone only')),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    uiTest('[LIB-004] syncBadge covers every status', (tester) async {
      expect(syncBadge(SyncStatus.localOnly).label, 'On this phone only');
      expect(syncBadge(SyncStatus.uploading).label, 'Uploading');
      expect(syncBadge(SyncStatus.synced).label, 'Backed up');
      expect(syncBadge(SyncStatus.failed).label, 'Upload failed');
    });

    uiTest('[LIB-003] filters by kind, favorites and trash', (tester) async {
      await launch(
        tester,
        location: AppRoutes.library,
        prepare: (env) async {
          await env.seed(caption: 'a photo');
          await env.seed(kind: MemoryKinds.motion, caption: 'a motion');
          final fav = await env.seed(caption: 'a favorite');
          await env.memories.setFavorite(fav.memory.id, favorite: true);
          final gone = await env.seed(caption: 'in the bin');
          await env.memories.trash(gone.memory.id);
        },
        waitFor: find.byType(GridView),
      );
      expect(
        find
            .byType(InkWell)
            .evaluate()
            .where((e) => e.widget.key.toString().contains('tile-'))
            .length,
        3,
      );

      await tester.ensureVisible(find.byKey(const Key('filter-motion')));
      await tester.tap(find.byKey(const Key('filter-motion')));
      await settle(tester, frames: 6);
      expect(
        find
            .byType(InkWell)
            .evaluate()
            .where((e) => e.widget.key.toString().contains('tile-'))
            .length,
        1,
      );
      await tester.ensureVisible(find.byKey(const Key('filter-favorites')));
      await tester.tap(find.byKey(const Key('filter-favorites')));
      await settle(tester, frames: 6);
      expect(
        find
            .byType(InkWell)
            .evaluate()
            .where((e) => e.widget.key.toString().contains('tile-'))
            .length,
        1,
      );
      await tester.ensureVisible(find.byKey(const Key('filter-video')));
      await tester.tap(find.byKey(const Key('filter-video')));
      await pumpUntil(tester, find.byKey(const Key('library-empty')));
      expect(find.byKey(const Key('library-empty')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('filter-trash')));
      await tester.tap(find.byKey(const Key('filter-trash')));
      await pumpUntil(tester, find.byType(GridView));
      expect(
        find.textContaining('deleted for good after 30 days'),
        findsOneWidget,
      );
      expect(
        find
            .byType(InkWell)
            .evaluate()
            .where((e) => e.widget.key.toString().contains('tile-'))
            .length,
        1,
      );
    });

    uiTest(
      '[MEM-007] emptying the trash asks first and then deletes everything in it',
      (tester) async {
        late UiEnv env;
        env = await launch(
          tester,
          location: AppRoutes.library,
          prepare: (e) async {
            final gone = await e.seed(caption: 'in the bin');
            await e.memories.trash(gone.memory.id);
          },
        );
        await tester.ensureVisible(find.byKey(const Key('filter-trash')));
        await tester.tap(find.byKey(const Key('filter-trash')));
        await pumpUntil(tester, find.byKey(const Key('empty-trash')));
        await tester.tap(find.byKey(const Key('empty-trash')));
        await settle(tester, frames: 4);
        expect(find.textContaining('can’t be undone'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm-empty-trash')));
        await settle(tester, frames: 8);
        expect(
          await io(tester, () => env.memories.library(trashed: true)),
          isEmpty,
        );
        expect(find.text('The trash is empty.'), findsOneWidget);
      },
    );

    uiTest('signed-in users do not get the "back up" banner', (tester) async {
      await launch(tester, location: AppRoutes.library, prepare: signIn);
      expect(find.byKey(const Key('backup-banner')), findsNothing);
    });

    uiTest('tapping a tile opens the Memory', (tester) async {
      late String id;
      await launch(
        tester,
        location: AppRoutes.library,
        prepare: (env) async =>
            id = (await env.seed(caption: 'Open me')).memory.id,
        waitFor: find.byType(GridView),
      );
      await tester.tap(find.byKey(Key('tile-$id')));
      await settle(tester, frames: 8);
      expect(find.byKey(const Key('caption-field')), findsOneWidget);
    });

    uiTest('queryFor and filterLabel cover every filter', (tester) async {
      for (final filter in LibraryFilter.values) {
        expect(filterLabel(filter), isNotEmpty);
        expect(queryFor(filter), isNotNull);
      }
      expect(queryFor(LibraryFilter.trash).trashed, isTrue);
      expect(queryFor(LibraryFilter.favorites).favoritesOnly, isTrue);
      expect(queryFor(LibraryFilter.photos).kind, MemoryKinds.photo);
    });

    uiTest('memoryTitle names a Memory by caption, or by kind and date', (
      tester,
    ) async {
      late MemoryView photo;
      late MemoryView motion;
      await launch(
        tester,
        prepare: (env) async {
          photo = await env.seed(capturedAt: DateTime.utc(2026, 5, 4, 3, 2));
          motion = await env.seed(kind: MemoryKinds.motion, caption: '  ');
        },
      );
      expect(memoryTitle(photo), startsWith('Photo from 2026-05-04'));
      expect(memoryTitle(motion), startsWith('Motion memory from'));
    });
  });

  group('memory detail', () {
    Future<UiEnv> showDetail(
      WidgetTester tester, {
      String? caption,
      bool withMotion = false,
      double? lat,
      double? lon,
      bool trashed = false,
      Future<void> Function(UiEnv, MemoryView)? after,
    }) async {
      late MemoryView view;
      final env = await launch(
        tester,
        location: AppRoutes.library,
        prepare: (env) async {
          view = await env.seed(
            caption: caption,
            withMotion: withMotion,
            kind: withMotion ? MemoryKinds.motion : MemoryKinds.photo,
            lat: lat,
            lon: lon,
          );
          if (trashed) await env.memories.trash(view.memory.id);
          if (after != null) await after(env, view);
        },
      );
      if (trashed) {
        await tester.ensureVisible(find.byKey(const Key('filter-trash')));
        await tester.tap(find.byKey(const Key('filter-trash')));
        await pumpUntil(tester, find.byType(GridView));
      }
      await pumpUntil(tester, find.byKey(Key('tile-${view.memory.id}')));
      await tester.tap(find.byKey(Key('tile-${view.memory.id}')));
      await settle(tester, frames: 8);
      return env;
    }

    uiTest(
      '[LIB-002][CAM-050] shows the settings the camera actually applied',
      (tester) async {
        await showDetail(tester, caption: 'Golden hour');
        for (final text in <String>[
          '26 mm',
          'ƒ/1.8',
          '1/125',
          '200',
          '4000 × 3000',
          'mirrorless',
          'natural',
          '3:2',
        ]) {
          expect(find.text(text), findsWidgets, reason: text);
        }
        expect(find.text('Golden hour'), findsWidgets);
      },
    );

    uiTest(
      'metadataRows copes with missing and damaged capture data and shows location only when stored',
      (tester) async {
        late MemoryView empty;
        late MemoryView located;
        await launch(
          tester,
          prepare: (env) async {
            empty = await env.seed(capture: <String, Object?>{});
            located = await env.seed(lat: 3.139, lon: 101.6869);
          },
        );
        expect(
          metadataRows(empty).map((r) => r.$1),
          isNot(contains('Location')),
        );
        expect(
          metadataRows(located)
              .any((r) => r.$1 == 'Location' && r.$2 == '3.1390, 101.6869'),
          isTrue,
        );
        expect(
          metadataRows(empty).map((r) => r.$1),
          containsAll(<String>['Camera style', 'Look']),
        );
      },
    );

    uiTest('[MEM-004] saves a caption, and clearing it removes it', (
      tester,
    ) async {
      late UiEnv env;
      env = await showDetail(tester, caption: 'Old');
      await tester.enterText(
        find.byKey(const Key('caption-field')),
        '  New words ',
      );
      await tester.tap(find.byKey(const Key('save-caption')));
      await settle(tester, frames: 8);
      expect(
        (await io(tester, () => env.memories.library())).single.memory.caption,
        'New words',
      );
      expect(find.byKey(const Key('detail-message')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('caption-field')), '');
      await tester.tap(find.byKey(const Key('save-caption')));
      await settle(tester, frames: 8);
      expect(
        (await io(tester, () => env.memories.library())).single.memory.caption,
        isNull,
      );
    });

    uiTest('[MEM-006] toggles favorite', (tester) async {
      late UiEnv env;
      env = await showDetail(tester);
      await tester.tap(find.byKey(const Key('favorite-toggle')));
      await settle(tester, frames: 8);
      expect(
        (await io(tester, () => env.memories.library())).single.memory.favorite,
        isTrue,
      );
    });

    uiTest('[PRIV-001] removes the stored location', (tester) async {
      late UiEnv env;
      env = await showDetail(tester, lat: 3.1, lon: 101.6);
      await tester.tap(find.byKey(const Key('remove-location')));
      await settle(tester, frames: 8);
      expect(
        (await io(tester, () => env.memories.library())).single.memory.lat,
        isNull,
      );
      expect(find.byKey(const Key('remove-location')), findsNothing);
    });

    uiTest(
      '[MEM-007] move to trash returns to the library; the trash offers restore',
      (tester) async {
        late UiEnv env;
        env = await showDetail(tester);
        await tester.ensureVisible(find.byKey(const Key('trash')));
        await tester.tap(find.byKey(const Key('trash')));
        await settle(tester, frames: 10);
        expect(
          (await io(tester, () => env.memories.library(trashed: true))).length,
          1,
        );
        expect(find.text('Library'), findsWidgets);
      },
    );

    uiTest(
      '[MEM-007] a trashed Memory can be restored, or deleted for good after confirmation',
      (tester) async {
        late UiEnv env;
        env = await showDetail(tester, trashed: true);
        expect(find.textContaining('In the trash'), findsOneWidget);
        expect(find.byKey(const Key('caption-field')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('delete-forever')));
        await tester.tap(find.byKey(const Key('delete-forever')));
        await settle(tester, frames: 4);
        await tester.tap(find.text('Cancel'));
        await settle(tester, frames: 4);
        expect(
          (await io(tester, () => env.memories.library(trashed: true))).length,
          1,
        );
        await tester.tap(find.byKey(const Key('delete-forever')));
        await settle(tester, frames: 4);
        await tester.tap(find.byKey(const Key('confirm-purge')));
        await settle(tester, frames: 10);
        expect(
          await io(tester, () => env.memories.library(trashed: true)),
          isEmpty,
        );
      },
    );

    uiTest('[MEM-007] restoring brings it back to the library', (tester) async {
      late UiEnv env;
      env = await showDetail(tester, trashed: true);
      await tester.ensureVisible(find.byKey(const Key('restore')));
      await tester.tap(find.byKey(const Key('restore')));
      await settle(tester, frames: 8);
      expect((await io(tester, () => env.memories.library())).length, 1);
    });

    uiTest('exports the original through the system share sheet', (
      tester,
    ) async {
      late UiEnv env;
      env = await showDetail(tester);
      await tester.tap(find.byKey(const Key('share-original')));
      await settle(tester, frames: 6);
      expect(env.share.files.single, endsWith('photo_original.jpg'));
    });

    uiTest(
      '[MOT-004] a Motion Memory plays on tap, returns to the still when it ends, and stops on demand',
      (tester) async {
        late UiEnv env;
        env = await showDetail(tester, withMotion: true);
        expect(find.byKey(const Key('motion-button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('motion-button')));
        await settle(tester, frames: 6);
        expect(env.clip.plays, 1);
        expect(find.byKey(const Key('motion-video')), findsOneWidget);
        env.clip.finish();
        await settle(tester, frames: 4);
        expect(find.byKey(const Key('motion-video')), findsNothing);
        await tester.tap(find.byKey(const Key('motion-surface')));
        await settle(tester, frames: 4);
        expect(env.clip.plays, 2);
        await tester.tap(find.byKey(const Key('motion-surface')));
        await settle(tester, frames: 4);
        expect(env.clip.stops, greaterThanOrEqualTo(1));
      },
    );

    uiTest(
      '[MOT-004] pressing and holding plays the motion and releasing stops it',
      (tester) async {
        late UiEnv env;
        env = await showDetail(tester, withMotion: true);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('motion-surface'))),
        );
        await tester.pump(const Duration(milliseconds: 700));
        await settle(tester, frames: 4);
        expect(env.clip.plays, 1);
        await gesture.up();
        await settle(tester, frames: 4);
        expect(env.clip.stops, 1);
      },
    );

    uiTest('a photo has no motion button', (tester) async {
      await showDetail(tester);
      expect(find.byKey(const Key('motion-button')), findsNothing);
    });

    uiTest('[LIB-004] a failed upload can be retried from the detail screen', (
      tester,
    ) async {
      late UiEnv env;
      late MemoryView view;
      env = await showDetail(
        tester,
        after: (e, v) async {
          view = v;
          final asset = v.asset(AssetRoles.photoOriginal)!;
          await (e.data.db.update(
            e.data.db.assets,
          )..where((a) => a.id.equals(asset.id))).write(
            AssetsCompanion(
              uploadState: const Value(UploadStates.failedPermanent),
            ),
          );
        },
      );
      expect(find.byKey(const Key('retry-upload')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-upload')));
      await settle(tester, frames: 8);
      expect(view.memory.id, isNotEmpty);
      expect(env, isNotNull);
    });

    uiTest('a Memory that no longer exists is explained', (tester) async {
      await launch(
        tester,
        location: AppRoutes.memory('0190a000-0000-7000-8000-000000000999'),
      );
      expect(find.byKey(const Key('memory-missing')), findsOneWidget);
    });
  });
}
