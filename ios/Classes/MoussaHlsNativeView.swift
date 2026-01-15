import Flutter
import UIKit
import AVFoundation

// ✅ Container UIView that keeps AVPlayerLayer in sync with resizing
final class MoussaHlsContainerView: UIView {
  let playerLayer: AVPlayerLayer

  init(frame: CGRect, player: AVPlayer) {
    self.playerLayer = AVPlayerLayer(player: player)
    super.init(frame: frame)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
    layer.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer.frame = bounds
  }
}

final class MoussaHlsNativeView: NSObject, FlutterPlatformView, FlutterStreamHandler {

  private let player = AVPlayer()
  private let container: MoussaHlsContainerView

  private var channel: FlutterMethodChannel

  // ✅ EventChannel per viewId
  private var eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var qualityUrls: [String: String] = [:]
  private var currentQuality: String? = nil

  private var statusObs: NSKeyValueObservation?
  private var timeControlObs: NSKeyValueObservation?
  private var loadedRangesObs: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?

  private var positionTimer: DispatchSourceTimer?
  private var lastSentPositionMs: Int64 = -1
  private var lastSentDurationMs: Int64 = -1

  // ✅ Audio session guard (avoid re-applying too often)
  private var audioSessionConfigured: Bool = false

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {

    self.channel = FlutterMethodChannel(
      name: "com.moussait.moussa_hls_player/methods/\(viewId)",
      binaryMessenger: messenger
    )

    self.eventChannel = FlutterEventChannel(
      name: "moussa_hls_player/event_\(viewId)",
      binaryMessenger: messenger
    )

    self.container = MoussaHlsContainerView(frame: frame, player: player)

    super.init()

    channel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)

    // Observe global player state (playing/buffering/paused)
    attachPlayerStateObservers()
  }

  func view() -> UIView {
    return container
  }

  // MARK: - Stream handler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    sendEvent(type: "stream_ready", data: [:])

    startPositionTimerIfNeeded()
    sendPlaybackSnapshot()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    stopPositionTimer()
    return nil
  }

  // MARK: - Method channel
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    case "setSource":
      guard
        let args = call.arguments as? [String: Any],
        let urls = args["qualityUrls"] as? [String: Any],
        let initialQuality = args["initialQuality"] as? String
      else {
        sendError(code: 2001, message: "bad_args: qualityUrls and initialQuality are required", details: ["method": "setSource"])
        result(FlutterError(code: "bad_args", message: "qualityUrls and initialQuality are required", details: nil))
        return
      }

      let autoPlay = (args["autoPlay"] as? Bool) ?? true

      qualityUrls.removeAll()
      for (k, v) in urls {
        if let url = v as? String {
          qualityUrls[k] = url
        }
      }

      guard let initialUrl = qualityUrls[initialQuality] else {
        sendError(code: 2002, message: "bad_quality: initialQuality not found", details: ["initialQuality": initialQuality])
        result(FlutterError(code: "bad_quality", message: "initialQuality not found", details: nil))
        return
      }

      currentQuality = initialQuality
      setMediaUrl(initialUrl, seekMs: 0, play: autoPlay)
      result(nil)

    case "play":
      configureAudioSessionIfNeeded()
      player.isMuted = false
      player.play()
      sendEvent(type: "playing", data: ["by": "method"])
      result(nil)

    case "pause":
      player.pause()
      sendEvent(type: "paused", data: ["by": "method"])
      result(nil)

    case "seekTo":
      guard
        let args = call.arguments as? [String: Any],
        let positionMs = args["positionMs"] as? NSNumber
      else {
        sendError(code: 2003, message: "bad_args: positionMs required", details: ["method": "seekTo"])
        result(FlutterError(code: "bad_args", message: "positionMs required", details: nil))
        return
      }

      let sec = positionMs.doubleValue / 1000.0
      player.seek(to: CMTime(seconds: sec, preferredTimescale: 600)) { [weak self] _ in
        self?.sendEvent(type: "seeked", data: ["positionMs": positionMs.int64Value])
      }
      result(nil)

    case "setQuality":
      guard
        let args = call.arguments as? [String: Any],
        let label = args["label"] as? String
      else {
        sendError(code: 2004, message: "bad_args: label required", details: ["method": "setQuality"])
        result(FlutterError(code: "bad_args", message: "label required", details: nil))
        return
      }

      guard let url = qualityUrls[label] else {
        sendError(code: 2005, message: "bad_quality: quality label not found", details: ["label": label])
        result(FlutterError(code: "bad_quality", message: "quality label not found", details: nil))
        return
      }

      let wasPlaying = isPlaying()
      let posMs = Int(getPositionMs())
      let vol = player.volume

      currentQuality = label
      setMediaUrl(url, seekMs: posMs, play: wasPlaying)

      player.volume = vol
      sendEvent(type: "quality_changed", data: [
  "label": label,
  "quality": label,
  "positionMs": posMs
])
      result(nil)

    case "setVolume":
      guard
        let args = call.arguments as? [String: Any],
        let volume = args["volume"] as? NSNumber
      else {
        sendError(code: 2006, message: "bad_args: volume required", details: ["method": "setVolume"])
        result(FlutterError(code: "bad_args", message: "volume required", details: nil))
        return
      }

      let v = max(0.0, min(1.0, volume.floatValue))
      player.volume = v
      player.isMuted = false
      sendEvent(type: "volume_changed", data: ["volume": Double(v)])
      result(nil)

    case "getPosition":
      result(getPositionMs())

    case "getDuration":
      result(getDurationMs())

    case "isPlaying":
      result(isPlaying())

    case "getCurrentQuality":
      result(currentQuality)

    case "getVolume":
      result(Double(player.volume))

    case "dispose":
      disposeNative()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureAudioSessionForPlayback() {
  do {
    let session = AVAudioSession.sharedInstance()

    // Playback => الصوت يطلع حتى لو الجهاز Silent
    if #available(iOS 10.0, *) {
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
    } else {
      try session.setCategory(.playback, options: [])
    }

    try session.setActive(true)
  } catch {
    sendError(
      code: 1298,
      message: "AudioSession error: \(error.localizedDescription)",
      details: [:]
    )
  }
}


  // MARK: - Audio Session
  private func configureAudioSessionIfNeeded() {
    if audioSessionConfigured { return }
    audioSessionConfigured = true

    let session = AVAudioSession.sharedInstance()
    do {
      // ✅ playback => audio works even if device is on silent
      // ✅ allowBluetooth => airpods / bluetooth
      // ✅ defaultToSpeaker => if route needs speaker by default
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetooth, .defaultToSpeaker])
      try session.setActive(true)
    } catch {
      // don't crash; just emit debug event
      sendEvent(type: "audio_session_error", data: [
        "message": error.localizedDescription
      ])
    }
  }

private func setMediaUrl(_ urlString: String, seekMs: Int, play: Bool) {
  guard let url = URL(string: urlString) else {
    sendError(code: 2990, message: "Invalid URL", details: ["url": urlString])
    return
  }

  // ✅ مهم للصوت
  configureAudioSessionIfNeeded()
  player.isMuted = false

  let item = AVPlayerItem(url: url)
  attachItemObservers(item: item)
  player.replaceCurrentItem(with: item)

  lastSentPositionMs = -1
  lastSentDurationMs = -1

  if seekMs > 0 {
    let sec = Double(seekMs) / 1000.0
    player.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
  }

  if play { player.play() }

  // ✅ ابعت الاتنين عشان التوافق
  sendEvent(type: "source_set", data: [
    "url": urlString,
    "label": currentQuality ?? "",
    "quality": currentQuality ?? "",
    "autoPlay": play
  ])

  startPositionTimerIfNeeded()
}


  private func attachItemObservers(item: AVPlayerItem) {
    statusObs?.invalidate()
    loadedRangesObs?.invalidate()
    NotificationCenter.default.removeObserver(self)
    if let endObserver = endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }

    statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      switch item.status {
      case .readyToPlay:
        self.sendEvent(type: "ready", data: [
          "durationMs": self.getDurationMs()
        ])
        self.sendDurationIfChanged()
      case .failed:
        let nsErr = item.error as NSError?
        let nsCode = nsErr?.code ?? -1
        let domain = nsErr?.domain ?? ""
        let msg = nsErr?.localizedDescription ?? "AVPlayerItem failed"

        let mapped = self.mapIosError(nsCode: nsCode)
        self.sendError(
          code: mapped,
          message: msg,
          details: [
            "nsCode": nsCode,
            "domain": domain,
            "reason": nsErr?.localizedFailureReason ?? ""
          ]
        )
      default:
        break
      }
    }

    loadedRangesObs = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return }
      let start = CMTimeGetSeconds(range.start)
      let dur = CMTimeGetSeconds(range.duration)
      if start.isNaN || dur.isNaN { return }
      let bufferedTo = (start + dur) * 1000.0
      self.sendEvent(type: "buffer_update", data: [
        "bufferedToMs": Int64(bufferedTo)
      ])
    }

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      self.sendEvent(type: "ended", data: [
        "positionMs": self.getPositionMs(),
        "durationMs": self.getDurationMs()
      ])
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerFailedToEnd(_:)),
      name: .AVPlayerItemFailedToPlayToEndTime,
      object: item
    )
  }

  private func attachPlayerStateObservers() {
    if #available(iOS 10.0, *) {
      timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
        guard let self = self else { return }
        switch player.timeControlStatus {
        case .waitingToPlayAtSpecifiedRate:
          self.sendEvent(type: "buffering", data: ["reason": "waitingToPlay"])
        case .playing:
          self.sendEvent(type: "playing", data: ["by": "state"])
        case .paused:
          self.sendEvent(type: "paused", data: ["by": "state"])
        @unknown default:
          break
        }
      }
    }
  }

  @objc private func playerFailedToEnd(_ notification: Notification) {
    let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
    let nsCode = err?.code ?? -1
    let msg = err?.localizedDescription ?? "FailedToPlayToEndTime"

    sendError(
      code: mapIosError(nsCode: nsCode),
      message: msg,
      details: [
        "nsCode": nsCode,
        "domain": err?.domain ?? ""
      ]
    )
  }

  private func sendEvent(type: String, data: [String: Any]) {
    guard let sink = eventSink else { return }
    var payload: [String: Any] = [
      "type": type,
      "platform": "ios",
      "ts": Int64(Date().timeIntervalSince1970 * 1000.0)
    ]
    for (k, v) in data { payload[k] = v }
    sink(payload)
  }

  private func sendDurationIfChanged() {
    let d = getDurationMs()
    if d > 0 && d != lastSentDurationMs {
      lastSentDurationMs = d
      sendEvent(type: "duration", data: ["durationMs": d])
    }
  }

  private func sendPlaybackSnapshot() {
  sendEvent(type: "snapshot", data: [
    "positionMs": getPositionMs(),
    "durationMs": getDurationMs(),
    "isPlaying": isPlaying(),
    "label": currentQuality ?? "",
    "quality": currentQuality ?? "",
    "volume": Double(player.volume)
  ])
}

  private func startPositionTimerIfNeeded() {
    guard eventSink != nil else { return }
    if positionTimer != nil { return }

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(500))
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.sendDurationIfChanged()

      let pos = self.getPositionMs()
      if pos != self.lastSentPositionMs {
        self.lastSentPositionMs = pos
        self.sendEvent(type: "position", data: ["positionMs": pos])
      }
    }
    timer.resume()
    positionTimer = timer
  }

  private func stopPositionTimer() {
    positionTimer?.cancel()
    positionTimer = nil
  }

  private func sendError(code: Int, message: String, details: [String: Any] = [:]) {
    guard let sink = eventSink else { return }
    sink([
      "type": "error",
      "platform": "ios",
      "code": code,
      "message": message,
      "details": details,
      "ts": Int64(Date().timeIntervalSince1970 * 1000.0)
    ])
  }

  private func mapIosError(nsCode: Int) -> Int {
    switch nsCode {
    case -11828: return 1201
    case -11850: return 1202
    case -1100:  return 1203
    case -1009:  return 1204
    default:     return 1299
    }
  }

  private func getPositionMs() -> Int64 {
    let sec = CMTimeGetSeconds(player.currentTime())
    if sec.isNaN || sec.isInfinite { return 0 }
    return Int64(sec * 1000.0)
  }

  private func getDurationMs() -> Int64 {
    guard let item = player.currentItem else { return 0 }
    let sec = CMTimeGetSeconds(item.duration)
    if sec.isNaN || sec.isInfinite { return 0 }
    return Int64(sec * 1000.0)
  }

  private func isPlaying() -> Bool {
    if #available(iOS 10.0, *) {
      return player.timeControlStatus == .playing
    } else {
      return player.rate != 0
    }
  }

  private func disposeNative() {
    channel.setMethodCallHandler(nil)

    statusObs?.invalidate()
    statusObs = nil

    loadedRangesObs?.invalidate()
    loadedRangesObs = nil

    timeControlObs?.invalidate()
    timeControlObs = nil

    if let endObserver = endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    NotificationCenter.default.removeObserver(self)

    stopPositionTimer()

    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
    eventChannel.setStreamHandler(nil)

    player.pause()
    player.replaceCurrentItem(with: nil)
  }

  deinit {
    statusObs?.invalidate()
    loadedRangesObs?.invalidate()
    timeControlObs?.invalidate()
    if let endObserver = endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    NotificationCenter.default.removeObserver(self)
    stopPositionTimer()
    player.pause()
    player.replaceCurrentItem(with: nil)
  }
}
