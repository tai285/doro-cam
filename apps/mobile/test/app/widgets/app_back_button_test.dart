import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/here',
  routes: [
    GoRoute(
      path: '/here',
      builder: (context, state) => const Scaffold(
        body: AppBackButton(label: 'Back to somewhere', location: '/there'),
      ),
    ),
    GoRoute(path: '/there', builder: (context, state) => const Scaffold(body: Text('There'))),
  ],
);

void main() {
  testWidgets('[NFR-007] exposes its label as the accessible name and as a tooltip', (tester) async {
    final handle = tester.ensureSemantics();
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final node = tester.getSemantics(find.byType(IconButton));
    expect(node.label, contains('Back to somewhere'));
    expect(node.tooltip, 'Back to somewhere');
    expect(find.byTooltip('Back to somewhere'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('navigates to its location when tapped', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('There'), findsOneWidget);
    expect(router.state.uri.path, '/there');
  });

  testWidgets('has a touch target of at least 48x48 dp', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
