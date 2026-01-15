class MoussaPlayerError {
  final int code;
  final String platform; // "android" | "ios"
  final String message;
  final Map<String, dynamic> details;

  /// optional: timestamp (ms)
  final int? timestamp;

  MoussaPlayerError({
    required this.code,
    required this.platform,
    required this.message,
    required this.details,
    this.timestamp,
  });

  factory MoussaPlayerError.fromMap(Map<dynamic, dynamic> m) {
    return MoussaPlayerError(
      code: (m['code'] ?? -1) is int
          ? m['code']
          : int.tryParse('${m['code']}') ?? -1,
      platform: (m['platform'] ?? '').toString(),
      message: (m['message'] ?? '').toString(),
      details: Map<String, dynamic>.from((m['details'] ?? {}) as Map),
      timestamp: m['ts'] is int ? m['ts'] as int : null,
    );
  }

  /// Network-related error?
  bool get isNetworkError =>
      code == 1103 || // android: network failed
      code == 1204;   // ios: no internet

  /// Fatal error? (usually no retry without new source)
  bool get isFatal =>
      code == 1106 || // decoding failed
      code == 1201 || // cannot decode
      code == 1202;   // playback failed
}
