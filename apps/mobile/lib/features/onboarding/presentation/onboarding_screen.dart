import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const List<_Page> _pages = <_Page>[
  _Page(
    Icons.photo_camera_outlined,
    'Capture the moment',
    'Real camera controls that only appear when your phone can actually do them, in four camera styles.',
  ),
  _Page(
    Icons.motion_photos_on,
    'Keep the feeling',
    'LIVE photos keep a moment of motion and sound around the shutter, so you can relive it, not just see it.',
  ),
  _Page(
    Icons.cloud_done_outlined,
    'Yours, at original quality',
    'Everything works offline. Sign in any time to back up the originals and see them on the web.',
  ),
];

/// First-run introduction and the camera / microphone permission request with a clear explanation (CAM-052).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool askPermissions}) async {
    await ref
        .read(settingsRepositoryProvider)
        .writeBool(onboardedKey, value: true);
    if (askPermissions) {
      try {
        await ref.read(doroCameraProvider).requestPermissions();
      } on Object {
        // The camera screen explains and offers recovery if this fails.
      }
    }
    if (mounted) {
      context.go(AppRoutes.camera);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('onboarding-skip'),
                onPressed: () => _finish(askPermissions: false),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                key: const Key('onboarding-pages'),
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: <Widget>[
                  for (final page in _pages)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(page.icon, size: 96, semanticLabel: ''),
                          const SizedBox(height: 24),
                          Text(
                            page.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(page.body, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '${_index + 1} of ${_pages.length}',
              key: const Key('onboarding-position'),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: last
                  ? Column(
                      children: <Widget>[
                        const Text(
                          'Doro Cam needs your camera to take photos. The microphone is optional: without it, LIVE photos are silent.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const Key('onboarding-allow'),
                          onPressed: () => _finish(askPermissions: true),
                          child: const Text('Allow camera and microphone'),
                        ),
                        TextButton(
                          key: const Key('onboarding-later'),
                          onPressed: () => _finish(askPermissions: false),
                          child: const Text('Not now'),
                        ),
                      ],
                    )
                  : FilledButton(
                      key: const Key('onboarding-next'),
                      onPressed: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Next'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
