import Flutter
import UIKit
import native_geofence

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
      // Used by plugin: native_geofence — a geofence event can launch the app
      // in the background without a UI scene, so register plugins here too.
      NativeGeofencePlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
