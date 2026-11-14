import 'dart:async';
import 'dart:io';

import 'package:doro_cam/features/library/presentation/library_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// A playable motion clip. A seam so widget tests can drive playback without a video decoder.
abstract interface class MotionClip {
  Future<void> prepare();
  Future<void> play();
  Future<void> stop();

  /// Fires once each time playback reaches the end.
  Stream<void> get ended;
  Widget view();
  double get aspectRatio;
  void dispose();
}

class VideoPlayerMotionClip implements MotionClip {
  VideoPlayerMotionClip(File file)
    : _controller = VideoPlayerController.file(file);

  final VideoPlayerController _controller;
  final StreamController<void> _ended = StreamController<void>.broadcast();
  bool _wasPlaying = false;

  @override
  Future<void> prepare() async {
    await _controller.initialize();
    await _controller.setLooping(false);
    _controller.addListener(() {
      final value = _controller.value;
      final atEnd =
          value.isInitialized &&
          value.duration > Duration.zero &&
          value.position >= value.duration;
      if (_wasPlaying && atEnd && !value.isPlaying) {
        _wasPlaying = false;
        _ended.add(null);
      }
      if (value.isPlaying) {
        _wasPlaying = true;
      }
    });
  }

  @override
  Future<void> play() async {
    await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  @override
  Future<void> stop() async {
    await _controller.pause();
    await _controller.seekTo(Duration.zero);
  }

  @override
  Stream<void> get ended => _ended.stream;

  @override
  Widget view() => VideoPlayer(_controller);

  @override
  double get aspectRatio =>
      _controller.value.isInitialized ? _controller.value.aspectRatio : 4 / 3;

  @override
  void dispose() {
    unawaited(_ended.close());
    unawaited(_controller.dispose());
  }
}

final motionClipFactoryProvider = Provider<MotionClip Function(File)>(
  (ref) => VideoPlayerMotionClip.new,
);

/// The still of a Motion Memory; press or tap to play the motion and sound, then it returns to the still (MOT-004).
class MotionPlayerView extends ConsumerStatefulWidget {
  const MotionPlayerView({
    super.key,
    required this.stillPath,
    required this.clipPath,
    required this.label,
  });

  final String? stillPath;
  final String? clipPath;
  final String label;

  @override
  ConsumerState<MotionPlayerView> createState() => _MotionPlayerViewState();
}

class _MotionPlayerViewState extends ConsumerState<MotionPlayerView> {
  MotionClip? _clip;
  StreamSubscription<void>? _endedSub;
  bool _playing = false;
  String? _error;

  bool get _hasClip =>
      widget.clipPath != null && File(widget.clipPath!).existsSync();

  @override
  void dispose() {
    unawaited(_endedSub?.cancel());
    _clip?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (!_hasClip || _playing) {
      return;
    }
    try {
      var clip = _clip;
      if (clip == null) {
        clip = ref.read(motionClipFactoryProvider)(File(widget.clipPath!));
        await clip.prepare();
        _endedSub = clip.ended.listen((_) {
          if (mounted) {
            setState(() => _playing = false);
          }
        });
        _clip = clip;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _playing = true;
        _error = null;
      });
      await clip.play();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _playing = false;
          _error = 'The motion could not be played: $error';
        });
      }
    }
  }

  Future<void> _stop() async {
    await _clip?.stop();
    if (mounted) {
      setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    return Column(
      children: <Widget>[
        GestureDetector(
          key: const Key('motion-surface'),
          onTap: _playing ? _stop : _play,
          onLongPressStart: (_) => _play(),
          onLongPressEnd: (_) => _stop(),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                LocalImage(
                  path: widget.stillPath,
                  fit: BoxFit.contain,
                  semanticLabel: widget.label,
                ),
                if (_playing && clip != null)
                  Container(
                    key: const Key('motion-video'),
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: clip.aspectRatio,
                        child: clip.view(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_hasClip)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const Key('motion-button'),
              onPressed: _playing ? _stop : _play,
              icon: Icon(_playing ? Icons.stop : Icons.motion_photos_on),
              label: Text(_playing ? 'Back to photo' : 'Play motion'),
            ),
          ),
        if (_error != null) Text(_error!, key: const Key('motion-error')),
      ],
    );
  }
}
