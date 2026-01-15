class MoussaHlsQuality {
  final String label;
  final String url; // لينك m3u8

  const MoussaHlsQuality({
    required this.label,
    required this.url,
  });
}

class MoussaPlaybackState {
  final bool isPlaying;
  final bool isBuffering; // ✅ جديد
  final int positionMs;
  final int durationMs;
  final int bufferedToMs; // ✅ جديد (اختياري لكن مفيد جدًا)
  final double volume;
  final String? currentQuality;

  const MoussaPlaybackState({
    required this.isPlaying,
    required this.isBuffering,
    required this.positionMs,
    required this.durationMs,
    required this.bufferedToMs,
    required this.volume,
    required this.currentQuality,
  });

  MoussaPlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    int? positionMs,
    int? durationMs,
    int? bufferedToMs,
    double? volume,
    String? currentQuality,
  }) {
    return MoussaPlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      bufferedToMs: bufferedToMs ?? this.bufferedToMs,
      volume: volume ?? this.volume,
      currentQuality: currentQuality ?? this.currentQuality,
    );
  }
}
