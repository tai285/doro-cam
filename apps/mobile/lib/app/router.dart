import 'package:doro_cam/app/not_found_screen.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/albums/presentation/albums_screens.dart';
import 'package:doro_cam/features/auth/presentation/auth_screens.dart';
import 'package:doro_cam/features/camera/presentation/camera_screen.dart';
import 'package:doro_cam/features/insights/presentation/insights_screen.dart';
import 'package:doro_cam/features/library/presentation/library_screen.dart';
import 'package:doro_cam/features/memory_detail/presentation/memory_detail_screen.dart';
import 'package:doro_cam/features/onboarding/presentation/onboarding_screen.dart';
import 'package:doro_cam/features/presets/presentation/presets_screen.dart';
import 'package:doro_cam/features/settings/presentation/settings_screen.dart';
import 'package:doro_cam/features/sync/presentation/sync_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route locations. The camera is the app's home (docs/architecture/mobile.md).
abstract final class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String camera = '/camera';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String sync = '/settings/sync';
  static const String presets = '/settings/presets';
  static const String signIn = '/auth/sign-in';
  static const String signUp = '/auth/sign-up';
  static const String forgotPassword = '/auth/forgot';
  static const String albums = '/albums';
  static const String insights = '/insights';
  static const String memoryPattern = '/memory/:id';
  static const String albumPattern = '/albums/:id';
  static const String invitePattern = '/invites/:token';
  static const String inviteBase = '/invites';

  static String memory(String id) => '/memory/${Uri.encodeComponent(id)}';
  static String album(String id) => '/albums/${Uri.encodeComponent(id)}';
  static String invite(String token) =>
      token.isEmpty ? inviteBase : '/invites/${Uri.encodeComponent(token)}';
}

/// Settings key: the first-run introduction was seen.
const String onboardedKey = 'ui.onboarded';

/// Builds the app's routes. [isOnboarded] decides whether the first launch shows the introduction;
/// leave it null to skip it (tests that only care about a screen).
GoRouter createRouter({
  String initialLocation = AppRoutes.camera,
  Future<bool> Function()? isOnboarded,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    errorBuilder: (context, state) =>
        NotFoundScreen(location: state.uri.toString()),
    redirect: (context, state) async {
      if (isOnboarded != null &&
          state.matchedLocation == AppRoutes.camera &&
          !await isOnboarded()) {
        return AppRoutes.onboarding;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => AppRoutes.camera),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
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
        builder: (context, state) =>
            MemoryDetailScreen(memoryId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.sync,
        builder: (context, state) => const SyncScreen(),
      ),
      GoRoute(
        path: AppRoutes.presets,
        builder: (context, state) => const PresetsScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.albums,
        builder: (context, state) => const AlbumsScreen(),
      ),
      GoRoute(
        path: AppRoutes.albumPattern,
        builder: (context, state) =>
            AlbumScreen(albumId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.insights,
        builder: (context, state) => const InsightsScreen(),
      ),
      GoRoute(
        path: AppRoutes.inviteBase,
        builder: (context, state) => const InviteScreen(),
      ),
      GoRoute(
        path: AppRoutes.invitePattern,
        builder: (context, state) =>
            InviteScreen(token: state.pathParameters['token'] ?? ''),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter(
    isOnboarded: () => ref
        .read(settingsRepositoryProvider)
        .readBool(onboardedKey, fallback: false),
  );
  ref.onDispose(router.dispose);
  return router;
});
