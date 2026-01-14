package com.moussait.moussa_hls_player

import android.content.Context
import android.net.Uri
import android.view.View
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class MoussaHlsNativeView(
  context: Context,
  messenger: BinaryMessenger,
  viewId: Int,
  args: Any?
) : PlatformView, MethodChannel.MethodCallHandler {

  private val playerView: PlayerView = PlayerView(context)
  private val player: ExoPlayer = ExoPlayer.Builder(context).build()

  private val channel: MethodChannel =
    MethodChannel(messenger, "com.moussait.moussa_hls_player/methods/$viewId")

  // الجودة -> لينك
  private var qualityUrls: MutableMap<String, String> = mutableMapOf()
  private var currentQuality: String? = null

  init {
    playerView.player = player
    playerView.useController = false // Flutter هتعمل UI فوقه
    channel.setMethodCallHandler(this)
  }

  override fun getView(): View = playerView

  override fun dispose() {
    try {
      channel.setMethodCallHandler(null)
    } catch (_: Exception) {}

    player.release()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {

      "setSource" -> {
        val argsMap = call.arguments as? Map<*, *>
        val urlsAny = argsMap?.get("qualityUrls") as? Map<*, *>
        val initialQuality = argsMap?.get("initialQuality") as? String
        val autoPlay = (argsMap?.get("autoPlay") as? Boolean) ?: true

        if (urlsAny == null || initialQuality.isNullOrEmpty()) {
          result.error("bad_args", "qualityUrls and initialQuality are required", null)
          return
        }

        qualityUrls.clear()
        for ((k, v) in urlsAny) {
          val label = k?.toString() ?: continue
          val url = v?.toString() ?: continue
          qualityUrls[label] = url
        }

        val initialUrl = qualityUrls[initialQuality]
        if (initialUrl.isNullOrEmpty()) {
          result.error("bad_quality", "initialQuality not found in qualityUrls", null)
          return
        }

        currentQuality = initialQuality
        setMediaUrl(initialUrl, seekMs = 0L, playWhenReady = autoPlay)
        result.success(null)
      }

      "play" -> {
        player.playWhenReady = true
        player.play()
        result.success(null)
      }

      "pause" -> {
        player.pause()
        result.success(null)
      }

      "seekTo" -> {
        val argsMap = call.arguments as? Map<*, *>
        val pos = (argsMap?.get("positionMs") as? Number)?.toLong()
        if (pos == null) {
          result.error("bad_args", "positionMs required", null)
          return
        }
        player.seekTo(pos)
        result.success(null)
      }

      "setQuality" -> {
        val argsMap = call.arguments as? Map<*, *>
        val label = argsMap?.get("label")?.toString()

        if (label.isNullOrEmpty()) {
          result.error("bad_args", "label required", null)
          return
        }

        val url = qualityUrls[label]
        if (url.isNullOrEmpty()) {
          result.error("bad_quality", "quality label not found", null)
          return
        }

        val wasPlaying = player.isPlaying
        val currentPos = player.currentPosition.coerceAtLeast(0L)
        val currentVol = player.volume

        currentQuality = label
        setMediaUrl(url, seekMs = currentPos, playWhenReady = wasPlaying)

        // حافظ على الصوت
        player.volume = currentVol

        result.success(null)
      }

      "setVolume" -> {
        val argsMap = call.arguments as? Map<*, *>
        val vol = (argsMap?.get("volume") as? Number)?.toFloat()
        if (vol == null) {
          result.error("bad_args", "volume required", null)
          return
        }
        val v = vol.coerceIn(0f, 1f)
        player.volume = v
        result.success(null)
      }

      "getPosition" -> result.success(player.currentPosition)

      "getDuration" -> {
        val d = player.duration
        result.success(if (d == Player.TIME_UNSET) 0L else d)
      }

      "isPlaying" -> result.success(player.isPlaying)

      "getCurrentQuality" -> result.success(currentQuality)

      "getVolume" -> result.success(player.volume.toDouble())

      "dispose" -> {
        dispose()
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  private fun setMediaUrl(url: String, seekMs: Long, playWhenReady: Boolean) {
    val mediaItem = MediaItem.fromUri(Uri.parse(url))
    player.setMediaItem(mediaItem)
    player.prepare()
    if (seekMs > 0) player.seekTo(seekMs)
    player.playWhenReady = playWhenReady
    if (playWhenReady) player.play()
  }
}
