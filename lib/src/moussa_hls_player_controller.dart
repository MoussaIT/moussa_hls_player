import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../moussa_hls_player_method_channel.dart';
import 'moussa_hls_player_types.dart';
import 'moussa_player_error.dart';

class MoussaHlsPlayerController {
  MoussaHlsPlayerController._(this._viewId);

  final int _viewId;

  late final MethodChannel _channel = MethodChannel(
    MoussaHlsChannel.forView(_viewId),
  );

  // ✅ EventChannel per viewId
  late final EventChannel _eventChannel = EventChannel(
    MoussaHlsChannel.eventsForView(_viewId),
  );

  StreamSubscription? _eventSub;

  bool _disposed = false;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final ValueNotifier<MoussaPlaybackState> state =
      ValueNotifier<MoussaPlaybackState>(
    const MoussaPlaybackState(
      isPlaying: false,
      positionMs: 0,
      durationMs: 0,
      volume: 1.0,
      currentQuality: null,
    ),
  );

  final ValueNotifier<MoussaPlayerError?> error = ValueNotifier(null);

  static MoussaHlsPlayerController fromViewId(int viewId) {
    return MoussaHlsPlayerController._(viewId);
  }

  /// ✅ attach once after platform view created
  void attachToView() {
    if (_disposed || !_isSupportedPlatform) return;

    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        // event expected: {type:'error', code:int, platform:'ios|android', message:'..', details:{...}}
        if (event is Map) {
          final type = (event['type'] ?? '').toString();
          if (type == 'error') {
            error.value = MoussaPlayerError.fromMap(event);
          }
        }
      },
      onError: (e) {
        error.value = MoussaPlayerError(
          code: -2,
          platform: 'flutter',
          message: 'EventChannel error: $e',
          details: const {},
        );
      },
    );
  }

  void clearError() => error.value = null;

  Future<T?> _safeInvoke<T>(String method, [dynamic args]) async {
    if (_disposed) return null;
    if (!_isSupportedPlatform) return null;

    try {
      final res = await _channel.invokeMethod<T>(method, args);
      return res;
    } catch (_) {
      return null;
    }
  }

  // ✅ Named Parameters عشان الـ example بيستخدم qualities
  Future<void> setSource({
    required List<MoussaHlsQuality> qualities,
    required String initialQuality,
    bool autoPlay = true,
  }) async {
    if (_disposed || !_isSupportedPlatform) return;

    final qualityUrls = <String, String>{
      for (final q in qualities) q.label: q.url,
    };

    await _safeInvoke<void>('setSource', {
      'qualityUrls': qualityUrls,
      'initialQuality': initialQuality,
      'autoPlay': autoPlay,
    });
  }

  Future<void> play() async => _safeInvoke<void>('play');
  Future<void> pause() async => _safeInvoke<void>('pause');

  Future<void> seekToMs(int positionMs) async =>
      _safeInvoke<void>('seekTo', {'positionMs': positionMs});

  Future<void> setQuality(String label) async =>
      _safeInvoke<void>('setQuality', {'label': label});

  Future<void> setVolume(double volume) async {
    if (_disposed) return;

    final v = volume.clamp(0.0, 1.0);
    await _safeInvoke<void>('setVolume', {'volume': v});

    if (!_disposed) {
      state.value = state.value.copyWith(volume: v);
    }
  }

  Future<int> getPositionMs() async =>
      (await _safeInvoke<num>('getPosition'))?.toInt() ?? 0;

  Future<int> getDurationMs() async =>
      (await _safeInvoke<num>('getDuration'))?.toInt() ?? 0;

  Future<bool> getIsPlaying() async =>
      (await _safeInvoke<bool>('isPlaying')) ?? false;

  Future<String?> getCurrentQuality() async =>
      await _safeInvoke<String>('getCurrentQuality');

  Future<double> getVolume() async =>
      (await _safeInvoke<num>('getVolume'))?.toDouble() ?? 1.0;

  Future<void> refreshState() async {
    if (_disposed || !_isSupportedPlatform) return;

    final results = await Future.wait([
      getIsPlaying(),
      getPositionMs(),
      getDurationMs(),
      getVolume(),
      getCurrentQuality(),
    ]);

    if (_disposed) return;

    state.value = state.value.copyWith(
      isPlaying: results[0] as bool,
      positionMs: results[1] as int,
      durationMs: results[2] as int,
      volume: results[3] as double,
      currentQuality: results[4] as String?,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // stop listening events
    await _eventSub?.cancel();
    _eventSub = null;

    await _safeInvoke<void>('dispose');

    try {
      state.dispose();
    } catch (_) {}

    try {
      error.dispose();
    } catch (_) {}
  }
}
