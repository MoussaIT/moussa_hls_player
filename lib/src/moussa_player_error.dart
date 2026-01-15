class MoussaPlayerError {
  final int code;
  final String platform; // "android" | "ios"
  final String message;
  final Map<String, dynamic> details;

  MoussaPlayerError({
    required this.code,
    required this.platform,
    required this.message,
    required this.details,
  });

  factory MoussaPlayerError.fromMap(Map<dynamic, dynamic> m) {
    return MoussaPlayerError(
      code: (m['code'] ?? -1) is int ? m['code'] : int.tryParse('${m['code']}') ?? -1,
      platform: (m['platform'] ?? '').toString(),
      message: (m['message'] ?? '').toString(),
      details: Map<String, dynamic>.from((m['details'] ?? {}) as Map),
    );
  }
}
