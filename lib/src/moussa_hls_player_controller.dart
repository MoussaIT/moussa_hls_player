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
      isBuffering: false,
      positionMs: 0,
      durationMs: 0,
      bufferedToMs: 0,
      volume: 1.0,
      currentQuality: null,
    ),
  );

  final ValueNotifier<MoussaPlayerError?> error = ValueNotifier(null);

  final StreamController<Map<String, dynamic>> _eventsCtrl =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get events => _eventsCtrl.stream;

  // Keep qualities for UI
  List<MoussaHlsQuality> _qualities = const [];
  List<MoussaHlsQuality> get qualities => _qualities;

  // mute helpers
  double _lastNonZeroVolume = 1.0;
  bool get isMuted => state.value.volume <= 0.0001;

  static MoussaHlsPlayerController fromViewId(int viewId) {
    return MoussaHlsPlayerController._(viewId);
  }

  void attachToView() {
    if (_disposed || !_isSupportedPlatform) return;

    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) return;
        if (event is! Map) return;

        final e = Map<String, dynamic>.from(event);
        _eventsCtrl.add(e);

        final type = (e['type'] ?? '').toString();

        if (type == 'error') {
          error.value = MoussaPlayerError.fromMap(e);
          return;
        }

        _handleStateEvent(type, e);
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

  void _handleStateEvent(String type, Map<String, dynamic> e) {
    final s = state.value;

    int? pos;
    int? dur;
    int? buf;
    double? vol;
    String? quality;
    bool? isPlaying;
    bool? isBuffering;

    if (e.containsKey('positionMs')) pos = _toInt(e['positionMs']);
    if (e.containsKey('durationMs')) dur = _toInt(e['durationMs']);
    if (e.containsKey('bufferedToMs')) buf = _toInt(e['bufferedToMs']);

    if (e.containsKey('volume')) vol = _toDouble(e['volume']);

    // We accept both "quality" & "label" & "currentQuality"
    if (e.containsKey('quality')) quality = (e['quality'] ?? '').toString();
    if (e.containsKey('currentQuality')) quality = (e['currentQuality'] ?? '').toString();
    if (e.containsKey('label')) quality = (e['label'] ?? '').toString();

    switch (type) {
      case 'snapshot':
        isPlaying = _toBool(e['isPlaying']);
        // snapshot may include bufferedToMs on android; ok
        break;

      case 'playing':
        isPlaying = true;
        isBuffering = false;
        break;

      case 'paused':
        isPlaying = false;
        break;

      case 'buffering':
        isBuffering = true;
        break;

      case 'ready':
        // often means buffering ended
        isBuffering = false;
        break;

      case 'buffer_update':
        // keep best-effort: doesn't mean buffering true/false
        break;

      case 'ended':
        isPlaying = false;
        isBuffering = false;
        break;

      case 'quality_changed':
        // ensure reflect label
        quality = (e['label'] ?? quality)?.toString();
        break;

      default:
        break;
    }

    final next = s.copyWith(
      isPlaying: isPlaying ?? s.isPlaying,
      isBuffering: isBuffering ?? s.isBuffering,
      positionMs: pos ?? s.positionMs,
      durationMs: dur ?? s.durationMs,
      bufferedToMs: buf ?? s.bufferedToMs,
      volume: vol ?? s.volume,
      currentQuality: (quality != null && quality.trim().isEmpty)
          ? s.currentQuality
          : (quality ?? s.currentQuality),
    );

    if (!_disposed) {
      // track last non-zero vol
      if (next.volume > 0.0001) _lastNonZeroVolume = next.volume;
      state.value = next;
    }
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return null;
  }

  void clearError() => error.value = null;

  Future<T?> _safeInvoke<T>(String method, [dynamic args]) async {
    if (_disposed) return null;
    if (!_isSupportedPlatform) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSource({
    required List<MoussaHlsQuality> qualities,
    required String initialQuality,
    bool autoPlay = true,
  }) async {
    if (_disposed || !_isSupportedPlatform) return;

    _qualities = List<MoussaHlsQuality>.from(qualities);

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

  /// Seek relative to current position (delta in milliseconds).
  /// Example: -5000 for back 5s, +5000 for forward 5s.
  Future<void> seekByMs(int deltaMs) async =>
      _safeInvoke<void>('seekBy', {'deltaMs': deltaMs});

  /// Set playback speed (e.g. 0.5, 1.0, 1.25, 1.5, 2.0).
  /// Native clamps to a safe range.
  Future<void> setPlaybackSpeed(double speed) async =>
      _safeInvoke<void>('setPlaybackSpeed', {'speed': speed});

  /// Enable/disable pinch-to-zoom (typically enable in fullscreen only).
  Future<void> setZoomEnabled(bool enabled) async =>
      // Native method name is `enableZoom`.
      _safeInvoke<void>('enableZoom', {'enabled': enabled});

  /// Set maximum zoom factor (default is 4.0 on native).
  Future<void> setMaxZoom(double maxZoom) async =>
      // Native expects key `max`.
      _safeInvoke<void>('setMaxZoom', {'max': maxZoom});

  /// Reset zoom back to 1.0.
  Future<void> resetZoom() async => _safeInvoke<void>('resetZoom');

  Future<void> setQuality(String label) async =>
      _safeInvoke<void>('setQuality', {'label': label});

  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final v = volume.clamp(0.0, 1.0);
    await _safeInvoke<void>('setVolume', {'volume': v});
    if (!_disposed) {
      if (v > 0.0001) _lastNonZeroVolume = v;
      state.value = state.value.copyWith(volume: v);
    }
  }

  Future<void> toggleMute() async {
    if (_disposed) return;
    if (isMuted) {
      final v = (_lastNonZeroVolume <= 0.0001) ? 1.0 : _lastNonZeroVolume;
      await setVolume(v);
    } else {
      await setVolume(0.0);
    }
  }

  // Optional fallback manual refresh
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

    await _eventSub?.cancel();
    _eventSub = null;

    await _safeInvoke<void>('dispose');

    try {
      await _eventsCtrl.close();
    } catch (_) {}

    try {
      state.dispose();
    } catch (_) {}

    try {
      error.dispose();
    } catch (_) {}
  }
}
