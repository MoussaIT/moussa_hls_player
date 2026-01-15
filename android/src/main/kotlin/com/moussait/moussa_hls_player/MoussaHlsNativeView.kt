package com.moussait.moussa_hls_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
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

  // ticker for position updates (500ms)
  private val mainHandler = Handler(Looper.getMainLooper())
  private var positionRunnable: Runnable? = null
  private var lastSentPositionMs: Long = -1L
  private var lastSentDurationMs: Long = -1L

  // track last known state
  private var lastPlaybackState: Int = Player.STATE_IDLE
  private var lastIsPlaying: Boolean = false

  init {
    playerView.player = player
    playerView.useController = false // Flutter UI فوقه
    channel.setMethodCallHandler(this)

    // ✅ Stream handler
    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sendEvent("stream_ready", emptyMap())
        startPositionTickerIfNeeded()
        sendSnapshot()
      }

      override fun onCancel(arguments: Any?) {
        eventSink = null
        stopPositionTicker()
      }
    })

    // ✅ Player listener: errors + state + end
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

      override fun onIsPlayingChanged(isPlaying: Boolean) {
        lastIsPlaying = isPlaying
        if (isPlaying) {
          sendEvent("playing", mapOf("by" to "state"))
        } else {
          sendEvent("paused", mapOf("by" to "state"))
        }
      }

      override fun onPlaybackStateChanged(playbackState: Int) {
        lastPlaybackState = playbackState

        when (playbackState) {
          Player.STATE_BUFFERING -> {
            sendEvent("buffering", mapOf("reason" to "state_buffering"))
          }

          Player.STATE_READY -> {
            sendEvent("ready", mapOf("durationMs" to getDurationMs()))
            sendDurationIfChanged()
          }

          Player.STATE_ENDED -> {
            sendEvent(
              "ended",
              mapOf(
                "positionMs" to getPositionMs(),
                "durationMs" to getDurationMs()
              )
            )
          }

          else -> {}
        }
      }
    })
  }

  override fun getView(): View = playerView

  override fun dispose() {
    try { channel.setMethodCallHandler(null) } catch (_: Exception) {}
    try { eventChannel.setStreamHandler(null) } catch (_: Exception) {}

    stopPositionTicker()

    eventSink?.endOfStream()
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
            code = 2001,
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
            code = 2002,
            message = "bad_quality: initialQuality not found",
            details = mapOf("initialQuality" to initialQuality)
          )
          result.error("bad_quality", "initialQuality not found", null)
          return
        }

        currentQuality = initialQuality
        setMediaUrl(initialUrl, seekMs = 0L, playWhenReady = autoPlay)

        sendEvent(
          "source_set",
          mapOf(
            "url" to initialUrl,
            "label" to (currentQuality ?: ""),
            "autoPlay" to autoPlay
          )
        )

        startPositionTickerIfNeeded()
        result.success(null)
      }

      "play" -> {
        player.playWhenReady = true
        player.play()
        sendEvent("playing", mapOf("by" to "method"))
        result.success(null)
      }

      "pause" -> {
        player.pause()
        sendEvent("paused", mapOf("by" to "method"))
        result.success(null)
      }

      "seekTo" -> {
        val argsMap = call.arguments as? Map<*, *>
        val pos = (argsMap?.get("positionMs") as? Number)?.toLong()
        if (pos == null) {
          sendError(
            code = 2003,
            message = "bad_args: positionMs required",
            details = mapOf("method" to "seekTo")
          )
          result.error("bad_args", "positionMs required", null)
          return
        }

        player.seekTo(pos)
        sendEvent("seeked", mapOf("positionMs" to pos))
        result.success(null)
      }

      "setQuality" -> {
        val argsMap = call.arguments as? Map<*, *>
        val label = argsMap?.get("label")?.toString()

        if (label.isNullOrEmpty()) {
          sendError(
            code = 2004,
            message = "bad_args: label required",
            details = mapOf("method" to "setQuality")
          )
          result.error("bad_args", "label required", null)
          return
        }

        val url = qualityUrls[label]
        if (url.isNullOrEmpty()) {
          sendError(
            code = 2005,
            message = "bad_quality: quality label not found",
            details = mapOf("label" to label)
          )
          result.error("bad_quality", "quality label not found", null)
          return
        }

        val wasPlaying = player.isPlaying
        val currentPos = getPositionMs().coerceAtLeast(0L)
        val currentVol = player.volume

        currentQuality = label
        setMediaUrl(url, seekMs = currentPos, playWhenReady = wasPlaying)

        player.volume = currentVol

        sendEvent(
          "quality_changed",
          mapOf(
            "label" to label,
            "positionMs" to currentPos
          )
        )

        result.success(null)
      }

      "setVolume" -> {
        val argsMap = call.arguments as? Map<*, *>
        val vol = (argsMap?.get("volume") as? Number)?.toFloat()
        if (vol == null) {
          sendError(
            code = 2006,
            message = "bad_args: volume required",
            details = mapOf("method" to "setVolume")
          )
          result.error("bad_args", "volume required", null)
          return
        }
        val v = vol.coerceIn(0f, 1f)
        player.volume = v
        sendEvent("volume_changed", mapOf("volume" to v.toDouble()))
        result.success(null)
      }

      "getPosition" -> result.success(getPositionMs())
      "getDuration" -> result.success(getDurationMs())
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

      lastSentPositionMs = -1L
      lastSentDurationMs = -1L

      if (seekMs > 0) player.seekTo(seekMs)
      player.playWhenReady = playWhenReady
      if (playWhenReady) player.play()

      sendSnapshot()
    } catch (e: Exception) {
      sendError(
        code = 2999,
        message = "setMediaUrl failed: ${e.message}",
        details = mapOf("url" to url, "exception" to e.toString())
      )
    }
  }

  private fun sendEvent(type: String, data: Map<String, Any?>) {
    val sink = eventSink ?: return
    val payload = HashMap<String, Any?>()
    payload["type"] = type
    payload["platform"] = "android"
    payload["ts"] = System.currentTimeMillis()
    for ((k, v) in data) payload[k] = v
    sink.success(payload)
  }

  private fun sendSnapshot() {
    sendEvent(
      "snapshot",
      mapOf(
        "positionMs" to getPositionMs(),
        "durationMs" to getDurationMs(),
        "isPlaying" to player.isPlaying,
        "label" to (currentQuality ?: ""),
        "volume" to player.volume.toDouble()
      )
    )
  }

  private fun sendDurationIfChanged() {
    val d = getDurationMs()
    if (d > 0 && d != lastSentDurationMs) {
      lastSentDurationMs = d
      sendEvent("duration", mapOf("durationMs" to d))
    }
  }

  private fun startPositionTickerIfNeeded() {
    if (eventSink == null) return
    if (positionRunnable != null) return

    val runnable = object : Runnable {
      override fun run() {
        if (eventSink == null) {
          stopPositionTicker()
          return
        }

        sendDurationIfChanged()

        val pos = getPositionMs()
        if (pos != lastSentPositionMs) {
          lastSentPositionMs = pos
          sendEvent("position", mapOf("positionMs" to pos))
        }

        val buffered = player.bufferedPosition.coerceAtLeast(0L)
        sendEvent("buffer_update", mapOf("bufferedToMs" to buffered))

        mainHandler.postDelayed(this, 500L)
      }
    }

    positionRunnable = runnable
    mainHandler.postDelayed(runnable, 200L)
  }

  private fun stopPositionTicker() {
    val r = positionRunnable ?: return
    mainHandler.removeCallbacks(r)
    positionRunnable = null
  }

  private fun sendError(code: Int, message: String, details: Map<String, Any?> = emptyMap()) {
    val sink = eventSink ?: return
    sink.success(
      mapOf(
        "type" to "error",
        "platform" to "android",
        "code" to code,
        "message" to message,
        "details" to details,
        "ts" to System.currentTimeMillis()
      )
    )
  }

  private fun getPositionMs(): Long {
    val p = player.currentPosition
    return if (p < 0) 0L else p
  }

  private fun getDurationMs(): Long {
    val d = player.duration
    return if (d == Player.TIME_UNSET) 0L else d
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

private fun EventChannel.EventSink.endOfStream() {
  try { success(null) } catch (_: Exception) {}
}
