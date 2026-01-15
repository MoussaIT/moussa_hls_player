class MoussaHlsChannel {
  static const String base = 'com.moussait.moussa_hls_player/methods';
  static String forView(int viewId) => '$base/$viewId';

  // ✅ event channel name helper
  static String eventsForView(int viewId) => 'moussa_hls_player/event_$viewId';
}