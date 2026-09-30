import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/features/camera/presentation/camera_screen.dart';
import 'package:doro_cam/features/library/presentation/library_screen.dart';
import 'package:doro_cam/features/memory_detail/presentation/memory_detail_screen.dart';
import 'package:doro_cam/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group('AppRoutes', () {
    test('memory() builds a path and percent-encodes the id', () {
      expect(AppRoutes.memory('abc-123'), '/memory/abc-123');
      expect(AppRoutes.memory('a/b c'), '/memory/a%2Fb%20c');
      expect(AppRoutes.memory('50%'), '/memory/50%25');
    });

    test('route constants match the documented locations', () {
      expect(AppRoutes.camera, '/camera');
      expect(AppRoutes.library, '/library');
      expect(AppRoutes.settings, '/settings');
      expect(AppRoutes.memoryPattern, '/memory/:id');
    });
  });

  group('router', () {
    testWidgets('starts on the camera, the app home', (tester) async {
      final router = await pumpApp(tester);
      expect(currentPath(router), AppRoutes.camera);
      expect(find.byType(CameraScreen), findsOneWidget);
    });

    testWidgets('the root path redirects to the camera', (tester) async {
      final router = await pumpApp(tester, location: '/');
      expect(currentPath(router), AppRoutes.camera);
      expect(find.byType(CameraScreen), findsOneWidget);
    });

    testWidgets('deep link to the library', (tester) async {
      await pumpApp(tester, location: AppRoutes.library);
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.text('No memories yet'), findsOneWidget);
    });

    testWidgets('deep link to settings', (tester) async {
      await pumpApp(tester, location: AppRoutes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('deep link to a memory passes the id through', (tester) async {
      await pumpApp(tester, location: AppRoutes.memory('0191-abc'));
      expect(find.byType(MemoryDetailScreen), findsOneWidget);
      expect(find.text('Memory 0191-abc'), findsOneWidget);
    });

    testWidgets('a memory id with reserved characters round-trips intact', (tester) async {
      await pumpApp(tester, location: AppRoutes.memory('a/b c'));
      expect(find.text('Memory a/b c'), findsOneWidget);
    });

    testWidgets('an unknown location shows the not-found screen with the location', (tester) async {
      await pumpApp(tester, location: '/does/not/exist');
      expect(find.text('Not found'), findsOneWidget);
      expect(find.text('There is nothing at /does/not/exist'), findsOneWidget);
    });

    testWidgets('the not-found screen leads back to the camera', (tester) async {
      final router = await pumpApp(tester, location: '/nope');
      await tester.tap(find.text('Back to camera'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.camera);
      expect(find.byType(CameraScreen), findsOneWidget);
    });
  });

  group('navigation between screens', () {
    testWidgets('camera → library → back to camera', (tester) async {
      final router = await pumpApp(tester);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.library);

      await tester.tap(find.byTooltip('Back to camera'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.camera);
    });

    testWidgets('camera → settings → back to camera', (tester) async {
      final router = await pumpApp(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back to camera'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.camera);
    });

    testWidgets('memory detail leads back to the library', (tester) async {
      final router = await pumpApp(tester, location: AppRoutes.memory('m1'));
      await tester.tap(find.byTooltip('Back to library'));
      await tester.pumpAndSettle();
      expect(currentPath(router), AppRoutes.library);
    });
  });

  group('accessibility', () {
    testWidgets('[NFR-007] navigation controls expose semantic labels', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(find.bySemanticsLabel('Library'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Back to camera'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('[NFR-007] text scales with the system text scale factor', (tester) async {
      await pumpApp(tester);
      final base = tester.getSize(find.text('Camera')).height;

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final scaled = tester.getSize(find.text('Camera')).height;

      expect(scaled, greaterThan(base * 1.5));
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  test('createRouter builds independent routers', () {
    final a = createRouter();
    final b = createRouter(initialLocation: AppRoutes.library);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(identical(a, b), isFalse);
    expect(a.routeInformationProvider.value.uri.path, AppRoutes.camera);
    expect(b.routeInformationProvider.value.uri.path, AppRoutes.library);
  });
}
