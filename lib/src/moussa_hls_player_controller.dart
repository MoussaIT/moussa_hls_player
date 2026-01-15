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
      isBuffering: false,
      positionMs: 0,
      durationMs: 0,
      bufferedToMs: 0,
      volume: 1.0,
      currentQuality: null,
    ),
  );

  final ValueNotifier<MoussaPlayerError?> error = ValueNotifier(null);

  // optional: expose raw events (useful for UI later)
  final StreamController<Map<String, dynamic>> _eventsCtrl =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsCtrl.stream;

  static MoussaHlsPlayerController fromViewId(int viewId) {
    return MoussaHlsPlayerController._(viewId);
  }

  /// ✅ attach once after platform view created
  void attachToView() {
    if (_disposed || !_isSupportedPlatform) return;

    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) return;
        if (event is! Map) return;

        final e = Map<String, dynamic>.from(event as Map);
        _eventsCtrl.add(e);

        final type = (e['type'] ?? '').toString();

        // ✅ Errors
        if (type == 'error') {
          error.value = MoussaPlayerError.fromMap(e);
          _applyStatePatch(isPlaying: false, isBuffering: false);
          return;
        }

        // ✅ Update state from native events
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
    // We always read common fields if present
    int? pos = e.containsKey('positionMs') ? _toInt(e['positionMs']) : null;
    int? dur = e.containsKey('durationMs') ? _toInt(e['durationMs']) : null;
    int? bufferedTo =
        e.containsKey('bufferedToMs') ? _toInt(e['bufferedToMs']) : null;

    double? vol = e.containsKey('volume') ? _toDouble(e['volume']) : null;

    // ✅ unified: quality label should come as "label"
    String? label;
    if (e.containsKey('label')) {
      final v = e['label'];
      label = v == null ? null : v.toString();
    }

    // backward-compat (لو لسه في أي مكان قديم)
    if (label == null && e.containsKey('quality')) {
      final v = e['quality'];
      label = v == null ? null : v.toString();
    }
    if (label == null && e.containsKey('currentQuality')) {
      final v = e['currentQuality'];
      label = v == null ? null : v.toString();
    }

    bool? isPlaying;
    bool? isBuffering;

    switch (type) {
      case 'stream_ready':
        // no state change required
        break;

      case 'snapshot':
        // snapshot: {positionMs,durationMs,isPlaying,label,volume, bufferedToMs?}
        isPlaying = _toBool(e['isPlaying']);
        break;

      case 'source_set':
        // source_set: {url,label,autoPlay}
        break;

      case 'buffering':
        // buffering: {reason}
        isBuffering = true;
        break;

      case 'buffer_update':
        // buffer_update: {bufferedToMs}
        break;

      case 'ready':
        // ready: {durationMs}
        isBuffering = false;
        break;

      case 'duration':
        // durationMs comes
        break;

      case 'position':
        // positionMs comes
        break;

      case 'playing':
        isPlaying = true;
        isBuffering = false;
        break;

      case 'paused':
        isPlaying = false;
        isBuffering = false;
        break;

      case 'seeked':
        pos = _toInt(e['positionMs']) ?? pos;
        break;

      case 'quality_changed':
        // quality_changed: {label, positionMs}
        label = (e['label'] ?? label)?.toString();
        break;

      case 'volume_changed':
        // volume comes
        break;

      case 'ended':
        isPlaying = false;
        isBuffering = false;
        break;

      default:
        // ignore unknown types
        break;
    }

    _applyStatePatch(
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      positionMs: pos,
      durationMs: dur,
      bufferedToMs: bufferedTo,
      volume: vol,
      currentQuality: label,
    );
  }

  void _applyStatePatch({
    bool? isPlaying,
    bool? isBuffering,
    int? positionMs,
    int? durationMs,
    int? bufferedToMs,
    double? volume,
    String? currentQuality,
  }) {
    if (_disposed) return;

    final s = state.value;
    final next = s.copyWith(
      isPlaying: isPlaying ?? s.isPlaying,
      isBuffering: isBuffering ?? s.isBuffering,
      positionMs: positionMs ?? s.positionMs,
      durationMs: durationMs ?? s.durationMs,
      bufferedToMs: bufferedToMs ?? s.bufferedToMs,
      volume: volume ?? s.volume,
      currentQuality: currentQuality ?? s.currentQuality,
    );

    state.value = next;
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
      final res = await _channel.invokeMethod<T>(method, args);
      return res;
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

    final qualityUrls = <String, String>{
      for (final q in qualities) q.label: q.url,
    };

    await _safeInvoke<void>('setSource', {
      'qualityUrls': qualityUrls,
      'initialQuality': initialQuality,
      'autoPlay': autoPlay,
    });

    // UI responsiveness: optimistically set currentQuality 
    _applyStatePatch(currentQuality: initialQuality);
  }

  Future<void> play() async => _safeInvoke<void>('play');
  Future<void> pause() async => _safeInvoke<void>('pause');

  Future<void> seekToMs(int positionMs) async =>
      _safeInvoke<void>('seekTo', {'positionMs': positionMs});

  Future<void> setQuality(String label) async {
    if (_disposed) return;

    await _safeInvoke<void>('setQuality', {'label': label});
    // Optimistic
    _applyStatePatch(currentQuality: label);
  }

  Future<void> setVolume(double volume) async {
    if (_disposed) return;

    final v = volume.clamp(0.0, 1.0);
    await _safeInvoke<void>('setVolume', {'volume': v});

    // state will also be updated by event (volume_changed),
    // but keep UI responsive immediately
    _applyStatePatch(volume: v);
  }

  // ✅ fallback manual refresh (optional)
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

    _applyStatePatch(
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
