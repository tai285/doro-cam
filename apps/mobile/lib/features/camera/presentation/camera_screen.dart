import 'dart:async';
import 'dart:io';

import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/control_availability.dart';
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/application/camera_state.dart';
import 'package:doro_cam/features/camera/application/stops.dart';
import 'package:doro_cam/features/camera/presentation/camera_overlays.dart';
import 'package:doro_cam/features/camera/presentation/camera_panels.dart';
import 'package:doro_cam/features/camera/presentation/preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The home screen: viewfinder, controls and shutter (docs/design/camera-ux.md).
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The controller lives for the screen: opened here, closed with it (NFR-012: nothing runs while idle).
    unawaited(
      Future<void>.microtask(
        () => ref.read(cameraControllerProvider.notifier).open(),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final controller = ref.read(cameraControllerProvider.notifier);
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        // Permissions may have changed in the system settings while we were away.
        if (ref.read(cameraControllerProvider).phase ==
            CameraPhase.needsPermission) {
          unawaited(controller.open());
        } else {
          unawaited(controller.resume());
        }
      case AppLifecycleState.inactive ||
          AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        unawaited(controller.suspend());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final theme = state.experience.theme;
    return Scaffold(
      backgroundColor: state.isReady ? Colors.black : Color(theme.surface),
      body: SafeArea(
        child: switch (state.phase) {
          CameraPhase.initializing => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Starting the camera',
            ),
          ),
          CameraPhase.needsPermission => _permissionView(state, controller),
          CameraPhase.noCamera => CameraStatusView(
            title: 'No camera found',
            message: 'This device has no camera that apps can use. You can still browse your library.',
            primaryLabel: 'Open library',
            onPrimary: () => context.go(AppRoutes.library),
          ),
          CameraPhase.failed => CameraStatusView(
            title: 'The camera isn’t available',
            message:
                state.errorMessage ??
                'Something went wrong while starting the camera.',
            primaryLabel: 'Try again',
            onPrimary: controller.open,
            secondaryLabel: 'Open library',
            onSecondary: () => context.go(AppRoutes.library),
          ),
          CameraPhase.ready => _CameraBody(state: state),
        },
      ),
    );
  }

  Widget _permissionView(CameraState state, CameraController controller) {
    final permissions = state.permissions;
    final blocked =
        (permissions?.cameraPermanentlyDenied ?? false) ||
        (permissions?.cameraRestricted ?? false);
    final restricted = permissions?.cameraRestricted ?? false;
    return CameraStatusView(
      icon: Icons.photo_camera_outlined,
      title: restricted
          ? 'The camera is restricted'
          : 'Doro Cam needs the camera',
      message: restricted
          ? 'Camera access is restricted on this device (for example by parental controls), so the app can’t ask for it. You can still browse your library.'
          : blocked
          ? 'Camera access is turned off for Doro Cam. Turn it on in Settings to take photos. Your library still works without it.'
          : 'To take photos, Doro Cam needs to use your camera. The microphone is optional: without it, Motion Memories are silent.',
      primaryLabel: restricted
          ? 'Open library'
          : blocked
          ? 'Open Settings'
          : 'Allow camera',
      onPrimary: restricted
          ? () => context.go(AppRoutes.library)
          : controller.requestPermissions,
      secondaryLabel: restricted ? null : 'Open library',
      onSecondary: restricted ? null : () => context.go(AppRoutes.library),
    );
  }
}

class _CameraBody extends ConsumerWidget {
  const _CameraBody({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cameraControllerProvider.notifier);
    final adjustment = state.result?.adjustments.isNotEmpty ?? false
        ? state.result!.adjustments.first.message
        : null;
    final notice = state.notice ?? (state.result?.rejection?.message);
    return Column(
      children: <Widget>[
        _TopBar(state: state),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CameraPreviewView(
                state: state,
                onTapFocus: controller.tapToFocus,
              ),
              if (state.recording)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _RecordingBadge(seconds: state.recordingSeconds),
                  ),
                ),
              Positioned(top: 8, left: 12, child: _Readout(state: state)),
              if (notice != null || adjustment != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: NoticeBanner(
                    message: notice ?? adjustment!,
                    onDismiss: controller.dismissNotice,
                  ),
                ),
              CaptureFlash(pulse: state.flashPulse),
              if (state.developing != null)
                DevelopingPrint(
                  memory: state.developing!,
                  onDone: controller.finishDeveloping,
                ),
            ],
          ),
        ),
        const ControlPanel(),
        _ShutterBar(state: state),
      ],
    );
  }
}

/// Focal length (35 mm equivalent, CAM-007) and live exposure readouts, over the viewfinder.
class _Readout extends StatelessWidget {
  const _Readout({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context) {
    final camera = state.camera;
    final settings = state.settings;
    final base = camera?.focalLength35mmEq;
    final eq = base == null ? null : base * (settings?.zoom ?? 1);
    final pieces = <String>[
      if (eq != null) '${eq.round()} mm',
      if (settings?.digitalZoom ?? false) 'digital zoom',
      if (state.experience.workflow.showsExposureReadout &&
          settings?.iso != null)
        'ISO ${settings!.iso}',
      if (state.experience.workflow.showsExposureReadout &&
          settings?.exposureTimeNs != null)
        formatShutterNs(settings!.exposureTimeNs!),
    ];
    if (pieces.isEmpty) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          pieces.join(' · '),
          key: const Key('readout'),
          style: const TextStyle(
            color: Colors.white,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final text =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: 'Recording, $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            '● $text',
            key: const Key('recording-time'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cameraControllerProvider.notifier);
    final settings = state.settings;
    final availability = controlAvailability(state.caps);
    final flashModes = <FlashMode>[...state.caps.flash]
      ..sort((a, b) => a.index.compareTo(b.index));
    final hasFlash = availability[Control.flash]?.isVisible ?? false;
    final live = availability[Control.live];
    final liveOn = state.liveOn;
    final foreground = Colors.white;

    Widget icon(
      Key key,
      IconData data,
      String label,
      VoidCallback? onTap, {
      bool active = false,
      String? tooltip,
    }) => IconButton(
      key: key,
      tooltip: tooltip ?? label,
      onPressed: onTap,
      color: active ? Colors.amber : foreground,
      icon: Icon(data, semanticLabel: label),
    );

    return Container(
      color: Colors.black,
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            icon(
              const Key('open-settings'),
              Icons.settings_outlined,
              'Settings',
              () => context.go(AppRoutes.settings),
            ),
            if (hasFlash && settings != null)
              icon(
                const Key('flash-button'),
                switch (settings.flash) {
                  FlashMode.off => Icons.flash_off,
                  FlashMode.auto => Icons.flash_auto,
                  FlashMode.on => Icons.flash_on,
                },
                'Flash: ${flashLabel(settings.flash)}',
                () => controller.adjust(
                  (u) => u.merge(
                    CaptureIntent(
                      flash:
                          flashModes[(flashModes.indexOf(settings.flash) + 1) %
                              flashModes.length],
                    ),
                  ),
                ),
                active: settings.flash != FlashMode.off,
              ),
            if (availability[Control.torch]?.isVisible ?? false)
              icon(
                const Key('torch-button'),
                Icons.highlight,
                'Torch ${settings?.torch ?? false ? 'on' : 'off'}',
                () => controller.adjust(
                  (u) => u.merge(
                    CaptureIntent(torch: !(settings?.torch ?? false)),
                  ),
                ),
                active: settings?.torch ?? false,
              ),
            icon(
              const Key('live-button'),
              liveOn ? Icons.motion_photos_on : Icons.motion_photos_off,
              liveOn ? 'LIVE on' : 'LIVE off',
              (live?.isEnabled ?? false)
                  ? () => controller.setLive(enabled: !liveOn)
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          live?.reason ?? 'Motion capture isn’t available.',
                        ),
                      ),
                    ),
              active: liveOn,
              tooltip: (live?.isEnabled ?? false)
                  ? (liveOn ? 'LIVE on' : 'LIVE off')
                  : (live?.reason ?? 'LIVE unavailable'),
            ),
            icon(
              const Key('timer-button'),
              Icons.timer_outlined,
              'Timer: ${(settings?.timerSeconds ?? 0) == 0 ? 'off' : '${settings!.timerSeconds} seconds'}',
              () {
                final next = switch (settings?.timerSeconds ?? 0) {
                  0 => 3,
                  3 => 10,
                  _ => 0,
                };
                controller.adjust(
                  (u) => u.merge(CaptureIntent(timerSeconds: next)),
                );
              },
              active: (settings?.timerSeconds ?? 0) > 0,
            ),
            icon(
              const Key('aspect-button'),
              Icons.crop_free,
              'Aspect ratio ${settings?.aspect ?? ''}',
              () {
                final current = aspectChoices.indexOf(
                  settings?.aspect ?? '4:3',
                );
                controller.adjust(
                  (u) => u.merge(
                    CaptureIntent(
                      aspect:
                          aspectChoices[(current + 1) % aspectChoices.length],
                    ),
                  ),
                );
              },
            ),
            icon(
              const Key('grid-button'),
              Icons.grid_3x3,
              'Grid ${settings?.grid ?? false ? 'on' : 'off'}',
              () => controller.adjust(
                (u) => u.merge(CaptureIntent(grid: !(settings?.grid ?? false))),
              ),
              active: settings?.grid ?? false,
            ),
            if (state.cameras.length > 1)
              icon(
                const Key('flip-button'),
                Icons.flip_camera_android_outlined,
                'Switch camera',
                controller.flip,
              ),
            if (settings != null && (settings.cropNeeded))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Text(
                    'crop',
                    key: Key('crop-note'),
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShutterBar extends ConsumerWidget {
  const _ShutterBar({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cameraControllerProvider.notifier);
    final theme = state.experience.theme;
    final video = state.mode == CaptureMode.video;
    final last = state.lastCapture;
    return Container(
      color: Color(theme.surface),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _LastCapture(
            view: last,
            onTap: () => last == null
                ? context.go(AppRoutes.library)
                : context.push(AppRoutes.memory(last.memory.id)),
          ),
          Semantics(
            button: true,
            label: video
                ? (state.recording ? 'Stop recording' : 'Start recording')
                : 'Take photo',
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('shutter-button'),
              onTap: state.capturing
                  ? null
                  : video
                  ? (state.recording
                        ? controller.stopVideo
                        : controller.startVideo)
                  : controller.capture,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(theme.accent), width: 4),
                  color: video
                      ? (state.recording ? Colors.red : Colors.red.shade300)
                      : Colors.white,
                ),
                child: state.capturing
                    ? const Padding(
                        padding: EdgeInsets.all(22),
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : (state.recording
                          ? const Icon(
                              Icons.stop,
                              color: Colors.white,
                              size: 36,
                            )
                          : null),
              ),
            ),
          ),
          SegmentedButton<CaptureMode>(
            key: const Key('mode-switch'),
            showSelectedIcon: false,
            segments: const <ButtonSegment<CaptureMode>>[
              ButtonSegment<CaptureMode>(
                value: CaptureMode.photo,
                icon: Icon(Icons.photo_camera_outlined),
                tooltip: 'Photo mode',
              ),
              ButtonSegment<CaptureMode>(
                value: CaptureMode.video,
                icon: Icon(Icons.videocam_outlined),
                tooltip: 'Video mode',
              ),
            ],
            selected: <CaptureMode>{state.mode},
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),
        ],
      ),
    );
  }
}

class _LastCapture extends StatelessWidget {
  const _LastCapture({required this.view, required this.onTap});

  final MemoryView? view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = view?.thumbnail?.localPath;
    return Semantics(
      button: true,
      label: view == null ? 'Open library' : 'Open last photo',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('last-capture'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(
                  color: Colors.grey.shade800,
                  child: path != null && File(path).existsSync()
                      ? Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                        )
                      : const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white70,
                        ),
                ),
                if (view?.memory.kind == MemoryKinds.motion)
                  const Positioned(
                    left: 2,
                    bottom: 2,
                    child: Text(
                      'LIVE',
                      key: Key('last-live-badge'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
