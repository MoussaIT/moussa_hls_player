import 'package:flutter/material.dart';
import 'moussa_fullscreen.dart';
import 'moussa_hls_player_controller.dart';
import 'moussa_hls_player_view.dart';
import 'moussa_minimal_controls.dart';

/// Result returned when exiting fullscreen.
/// Used to sync state back to the original (inline) controller.
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
  const MoussaHlsFullscreenPage({
    super.key,
    required this.sourceController,
  });

  final MoussaHlsPlayerController sourceController;

  @override
  State<MoussaHlsFullscreenPage> createState() => _MoussaHlsFullscreenPageState();
}

class _MoussaHlsFullscreenPageState extends State<MoussaHlsFullscreenPage> {
  MoussaHlsPlayerController? _fsController;

  double _zoom = 1.0;
  double _zoomBase = 1.0;
  
  @override
  void initState() {
    super.initState();
    MoussaFullscreen.enter();
  }

  @override
  void dispose() {
    MoussaFullscreen.exit();
    super.dispose();
  }

  Future<void> _syncFromSource(MoussaHlsPlayerController fs) async {
    final src = widget.sourceController;
    final s = src.state.value;

    final qualities = src.qualities;
    final initial = (s.currentQuality != null &&
            qualities.any((q) => q.label == s.currentQuality))
        ? s.currentQuality!
        : (qualities.isNotEmpty ? qualities.first.label : '');

    if (qualities.isNotEmpty && initial.isNotEmpty) {
      await fs.setSource(
        qualities: qualities,
        initialQuality: initial,
        autoPlay: s.isPlaying, // يكمل نفس حالة التشغيل
      );

      // نفس الصوت
      await fs.setVolume(s.volume);

      // نفس المكان
      if (s.positionMs > 0) {
        await fs.seekToMs(s.positionMs);
      }

      // لو كان شغال خليّه يكمل
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
    // Disable zoom when leaving fullscreen to avoid gesture conflicts inline.
    final c = _fsController;
    if (c != null) {
      // Best-effort; ignore failures.
      c.setZoomEnabled(false);
      c.resetZoom();
    }
    Navigator.of(context).pop(_currentResult());
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
        body: GestureDetector(
  behavior: HitTestBehavior.translucent,

  onScaleStart: (_) {
    _zoomBase = _zoom;
  },

  onScaleUpdate: (d) async {
    final c = _fsController;
    if (c == null) return;

    // scale بتطلع relative للgesture الحالي
    final next = (_zoomBase * d.scale).clamp(1.0, 4.0);
    _zoom = next;

    // ابعت scale للنيتف
    await c.setZoomScale(_zoom);
  },

  onDoubleTap: () async {
    final c = _fsController;
    if (c == null) return;

    _zoom = 1.0;
    await c.resetZoom();
  },

  child: MoussaHlsPlayerView(
            onCreated: (fs) async {
              _fsController = fs;
              await _syncFromSource(fs);
          
              // Enable pinch-to-zoom in fullscreen (1..4 by default)
              await fs.setMaxZoom(4.0);
              await fs.setZoomEnabled(true);
            },
            showErrorOverlay: true,
            showBufferingOverlay: true,
            showControls: false,
            child: (_fsController == null)
                ? const SizedBox.shrink()
                : MoussaMinimalControls(
                    controller: _fsController!,
                    onExitFullscreen: _exitFullscreen,
                  ),
          ),
        ),
      ),
    );
  }
}
