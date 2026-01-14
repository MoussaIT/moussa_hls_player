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
  });

  final MoussaHlsPlayerCreatedCallback onCreated;

  /// Optional: custom UI when platform isn't supported
  final WidgetBuilder? unsupportedBuilder;

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

  @override
  Widget build(BuildContext context) {
    // ✅ Web: don't try PlatformViews
    if (kIsWeb) return _unsupported(context);

    const viewType = 'moussa_hls_player/native_view';

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: (id) {
          final c = MoussaHlsPlayerController.fromViewId(id);
          _controller = c;
          widget.onCreated(c);
          _startTicker(c);
        },
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        onPlatformViewCreated: (id) {
          final c = MoussaHlsPlayerController.fromViewId(id);
          _controller = c;
          widget.onCreated(c);
          _startTicker(c);
        },
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // ✅ macOS / Windows / Linux (and others)
    return _unsupported(context);
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
