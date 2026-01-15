import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'moussa_hls_player_controller.dart';

typedef MoussaHlsPlayerCreatedCallback = void Function(
  MoussaHlsPlayerController controller,
);

class MoussaHlsPlayerView extends StatefulWidget {
  const MoussaHlsPlayerView({
    super.key,
    required this.onCreated,
    this.unsupportedBuilder,
    this.showErrorOverlay = true,
    this.showBufferingOverlay = true, // ✅ جديد
  });

  final MoussaHlsPlayerCreatedCallback onCreated;
  final WidgetBuilder? unsupportedBuilder;

  /// ✅ Show native error overlay if player reports errors
  final bool showErrorOverlay;

  /// ✅ Show buffering overlay (uses controller.state.isBuffering)
  final bool showBufferingOverlay;

  @override
  State<MoussaHlsPlayerView> createState() => _MoussaHlsPlayerViewState();
}

class _MoussaHlsPlayerViewState extends State<MoussaHlsPlayerView> {
  MoussaHlsPlayerController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onPlatformCreated(int id) async {
    final c = MoussaHlsPlayerController.fromViewId(id);
    _controller = c;

    // ✅ start receiving events (state/error/buffering/progress)
    c.attachToView();

    widget.onCreated(c);

    // ✅ optional: one manual refresh at start (nice fallback)
    await c.refreshState();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Web: don't try PlatformViews
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

    // If no overlays at all, return raw platform view
    if (!widget.showErrorOverlay && !widget.showBufferingOverlay) {
      return platformView;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        platformView,

        // ✅ Buffering overlay (spinner)
        if (_controller != null && widget.showBufferingOverlay)
          ValueListenableBuilder(
            valueListenable: _controller!.state,
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
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

        // ✅ Error overlay
        if (_controller != null && widget.showErrorOverlay)
          ValueListenableBuilder(
            valueListenable: _controller!.error,
            builder: (context, err, _) {
              if (err == null) return const SizedBox.shrink();

              return Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Video Error (${err.platform})\nCode: ${err.code}\n${err.message}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              _controller!.clearError();
                              await _controller!.play();
                            },
                            child: const Text('Retry'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              _controller!.clearError();
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _unsupported(BuildContext context) {
    if (widget.unsupportedBuilder != null) {
      return widget.unsupportedBuilder!(context);
    }
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
