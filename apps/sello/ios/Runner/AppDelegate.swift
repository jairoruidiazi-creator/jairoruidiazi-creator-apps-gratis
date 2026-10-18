import CoreLocation
import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SelloHeading") {
      SelloHeading.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SelloFiles") {
      SelloFiles.register(with: registrar)
    }
  }
}

/// Espacio libre para la copia completa (canal co.appsgratis.sello/files).
/// En iPhone la copia se ofrece con la hoja de compartir y se restaura con el
/// selector de archivos, que ya trabajan en disco: aquí solo hace falta saber
/// cuánto espacio queda.
enum SelloFiles {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "co.appsgratis.sello/files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "freeBytes":
        result(SelloFiles.freeBytes())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func freeBytes() -> NSNumber? {
    guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let capacity = values.volumeAvailableCapacityForImportantUsage
    else {
      return nil
    }
    return NSNumber(value: capacity)
  }
}

/// Rumbo de la cámara en iPhone para Sello (canal co.appsgratis.sello/heading).
///
/// El magnetómetro crudo de iOS trae el sesgo del propio teléfono; aquí se usa
/// lo que ya calibra el sistema:
/// - CMDeviceMotion con el marco "X al norte magnético, Z vertical": fusiona
///   el giroscopio con el magnetómetro calibrado y da la orientación completa,
///   de donde salen el rumbo del eje de la cámara trasera (que CLHeading no da
///   con el teléfono vertical: el suyo es el del borde superior) y el del
///   borde superior.
/// - CLLocationManager: la precisión del rumbo (headingAccuracy) y el norte
///   verdadero; trueHeading − magneticHeading es la declinación del sistema.
///   trueHeading solo vale si este mismo administrador recibe la posición.
///
/// Cada evento es un mapa: "camera" y "top" (grados, magnéticos), y si los hay
/// "declination" (grados, este positivo), "accuracy" (grados) y "calibration"
/// (-1 sin calibrar, 0 baja, 1 media, 2 alta).
final class SelloHeading: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private static var instance: SelloHeading?

  private let motion = CMMotionManager()
  private let location = CLLocationManager()
  private var sink: FlutterEventSink?
  private var declination: Double?
  private var accuracy: Double?
  private var lastSent: TimeInterval = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let handler = SelloHeading()
    let channel = FlutterEventChannel(name: "co.appsgratis.sello/heading", binaryMessenger: registrar.messenger())
    channel.setStreamHandler(handler)
    instance = handler
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard motion.isDeviceMotionAvailable,
      CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
    else {
      return FlutterError(code: "unavailable", message: "Este equipo no tiene brújula", details: nil)
    }
    sink = events
    declination = nil
    accuracy = nil
    location.delegate = self
    location.headingFilter = kCLHeadingFilterNone
    location.desiredAccuracy = kCLLocationAccuracyKilometer
    if CLLocationManager.headingAvailable() {
      location.startUpdatingHeading()
    }
    if isAuthorized() {
      location.startUpdatingLocation()
    }
    motion.deviceMotionUpdateInterval = 1.0 / 30.0
    motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue.main) { [weak self] data, _ in
      if let self = self, let data = data {
        self.send(data)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    location.stopUpdatingHeading()
    location.stopUpdatingLocation()
    sink = nil
    return nil
  }

  private func isAuthorized() -> Bool {
    let status = location.authorizationStatus
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private func send(_ data: CMDeviceMotion) {
    guard let sink = sink else {
      return
    }
    // Hasta 20 eventos por segundo.
    if data.timestamp - lastSent < 0.05 {
      return
    }
    lastSent = data.timestamp
    // Las filas de la matriz son los ejes del teléfono en el marco de
    // referencia (X = norte magnético, Y = oeste, Z = arriba); el rumbo de un
    // eje es atan2(este, norte), con este = −Y.
    let r = data.attitude.rotationMatrix
    let camera = SelloHeading.degrees(atan2(r.m32, -r.m31))  // eje −Z: cámara trasera
    let top = SelloHeading.degrees(atan2(-r.m22, r.m21))  // eje +Y: borde superior
    var event: [String: Any] = [
      "camera": camera,
      "top": top,
      "calibration": Int(data.magneticField.accuracy.rawValue),
    ]
    if let d = declination {
      event["declination"] = d
    }
    if let a = accuracy {
      event["accuracy"] = a
    }
    sink(event)
  }

  private static func degrees(_ radians: Double) -> Double {
    let d = radians * 180.0 / Double.pi
    return d < 0 ? d + 360.0 : d
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if sink != nil && isAuthorized() {
      manager.startUpdatingLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    accuracy = newHeading.headingAccuracy >= 0 ? newHeading.headingAccuracy : nil
    if newHeading.trueHeading >= 0 && newHeading.headingAccuracy >= 0 {
      var d = newHeading.trueHeading - newHeading.magneticHeading
      if d > 180 {
        d -= 360
      } else if d < -180 {
        d += 360
      }
      declination = d
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

  // El aviso de calibración de iOS taparía la cámara; la hoja del GPS ya
  // explica cómo calibrar cuando el rumbo es poco preciso.
  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    return false
  }
}
