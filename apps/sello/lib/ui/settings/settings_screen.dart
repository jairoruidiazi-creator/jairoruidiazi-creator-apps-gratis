import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../legal/legal_document.dart';

/// Ajustes de la app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.settings,
      builder: (BuildContext context, Widget? _) {
        final AppSettings st = s.settings;
        final TextTheme tt = Theme.of(context).textTheme;
        void save() => st.save();
        return Scaffold(
          appBar: AppBar(title: Text(t(context, 'Ajustes', 'Settings'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
            children: <Widget>[
              _Section(t(context, 'Idioma y apariencia', 'Language and appearance')),
              _left(SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'es', label: Text('Español')), ButtonSegment<String>(value: 'en', label: Text('English'))],
                selected: <String>{st.language},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.language = v.first;
                  s.location.localeIdentifier = st.spanish ? 'es_CO' : 'en_US';
                  save();
                },
              )),
              const SizedBox(height: 8),
              _left(SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'system', label: Text(t(context, 'Sistema', 'System'))),
                  ButtonSegment<String>(value: 'light', label: Text(t(context, 'Claro', 'Light'))),
                  ButtonSegment<String>(value: 'dark', label: Text(t(context, 'Oscuro', 'Dark'))),
                ],
                selected: <String>{st.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.themeMode = v.first;
                  save();
                },
              )),
              _Section(t(context, 'Foto', 'Photo')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Resolución', 'Resolution')),
                subtitle: Text(t(context, 'Más resolución = archivos más grandes y sellado más lento.', 'Higher resolution = bigger files and slower stamping.')),
              ),
              _left(SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'high', label: Text(t(context, 'Media', 'Medium'))),
                  ButtonSegment<String>(value: 'veryHigh', label: Text(t(context, 'Alta', 'High'))),
                  ButtonSegment<String>(value: 'ultraHigh', label: Text(t(context, 'Muy alta', 'Very high'))),
                  ButtonSegment<String>(value: 'max', label: Text(t(context, 'Máxima', 'Max'))),
                ],
                selected: <String>{st.resolution},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.resolution = v.first;
                  save();
                },
              )),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${t(context, 'Calidad JPEG', 'JPEG quality')}: ${st.jpegQuality}'),
                subtitle: Slider(
                  min: 60,
                  max: 100,
                  divisions: 40,
                  value: st.jpegQuality.toDouble().clamp(60, 100),
                  label: '${st.jpegQuality}',
                  onChanged: (double v) {
                    st.jpegQuality = v.round();
                    st.refresh();
                  },
                  onChangeEnd: (_) => save(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Conservar la foto original', 'Keep the original photo')),
                subtitle: Text(t(context, 'Sin sello, dentro de la app. Permite volver a sellar y ocupa el doble de espacio.', 'Unstamped, inside the app. Allows re-stamping and doubles the storage used.')),
                value: st.keepOriginal,
                onChanged: (bool v) {
                  st.keepOriginal = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Copiar a la fototeca del teléfono', 'Copy to the phone\'s photo library')),
                subtitle: Text(t(context, 'Álbum "Sello". La copia de la app se conserva igual.', '"Sello" album. The app\'s own copy is kept anyway.')),
                value: st.saveToGallery,
                onChanged: (bool v) {
                  st.saveToGallery = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Vibrar al disparar', 'Vibrate on shutter')),
                value: st.hapticShutter,
                onChanged: (bool v) {
                  st.hapticShutter = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Pantalla encendida en la cámara', 'Keep screen on in camera')),
                value: st.keepAwake,
                onChanged: (bool v) {
                  st.keepAwake = v;
                  save();
                },
              ),
              _Section(t(context, 'Ubicación y brújula', 'Location and compass')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Altitud en el sello', 'Altitude on the stamp')),
                subtitle: Text(t(context, 'Sobre el nivel del mar (la de los mapas y planos; se calcula con el geoide EGM96 sin internet) o sobre el elipsoide WGS84 (la cruda del GPS). En Colombia difieren entre 5 y 30 m.', 'Above mean sea level (as on maps; computed offline with the EGM96 geoid) or above the WGS84 ellipsoid (raw GPS).')),
              ),
              _left(SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'msl', label: Text(t(context, 'Nivel del mar', 'Sea level'))),
                  ButtonSegment<String>(value: 'ellipsoid', label: Text(t(context, 'Elipsoide', 'Ellipsoid'))),
                ],
                selected: <String>{st.altitudeReference},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.altitudeReference = v.first;
                  save();
                },
              )),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Dirección aproximada', 'Approximate address')),
                subtitle: Text(t(context, 'Envía las coordenadas al servicio de direcciones del teléfono (Google en Android, Apple en iOS) y necesita internet. Las coordenadas funcionan siempre sin conexión.', 'Sends the coordinates to the phone\'s address service (Google on Android, Apple on iOS) and needs internet. Coordinates always work offline.')),
                value: st.geocoding,
                onChanged: (bool v) {
                  st.geocoding = v;
                  s.location.geocodingEnabled = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Mapa en línea', 'Online map')),
                subtitle: Text(t(context, 'Descarga el fondo del mapa de OpenStreetMap: su servidor recibe la zona que miras y tu dirección IP. Apagado, el mapa muestra solo tus fotos y tu posición.', 'Downloads the map background from OpenStreetMap: its server receives the area you view and your IP address. Off, the map shows only your photos and position.')),
                value: st.mapTiles,
                onChanged: (bool v) {
                  st.mapTiles = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Avisar cuando la precisión sea baja', 'Warn when accuracy is low')),
                value: st.showAccuracyWarning,
                onChanged: (bool v) {
                  st.showAccuracyWarning = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Norte verdadero automático', 'Automatic true north')),
                subtitle: Text(
                  st.autoDeclination
                      ? '${t(context, 'La declinación magnética se calcula con el modelo WMM2025 a partir del GPS (sin internet). Valor actual', 'Magnetic declination is computed with the WMM2025 model from the GPS (offline). Current value')}: ${st.lastAutoDeclination >= 0 ? '+' : ''}${st.lastAutoDeclination.toStringAsFixed(1)}°'
                      : t(context, 'Apagado: se usa el valor manual de abajo.', 'Off: the manual value below is used.'),
                ),
                value: st.autoDeclination,
                onChanged: (bool v) {
                  st.autoDeclination = v;
                  save();
                },
              ),
              if (!st.autoDeclination) ...<Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${t(context, 'Declinación manual', 'Manual declination')}: ${st.declination >= 0 ? '+' : ''}${st.declination.toStringAsFixed(1)}°'),
                  subtitle: Text(t(context, 'Se suma al rumbo de la brújula. En Colombia (2026) va de −6° (Nariño) a −11° (Guajira, Amazonas); Bogotá ≈ −9°, Medellín ≈ −8°, Cali ≈ −7°, Barranquilla ≈ −9°.', 'Added to the compass heading. Check your area\'s value in a declination calculator (e.g. NOAA).')),
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(width: 8),
                    const Text('−20°'),
                    Expanded(
                      child: Slider(
                        min: -20,
                        max: 20,
                        divisions: 80,
                        value: st.declination.clamp(-20.0, 20.0),
                        label: st.declination.toStringAsFixed(1),
                        onChanged: (double v) {
                          st.declination = (v * 2).round() / 2;
                          st.refresh();
                        },
                        onChangeEnd: (_) => save(),
                      ),
                    ),
                    const Text('+20°'),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
              _Section(t(context, 'Acerca de', 'About')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.approval_outlined),
                title: const Text('$kAppName $kAppVersion'),
                subtitle: Text(t(context, 'Cámara de campo con sello de GPS, hora y rumbo. Gratis, sin anuncios y sin cuentas. Sello no sube tus fotos a ningún servidor. El sello informa, no prueba: la hora y el GPS de un teléfono se pueden alterar.', 'Field camera with GPS, time and heading stamp. Free, no ads, no accounts. Sello never uploads your photos to any server. The stamp informs; it is not proof: a phone\'s time and GPS can be altered.')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(t(context, 'Política de privacidad', 'Privacy policy')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PrivacyPolicyScreen(spanish: s.settings.spanish))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(t(context, 'Licencias de código abierto', 'Open-source licenses')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(context: context, applicationName: kAppName, applicationVersion: kAppVersion),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t(context, 'Mapa: © OpenStreetMap contributors. Dirección: servicio de geocodificación del sistema (Google en Android, Apple en iOS).', 'Map: © OpenStreetMap contributors. Address: the system geocoder (Google on Android, Apple on iOS).'), style: tt.bodySmall),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _left(Widget child) => Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: child));
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
