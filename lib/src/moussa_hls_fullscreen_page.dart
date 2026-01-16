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
  State<MoussaHlsFullscreenPage> createState() => _MoussaHlsFullscreenPageState();
}

class _MoussaHlsFullscreenPageState extends State<MoussaHlsFullscreenPage> {
  MoussaHlsPlayerController? _fsController;

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
        (s.currentQuality != null && qualities.any((q) => q.label == s.currentQuality))
            ? s.currentQuality!
            : (qualities.isNotEmpty ? qualities.first.label : '');

    if (qualities.isEmpty || initial.isEmpty) return;

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

  void _onDoubleTap() {
    final currentScale = _tx.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      _tx.value = Matrix4.identity();
    } else {
      _tx.value = Matrix4.identity()..scale(2.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ratio = (size.height <= 0) ? (16 / 9) : (size.width / size.height);

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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _tx,
                minScale: 1.0,
                maxScale: 4.0,
                constrained: false,
                // ✅ بدل infinity: رقم كبير آمن
                boundaryMargin: const EdgeInsets.all(3000),

                child: Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: MoussaHlsPlayerView(
                          onCreated: (fs) async {
                            _fsController = fs;
                            if (mounted) setState(() {}); // ✅ عشان الـ controls تظهر
                            await _syncFromSource(fs);
                          },
                          showErrorOverlay: true,
                          showBufferingOverlay: true,
                          showControls: false,
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

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
