import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/maps_links.dart';
import '../../geo/coords.dart';
import '../../geo/declination.dart';
import '../../geo/heading.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';

/// Hoja con el detalle del GPS y la brújula: formatos de coordenadas,
/// precisión, promedio, bloqueo y posición manual.
Future<void> showGpsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _GpsSheet(),
  );
}

class _GpsSheet extends StatelessWidget {
  const _GpsSheet();

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.location, s.heading]),
      builder: (BuildContext context, Widget? _) {
        final LocationService loc = s.location;
        final Fix? f = loc.fix;
        final Orientation3? o = s.heading.orientation;
        final bool spanish = s.settings.spanish;
        final TextTheme tt = Theme.of(context).textTheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (BuildContext context, ScrollController sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.gps_fixed, color: f == null ? Colors.redAccent : Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusText(context, loc), style: tt.titleMedium)),
                ],
              ),
              // Permiso de ubicación aproximada: ni el cielo abierto ni promediar
              // lo arreglan; hay que pedir la precisa o activarla en los ajustes.
              if (loc.approximate) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  t(context, 'Diste permiso de ubicación aproximada: las coordenadas pueden estar a kilómetros. Las fotos quedan marcadas como «ubicación aproximada». Para coordenadas útiles, pide la ubicación precisa o activa «Ubicación precisa» para Sello en los ajustes del teléfono.', 'You allowed approximate location: the coordinates may be kilometres off. Photos are marked "approximate location". For useful coordinates, ask for precise location or turn on "Precise location" for Sello in the phone settings.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () async {
                        final bool ok = await loc.requestPreciseLocation();
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t(context, 'Sigue aproximada. En los ajustes de Sello activa la ubicación precisa (botón «Abrir ajustes»).', 'Still approximate. In Sello\'s settings turn on precise location ("Open settings" button).'))));
                        }
                      },
                      icon: const Icon(Icons.my_location_rounded),
                      label: Text(t(context, 'Pedir ubicación precisa', 'Ask for precise location')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => loc.backend.openAppSettings(),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(t(context, 'Abrir ajustes', 'Open settings')),
                    ),
                  ],
                ),
              ],
              // Punto fijado cuando la ubicación era aproximada, con la precisa
              // ya concedida: sigue siendo aproximado hasta liberarlo.
              if (f != null && f.approximate && !loc.approximate) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  t(context, 'Esta posición fijada es aproximada: libérala para usar la precisa.', 'This locked position is approximate: unlock it to use the precise one.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (f != null) ...<Widget>[
                const SizedBox(height: 8),
                for (final CoordFormat cf in Coords.formatsFor(f.latitude, f.longitude, coarse: f.approximate))
                  _CoordRow(label: Coords.formatName(cf, spanish: spanish, coarse: f.approximate), value: Coords.format(cf, f.latitude, f.longitude, coarse: f.approximate)),
                const Divider(),
                if (f.manual)
                  _Line(t(context, 'Posición', 'Position'), t(context, 'Escrita a mano: sin precisión ni altitud medidas.', 'Entered by hand: no measured accuracy or altitude.'))
                else ...<Widget>[
                  _Line(t(context, 'Precisión horizontal', 'Horizontal accuracy'), f.accuracy == null ? t(context, 'desconocida', 'unknown') : '± ${f.accuracy!.toStringAsFixed(1)} m${f.averagedSamples > 1 ? ' · ${t(context, 'promedio de', 'average of')} ${f.averagedSamples}' : ''}'),
                  _Line(t(context, 'Altitud', 'Altitude'), _altitudeText(context, f)),
                  if (!f.locked) _Line(t(context, 'Velocidad', 'Speed'), '${(f.speed * 3.6).toStringAsFixed(1)} km/h'),
                  _Line(t(context, 'Hora de la lectura', 'Fix time'), TimeOfDay.fromDateTime(f.time.toLocal()).format(context)),
                ],
                // Con la aproximada el cielo abierto no sirve: lo que hay que
                // hacer lo dice el bloque de arriba.
                if (loc.stale && !f.approximate)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      t(context, 'La última lectura del GPS es vieja: el teléfono puede estar en otro lugar. Sal a cielo abierto o fija la posición a propósito.', 'The last GPS reading is old: the phone may be somewhere else. Go out to open sky or lock the position on purpose.'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (loc.address != null) _Line(t(context, 'Dirección aproximada', 'Approximate address'), loc.address!.full),
                if (!f.manual && !f.approximate && (f.accuracy ?? 0) > 30 && s.settings.showAccuracyWarning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      t(context, 'Precisión baja. Sal a cielo abierto, espera unos segundos o usa "Promediar".', 'Low accuracy. Move to open sky, wait a few seconds or use "Average".'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (loc.averaging) ...<Widget>[
                    FilledButton.tonalIcon(
                      onPressed: loc.finishAveraging,
                      icon: const Icon(Icons.check_rounded),
                      label: Text('${t(context, 'Terminar y fijar', 'Finish and lock')} (${loc.averagingSamples})'),
                    ),
                    OutlinedButton(onPressed: loc.cancelAveraging, child: Text(t(context, 'Cancelar promedio', 'Cancel averaging'))),
                  ] else
                    FilledButton.tonalIcon(
                      onPressed: loc.live == null ? null : () => loc.startAveraging(seconds: 20),
                      icon: const Icon(Icons.timelapse_rounded),
                      label: Text(t(context, 'Promediar 20 s y fijar', 'Average 20 s and lock')),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: loc.locked ? loc.unlock : (loc.live == null ? null : loc.lock),
                    icon: Icon(loc.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                    label: Text(loc.locked ? t(context, 'Liberar posición', 'Unlock position') : t(context, 'Fijar posición', 'Lock position')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _manual(context, loc),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: Text(t(context, 'Posición manual', 'Manual position')),
                  ),
                  if (f != null)
                    OutlinedButton.icon(
                      onPressed: () => openInMaps(f.latitude, f.longitude),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(t(context, 'Abrir en mapas', 'Open in maps')),
                    ),
                  if (loc.status != 'ok')
                    OutlinedButton.icon(
                      onPressed: () => loc.retry(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t(context, 'Reintentar GPS', 'Retry GPS')),
                    ),
                  if (loc.needsSettings && !loc.approximate)
                    OutlinedButton.icon(
                      onPressed: () => loc.status == 'disabled' ? loc.backend.openLocationSettings() : loc.backend.openAppSettings(),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(t(context, 'Abrir ajustes', 'Open settings')),
                    ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: <Widget>[
                  const Icon(Icons.explore_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t(context, 'Brújula', 'Compass'), style: tt.titleMedium)),
                ],
              ),
              if (o == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t(context, 'Sin lectura de brújula (este equipo puede no tener magnetómetro).', 'No compass reading (this device may lack a magnetometer).')),
                )
              else ...<Widget>[
                _Line(t(context, 'Rumbo de la cámara', 'Camera heading'), '${o.cameraHeading.toStringAsFixed(0)}° ${Coords.cardinal(o.cameraHeading, spanish: spanish)} ${o.trueNorth ? t(context, '(norte verdadero)', '(true north)') : t(context, '(norte magnético)', '(magnetic north)')}'),
                if (o.accuracy != null) _Line(t(context, 'Precisión del rumbo', 'Heading accuracy'), '± ${o.accuracy!.toStringAsFixed(0)}°'),
                _Line(t(context, 'Fachada fotografiada', 'Facade photographed'), Coords.facade(o.cameraHeading, spanish: spanish)),
                _Line(t(context, 'Inclinación', 'Tilt'), '${o.pitch.toStringAsFixed(0)}°${o.flat ? ' · ${t(context, 'teléfono horizontal', 'phone flat')}' : ''}'),
                _Line(t(context, 'Declinación', 'Declination'), _declinationText(context, s)),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (o.accuracy ?? 0) > 20
                        ? t(context, 'Rumbo poco preciso: mueve el teléfono dibujando un 8 para calibrar y aléjate de metales e imanes.', 'Imprecise heading: move the phone in a figure 8 to calibrate and keep away from metal and magnets.')
                        : t(context, 'Si el rumbo parece errado, mueve el teléfono dibujando un 8 para calibrar y aléjate de metales e imanes.', 'If the heading looks wrong, move the phone in a figure 8 to calibrate and keep away from metal and magnets.'),
                    style: tt.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _altitudeText(BuildContext context, Fix f) {
    if (!f.hasAltitude) {
      return t(context, 'sin dato (el GPS aún no la mide)', 'no data (the GPS has not measured it yet)');
    }
    final List<String> parts = <String>[
      if (f.altitudeMsl != null) '${f.altitudeMsl!.toStringAsFixed(1)} m ${t(context, 's. n. m.', 'MSL')}',
      if (f.altitudeEllipsoid != null) '${f.altitudeEllipsoid!.toStringAsFixed(1)} m ${t(context, 'elipsoidal', 'ellipsoidal')}',
    ];
    final double? acc = f.altitudeAccuracy;
    return '${parts.join(' · ')}${acc != null && acc > 0 ? ' (± ${acc.toStringAsFixed(0)} m)' : ''}';
  }

  static String _declinationText(BuildContext context, Services s) {
    String fmt(double d) => '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}°';
    if (s.heading.usingSystemDeclination) {
      return '${fmt(s.heading.systemDeclination!)} (${t(context, 'calculada por iOS', 'computed by iOS')})';
    }
    final DeclinationSource? source = s.declinationLink?.source;
    final String value = fmt(s.heading.declination);
    if (!s.heading.declinationKnown || source == DeclinationSource.unknown) {
      return t(context, 'sin GPS todavía: el rumbo es magnético', 'no GPS yet: the heading is magnetic');
    }
    if (source == DeclinationSource.manual || !s.settings.autoDeclination) {
      return '$value (${t(context, 'manual', 'manual')})';
    }
    final bool expired = s.declinationLink?.extrapolated ?? false;
    return '$value (WMM2025)${expired ? ' · ${t(context, 'modelo vencido, actualiza la app', 'model expired, update the app')}' : ''}';
  }

  String _statusText(BuildContext context, LocationService loc) {
    final Fix? f = loc.fix;
    if (f != null && f.manual) {
      return t(context, 'Posición escrita a mano', 'Position entered by hand');
    }
    if (f != null && f.source == PositionSource.averaged) {
      return '${t(context, 'Posición promediada y fijada', 'Averaged and locked position')} (${f.averagedSamples})';
    }
    switch (loc.status) {
      case 'denied':
      case 'deniedForever':
        return t(context, 'Sin permiso de ubicación. Actívalo en los ajustes del teléfono.', 'Location permission denied. Enable it in the phone settings.');
      case 'disabled':
        return t(context, 'Ubicación apagada o sin señal.', 'Location off or unavailable.');
      case 'searching':
        return t(context, 'Buscando satélites…', 'Searching for satellites…');
      case 'ok':
        if (loc.approximate) {
          return t(context, 'Ubicación aproximada', 'Approximate location');
        }
        if (loc.averaging) {
          return '${t(context, 'Promediando lecturas…', 'Averaging readings…')} (${loc.averagingSamples})';
        }
        return loc.locked ? t(context, 'Posición fijada', 'Position locked') : t(context, 'Posición en vivo', 'Live position');
      default:
        return t(context, 'GPS apagado', 'GPS off');
    }
  }

  Future<void> _manual(BuildContext context, LocationService loc) async {
    final Fix? f = loc.fix;
    // Con una lectura aproximada no se rellena nada: fijarla sin tocarla le
    // daría seis decimales a un punto que puede estar a kilómetros y le
    // quitaría la marca. La persona escribe las coordenadas reales.
    final bool approximate = (f?.approximate ?? false) || loc.approximate;
    String start(double? v) => v == null || approximate ? '' : v.toStringAsFixed(6);
    final TextEditingController lat = TextEditingController(text: start(f?.latitude));
    final TextEditingController lon = TextEditingController(text: start(f?.longitude));
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, 'Posición manual', 'Manual position')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: t(context, 'Latitud (grados decimales)', 'Latitude (decimal degrees)'))),
              TextField(controller: lon, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: t(context, 'Longitud (grados decimales)', 'Longitude (decimal degrees)'))),
              if (approximate) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  t(context, 'La ubicación del teléfono es aproximada (puede estar a kilómetros): escribe las coordenadas reales del lugar.', 'The phone location is approximate (it may be kilometres off): type the real coordinates of the place.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Text(t(context, 'Queda fija hasta que la liberes. Las fotos dicen "posición manual" y no llevan precisión ni altitud, porque no se midieron.', 'Stays locked until you release it. Photos say "manual position" and carry no accuracy or altitude, because they were not measured.'), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Fijar', 'Lock'))),
        ],
      ),
    );
    if (ok == true) {
      final double? la = double.tryParse(lat.text.trim().replaceAll(',', '.'));
      final double? lo = double.tryParse(lon.text.trim().replaceAll(',', '.'));
      if (la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) {
        loc.lockManual(la, lo);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Coordenadas no válidas.', 'Invalid coordinates.'))));
      }
    }
    disposeLater(<ChangeNotifier>[lat, lon]);
  }
}

class _CoordRow extends StatelessWidget {
  const _CoordRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    void copy() {
      Clipboard.setData(ClipboardData(text: value));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Copiado', 'Copied')}: $value'), duration: const Duration(seconds: 1)));
    }

    // Como en el detalle de la foto: al menos 48 dp (en campo, con guantes)
    // y el lector de pantalla anuncia «copiar».
    return Semantics(
      button: true,
      label: '$label: $value',
      onTapHint: t(context, 'copiar', 'copy'),
      onTap: copy,
      excludeSemantics: true,
      child: InkWell(
        onTap: copy,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  SizedBox(width: 102, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: <FontFeature>[FontFeature.tabularFigures()]))),
                  const Icon(Icons.copy_rounded, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 142, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
