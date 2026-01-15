package com.moussait.moussa_hls_player

import android.content.Context
import android.net.Uri
import android.view.View
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
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

  // ✅ EventChannel per viewId
  private val eventChannel: EventChannel =
    EventChannel(messenger, "moussa_hls_player/event_$viewId")

  private var eventSink: EventChannel.EventSink? = null

  // الجودة -> لينك
  private var qualityUrls: MutableMap<String, String> = mutableMapOf()
  private var currentQuality: String? = null

  init {
    playerView.player = player
    playerView.useController = false // Flutter هتعمل UI فوقه
    channel.setMethodCallHandler(this)

    // ✅ Stream handler
    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
      }

      override fun onCancel(arguments: Any?) {
        eventSink = null
      }
    })

    // ✅ Player error listener
    player.addListener(object : Player.Listener {
      override fun onPlayerError(error: PlaybackException) {
        sendError(
          code = mapExoErrorCode(error),
          message = error.message ?: "ExoPlayer error",
          details = mapOf(
            "exoErrorCode" to error.errorCode,
            "cause" to (error.cause?.toString() ?: ""),
            "name" to error.javaClass.simpleName
          )
        )
      }

      override fun onPlaybackStateChanged(playbackState: Int) {
        // (اختياري) تقدر تبعت events buffering/ready لو حبيت بعدين
      }
    })
  }

  override fun getView(): View = playerView

  override fun dispose() {
    try {
      channel.setMethodCallHandler(null)
    } catch (_: Exception) {}

    try {
      eventChannel.setStreamHandler(null)
    } catch (_: Exception) {}

    eventSink = null
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
          sendError(
            code = 1001,
            message = "bad_args: qualityUrls and initialQuality are required",
            details = mapOf("method" to "setSource")
          )
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
          sendError(
            code = 1002,
            message = "bad_quality: initialQuality not found in qualityUrls",
            details = mapOf("initialQuality" to initialQuality)
          )
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
          sendError(
            code = 1003,
            message = "bad_args: positionMs required",
            details = mapOf("method" to "seekTo")
          )
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
          sendError(
            code = 1004,
            message = "bad_args: label required",
            details = mapOf("method" to "setQuality")
          )
          result.error("bad_args", "label required", null)
          return
        }

        val url = qualityUrls[label]
        if (url.isNullOrEmpty()) {
          sendError(
            code = 1005,
            message = "bad_quality: quality label not found",
            details = mapOf("label" to label)
          )
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
          sendError(
            code = 1006,
            message = "bad_args: volume required",
            details = mapOf("method" to "setVolume")
          )
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
    try {
      val mediaItem = MediaItem.fromUri(Uri.parse(url))
      player.setMediaItem(mediaItem)
      player.prepare()
      if (seekMs > 0) player.seekTo(seekMs)
      player.playWhenReady = playWhenReady
      if (playWhenReady) player.play()
    } catch (e: Exception) {
      sendError(
        code = 1999,
        message = "setMediaUrl failed: ${e.message}",
        details = mapOf("url" to url, "exception" to e.toString())
      )
    }
  }

  private fun sendError(code: Int, message: String, details: Map<String, Any?> = emptyMap()) {
    eventSink?.success(
      mapOf(
        "type" to "error",
        "platform" to "android",
        "code" to code,
        "message" to message,
        "details" to details
      )
    )
  }

  private fun mapExoErrorCode(e: PlaybackException): Int {
    return when (e.errorCode) {
      PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS -> 1101
      PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> 1102
      PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED -> 1103
      PlaybackException.ERROR_CODE_IO_NO_PERMISSION -> 1104
      PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED -> 1105
      PlaybackException.ERROR_CODE_DECODING_FAILED -> 1106
      else -> 1199
    }
  }
}
