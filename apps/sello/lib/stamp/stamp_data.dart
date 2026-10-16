import '../geo/coords.dart';
import '../model/models.dart';

/// Todo lo que el sello puede escribir, ya resuelto.
class StampData {
  const StampData({
    required this.time,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.heading,
    this.pitch,
    this.speed,
    this.address = '',
    this.projectName = '',
    this.fields = const <String, String>{},
    this.fieldLabels = const <String, String>{},
    this.notes = '',
    this.spanish = true,
    this.locked = false,
    this.averaged = 0,
    this.altitudeIsMsl = true,
  });

  final DateTime time;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? altitude;
  final double? heading;
  final double? pitch;
  final double? speed;
  final String address;
  final String projectName;
  final Map<String, String> fields;
  final Map<String, String> fieldLabels;
  final String notes;
  final bool spanish;
  final bool locked;
  final int averaged;

  /// Verdadero si [altitude] es sobre el nivel del mar; falso si es elipsoidal.
  final bool altitudeIsMsl;

  bool get hasLocation => latitude != null && longitude != null;

  /// Líneas de texto del sello según la plantilla, en orden.
  List<StampLine> lines(StampTemplate t) {
    final List<StampLine> out = <StampLine>[];
    String label(String es, String en) => t.showLabels ? '${spanish ? es : en}: ' : '';
    for (final StampItem item in StampItem.values) {
      if (!t.items.contains(item)) {
        continue;
      }
      switch (item) {
        case StampItem.dateTime:
          out.add(StampLine(item, '${formatDate(time, t.dateFormat, spanish: spanish)} ${utcOffsetLabel(time)}', strong: true));
          break;
        case StampItem.utc:
          out.add(StampLine(item, '${label('UTC', 'UTC')}${formatDate(time.toUtc(), 'yyyy-MM-dd HH:mm:ss')}Z'));
          break;
        case StampItem.coords:
          if (hasLocation) {
            out.add(StampLine(item, '${label(_coordLabel(t.coordFormat), _coordLabel(t.coordFormat))}${Coords.format(t.coordFormat, latitude!, longitude!)}${locked ? (spanish ? ' (fija)' : ' (locked)') : ''}'));
          } else {
            out.add(StampLine(item, spanish ? 'Sin señal GPS' : 'No GPS fix'));
          }
          break;
        case StampItem.coords2:
          if (hasLocation && t.coordFormat2 != t.coordFormat) {
            out.add(StampLine(item, '${label(_coordLabel(t.coordFormat2), _coordLabel(t.coordFormat2))}${Coords.format(t.coordFormat2, latitude!, longitude!)}'));
          }
          break;
        case StampItem.altitude:
          if (altitude != null && hasLocation) {
            out.add(StampLine(item, '${label('Alt.', 'Alt.')}${altitude!.toStringAsFixed(0)} m ${altitudeIsMsl ? (spanish ? 's. n. m.' : 'MSL') : (spanish ? 'elip.' : 'ellips.')}'));
          }
          break;
        case StampItem.accuracy:
          if (accuracy != null && hasLocation) {
            final String avg = averaged > 1 ? (spanish ? ' · promedio de $averaged' : ' · avg of $averaged') : '';
            out.add(StampLine(item, '${label('Precisión', 'Accuracy')}± ${accuracy!.toStringAsFixed(accuracy! < 10 ? 1 : 0)} m$avg'));
          }
          break;
        case StampItem.heading:
          if (heading != null) {
            out.add(StampLine(item, '${label('Rumbo', 'Heading')}${heading!.toStringAsFixed(0)}° ${Coords.cardinal(heading!, spanish: spanish)}${pitch != null ? ' · ${label('incl.', 'tilt')}${pitch!.toStringAsFixed(0)}°' : ''}'));
          }
          break;
        case StampItem.facade:
          if (heading != null) {
            out.add(StampLine(item, '${label('Fachada', 'Facade')}${Coords.facade(heading!, spanish: spanish)}'));
          }
          break;
        case StampItem.speed:
          if (speed != null && speed! > 0.5) {
            out.add(StampLine(item, '${label('Velocidad', 'Speed')}${(speed! * 3.6).toStringAsFixed(0)} km/h'));
          }
          break;
        case StampItem.address:
          if (address.isNotEmpty) {
            out.add(StampLine(item, address));
          }
          break;
        case StampItem.project:
          if (projectName.isNotEmpty) {
            out.add(StampLine(item, '${label('Proyecto', 'Project')}$projectName', strong: true));
          }
          break;
        case StampItem.fields:
          for (final MapEntry<String, String> e in fields.entries) {
            if (e.value.trim().isNotEmpty) {
              out.add(StampLine(item, '${fieldLabels[e.key] ?? e.key}: ${e.value}'));
            }
          }
          break;
        case StampItem.notes:
          if (notes.trim().isNotEmpty) {
            out.add(StampLine(item, notes.trim()));
          }
          break;
        case StampItem.compass:
          break; // se dibuja, no se escribe
      }
    }
    return out;
  }

  String _coordLabel(CoordFormat f) {
    switch (f) {
      case CoordFormat.dd:
        return 'GPS';
      case CoordFormat.dms:
        return 'GPS';
      case CoordFormat.ddm:
        return 'GPS';
      case CoordFormat.utm:
        return 'UTM';
      case CoordFormat.mgrs:
        return 'MGRS';
      case CoordFormat.plusCode:
        return 'Plus Code';
      case CoordFormat.ctm12:
        return 'CTM12';
      case CoordFormat.magna:
        return 'MAGNA';
    }
  }

  /// Texto plano con todos los datos (para EXIF, CSV y compartir).
  String summary(StampTemplate t) => lines(t).map((StampLine l) => l.text).join(' | ');
}

class StampLine {
  const StampLine(this.item, this.text, {this.strong = false});

  final StampItem item;
  final String text;
  final bool strong;
}

/// Nombre de archivo según la plantilla del proyecto.
String buildFileName(String pattern, {required String project, required DateTime time, double? lat, double? lon, required int n}) {
  String clean(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚáéíóúÑñ_\-]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  String two(int v) => v.toString().padLeft(2, '0');
  final String out = pattern
      .replaceAll('{proyecto}', clean(project.isEmpty ? 'foto' : project))
      .replaceAll('{project}', clean(project.isEmpty ? 'photo' : project))
      .replaceAll('{fecha}', '${time.year}${two(time.month)}${two(time.day)}')
      .replaceAll('{date}', '${time.year}${two(time.month)}${two(time.day)}')
      .replaceAll('{hora}', '${two(time.hour)}${two(time.minute)}${two(time.second)}')
      .replaceAll('{time}', '${two(time.hour)}${two(time.minute)}${two(time.second)}')
      .replaceAll('{lat}', lat == null ? 'x' : lat.toStringAsFixed(5))
      .replaceAll('{lon}', lon == null ? 'x' : lon.toStringAsFixed(5))
      .replaceAll('{n}', n.toString().padLeft(4, '0'));
  final String c = clean(out.replaceAll('.', 'p'));
  return c.isEmpty ? 'foto_$n' : c;
}
