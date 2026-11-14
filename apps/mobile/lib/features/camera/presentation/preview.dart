import 'dart:async';
import 'dart:ui' as ui;

import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/application/camera_state.dart';
import 'package:doro_cam/profiles/image_profile.dart';
import 'package:doro_cam/profiles/shader_params.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A compiled look ready for the preview: the fragment program plus the profile's tiled LUT as an image (PRF-001).
class PreviewLook {
  PreviewLook(this.program, this.lut);
  final ui.FragmentProgram program;
  final ui.Image lut;
}

/// Loads the shader and LUT for [profileId], or null when the GPU path is unavailable (the capture still gets the
/// look: the photo is rendered natively from the same LUT, PRF-003). Overridden with a null value in tests.
final previewLookProvider = FutureProvider.family<PreviewLook?, String>((
  ref,
  profileId,
) async {
  try {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return null;
    }
    final lut = ref.watch(compiledLutProvider(profileId));
    final texture = TiledLutTexture.forLut(lut);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      texture.pixels,
      texture.width,
      texture.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final program = await ui.FragmentProgram.fromAsset(profileShaderAsset);
    return PreviewLook(program, await completer.future);
  } on Object {
    return null;
  }
});

/// The live viewfinder: the camera texture, the profile's look on top of it, framing and grid guides,
/// tap-to-focus and the self-timer count.
class CameraPreviewView extends ConsumerWidget {
  const CameraPreviewView({
    super.key,
    required this.state,
    required this.onTapFocus,
  });

  final CameraState state;
  final void Function(double x, double y) onTapFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = state.session;
    final settings = state.settings;
    if (session == null) {
      return const SizedBox.expand();
    }
    final previewSize = session.info.previewSize;
    // The sensor is landscape; the app is portrait-first.
    final previewAspect = previewSize.height / previewSize.width;
    final profileId = settings?.profileId ?? 'natural';
    final look = ref.watch(previewLookProvider(profileId)).value;
    final profile = ref.watch(profileRegistryProvider).resolve(profileId);

    return Center(
      child: AspectRatio(
        aspectRatio: previewAspect,
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => onTapFocus(
              details.localPosition.dx / box.maxWidth,
              details.localPosition.dy / box.maxHeight,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Semantics(
                  label: 'Camera preview with the ${profile.name} look',
                  image: true,
                  child: Texture(textureId: session.textureId),
                ),
                if (look != null)
                  _LookLayer(
                    look: look,
                    profile: profile,
                    size: Size(box.maxWidth, box.maxHeight),
                  ),
                if (settings != null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _FramePainter(
                        aspect: settings.aspect,
                        previewAspect: previewAspect,
                        grid: settings.grid,
                      ),
                    ),
                  ),
                if (state.focusPoint != null)
                  _FocusRing(
                    point: state.focusPoint!,
                    box: Size(box.maxWidth, box.maxHeight),
                    onDone: () => ref
                        .read(cameraControllerProvider.notifier)
                        .clearFocusPoint(),
                  ),
                if (state.countdown != null)
                  Center(
                    child: Semantics(
                      liveRegion: true,
                      label: 'Photo in ${state.countdown} seconds',
                      child: Text(
                        '${state.countdown}',
                        key: const Key('countdown'),
                        style: const TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                        ),
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

class _LookLayer extends StatelessWidget {
  const _LookLayer({
    required this.look,
    required this.profile,
    required this.size,
  });

  final PreviewLook look;
  final ImageProfile profile;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final shader = look.program.fragmentShader();
    final floats = ProfileShaderParams.from(
      profile,
      width: size.width,
      height: size.height,
    ).floats;
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    shader.setImageSampler(1, look.lut);
    return IgnorePointer(
      child: BackdropFilter(
        filter: ui.ImageFilter.shader(shader),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Dims what the chosen aspect ratio will crop out of the rendition, and draws the thirds grid.
class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.aspect,
    required this.previewAspect,
    required this.grid,
  });

  final String aspect;
  final double previewAspect;
  final bool grid;

  double get _targetAspect {
    final parts = aspect.split(':');
    if (parts.length != 2) {
      return previewAspect;
    }
    final w = double.tryParse(parts[0]) ?? 3;
    final h = double.tryParse(parts[1]) ?? 4;
    return h / w; // portrait height/width
  }

  @override
  void paint(Canvas canvas, Size size) {
    var frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final target = _targetAspect;
    final current = size.height / size.width;
    if ((target - current).abs() > 0.01) {
      if (target < current) {
        final h = size.width * target;
        frame = Rect.fromLTWH(0, (size.height - h) / 2, size.width, h);
      } else {
        final w = size.height / target;
        frame = Rect.fromLTWH((size.width - w) / 2, 0, w, size.height);
      }
      final dim = Paint()..color = const Color(0x99000000);
      canvas
        ..drawRect(Rect.fromLTRB(0, 0, size.width, frame.top), dim)
        ..drawRect(Rect.fromLTRB(0, frame.bottom, size.width, size.height), dim)
        ..drawRect(Rect.fromLTRB(0, frame.top, frame.left, frame.bottom), dim)
        ..drawRect(
          Rect.fromLTRB(frame.right, frame.top, size.width, frame.bottom),
          dim,
        );
    }
    if (grid) {
      final line = Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        canvas
          ..drawLine(
            Offset(frame.left + frame.width * i / 3, frame.top),
            Offset(frame.left + frame.width * i / 3, frame.bottom),
            line,
          )
          ..drawLine(
            Offset(frame.left, frame.top + frame.height * i / 3),
            Offset(frame.right, frame.top + frame.height * i / 3),
            line,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.aspect != aspect ||
      old.grid != grid ||
      old.previewAspect != previewAspect;
}

class _FocusRing extends StatefulWidget {
  const _FocusRing({
    required this.point,
    required this.box,
    required this.onDone,
  });

  final (double, double) point;
  final Size box;
  final VoidCallback onDone;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.point.$1 * widget.box.width - 32,
      top: widget.point.$2 * widget.box.height - 32,
      child: IgnorePointer(
        child: Container(
          key: const Key('focus-ring'),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.amber, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
