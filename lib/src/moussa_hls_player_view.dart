import 'dart:async';
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
  });

  final MoussaHlsPlayerCreatedCallback onCreated;

  /// Optional: custom UI when platform isn't supported
  final WidgetBuilder? unsupportedBuilder;

  /// ✅ Show native error overlay if player reports errors
  final bool showErrorOverlay;

  @override
  State<MoussaHlsPlayerView> createState() => _MoussaHlsPlayerViewState();
}

class _MoussaHlsPlayerViewState extends State<MoussaHlsPlayerView> {
  MoussaHlsPlayerController? _controller;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startTicker(MoussaHlsPlayerController controller) {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      controller.refreshState();
    });
  }

  void _onPlatformCreated(int id) {
    final c = MoussaHlsPlayerController.fromViewId(id);
    _controller = c;

    // ✅ هنا مكان EventChannel attach (لازم تكون عاملها في controller)
    // هتبدأ تستقبل errors/events per viewId
    c.attachToView();

    widget.onCreated(c);
    _startTicker(c);
    setState(() {});
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

    // ✅ لو مش عايز Overlay خالص
    if (!widget.showErrorOverlay) return platformView;

    // ✅ Stack overlay لعرض error فوق الفيديو
    return Stack(
      fit: StackFit.expand,
      children: [
        platformView,

        // لو controller لسه null، مفيش overlay
        if (_controller != null)
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

                      // ✅ زر Retry اختياري (لو عامل clearError + play)
                      Wrap(
                        spacing: 10,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              // اختياري: لو عامل clearError في controller
                              _controller!.clearError();
                              // وممكن تحاول play تاني
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
