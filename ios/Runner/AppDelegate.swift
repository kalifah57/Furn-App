import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Owns the RoomPlan plugin for the app's lifetime. Without this reference the
  /// plugin — and the channel it holds — would deallocate at the end of
  /// `didFinishLaunchingWithOptions`, and `startRoomScan` would never answer.
  /// Typed `Any?` because the plugin is gated on iOS 16.
  private var roomScanPlugin: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      // RoomPlan is iOS 16+. On anything older the channel is simply never
      // registered, so Dart gets MissingPluginException and reports the device
      // as unsupported — which is exactly the desired behaviour.
      if #available(iOS 16.0, *) {
        roomScanPlugin = RoomScanPlugin.register(
          with: controller.binaryMessenger,
          host: controller
        )
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
