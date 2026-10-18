import AudioToolbox
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Canal de la vibración del temporizador (se guarda mientras viva la app).
  private var vibracion: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Los toques en los recordatorios y sus botones (Hecho, Posponer) llegan a
    // la app, y los avisos también se muestran mientras está abierta.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Vibración del temporizador: la del sistema, que respeta el ajuste de
    // vibración del iPhone (la respuesta táctil de Flutter es un toque breve
    // que no se siente si se apagó en Configuración).
    let canal = FlutterMethodChannel(name: "rutinas/vibracion", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    canal.setMethodCallHandler { call, result in
      if call.method == "vibrar" {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    vibracion = canal
  }
}
