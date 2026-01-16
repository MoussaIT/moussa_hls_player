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
  double _speed = 1.0;
  bool _isScrubbing = false;
  double? _scrubValue; // 0..1

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
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(50),
                      ),
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
                          // Quick actions: -5s, speed, +5s
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(24),
                                  ), child: IconButton(
                                  onPressed: () async {
                                    await widget.controller.seekByMs(-5000);
                                    _restartAutoHide();
                                  },
                                  icon: const Icon(
                                    Icons.replay_5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8,),
                              PopupMenuButton<double>(
                                initialValue: _speed,
                                color: Colors.black87,
                                onSelected: (v) async {
                                  setState(() => _speed = v);
                                  await widget.controller.setPlaybackSpeed(v);
                                  _restartAutoHide();
                                },
                                itemBuilder: (_) {
                                  const speeds = <double>[
                                    0.5,
                                    0.75,
                                    1.0,
                                    1.25,
                                    1.5,
                                    2.0,
                                  ];
                                  return speeds
                                      .map(
                                        (s) => PopupMenuItem<double>(
                                          value: s,
                                          child: Text(
                                            '${s.toStringAsFixed(s == 1.0 ? 0 : 2)}x',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Text(
                                    '${_speed.toStringAsFixed(_speed == 1.0 ? 0 : 2)}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8,),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(24),
                                  ), child: IconButton(
                                  onPressed: () async {
                                    await widget.controller.seekByMs(5000);
                                    _restartAutoHide();
                                  },
                                  icon: const Icon(
                                    Icons.forward_5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Buffered bar (خلفية)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              children: [
                                // Background
                                Container(height: 4, color: Colors.white24),

                                // Buffered
                                FractionallySizedBox(
                                  widthFactor: bufferedValue.isNaN
                                      ? 0
                                      : bufferedValue,
                                  child: Container(
                                    height: 4,
                                    color: Colors.white38,
                                  ),
                                ),

                                // Slider فوقها
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                  ),
                                  child: Slider(
                                    value:
                                        (_isScrubbing
                                                ? (_scrubValue ?? positionValue)
                                                : positionValue)
                                            .isNaN
                                        ? 0
                                        : (_isScrubbing
                                              ? (_scrubValue ?? positionValue)
                                              : positionValue),

                                    onChangeStart: (_) {
                                      _hideTimer?.cancel();
                                      setState(() {
                                        _isScrubbing = true;
                                        _scrubValue = positionValue;
                                      });
                                    },

                                    // أثناء السحب: UI بس (من غير seek)
                                    onChanged: (v) {
                                      setState(() => _scrubValue = v);
                                    },

                                    // عند رفع الصباع: seek مرة واحدة
                                    onChangeEnd: (v) async {
                                      final newPos = (v * dur).round();
                                      await widget.controller.seekToMs(newPos);

                                      if (mounted) {
                                        setState(() {
                                          _isScrubbing = false;
                                          _scrubValue = null;
                                        });
                                      }

                                      _restartAutoHide();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 6),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(pos),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _fmt(dur),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
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
