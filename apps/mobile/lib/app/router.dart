import 'package:doro_cam/app/not_found_screen.dart';
import 'package:doro_cam/features/camera/presentation/camera_screen.dart';
import 'package:doro_cam/features/library/presentation/library_screen.dart';
import 'package:doro_cam/features/memory_detail/presentation/memory_detail_screen.dart';
import 'package:doro_cam/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route locations. The camera is the app's home (docs/architecture/mobile.md).
abstract final class AppRoutes {
  static const String camera = '/camera';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String memoryPattern = '/memory/:id';

  static String memory(String id) => '/memory/${Uri.encodeComponent(id)}';
}

GoRouter createRouter({String initialLocation = AppRoutes.camera}) {
  return GoRouter(
    initialLocation: initialLocation,
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => AppRoutes.camera),
      GoRoute(
        path: AppRoutes.camera,
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: AppRoutes.library,
        builder: (context, state) => const LibraryScreen(),
      ),
      GoRoute(
        path: AppRoutes.memoryPattern,
        builder: (context, state) => MemoryDetailScreen(memoryId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});
