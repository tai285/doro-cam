import 'dart:async';
import 'dart:io';

import 'package:doro_cam/data/models.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:flutter/material.dart';

/// Shown when the camera is not usable yet or any more. Always says what is wrong and what the user can do (CAM-052).
class CameraStatusView extends StatelessWidget {
  const CameraStatusView({
    super.key,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.icon = Icons.no_photography_outlined,
  });

  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, semanticLabel: ''),
            const SizedBox(height: 16),
            Text(
              title,
              key: const Key('camera-status-title'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (primaryLabel != null)
              FilledButton(
                key: const Key('camera-status-primary'),
                onPressed: onPrimary,
                child: Text(primaryLabel!),
              ),
            if (secondaryLabel != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('camera-status-secondary'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One-line message over the viewfinder: what the camera adjusted and why (EXP-008), or a notice (CAM-053).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    required this.onDismiss,
    this.warning = true,
  });

  final String message;
  final VoidCallback onDismiss;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: const Color(0xDD202020),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: <Widget>[
              Icon(
                warning ? Icons.info_outline : Icons.check_circle_outline,
                color: Colors.amber,
                size: 18,
                semanticLabel: 'Notice',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  key: const Key('notice-text'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                key: const Key('notice-dismiss'),
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brief white flash when a photo is taken (CAM-051). Skipped when the user prefers reduced motion.
class CaptureFlash extends StatefulWidget {
  const CaptureFlash({super.key, required this.pulse});

  final int pulse;

  @override
  State<CaptureFlash> createState() => _CaptureFlashState();
}

class _CaptureFlashState extends State<CaptureFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void didUpdateWidget(CaptureFlash old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ColoredBox(
          key: const Key('capture-flash'),
          color: Colors.white.withValues(
            alpha:
                (1 - _controller.value) * (_controller.isAnimating ? 0.8 : 0),
          ),
        ),
      ),
    );
  }
}

/// Instant: the print slides up and develops over ~2 s; a tap skips it. The Memory is already saved (EXP-010, NFR-002).
class DevelopingPrint extends StatefulWidget {
  const DevelopingPrint({
    super.key,
    required this.memory,
    required this.onDone,
    this.develop = const InstantDevelop(duration: Duration(seconds: 2)),
  });

  final MemoryView memory;
  final VoidCallback onDone;
  final InstantDevelop develop;

  @override
  State<DevelopingPrint> createState() => _DevelopingPrintState();
}

class _DevelopingPrintState extends State<DevelopingPrint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.develop.duration + const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _controller.value = 1;
      scheduleMicrotask(widget.onDone);
    } else {
      unawaited(
        _controller.forward().then<void>((_) {
          if (mounted) {
            widget.onDone();
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset =
        widget.memory.asset(AssetRoles.photoRendered) ??
        widget.memory.thumbnail;
    final path = asset?.localPath;
    return GestureDetector(
      key: const Key('developing-print'),
      onTap: widget.onDone,
      child: Semantics(
        label: 'Your photo is developing. Tap to skip.',
        button: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final elapsed = Duration(
              milliseconds:
                  (_controller.value *
                          (widget.develop.duration.inMilliseconds + 400))
                      .round(),
            );
            final slide = Curves.easeOut.transform(
              (_controller.value * 4).clamp(0, 1),
            );
            return Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, (1 - slide) * 240),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 36),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFDF7),
                    boxShadow: <BoxShadow>[
                      BoxShadow(blurRadius: 12, color: Color(0x66000000)),
                    ],
                  ),
                  width: 200,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        const ColoredBox(color: Color(0xFF2B2620)),
                        if (path != null && File(path).existsSync())
                          Opacity(
                            opacity: widget.develop.opacity(elapsed),
                            child: Image.file(File(path), fit: BoxFit.cover),
                          ),
                        Opacity(
                          opacity: widget.develop.chemicalHaze(elapsed) * 0.6,
                          child: const ColoredBox(color: Color(0xFFBFA77A)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
