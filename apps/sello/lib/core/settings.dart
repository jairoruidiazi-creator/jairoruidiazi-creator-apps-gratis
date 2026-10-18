import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;
import 'package:shared_preferences/shared_preferences.dart';

/// Idioma de la app para un idioma del teléfono: español para cualquier
/// variante de español; inglés para todo lo demás.
String appLanguageFor(Locale? device) => device?.languageCode.toLowerCase() == 'es' ? 'es' : 'en';

/// Preferencias del usuario.
class AppSettings extends ChangeNotifier {
  /// [deviceLocale] es el idioma del teléfono: manda mientras el usuario no
  /// elija otro en Ajustes. Sin él (pruebas), español.
  AppSettings({Locale? deviceLocale}) : _deviceLocale = deviceLocale;

  /// Con el idioma que tiene el teléfono ahora.
  factory AppSettings.forDevice() => AppSettings(deviceLocale: WidgetsBinding.instance.platformDispatcher.locale);

  Locale? _deviceLocale;

  /// Idioma del teléfono que se conoce (null en pruebas: español).
  Locale? get deviceLocale => _deviceLocale;
  SharedPreferences? _prefs;

  String _language = 'es';

  /// Verdadero si el usuario eligió el idioma en Ajustes; si no, se sigue el
  /// del teléfono y no se guarda (cambiar el del teléfono cambia el de la app).
  bool _languageChosen = false;

  String get language => _language;
  set language(String v) {
    _language = v;
    _languageChosen = true;
  }

  /// La app sigue el idioma del teléfono (nadie eligió otro en Ajustes).
  bool get followsDeviceLanguage => !_languageChosen;

  String get _deviceLanguage => _deviceLocale == null ? 'es' : appLanguageFor(_deviceLocale);

  /// «Idioma del teléfono» en Ajustes: deja de usar el elegido y vuelve a
  /// seguir al sistema (al guardar se borra la preferencia).
  void useDeviceLanguage() {
    _languageChosen = false;
    _language = _deviceLanguage;
  }

  /// El usuario cambió el idioma del teléfono con la app abierta
  /// (`didChangeLocales`): si la app lo sigue, cambia ya, sin reiniciarla.
  void deviceLocaleChanged(Locale? locale) {
    _deviceLocale = locale;
    if (_languageChosen) {
      return;
    }
    final String next = _deviceLanguage;
    if (next != _language) {
      _language = next;
      notifyListeners();
    }
  }

  /// Idioma del geocodificador (dirección aproximada), el mismo de la app.
  String get geocoderLocale => spanish ? 'es_CO' : 'en_US';
  String themeMode = 'system';
  // high | veryHigh | ultraHigh | max. Por defecto la máxima: todo el campo
  // del sensor (4:3), sin el recorte del 16:9 (ver docs/DECISIONES.md).
  String resolution = 'max';
  int jpegQuality = 92;
  bool keepOriginal = true;
  bool saveToGallery = true;
  bool silentShutter = false;
  bool grid = true;
  bool level = false;
  int timerSeconds = 0;
  bool redFilter = false;
  bool geocoding = true;

  /// Fondo del mapa con teselas de OpenStreetMap (necesita internet).
  bool mapTiles = true;
  double declination = 0;
  bool autoDeclination = true;

  /// Última declinación calculada por el modelo WMM (solo informativa).
  double lastAutoDeclination = 0;
  bool keepAwake = true;
  String currentProjectId = '';
  bool showAccuracyWarning = true;
  bool hapticShutter = true;
  String altitudeReference = 'msl'; // msl | ellipsoid

  bool get spanish => language == 'es';

  /// Avisa a la interfaz sin escribir en disco (para deslizadores).
  void refresh() => notifyListeners();

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _prefs = p;
    final String? saved = p.getString('language');
    _languageChosen = saved != null;
    _language = saved ?? _deviceLanguage;
    themeMode = p.getString('themeMode') ?? 'system';
    resolution = p.getString('resolution') ?? 'max';
    jpegQuality = p.getInt('jpegQuality') ?? 92;
    keepOriginal = p.getBool('keepOriginal') ?? true;
    saveToGallery = p.getBool('saveToGallery') ?? true;
    silentShutter = p.getBool('silentShutter') ?? false;
    grid = p.getBool('grid') ?? true;
    level = p.getBool('level') ?? false;
    timerSeconds = p.getInt('timerSeconds') ?? 0;
    redFilter = p.getBool('redFilter') ?? false;
    geocoding = p.getBool('geocoding') ?? true;
    mapTiles = p.getBool('mapTiles') ?? true;
    declination = p.getDouble('declination') ?? 0;
    autoDeclination = p.getBool('autoDeclination') ?? true;
    lastAutoDeclination = p.getDouble('lastAutoDeclination') ?? 0;
    keepAwake = p.getBool('keepAwake') ?? true;
    currentProjectId = p.getString('currentProjectId') ?? '';
    showAccuracyWarning = p.getBool('showAccuracyWarning') ?? true;
    hapticShutter = p.getBool('hapticShutter') ?? true;
    altitudeReference = p.getString('altitudeReference') ?? 'msl';
    notifyListeners();
  }

  Future<void> save() async {
    final SharedPreferences? p = _prefs;
    notifyListeners();
    if (p == null) {
      return;
    }
    if (_languageChosen) {
      await p.setString('language', _language);
    } else {
      await p.remove('language');
    }
    await p.setString('themeMode', themeMode);
    await p.setString('resolution', resolution);
    await p.setInt('jpegQuality', jpegQuality);
    await p.setBool('keepOriginal', keepOriginal);
    await p.setBool('saveToGallery', saveToGallery);
    await p.setBool('silentShutter', silentShutter);
    await p.setBool('grid', grid);
    await p.setBool('level', level);
    await p.setInt('timerSeconds', timerSeconds);
    await p.setBool('redFilter', redFilter);
    await p.setBool('geocoding', geocoding);
    await p.setBool('mapTiles', mapTiles);
    await p.setDouble('declination', declination);
    await p.setBool('autoDeclination', autoDeclination);
    await p.setDouble('lastAutoDeclination', lastAutoDeclination);
    await p.setBool('keepAwake', keepAwake);
    await p.setString('currentProjectId', currentProjectId);
    await p.setBool('showAccuracyWarning', showAccuracyWarning);
    await p.setBool('hapticShutter', hapticShutter);
    await p.setString('altitudeReference', altitudeReference);
  }
}
