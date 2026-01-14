class MoussaHlsQuality {
  final String label;
  final String url;   // لينك m3u8

  const MoussaHlsQuality({
    required this.label,
    required this.url,
  });
}

class MoussaPlaybackState {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final double volume;
  final String? currentQuality;

  const MoussaPlaybackState({
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.volume,
    required this.currentQuality,
  });

  MoussaPlaybackState copyWith({
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    double? volume,
    String? currentQuality,
  }) {
    return MoussaPlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      currentQuality: currentQuality ?? this.currentQuality,
    );
  }
}
