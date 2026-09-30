import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget. Owns only app-wide concerns: theme and routing (see docs/architecture/mobile.md).
class DoroCamApp extends ConsumerWidget {
  const DoroCamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Doro Cam',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The camera UI is dark by default (docs/design/ux-principles.md).
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
