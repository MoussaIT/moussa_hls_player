import 'dart:async';
import 'package:flutter/material.dart';
import 'moussa_hls_player_controller.dart';
import 'moussa_hls_player_types.dart';
import 'moussa_hls_player_view.dart';

class MoussaHlsPlayerWithControls extends StatefulWidget {
  const MoussaHlsPlayerWithControls({
    super.key,
    required this.qualities,
    required this.initialQuality,
    this.autoPlay = true,
    this.onController,
    this.backgroundColor = Colors.black,
  });

  final List<MoussaHlsQuality> qualities;
  final String initialQuality;
  final bool autoPlay;

  final ValueChanged<MoussaHlsPlayerController>? onController;
  final Color backgroundColor;

  @override
  State<MoussaHlsPlayerWithControls> createState() =>
      _MoussaHlsPlayerWithControlsState();
}

class _MoussaHlsPlayerWithControlsState extends State<MoussaHlsPlayerWithControls> {
  MoussaHlsPlayerController? _c;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isSeeking = false;
  double _seekTempMs = 0;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  void _kickAutoHide() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  String _fmt(int ms) {
    final s = (ms ~/ 1000).clamp(0, 1 << 30);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _enterFullscreen() async {
    if (_c == null) return;
    final controller = _c!;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenPlayerPage(controller: controller),
      ),
    );
    // after return
    _kickAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: MoussaHlsPlayerView(
        showErrorOverlay: true,
        showBufferingOverlay: true,
        onCreated: (controller) async {
          _c = controller;
          widget.onController?.call(controller);

          await controller.setSource(
            qualities: widget.qualities,
            initialQuality: widget.initialQuality,
            autoPlay: widget.autoPlay,
          );

          _kickAutoHide();
        },
        // Overlay controls above the native view
        child: _c == null
            ? const SizedBox.shrink()
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _kickAutoHide,
                child: ValueListenableBuilder(
                  valueListenable: _c!.state,
                  builder: (context, s, _) {
                    final duration = s.durationMs <= 0 ? 1 : s.durationMs;
                    final pos = _isSeeking ? _seekTempMs.toInt() : s.positionMs;
                    final buffered = s.bufferedToMs.clamp(0, duration);

                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _showControls ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: Stack(
                          children: [
                            // top gradient
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                height: 64,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.black54, Colors.transparent],
                                  ),
                                ),
                              ),
                            ),

                            // bottom gradient
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 110,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black54, Colors.transparent],
                                  ),
                                ),
                              ),
                            ),

                            // center play/pause
                            Center(
                              child: IconButton(
                                iconSize: 64,
                                color: Colors.white,
                                onPressed: () async {
                                  _kickAutoHide();
                                  if (s.isPlaying) {
                                    await _c!.pause();
                                  } else {
                                    await _c!.play();
                                  }
                                },
                                icon: Icon(
                                  s.isPlaying ? Icons.pause_circle : Icons.play_circle,
                                ),
                              ),
                            ),

                            // top-right actions: quality + fullscreen
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _QualityButton(
                                    current: s.currentQuality,
                                    qualities: _c!.qualities,
                                    onPick: (label) async {
                                      _kickAutoHide();
                                      await _c!.setQuality(label);
                                    },
                                  ),
                                  IconButton(
                                    color: Colors.white,
                                    onPressed: () {
                                      _kickAutoHide();
                                      _enterFullscreen();
                                    },
                                    icon: const Icon(Icons.fullscreen),
                                  ),
                                ],
                              ),
                            ),

                            // bottom controls
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 8,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // progress with buffer
                                  _BufferedSlider(
                                    valueMs: pos,
                                    durationMs: duration,
                                    bufferedToMs: buffered,
                                    onChangeStart: () {
                                      _kickAutoHide();
                                      setState(() => _isSeeking = true);
                                    },
                                    onChanged: (ms) {
                                      _kickAutoHide();
                                      setState(() => _seekTempMs = ms.toDouble());
                                    },
                                    onChangeEnd: (ms) async {
                                      _kickAutoHide();
                                      setState(() => _isSeeking = false);
                                      await _c!.seekToMs(ms);
                                    },
                                  ),

                                  const SizedBox(height: 6),

                                  Row(
                                    children: [
                                      // time
                                      Text(
                                        '${_fmt(pos)} / ${_fmt(duration)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                      const Spacer(),

                                      // mute
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () async {
                                          _kickAutoHide();
                                          await _c!.toggleMute();
                                        },
                                        icon: Icon(
                                          _c!.isMuted ? Icons.volume_off : Icons.volume_up,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

// ---------- Fullscreen Page ----------
class _FullscreenPlayerPage extends StatelessWidget {
  const _FullscreenPlayerPage({required this.controller});
  final MoussaHlsPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // NOTE: We re-use the same native view id (same controller),
            // so we just show controls overlay without creating another platform view.
            // Practical approach: show a rotated layout and keep same widget tree.
            // Simpler: just return previous widget via Navigator with fullscreen route wrapper in your app.
            Center(
              child: Text(
                'Fullscreen wrapper\n(Use your app route to place MoussaHlsPlayerWithControls full screen)',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Quality Button ----------
class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.current,
    required this.qualities,
    required this.onPick,
  });

  final String? current;
  final List<MoussaHlsQuality> qualities;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (qualities.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: 'Quality',
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final q in qualities)
          PopupMenuItem<String>(
            value: q.label,
            child: Row(
              children: [
                if (current == q.label)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(q.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          (current == null || current!.isEmpty) ? 'Quality' : current!,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

// ---------- Slider with buffer bar ----------
class _BufferedSlider extends StatelessWidget {
  const _BufferedSlider({
    required this.valueMs,
    required this.durationMs,
    required this.bufferedToMs,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int valueMs;
  final int durationMs;
  final int bufferedToMs;

  final VoidCallback onChangeStart;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final d = durationMs <= 0 ? 1 : durationMs;
    final v = valueMs.clamp(0, d);
    final b = bufferedToMs.clamp(0, d);

    return Stack(
      children: [
        // buffer background bar
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: b / d,
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),

        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            min: 0,
            max: d.toDouble(),
            value: v.toDouble(),
            onChangeStart: (_) => onChangeStart(),
            onChanged: (x) => onChanged(x.toInt()),
            onChangeEnd: (x) => onChangeEnd(x.toInt()),
          ),
        ),
      ],
    );
  }
}
