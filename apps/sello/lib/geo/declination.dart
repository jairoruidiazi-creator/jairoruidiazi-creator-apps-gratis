import '../core/settings.dart';
import 'heading.dart';
import 'location_service.dart';
import 'wmm.dart';

/// Mantiene la declinación de la brújula al día: automática con el modelo
/// WMM a partir de la posición GPS, o el valor manual de los ajustes.
class DeclinationLink {
  DeclinationLink({required this.settings, required this.location, required this.heading}) {
    settings.addListener(apply);
    location.addListener(apply);
    apply();
  }

  final AppSettings settings;
  final LocationService location;
  final HeadingService heading;

  double? _lat;
  double? _lon;
  double? _auto;
  bool _extrapolated = false;

  /// Última declinación calculada automáticamente (grados), si la hay.
  double? get automatic => _auto;

  /// Verdadero si la fecha quedó fuera de la vigencia del modelo WMM.
  bool get extrapolated => _extrapolated;

  void apply() {
    final Fix? f = location.fix;
    if (settings.autoDeclination && f != null) {
      // Se recalcula solo si nos movimos más de ~1 km (la declinación cambia
      // muy despacio con la posición).
      if (_lat == null || (f.latitude - _lat!).abs() > 0.01 || (f.longitude - _lon!).abs() > 0.01) {
        final MagneticField m = Wmm.compute(f.latitude, f.longitude, altitudeMeters: f.altitude.isFinite ? f.altitude : 0);
        _auto = m.declination;
        _extrapolated = m.extrapolated;
        _lat = f.latitude;
        _lon = f.longitude;
        settings.lastAutoDeclination = m.declination;
      }
      heading.declination = _auto ?? settings.declination;
    } else {
      heading.declination = settings.declination;
    }
  }

  void dispose() {
    settings.removeListener(apply);
    location.removeListener(apply);
  }
}
