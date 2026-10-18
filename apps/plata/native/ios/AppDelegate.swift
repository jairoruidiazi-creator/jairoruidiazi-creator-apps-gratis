import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Los datos de Plata van cifrados con una llave que vive solo en el Llavero
  /// de este iPhone y no viaja en las copias de iCloud. Si la carpeta entrara en
  /// la copia, en un iPhone nuevo llegarían datos que no se pueden abrir; por eso
  /// queda fuera, y el traslado se hace con la copia cifrada con contraseña.
  private func excludeDataFromBackup() {
    let fm = FileManager.default
    guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }
    var dir = support.appendingPathComponent("plata", isDirectory: true)
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try dir.setResourceValues(values)
    } catch {
      NSLog("Plata: no se pudo excluir la carpeta de datos de la copia de iCloud: \(error)")
    }
  }
}
