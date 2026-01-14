import Flutter
import UIKit
import AVFoundation

final class MoussaHlsNativeView: NSObject, FlutterPlatformView {
  private let container: UIView = UIView()
  private let player = AVPlayer()
  private let playerLayer: AVPlayerLayer

  private var channel: FlutterMethodChannel

  private var qualityUrls: [String: String] = [:]
  private var currentQuality: String? = nil

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
    self.playerLayer = AVPlayerLayer(player: player)
    self.channel = FlutterMethodChannel(
      name: "com.moussait.moussa_hls_player/methods/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.frame = frame
    container.backgroundColor = .black

    playerLayer.frame = container.bounds
    playerLayer.videoGravity = .resizeAspect
    container.layer.addSublayer(playerLayer)

    channel.setMethodCallHandler(handle)
  }

  func view() -> UIView {
    return container
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    case "setSource":
      guard
        let args = call.arguments as? [String: Any],
        let urls = args["qualityUrls"] as? [String: Any],
        let initialQuality = args["initialQuality"] as? String
      else {
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
        result(FlutterError(code: "bad_args", message: "label required", details: nil))
        return
      }

      guard let url = qualityUrls[label] else {
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

  private func setMediaUrl(_ urlString: String, seekMs: Int, play: Bool) {
    guard let url = URL(string: urlString) else { return }
    let item = AVPlayerItem(url: url)
    player.replaceCurrentItem(with: item)

    if seekMs > 0 {
      let sec = Double(seekMs) / 1000.0
      player.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
    }

    if play { player.play() }
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
    player.pause()
    player.replaceCurrentItem(with: nil)
  }
}
