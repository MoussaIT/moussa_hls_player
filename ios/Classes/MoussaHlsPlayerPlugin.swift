import Flutter
import UIKit

public class MoussaHlsPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = MoussaHlsNativeViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "moussa_hls_player/native_view")
  }
}
