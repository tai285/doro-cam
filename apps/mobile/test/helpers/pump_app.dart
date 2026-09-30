import 'package:doro_cam/app/app.dart';
import 'package:doro_cam/app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps the real app starting at [location]. Returns the router so tests can assert on it.
Future<GoRouter> pumpApp(WidgetTester tester, {String location = AppRoutes.camera}) async {
  final router = createRouter(initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routerProvider.overrideWithValue(router)],
      child: const DoroCamApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String currentPath(GoRouter router) => router.state.uri.path;
