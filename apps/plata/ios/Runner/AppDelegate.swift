import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Con clave puesta, Plata se tapa al dejar de estar activa (vista de apps
  /// recientes, centro de control). Lo fija Dart por el canal de privacidad y
  /// se recuerda entre arranques para tapar también antes de que cargue Flutter.
  private static let secureKey = "plata.secure"
  private static let coverTag = 0x504C_4154
  private var privacyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeDataFromBackup()
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(sceneWillDeactivate(_:)), name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(self, selector: #selector(sceneDidActivate(_:)), name: UIScene.didActivateNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "co.appsgratis.plata/privacy", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "setSecure" {
        UserDefaults.standard.set((call.arguments as? Bool) ?? false, forKey: AppDelegate.secureKey)
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    privacyChannel = channel
  }

  /// Pone una cubierta lisa sobre las ventanas de la escena: la captura que iOS
  /// guarda para la vista de apps recientes no muestra saldos ni movimientos.
  @objc private func sceneWillDeactivate(_ note: Notification) {
    guard UserDefaults.standard.bool(forKey: AppDelegate.secureKey), let scene = note.object as? UIWindowScene else {
      return
    }
    for window in scene.windows where window.viewWithTag(AppDelegate.coverTag) == nil {
      let cover = UIView(frame: window.bounds)
      cover.tag = AppDelegate.coverTag
      cover.backgroundColor = .systemBackground
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
      lock.tintColor = .secondaryLabel
      lock.contentMode = .scaleAspectFit
      lock.translatesAutoresizingMaskIntoConstraints = false
      cover.addSubview(lock)
      NSLayoutConstraint.activate([
        lock.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
        lock.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
        lock.widthAnchor.constraint(equalToConstant: 44),
        lock.heightAnchor.constraint(equalToConstant: 44),
      ])
      window.addSubview(cover)
    }
  }

  @objc private func sceneDidActivate(_ note: Notification) {
    guard let scene = note.object as? UIWindowScene else {
      return
    }
    for window in scene.windows {
      window.viewWithTag(AppDelegate.coverTag)?.removeFromSuperview()
    }
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
