package com.moussait.moussa_hls_player

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding

class MoussaHlsPlayerPlugin : FlutterPlugin {

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    binding
      .platformViewRegistry
      .registerViewFactory(
        "moussa_hls_player/native_view",
        MoussaHlsNativeViewFactory(binding.binaryMessenger, binding.applicationContext)
      )
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    // nothing
  }
}
