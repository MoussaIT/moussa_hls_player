import Flutter
import UIKit
import AVFoundation

final class MoussaHlsNativeView: NSObject, FlutterPlatformView, FlutterStreamHandler {
  private let container: UIView = UIView()
  private let player = AVPlayer()
  private let playerLayer: AVPlayerLayer

  private var channel: FlutterMethodChannel

  // ✅ EventChannel per viewId
  private var eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var qualityUrls: [String: String] = [:]
  private var currentQuality: String? = nil

  private var statusObs: NSKeyValueObservation?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
    self.playerLayer = AVPlayerLayer(player: player)

    self.channel = FlutterMethodChannel(
      name: "com.moussait.moussa_hls_player/methods/\(viewId)",
      binaryMessenger: messenger
    )

    self.eventChannel = FlutterEventChannel(
      name: "moussa_hls_player/event_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    container.frame = frame
    container.backgroundColor = .black

    playerLayer.frame = container.bounds
    playerLayer.videoGravity = .resizeAspect
    container.layer.addSublayer(playerLayer)

    channel.setMethodCallHandler(handle)

    // ✅ stream handler
    eventChannel.setStreamHandler(self)
  }

  func view() -> UIView {
    return container
  }

  // ✅ keep layer in sync (important on iOS PlatformView resizing)
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    playerLayer.frame = container.bounds
  }

  // MARK: - Stream handler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
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
      player.play()
      result(nil)

    case "pause":
      player.pause()
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
      player.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
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

  // MARK: - Player setup + observers
  private func setMediaUrl(_ urlString: String, seekMs: Int, play: Bool) {
    guard let url = URL(string: urlString) else {
      sendError(code: 2990, message: "Invalid URL", details: ["url": urlString])
      return
    }

    let item = AVPlayerItem(url: url)

    // ✅ attach observers for errors
    attachObservers(item: item)

    player.replaceCurrentItem(with: item)

    if seekMs > 0 {
      let sec = Double(seekMs) / 1000.0
      player.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
    }

    if play { player.play() }
  }

  private func attachObservers(item: AVPlayerItem) {
    // remove old
    statusObs?.invalidate()
    NotificationCenter.default.removeObserver(self)

    statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      if item.status == .failed {
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
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerFailedToEnd(_:)),
      name: .AVPlayerItemFailedToPlayToEndTime,
      object: item
    )
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

  private func sendError(code: Int, message: String, details: [String: Any] = [:]) {
    eventSink?([
      "type": "error",
      "platform": "ios",
      "code": code,
      "message": message,
      "details": details
    ])
  }

  private func mapIosError(nsCode: Int) -> Int {
    // common AV errors
    switch nsCode {
    case -11828: return 1201 // Cannot Decode
    case -11850: return 1202 // Playback Failed
    case -1100:  return 1203 // File not found
    case -1009:  return 1204 // No internet
    default:     return 1299
    }
  }

  // MARK: - Helpers
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
    NotificationCenter.default.removeObserver(self)

    eventSink = nil
    eventChannel.setStreamHandler(nil)

    player.pause()
    player.replaceCurrentItem(with: nil)
  }
}
