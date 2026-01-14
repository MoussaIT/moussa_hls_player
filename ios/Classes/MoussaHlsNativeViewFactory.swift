import Flutter
import UIKit

final class MoussaHlsNativeViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return MoussaHlsNativeView(frame: frame, viewId: viewId, messenger: messenger, args: args)
  }
}
