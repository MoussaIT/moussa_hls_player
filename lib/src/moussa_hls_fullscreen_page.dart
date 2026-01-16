import 'dart:async';
import 'package:flutter/material.dart';

import 'moussa_fullscreen.dart';
import 'moussa_hls_player_controller.dart';
import 'moussa_hls_player_view.dart';
import 'moussa_minimal_controls.dart';

class MoussaFullscreenResult {
  final int positionMs;
  final bool wasPlaying;
  final double volume;
  final String? quality;

  const MoussaFullscreenResult({
    required this.positionMs,
    required this.wasPlaying,
    required this.volume,
    required this.quality,
  });
}

class MoussaHlsFullscreenPage extends StatefulWidget {
  const MoussaHlsFullscreenPage({super.key, required this.sourceController});

  final MoussaHlsPlayerController sourceController;

  @override
  State<MoussaHlsFullscreenPage> createState() =>
      _MoussaHlsFullscreenPageState();
}

class _MoussaHlsFullscreenPageState extends State<MoussaHlsFullscreenPage> {
  MoussaHlsPlayerController? _fsController;

  // ✅ Flutter zoom controller (pinch + pan)
  final TransformationController _tx = TransformationController();

  @override
  void initState() {
    super.initState();
    MoussaFullscreen.enter();
  }

  @override
  void dispose() {
    MoussaFullscreen.exit();
    _tx.dispose();
    super.dispose();
  }

  Future<void> _syncFromSource(MoussaHlsPlayerController fs) async {
    final src = widget.sourceController;
    final s = src.state.value;

    final qualities = src.qualities;
    final initial =
        (s.currentQuality != null &&
            qualities.any((q) => q.label == s.currentQuality))
        ? s.currentQuality!
        : (qualities.isNotEmpty ? qualities.first.label : '');

    if (qualities.isNotEmpty && initial.isNotEmpty) {
      await fs.setSource(
        qualities: qualities,
        initialQuality: initial,
        autoPlay: s.isPlaying,
      );

      await fs.setVolume(s.volume);

      if (s.positionMs > 0) {
        await fs.seekToMs(s.positionMs);
      }

      if (s.isPlaying) {
        await fs.play();
      }
    }
  }

  MoussaFullscreenResult _currentResult() {
    final c = _fsController;
    if (c == null) {
      return const MoussaFullscreenResult(
        positionMs: 0,
        wasPlaying: false,
        volume: 1.0,
        quality: null,
      );
    }
    final s = c.state.value;
    return MoussaFullscreenResult(
      positionMs: s.positionMs,
      wasPlaying: s.isPlaying,
      volume: s.volume,
      quality: s.currentQuality,
    );
  }

  void _exitFullscreen() {
    Navigator.of(context).pop(_currentResult());
  }

  // ✅ double tap: toggle 1x <-> 2x (تقدر تخليها 3x لو عايز)
  void _onDoubleTap() {
    final m = _tx.value;
    final currentScale = m.getMaxScaleOnAxis();

    if (currentScale > 1.01) {
      _tx.value = Matrix4.identity();
    } else {
      // zoom in to 2x around center
      _tx.value = Matrix4.identity()..scale(2.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _exitFullscreen();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ✅ Flutter Zoom: pinch + pan
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _tx,
                minScale: 1.0,
                maxScale: 4.0,
                // ✅ يسمح إنه يطلع برا الإطار عادي
                constrained: false,
                // ✅ pan بحرية (بدون حدود)
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, cts) {
                      final w = cts.maxWidth;
                      final h = cts.maxHeight;

                      // حماية من القيم الغريبة
                      final ratio = (h <= 0) ? (16 / 9) : (w / h);

                      return Center(
                        child: AspectRatio(
                          aspectRatio: ratio,
                          child: MoussaHlsPlayerView(
                            onCreated: (fs) async {
                              _fsController = fs;
                              await _syncFromSource(fs);
                            },
                            showErrorOverlay: true,
                            showBufferingOverlay: true,
                            showControls: false,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ✅ Controls overlay فوق الفيديو (مبتتأثرش بالـ pinch)
            if (_fsController != null)
              MoussaMinimalControls(
                controller: _fsController!,
                onExitFullscreen: _exitFullscreen,
              ),
          ],
        ),
      ),
    );
  }
}
