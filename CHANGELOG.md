## [0.1.0] - 2026-01-14

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

---