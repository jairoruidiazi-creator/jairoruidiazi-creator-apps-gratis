import '../core/settings.dart';
import 'heading.dart';
import 'location_service.dart';
import 'wmm.dart';

/// De dónde sale la declinación que se aplica al rumbo.
enum DeclinationSource {
  /// Modelo WMM2025 con la posición del GPS de esta sesión.
  wmm,

  /// Valor fijado a mano en Ajustes.
  manual,

  /// Modo automático sin posición todavía: el rumbo queda magnético.
  unknown,
}

/// Mantiene la declinación de la brújula al día: automática con el modelo
/// WMM a partir de la posición GPS, o el valor manual de los ajustes. Sin
/// posición en modo automático no inventa un valor: el rumbo se marca
/// magnético hasta que haya GPS.
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
  DeclinationSource _source = DeclinationSource.unknown;

  /// Última declinación calculada automáticamente (grados), si la hay.
  double? get automatic => _auto;

  /// Verdadero si la fecha quedó fuera de la vigencia del modelo WMM.
  bool get extrapolated => _extrapolated;

  DeclinationSource get source => _source;

  void apply() {
    heading.systemTrueNorth = settings.autoDeclination;
    if (!settings.autoDeclination) {
      _source = DeclinationSource.manual;
      heading.setDeclination(settings.declination, known: true);
      return;
    }
    final Fix? f = location.fix;
    if (f != null) {
      // Se recalcula solo si nos movimos más de ~1 km (la declinación cambia
      // muy despacio con la posición).
      if (_lat == null || (f.latitude - _lat!).abs() > 0.01 || (f.longitude - _lon!).abs() > 0.01) {
        final MagneticField m = Wmm.compute(f.latitude, f.longitude, altitudeMeters: f.altitudeEllipsoid ?? 0);
        _auto = m.declination;
        _extrapolated = m.extrapolated;
        _lat = f.latitude;
        _lon = f.longitude;
        settings.lastAutoDeclination = m.declination;
      }
    }
    if (_auto != null) {
      _source = DeclinationSource.wmm;
      heading.setDeclination(_auto!, known: true);
    } else {
      _source = DeclinationSource.unknown;
      heading.setDeclination(0, known: false);
    }
  }

  void dispose() {
    settings.removeListener(apply);
    location.removeListener(apply);
  }
}
