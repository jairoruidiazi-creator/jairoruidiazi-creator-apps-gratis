import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/backup.dart';
import '../../core/device_files.dart';
import '../../core/exports.dart';
import '../../core/photo_library.dart';
import '../../core/settings.dart';
import '../../core/sharing.dart';
import '../../core/user_errors.dart';
import '../gallery/gallery_screen.dart';
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
                  s.location.localeIdentifier = st.geocoderLocale;
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
                subtitle: Text(_resolutionText(context, st.resolution)),
              ),
              _left(SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  const ButtonSegment<String>(value: 'high', label: Text('720p')),
                  const ButtonSegment<String>(value: 'veryHigh', label: Text('1080p')),
                  const ButtonSegment<String>(value: 'ultraHigh', label: Text('4K')),
                  ButtonSegment<String>(value: 'max', label: Text(t(context, 'Máxima', 'Max'))),
                ],
                selected: <String>{st.resolution},
                showSelectedIcon: false,
                // La cámara se vuelve a abrir con la nueva resolución al guardar.
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
                subtitle: Text(PhotoLibrary.album == null
                    ? t(context, 'En la app Fotos, solo con permiso para agregar. La copia de la app se conserva igual.', 'In the Photos app, with add-only access. The app\'s own copy is kept anyway.')
                    : t(context, 'Álbum "Sello". La copia de la app se conserva igual.', '"Sello" album. The app\'s own copy is kept anyway.')),
                value: st.saveToGallery,
                onChanged: (bool v) async {
                  if (v) {
                    // El permiso se pide aquí, en contexto, y no a mitad de una captura.
                    bool ok;
                    try {
                      ok = await PhotoLibrary.ensureAccess();
                    } catch (_) {
                      ok = false;
                    }
                    if (!ok) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(t(context, 'Sin permiso para la fototeca. Puedes darlo en los ajustes del teléfono.', 'No access to the photo library. You can allow it in the phone settings.')),
                          action: SnackBarAction(label: t(context, 'Ajustes', 'Settings'), onPressed: () => s.location.backend.openAppSettings()),
                        ));
                      }
                      return;
                    }
                  }
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
                subtitle: Text(t(context, 'Sobre el nivel del mar (la de los mapas y planos; se calcula con el geoide EGM96 sin internet) o sobre el elipsoide WGS84 (la cruda del GPS). En Colombia la diferencia va de unos −21 m en el norte de La Guajira a unos +28 m en Cauca y Nariño (Bogotá: +22 m); en la costa Caribe es negativa.', 'Above mean sea level (as on maps; computed offline with the EGM96 geoid) or above the WGS84 ellipsoid (raw GPS). In Colombia the difference ranges from about −21 m in northern La Guajira to about +28 m in Cauca and Nariño (Bogotá: +22 m).')),
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
                subtitle: Text(t(
                  context,
                  'Al abrir la pestaña Mapa descarga su fondo de OpenStreetMap: su servidor recibe las zonas que se muestran y tu dirección IP. Apagado, el mapa muestra solo tus fotos y tu posición.',
                  'When you open the Map tab it downloads the background from OpenStreetMap: its server receives the areas shown and your IP address. Off, the map shows only your photos and position.',
                )),
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
                      ? (s.heading.useSystemHeading
                          ? t(context, 'El iPhone calcula el norte verdadero con su posición. Mientras no la tenga, el rumbo se marca como magnético.', 'The iPhone works out true north from its position. Until it has one, the heading is marked as magnetic.')
                          : '${t(context, 'La declinación magnética se calcula con el modelo WMM2025 a partir del GPS (sin internet). Mientras no haya posición, el rumbo se marca como magnético. Último valor', 'Magnetic declination is computed with the WMM2025 model from the GPS (offline). Until there is a position, the heading is marked as magnetic. Last value')}: ${st.lastAutoDeclination >= 0 ? '+' : ''}${st.lastAutoDeclination.toStringAsFixed(1)}°')
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
                  subtitle: Text(t(
                    context,
                    'Se suma al rumbo de la brújula. En Colombia (2026, WMM2025) va de unos −5° (San Andrés, Tumaco) a −13° (Puerto Carreño); Bogotá ≈ −9°, Medellín ≈ −8°, Cali ≈ −7°, Barranquilla ≈ −9°.',
                    'Added to the compass heading. In Colombia (2026, WMM2025) it ranges from about −5° (San Andrés, Tumaco) to −13° (Puerto Carreño). Elsewhere, check a declination calculator (e.g. NOAA).',
                  )),
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
              _Section(t(context, 'Copia de seguridad', 'Backup')),
              Text(
                t(
                  context,
                  'Un solo archivo ZIP con todas las fotos (selladas y originales), sus datos, los proyectos, las plantillas y los logos: para pasarlo a otro teléfono o guardarlo donde quieras. La copia automática de Google no lleva las fotos (admite hasta 25 MB por app).',
                  'A single ZIP file with all the photos (stamped and original), their data, the projects, the templates and the logos: to move it to another phone or keep it wherever you want. Google\'s automatic backup does not carry the photos (it allows up to 25 MB per app).',
                ),
                style: tt.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Builder(
                    builder: (BuildContext bc) => FilledButton.tonalIcon(
                      onPressed: () => createBackup(bc),
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(t(context, 'Crear copia completa', 'Create full backup')),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => restoreBackup(context),
                    icon: const Icon(Icons.unarchive_outlined),
                    label: Text(t(context, 'Restaurar una copia', 'Restore a backup')),
                  ),
                ],
              ),
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
                child: Text(t(context, 'Mapa: © colaboradores de OpenStreetMap. Dirección: servicio de geocodificación del sistema (Google en Android, Apple en iOS).', 'Map: © OpenStreetMap contributors. Address: the system geocoder (Google on Android, Apple on iOS).'), style: tt.bodySmall),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _left(Widget child) => Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: child));

  /// Qué da cada opción de resolución (preajustes del complemento de cámara).
  static String _resolutionText(BuildContext context, String r) {
    switch (r) {
      case 'high':
        return t(context, '1280 × 720 (0,9 MP), 16:9. Archivos pequeños.', '1280 × 720 (0.9 MP), 16:9. Small files.');
      case 'veryHigh':
        return t(context, '1920 × 1080 (2 MP), 16:9.', '1920 × 1080 (2 MP), 16:9.');
      case 'ultraHigh':
        return t(context, '3840 × 2160 (8 MP), 16:9: recorta arriba y abajo cerca de un cuarto de lo que ve el sensor.', '3840 × 2160 (8 MP), 16:9: crops about a quarter of what the sensor sees, top and bottom.');
      case 'max':
      default:
        return t(context, 'La mayor que dé la cámara, con todo el campo de visión (12 MP o más en la mayoría, 4:3). La copia sellada se limita a 26 MP; el original se guarda completo.', 'The largest the camera offers, with the full field of view (12 MP or more on most phones, 4:3). The stamped copy is capped at 26 MP; the original is kept in full.');
    }
  }
}

String _backupStamp(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}

/// Margen de espacio libre que se deja además de la copia.
const int kBackupSpareBytes = 50 * 1024 * 1024;

/// Tamaño, en bytes, que tendrá un ZIP con [entries] (las fotos van sin
/// comprimir: un JPEG ya lo está).
Future<int> estimateZipBytes(List<ArchiveEntry> entries) async {
  int total = 22;
  for (final ArchiveEntry e in entries) {
    final String? path = e.path;
    if (path != null) {
      try {
        total += await File(path).length();
      } catch (_) {}
    } else {
      total += e.bytes?.length ?? 0;
    }
    // Cabeceras local y central de cada entrada.
    total += 2 * (46 + utf8.encode(e.name).length);
  }
  return total;
}

/// "350 MB", "1,2 GB" (coma decimal en español).
String formatBytes(int bytes, {required bool spanish}) {
  final double mb = bytes / (1024 * 1024);
  String n(double v) {
    final String text = v.toStringAsFixed(1);
    return spanish ? text.replaceAll('.', ',') : text;
  }

  if (mb >= 1024) {
    return '${n(mb / 1024)} GB';
  }
  if (mb >= 10) {
    return '${mb.round()} MB';
  }
  return '${n(mb < 0.1 ? 0.1 : mb)} MB';
}

/// Diálogo de espera que no se puede cerrar (se cierra con
/// `Navigator.of(context, rootNavigator: true).pop()`).
Future<void> showBusyDialog(BuildContext context, String text) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator()),
              const SizedBox(width: 16),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );

/// Arma la copia completa en un ZIP (en un isolate, con avance y cancelar).
/// Antes dice cuánto ocupará y cuánto espacio hay. En Android la guarda
/// donde el usuario elija con el selector de documentos del sistema (la
/// copia pasa de a 1 MB, nunca entera por la memoria) y borra la de la app;
/// en iPhone la ofrece en la hoja de compartir, anclada en el botón pulsado.
Future<void> createBackup(BuildContext buttonContext) async {
  final Services s = AppScope.of(buttonContext);
  final Rect origin = shareOriginOf(buttonContext);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(buttonContext);
  final bool spanish = s.settings.spanish;
  final bool picker = s.files.usesDocumentPicker;
  String k(String es, String en) => spanish ? es : en;
  String size(int b) => formatBytes(b, spanish: spanish);
  final List<ArchiveEntry> entries = await Backup.entries(s.state);
  final int needed = await estimateZipBytes(entries);
  final int? free = await s.files.freeBytes();
  if (!buttonContext.mounted) {
    return;
  }
  final bool enough = free == null || free >= needed + kBackupSpareBytes;
  final String where = picker
      ? k(' Después eliges dónde guardarla (Drive, una memoria USB, Descargas…); si la guardas en este mismo teléfono, ocupará otro tanto.', ' Then you choose where to save it (Drive, a USB drive, Downloads…); if you save it on this same phone, it takes as much again.')
      : k(' Después eliges dónde guardarla o a quién enviarla.', ' Then you choose where to save it or whom to send it to.');
  final bool? go = await showDialog<bool>(
    context: buttonContext,
    builder: (BuildContext context) => AlertDialog(
      title: Text(k('Crear copia completa', 'Create full backup')),
      content: Text(
        '${s.state.photos.length} ${k('fotos con sus datos, proyectos, plantillas y logos: unos', 'photos with their data, projects, templates and logos: about')} ${size(needed)}. '
        '${k('Se arma primero en el teléfono, así que hacen falta unos', 'It is built on the phone first, so it needs about')} ${size(needed)} ${k('libres', 'free')}'
        '${free == null ? '' : ' (${k('hay', 'there are')} ${size(free)})'}.$where'
        '${enough ? '' : '\n\n${k('No hay espacio suficiente. Libera espacio en el teléfono e inténtalo de nuevo.', 'There is not enough space. Free up space on the phone and try again.')}'}',
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(k('Cancelar', 'Cancel'))),
        if (enough) FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(k('Crear', 'Create'))),
      ],
    ),
  );
  if (go != true || !buttonContext.mounted) {
    return;
  }
  final ExportProgress progress = ExportProgress();
  unawaited(showExportProgress(buttonContext, progress, title: k('Creando la copia', 'Creating the backup')));
  final String name = 'sello_${k('copia', 'backup')}_${_backupStamp(clock.now())}.zip';
  final String path = await s.store.absolutePath('exports/$name');
  try {
    await writeZipFile(path, entries, onProgress: (int d, int tot) => progress.update(d, tot, '${k('Guardando', 'Saving')} $d ${k('de', 'of')} $tot'), cancel: progress.cancel);
    progress.close();
    if (picker) {
      if (!buttonContext.mounted) {
        return;
      }
      // Queda debajo del selector y se ve mientras se copia.
      final NavigatorState nav = Navigator.of(buttonContext, rootNavigator: true);
      unawaited(showBusyDialog(buttonContext, k('Guardando la copia donde elegiste…', 'Saving the backup where you chose…')));
      bool saved;
      try {
        saved = await s.files.saveDocument(path, name);
      } finally {
        if (nav.mounted && nav.canPop()) {
          nav.pop();
        }
      }
      messenger.showSnackBar(SnackBar(content: Text(saved ? k('Copia guardada.', 'Backup saved.') : k('No se guardó la copia.', 'The backup was not saved.'))));
    } else {
      await shareFiles(<String>[path], origin: origin, subject: k('Copia de Sello', 'Sello backup'));
    }
  } on ExportCancelled {
    progress.close();
  } catch (e) {
    progress.close();
    messenger.showSnackBar(SnackBar(content: Text(isNoSpaceError(e) ? k('No hay espacio para la copia donde elegiste guardarla (o en el teléfono). Libera espacio o elige otro lugar.', 'There is no space for the backup where you chose to save it (or on the phone). Free up space or choose another place.') : '${k('No se pudo crear la copia', 'Could not create the backup')}: ${errorReason(e, spanish: spanish)}.')));
  } finally {
    // En Android la copia ya quedó donde se eligió: la de la app sobra. En
    // iPhone la hoja de compartir la necesita; se borra al abrir la app.
    if (picker) {
      await _deleteQuietly(path);
    }
  }
}

Future<void> _deleteQuietly(String path) async {
  try {
    final File f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}

/// Elige un ZIP de copia y agrega lo que falte en este teléfono.
///
/// Antes de copiar nada dice cuánto pesa la copia y cuánto espacio hace
/// falta, y si no alcanza no deja seguir. En Android el documento elegido se
/// trae a la app de a 1 MB en un hilo aparte (nunca entero en la memoria) y
/// por eso hace falta unas dos veces su tamaño: la copia traída más las
/// fotos que se agregan (la traída se borra al terminar). En iPhone el
/// selector ya la copió. Traerla y agregar las fotos muestran el avance y se
/// pueden cancelar; cancelar no deja nada a medias.
Future<void> restoreBackup(BuildContext context) async {
  final Services s = AppScope.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool spanish = s.settings.spanish;
  final bool picker = s.files.usesDocumentPicker;
  String k(String es, String en) => spanish ? es : en;
  String size(int b) => formatBytes(b, spanish: spanish);
  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  // 1. Elegir la copia (en Android, sin copiarla todavía).
  PickedDocument? doc;
  String? pickedPath;
  int zipBytes = -1;
  try {
    if (picker) {
      doc = await s.files.pickDocument();
      zipBytes = doc?.size ?? -1;
    } else {
      pickedPath = await s.files.pickZipCopy();
      if (pickedPath != null) {
        try {
          zipBytes = await File(pickedPath).length();
        } catch (_) {}
      }
    }
  } catch (e) {
    say('${k('No se pudo abrir el selector', 'Could not open the picker')}: ${errorReason(e, spanish: spanish)}.');
    return;
  }
  if (doc == null && pickedPath == null) {
    return;
  }
  // En iPhone el selector dejó una copia del ZIP en tmp (pueden ser varios
  // GB): se borra al terminar, falle o se cancele.
  try {

    // 2. Espacio: en Android se trae la copia y después se agregan sus fotos
    // (casi todo el ZIP son fotos sin comprimir).
    final int? free = await s.files.freeBytes();
    if (!context.mounted) {
      return;
    }
    final int needed = zipBytes < 0 ? -1 : zipBytes * (picker ? 2 : 1) + kBackupSpareBytes;
    final bool enough = free == null || needed < 0 || free >= needed;
    final String weight = zipBytes < 0 ? k('No se sabe cuánto pesa la copia.', 'The backup size is unknown.') : '${k('La copia pesa', 'The backup weighs')} ${size(zipBytes)}.';
    final String space = needed < 0
        ? ''
        : ' ${picker ? k('Para restaurarla hacen falta unos ${size(needed)} libres: primero se trae al teléfono y después se agregan sus fotos (la copia traída se borra al terminar).', 'Restoring it needs about ${size(needed)} free: it is first brought to the phone and then its photos are added (the brought copy is deleted at the end).') : k('Para agregar sus fotos hacen falta unos ${size(needed)} libres.', 'Adding its photos needs about ${size(needed)} free.')}'
            '${free == null ? '' : ' ${k('Hay', 'There are')} ${size(free)} ${k('libres', 'free')}.'}';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(k('Restaurar copia', 'Restore backup')),
        content: Text(
          '${k('Se agregan las fotos, proyectos y plantillas de la copia que no estén en este teléfono. No se borra ni se reemplaza nada.', 'The backup\'s photos, projects and templates that are not on this phone are added. Nothing is deleted or replaced.')} $weight$space'
          '${enough ? '' : '\n\n${k('No hay espacio suficiente. Libera espacio en el teléfono e inténtalo de nuevo.', 'There is not enough space. Free up space on the phone and try again.')}'}',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(k('Cancelar', 'Cancel'))),
          if (enough) FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(k('Restaurar', 'Restore'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      return;
    }

    // 3. Traer la copia (Android) y agregar lo que falte, con avance y cancelar.
    final ExportProgress progress = ExportProgress();
    unawaited(showExportProgress(context, progress, title: k('Restaurando la copia', 'Restoring the backup')));
    String? brought;
    String message;
    try {
      String path;
      if (doc != null) {
        path = await s.store.absolutePath('exports/restaurar_copia.zip');
        brought = path;
        final int total = zipBytes;
        await s.files.copyDocument(
          doc,
          path,
          cancel: progress.cancel,
          onProgress: (int done, int tot) {
            final int all = tot > 0 ? tot : total;
            progress.update(done, all > 0 ? all : 0, '${k('Trayendo la copia', 'Bringing the backup')}: ${size(done)}${all > 0 ? ' ${k('de', 'of')} ${size(all)}' : ''}');
          },
        );
      } else {
        path = pickedPath!;
      }
      progress.update(0, 0, k('Agregando fotos…', 'Adding photos…'));
      final RestoreSummary r = await Backup.restore(
        path,
        s.state,
        cancel: progress.cancel,
        onProgress: (int done, int total) => progress.update(done, total, '${k('Agregando', 'Adding')} $done ${k('de', 'of')} $total'),
      );
      // Fotos que en el otro teléfono quedaron sin sellar.
      s.queue.resumePending();
      message = '${k('Copia restaurada', 'Backup restored')}: ${r.photos} ${k('fotos', 'photos')}, ${r.projects} ${k('proyectos', 'projects')}, ${r.templates} ${k('plantillas', 'templates')}.';
    } on DocumentCopyCancelled {
      message = k('Se canceló la restauración; no se agregó nada.', 'Restoring was cancelled; nothing was added.');
    } on ExportCancelled {
      message = k('Se canceló la restauración; no se agregó nada.', 'Restoring was cancelled; nothing was added.');
    } on DocumentNoSpace {
      message = k('El teléfono se quedó sin espacio al traer la copia. Libera espacio e inténtalo de nuevo.', 'The phone ran out of space while bringing the backup. Free up space and try again.');
    } on NotABackup {
      message = k('Ese archivo no es una copia de Sello.', 'That file is not a Sello backup.');
    } catch (e) {
      message = isNoSpaceError(e) ? k('El teléfono se quedó sin espacio. Libera espacio e inténtalo de nuevo; no se agregó nada.', 'The phone ran out of space. Free up space and try again; nothing was added.') : '${k('No se pudo restaurar', 'Could not restore')}: ${errorReason(e, spanish: spanish)}. ${k('No se agregó nada.', 'Nothing was added.')}';
    } finally {
      progress.close();
      // La copia que se trajo a la app (Android) ya no hace falta.
      if (brought != null) {
        await _deleteQuietly(brought);
      }
    }
    say(message);
  } finally {
    if (pickedPath != null) {
      await s.files.deletePickedCopy(pickedPath);
    }
  }
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
