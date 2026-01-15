import 'dart:async';
import 'package:flutter/material.dart';
import 'moussa_hls_player_controller.dart';

class MoussaMinimalControls extends StatefulWidget {
  const MoussaMinimalControls({
    super.key,
    required this.controller,
    required this.onExitFullscreen,
  });

  final MoussaHlsPlayerController controller;
  final VoidCallback onExitFullscreen;

  @override
  State<MoussaMinimalControls> createState() => _MoussaMinimalControlsState();
}

class _MoussaMinimalControlsState extends State<MoussaMinimalControls> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    _restartAutoHide();
  }

  void _restartAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  String _fmt(int ms) {
    final totalSec = (ms / 1000).floor();
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVisible,
      child: ValueListenableBuilder(
        valueListenable: widget.controller.state,
        builder: (context, s, _) {
          final dur = s.durationMs <= 0 ? 1 : s.durationMs;
          final pos = s.positionMs.clamp(0, dur);
          final buf = s.bufferedToMs.clamp(0, dur);

          // نسب
          final bufferedValue = buf / dur;
          final positionValue = pos / dur;

          if (_visible) _restartAutoHide();

          return Stack(
            children: [
              // Top bar (Exit)
              AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: IconButton(
                        onPressed: widget.onExitFullscreen,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),

              // Center play/pause
              AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: InkResponse(
                    onTap: () async {
                      if (s.isPlaying) {
                        await widget.controller.pause();
                      } else {
                        await widget.controller.play();
                      }
                      _restartAutoHide();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(60),
                      ),
                      child: Icon(
                        s.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom progress + time
              AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Buffered bar (خلفية)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              children: [
                                // Background
                                Container(height: 4, color: Colors.white24),

                                // Buffered
                                FractionallySizedBox(
                                  widthFactor: bufferedValue.isNaN ? 0 : bufferedValue,
                                  child: Container(height: 4, color: Colors.white38),
                                ),

                                // Slider فوقها
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  ),
                                  child: Slider(
                                    value: positionValue.isNaN ? 0 : positionValue,
                                    onChangeStart: (_) => _hideTimer?.cancel(),
                                    onChanged: (v) async {
                                      final newPos = (v * dur).round();
                                      await widget.controller.seekToMs(newPos);
                                    },
                                    onChangeEnd: (_) => _restartAutoHide(),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 6),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              Text(_fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
