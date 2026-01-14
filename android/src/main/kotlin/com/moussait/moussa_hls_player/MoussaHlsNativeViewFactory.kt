package com.moussait.moussa_hls_player

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

class MoussaHlsNativeViewFactory(
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    return MoussaHlsNativeView(appContext, messenger, viewId, args)
  }
}
