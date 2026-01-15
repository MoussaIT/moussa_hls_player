## [0.1.0]

### Added
- Native HLS video player for Flutter (Android & iOS).
- Android implementation based on ExoPlayer.
- iOS implementation based on AVPlayer.
- Support for multiple video qualities via separate HLS URLs.
- Runtime quality switching without recreating the player.
- Safe `MethodChannel` communication per viewId.
- `MoussaHlsPlayerController` with full playback controls:
  - play / pause
  - seek
  - volume
  - quality selection
  - playback state tracking
- Automatic state refresh with `ValueNotifier`.
- Platform guards to prevent crashes on unsupported platforms.
- Graceful fallback UI for Web, Windows, macOS, and Linux.

### Changed
- Adopted native platform views instead of WebView or iframe.
- Unified channel naming strategy across Flutter, Android, and iOS.

### Fixed
- Prevented crashes when calling player methods on unsupported platforms.
- Safe disposal of native resources and method channels.
- Handled missing or failed native responses without throwing exceptions.

### Notes
- Web and desktop platforms are not supported for playback (placeholder only).
- This release focuses on stability and production-ready native playback.


## [0.1.1]
### Added:

- EventChannel support per viewId for native player events.
- Native error reporting from Android (ExoPlayer) and iOS (AVPlayer) to Flutter.
- MoussaPlayerError model (code, platform, message, details).
- Error overlay UI inside MoussaHlsPlayerView with optional enable/disable.
- Retry and Dismiss actions for player errors.
- clearError() method in MoussaHlsPlayerController.

### Android:

- Added ExoPlayer Player.Listener to capture playback, network, decoding, and manifest errors.
- Mapped ExoPlayer PlaybackException error codes to stable plugin-level error codes.
- Errors are emitted through EventChannel without crashing the app.

### iOS:

- Added FlutterEventChannel integration per PlatformView.
- Added AVPlayerItem observers for playback failures.
- Handles AVPlayerItem.status == failed and AVPlayerItemFailedToPlayToEndTime.
- Mapped common AVFoundation errors (network, decode, file not found) to readable error codes.
- Improved observer and resource cleanup on dispose.

### Improved:

- Better lifecycle management for native views and channels.
- Clear separation between MethodChannel (commands) and EventChannel (events).
- Prevent silent black screen by surfacing native playback errors.
- Safer cleanup of native resources on dispose.

### Notes:

- No breaking API changes.
- Fully backward compatible with version 0.1.0.
- Recommended update for production usage.



## [0.1.2]

### 🚀 Added
- Unified **event-driven playback system** across Android & iOS
- Real-time playback events:
  - `playing`, `paused`, `buffering`, `ready`, `ended`
  - `position`, `duration`, `buffer_update`
  - `quality_changed`, `volume_changed`, `seeked`
- `MoussaPlaybackState` with:
  - `isPlaying`
  - `isBuffering`
  - `positionMs`
  - `durationMs`
  - `bufferedToMs`
  - `volume`
  - `currentQuality`
- Per-view `EventChannel` for multi-instance safety
- Normalized error model across platforms (`MoussaPlayerError`)
- Snapshot event on attach for immediate UI sync

### 🔧 Improved
- Native Android player:
  - Improved ExoPlayer state & error mapping
  - Accurate buffering and buffer progress reporting
- Native iOS player:
  - Improved AVPlayer observers for buffering, ready & end states
  - Accurate duration detection and buffer progress updates
- Manual quality switching keeps:
  - Playback position
  - Volume level
  - Playing / paused state
- Cleaner lifecycle handling (`dispose`) on both platforms
- Safer platform guards (Web / Desktop)

### 🧹 Removed
- Flutter-side polling timers
- Unreliable manual state refresh logic
- Implicit assumptions about UI or playback state

### 🐞 Fixed
- Inconsistent buffering state between Android & iOS
- Duration not updating correctly on first load
- Duplicate or stale playback events
- Potential crashes when disposing platform views