import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'moussa_hls_player_controller.dart';
import 'moussa_hls_player_types.dart';
import 'moussa_hls_fullscreen_page.dart';

typedef MoussaHlsPlayerCreatedCallback =
    void Function(MoussaHlsPlayerController controller);

class MoussaHlsPlayerView extends StatefulWidget {
  const MoussaHlsPlayerView({
    super.key,
    required this.onCreated,
    this.unsupportedBuilder,
    this.child,
    this.showErrorOverlay = true,
    this.showBufferingOverlay = true,
    this.showControls = true,
    this.controlsAutoHide = const Duration(seconds: 3),
  });

  final MoussaHlsPlayerCreatedCallback onCreated;
  final WidgetBuilder? unsupportedBuilder;

  final bool showErrorOverlay;
  final bool showBufferingOverlay;

  /// Optional extra overlay from user
  final Widget? child;

  /// ✅ Built-in controls
  final bool showControls;
  final Duration controlsAutoHide;

  @override
  State<MoussaHlsPlayerView> createState() => _MoussaHlsPlayerViewState();
}

class _MoussaHlsPlayerViewState extends State<MoussaHlsPlayerView> {
  MoussaHlsPlayerController? _controller;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _isFullscreen = false;

  @override
void dispose() {
  _hideTimer?.cancel();

  final c = _controller;
  if (c != null) {
    c.pause(); // ✅ وقف التشغيل
    // لو عندك stop() استخدمها بدل pause
  }

  _controller?.dispose();
  super.dispose();
}

  void _onPlatformCreated(int id) async {
    final c = MoussaHlsPlayerController.fromViewId(id);
    _controller = c;

    c.attachToView();
    widget.onCreated(c);

    await c.refreshState();
    _kickAutoHide();

    if (mounted) setState(() {});
  }

  void _toggleControls() {
    if (!widget.showControls) return;
    setState(() => _controlsVisible = !_controlsVisible);
    _kickAutoHide();
  }

  void _kickAutoHide() {
    _hideTimer?.cancel();
    if (!widget.showControls) return;
    if (!_controlsVisible) return;

    _hideTimer = Timer(widget.controlsAutoHide, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    // ✅ True fullscreen: push a dedicated fullscreen route.
    // This works even if the inline player isn't filling the screen.
    final src = _controller;
    if (src == null) return;
    if (_isFullscreen) return;

    _isFullscreen = true;
    if (mounted) setState(() {});

    final wasPlaying = src.state.value.isPlaying;

    // avoid double audio: pause inline before opening fullscreen
    await src.pause();

    final result = await Navigator.of(context).push<MoussaFullscreenResult>(
      MaterialPageRoute(
        builder: (_) => MoussaHlsFullscreenPage(sourceController: src),
        fullscreenDialog: true,
      ),
    );

    // back from fullscreen
    _isFullscreen = false;
    if (mounted) setState(() {});

    if (result != null) {
      // best-effort sync back
      if (result.volume >= 0 && result.volume <= 1) {
        await src.setVolume(result.volume);
      }
      if (result.quality != null && result.quality!.trim().isNotEmpty) {
        final q = result.quality!.trim();
        if (src.qualities.any((e) => e.label == q)) {
          await src.setQuality(q);
        }
      }

      // seek back to last position
      if (result.positionMs > 0) {
        await src.seekToMs(result.positionMs);
      }

      // resume if fullscreen was playing OR inline was playing before entry
      if (result.wasPlaying || wasPlaying) {
        await src.play();
      }
    } else {
      // user dismissed without result -> just resume if needed
      if (wasPlaying) await src.play();
    }

    await src.refreshState();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _unsupported(context);

    const viewType = 'moussa_hls_player/native_view';

    Widget platformView;
    if (defaultTargetPlatform == TargetPlatform.android) {
      platformView = AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformCreated,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platformView = UiKitView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformCreated,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      platformView = _unsupported(context);
    }

    final c = _controller;

    // no overlays at all
    if (!widget.showErrorOverlay &&
        !widget.showBufferingOverlay &&
        !widget.showControls &&
        widget.child == null) {
      return platformView;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        platformView,
    
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
          ),
        ),
    
        if (widget.child != null) widget.child!,
    
        // ✅ Buffering overlay
        if (c != null && widget.showBufferingOverlay)
          ValueListenableBuilder(
            valueListenable: c.state,
            builder: (context, s, _) {
              if (!s.isBuffering) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              );
            },
          ),
    
        // ✅ Controls overlay
        if (c != null && widget.showControls)
          ValueListenableBuilder(
            valueListenable: c.state,
            builder: (context, s, _) {
              return AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _ControlsOverlay(
                    controller: c,
                    state: s,
                    onInteracted: _kickAutoHide,
                    onToggleFullscreen: _toggleFullscreen,
                    isFullscreen: _isFullscreen,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _unsupported(BuildContext context) {
    if (widget.unsupportedBuilder != null)
      return widget.unsupportedBuilder!(context);
    return Container(
      alignment: Alignment.center,
      color: Colors.black12,
      child: const Text(
        'Moussa HLS Player is not supported on this platform',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.controller,
    required this.state,
    required this.onInteracted,
    required this.onToggleFullscreen,
    required this.isFullscreen,
  });

  final MoussaHlsPlayerController controller;
  final MoussaPlaybackState state;

  final VoidCallback onInteracted;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;

  String _fmt(int ms) {
    final s = (ms / 1000).floor();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0)
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = state.durationMs <= 0 ? 1 : state.durationMs;
    final pos = state.positionMs.clamp(0, duration);
    final buffered = state.bufferedToMs.clamp(0, duration);

    final bufferedFrac = buffered / duration;
    final posFrac = pos / duration;

    final isMuted = controller.isMuted;

    return Container(
      color: Colors.black26,
      child: Column(
        children: [
          // Top bar
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Quality
                  _QualityButton(
                    controller: controller,
                    onInteracted: onInteracted,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      onInteracted();
                      controller.toggleMute();
                    },
                    icon: Icon(
                      isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      onInteracted();
                      onToggleFullscreen();
                    },
                    icon: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Center play/pause
          Center(
            child: InkWell(
              onTap: () async {
                onInteracted();
                if (state.isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
              },
              borderRadius: BorderRadius.circular(48),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),

          const Spacer(),

          // Bottom bar (progress)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                children: [
                  // buffered bar + slider overlay
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // buffered line
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: bufferedFrac.isNaN ? 0 : bufferedFrac,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white54,
                          ),
                        ),
                      ),
                      // slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: posFrac.isNaN ? 0 : posFrac,
                          onChangeStart: (_) => onInteracted(),
                          onChanged: (_) => onInteracted(),
                          onChangeEnd: (v) async {
                            onInteracted();
                            final targetMs = (v * duration).round();
                            await controller.seekToMs(targetMs);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _fmt(pos),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _fmt(state.durationMs),
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
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.controller, required this.onInteracted});
  final MoussaHlsPlayerController controller;
  final VoidCallback onInteracted;

  @override
  Widget build(BuildContext context) {
    final qs = controller.qualities;

    return PopupMenuButton<MoussaHlsQuality>(
      tooltip: 'Quality',
      onOpened: onInteracted,
      onSelected: (q) async {
        onInteracted();
        await controller.setQuality(q.label);
      },
      itemBuilder: (context) {
        return qs.map((q) {
          return PopupMenuItem<MoussaHlsQuality>(
            value: q,
            child: Text(q.label),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hd, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              (controller.state.value.currentQuality ?? 'Auto'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
