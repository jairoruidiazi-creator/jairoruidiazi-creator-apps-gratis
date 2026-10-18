import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/maps_links.dart';
import '../../geo/coords.dart';
import '../../geo/heading.dart';
import '../../geo/location_service.dart';

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
              if (f != null) ...<Widget>[
                const SizedBox(height: 8),
                for (final CoordFormat cf in Coords.formatsFor(f.latitude, f.longitude))
                  _CoordRow(label: Coords.formatName(cf, spanish: spanish), value: Coords.format(cf, f.latitude, f.longitude)),
                const Divider(),
                _Line(t(context, 'Precisión horizontal', 'Horizontal accuracy'), '± ${f.accuracy.toStringAsFixed(1)} m${f.averagedSamples > 1 ? ' · ${t(context, 'promedio de', 'average of')} ${f.averagedSamples}' : ''}'),
                _Line(
                  t(context, 'Altitud', 'Altitude'),
                  '${f.altitudeMsl != null ? '${f.altitudeMsl!.toStringAsFixed(1)} m ${t(context, 's. n. m.', 'MSL')}' : ''}${f.altitudeMsl != null && f.altitudeEllipsoid != null ? ' · ' : ''}${f.altitudeEllipsoid != null ? '${f.altitudeEllipsoid!.toStringAsFixed(1)} m ${t(context, 'elipsoidal', 'ellipsoidal')}' : ''}${f.altitudeMsl == null && f.altitudeEllipsoid == null ? '${f.altitude.toStringAsFixed(1)} m' : ''}${f.altitudeAccuracy > 0 ? ' (± ${f.altitudeAccuracy.toStringAsFixed(0)} m)' : ''}',
                ),
                _Line(t(context, 'Velocidad', 'Speed'), '${(f.speed * 3.6).toStringAsFixed(1)} km/h'),
                _Line(t(context, 'Hora de la lectura', 'Fix time'), TimeOfDay.fromDateTime(f.time.toLocal()).format(context)),
                if (loc.address != null) _Line(t(context, 'Dirección aproximada', 'Approximate address'), loc.address!.full),
                if (f.accuracy > 30 && s.settings.showAccuracyWarning)
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
                  FilledButton.tonalIcon(
                    onPressed: loc.averaging ? loc.stopAveraging : () => loc.startAveraging(seconds: 20),
                    icon: Icon(loc.averaging ? Icons.stop_rounded : Icons.timelapse_rounded),
                    label: Text(loc.averaging ? t(context, 'Detener promedio', 'Stop averaging') : t(context, 'Promediar 20 s', 'Average 20 s')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: f == null && !loc.locked ? null : (loc.locked ? loc.unlock : loc.lock),
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
                  if (loc.status == 'denied' || loc.status == 'disabled')
                    OutlinedButton.icon(
                      onPressed: () => loc.start(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t(context, 'Reintentar GPS', 'Retry GPS')),
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
                _Line(t(context, 'Rumbo de la cámara', 'Camera heading'), '${o.cameraHeading.toStringAsFixed(0)}° ${Coords.cardinal(o.cameraHeading, spanish: spanish)}'),
                _Line(t(context, 'Fachada fotografiada', 'Facade photographed'), Coords.facade(o.cameraHeading, spanish: spanish)),
                _Line(t(context, 'Inclinación', 'Tilt'), '${o.pitch.toStringAsFixed(0)}°${o.flat ? ' · ${t(context, 'teléfono horizontal', 'phone flat')}' : ''}'),
                _Line(t(context, 'Declinación aplicada', 'Declination applied'), '${s.heading.declination >= 0 ? '+' : ''}${s.heading.declination.toStringAsFixed(1)}° (${s.settings.autoDeclination ? 'WMM2025' : t(context, 'manual', 'manual')})${(s.declinationLink?.extrapolated ?? false) ? ' · ${t(context, 'modelo vencido, actualiza la app', 'model expired, update the app')}' : ''}'),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t(context, 'Si el rumbo parece errado, mueve el teléfono dibujando un 8 para calibrar y aléjate de metales e imanes.', 'If the heading looks wrong, move the phone in a figure 8 to calibrate and keep away from metal and magnets.'),
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

  String _statusText(BuildContext context, LocationService loc) {
    switch (loc.status) {
      case 'denied':
        return t(context, 'Sin permiso de ubicación. Actívalo en los ajustes del teléfono.', 'Location permission denied. Enable it in the phone settings.');
      case 'disabled':
        return t(context, 'Ubicación apagada o sin señal.', 'Location off or unavailable.');
      case 'searching':
        return t(context, 'Buscando satélites…', 'Searching for satellites…');
      case 'ok':
        return loc.locked ? t(context, 'Posición fijada manualmente', 'Position locked') : t(context, 'Posición en vivo', 'Live position');
      default:
        return t(context, 'GPS apagado', 'GPS off');
    }
  }

  Future<void> _manual(BuildContext context, LocationService loc) async {
    final Fix? f = loc.fix;
    final TextEditingController lat = TextEditingController(text: f?.latitude.toStringAsFixed(6) ?? '');
    final TextEditingController lon = TextEditingController(text: f?.longitude.toStringAsFixed(6) ?? '');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, 'Posición manual', 'Manual position')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: t(context, 'Latitud (grados decimales)', 'Latitude (decimal degrees)'))),
            TextField(controller: lon, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: t(context, 'Longitud (grados decimales)', 'Longitude (decimal degrees)'))),
            const SizedBox(height: 8),
            Text(t(context, 'Queda fija hasta que la liberes. Útil bajo techo o cuando el GPS no llega.', 'Stays locked until you release it. Useful indoors or without GPS signal.'), style: Theme.of(context).textTheme.bodySmall),
          ],
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
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Copiado', 'Copied')}: $value'), duration: const Duration(seconds: 1)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: <FontFeature>[FontFeature.tabularFigures()]))),
            const Icon(Icons.copy_rounded, size: 16),
          ],
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
          SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
