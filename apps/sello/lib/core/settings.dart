import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del usuario.
class AppSettings extends ChangeNotifier {
  SharedPreferences? _prefs;

  String language = 'es';
  String themeMode = 'system';
  String resolution = 'ultraHigh'; // high | veryHigh | ultraHigh | max
  int jpegQuality = 92;
  bool keepOriginal = true;
  bool saveToGallery = true;
  bool silentShutter = false;
  bool grid = true;
  bool level = false;
  int timerSeconds = 0;
  bool redFilter = false;
  bool geocoding = true;
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
    language = p.getString('language') ?? 'es';
    themeMode = p.getString('themeMode') ?? 'system';
    resolution = p.getString('resolution') ?? 'ultraHigh';
    jpegQuality = p.getInt('jpegQuality') ?? 92;
    keepOriginal = p.getBool('keepOriginal') ?? true;
    saveToGallery = p.getBool('saveToGallery') ?? true;
    silentShutter = p.getBool('silentShutter') ?? false;
    grid = p.getBool('grid') ?? true;
    level = p.getBool('level') ?? false;
    timerSeconds = p.getInt('timerSeconds') ?? 0;
    redFilter = p.getBool('redFilter') ?? false;
    geocoding = p.getBool('geocoding') ?? true;
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
    await p.setString('language', language);
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
