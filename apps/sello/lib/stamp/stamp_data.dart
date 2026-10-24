import 'dart:convert';

import '../geo/coords.dart';
import '../model/models.dart';

/// Todo lo que el sello puede escribir, ya resuelto.
class StampData {
  const StampData({
    required this.time,
    this.utcOffsetMinutes,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.heading,
    this.headingTrue = true,
    this.pitch,
    this.speed,
    this.address = '',
    this.projectName = '',
    this.fields = const <String, String>{},
    this.fieldLabels = const <String, String>{},
    this.notes = '',
    this.spanish = true,
    this.locked = false,
    this.manual = false,
    this.approximate = false,
    this.averaged = 0,
    this.fixAgeSeconds = 0,
    this.altitudeIsMsl = true,
  });

  /// Datos del sello de una foto guardada (para sellarla o volver a sellarla).
  factory StampData.fromRecord(PhotoRecord p, {Project? project, required bool spanish}) {
    final Map<String, String> labels = <String, String>{};
    for (final String key in p.fields.keys) {
      final String? label = p.labelFor(key, project);
      if (label != null) {
        labels[key] = label;
      }
    }
    return StampData(
      time: p.takenAt,
      utcOffsetMinutes: p.utcOffsetMinutes,
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeIsMsl: p.altitudeReference != 'ellipsoid',
      heading: p.heading,
      headingTrue: p.headingTrue,
      pitch: p.pitch,
      speed: p.speed,
      address: p.address,
      projectName: project?.name ?? '',
      fields: Map<String, String>.from(p.fields),
      fieldLabels: labels,
      notes: p.notes,
      spanish: spanish,
      locked: p.positionSource == PositionSource.locked || p.positionSource == PositionSource.averaged,
      manual: p.positionSource == PositionSource.manual,
      approximate: p.approximateLocation,
      averaged: p.averagedSamples,
      fixAgeSeconds: p.fixAgeSeconds,
    );
  }

  /// Instante de la foto. Con [utcOffsetMinutes] se muestra en esa zona
  /// horaria; sin él, en la de [time].
  final DateTime time;
  final int? utcOffsetMinutes;
  final double? latitude;
  final double? longitude;

  /// Radio de error horizontal (m); null si no se midió (posición manual).
  final double? accuracy;
  final double? altitude;
  final double? heading;

  /// Falso si el rumbo es magnético (sin declinación conocida).
  final bool headingTrue;
  final double? pitch;
  final double? speed;
  final String address;
  final String projectName;
  final Map<String, String> fields;
  final Map<String, String> fieldLabels;
  final String notes;
  final bool spanish;

  /// Posición fijada (bloqueada o promediada).
  final bool locked;

  /// Coordenadas escritas a mano.
  final bool manual;

  /// Ubicación aproximada (permiso del sistema): se marca y las coordenadas
  /// van sin detalle que aparente precisión.
  final bool approximate;
  final int averaged;

  /// Antigüedad de la lectura del GPS al tomar la foto (segundos).
  final int fixAgeSeconds;

  /// Verdadero si [altitude] es sobre el nivel del mar; falso si es elipsoidal.
  final bool altitudeIsMsl;

  bool get hasLocation => latitude != null && longitude != null;

  /// Hora local de la foto (para formatear).
  DateTime get wall => utcOffsetMinutes == null ? time : wallClock(time, utcOffsetMinutes!);

  String get offsetLabel => utcOffsetMinutes == null ? utcOffsetLabel(time) : formatUtcOffset(utcOffsetMinutes!);

  /// La lectura del GPS era vieja (más de 30 s) y no estaba fijada a propósito.
  bool get staleFix => !locked && !manual && fixAgeSeconds > 30;

  /// Líneas de texto del sello según la plantilla, en orden.
  List<StampLine> lines(StampTemplate t) {
    final List<StampLine> out = <StampLine>[];
    String label(String es, String en) => t.showLabels ? '${spanish ? es : en}: ' : '';
    final bool colombia = hasLocation && Coords.inColombia(latitude!, longitude!);
    for (final StampItem item in StampItem.values) {
      if (!t.items.contains(item)) {
        continue;
      }
      switch (item) {
        case StampItem.dateTime:
          out.add(StampLine(item, '${formatDate(wall, t.dateFormat, spanish: spanish)} $offsetLabel', strong: true));
          break;
        case StampItem.utc:
          out.add(StampLine(item, '${label('UTC', 'UTC')}${formatDate(time.toUtc(), 'yyyy-MM-dd HH:mm:ss')}Z'));
          break;
        case StampItem.coords:
          if (hasLocation) {
            final String l = _coordLabel(t.coordFormat, colombia);
            out.add(StampLine(item, '${label(l, l)}${Coords.format(t.coordFormat, latitude!, longitude!, coarse: approximate)}${_positionNote()}'));
          } else {
            out.add(StampLine(item, spanish ? 'Sin señal GPS' : 'No GPS fix'));
          }
          break;
        case StampItem.coords2:
          if (hasLocation && t.coordFormat2 != t.coordFormat) {
            final String l = _coordLabel(t.coordFormat2, colombia);
            out.add(StampLine(item, '${label(l, l)}${Coords.format(t.coordFormat2, latitude!, longitude!, coarse: approximate)}'));
          }
          break;
        case StampItem.altitude:
          if (altitude != null && hasLocation && !manual) {
            out.add(StampLine(item, '${label('Alt.', 'Alt.')}${altitude!.toStringAsFixed(0)} m ${altitudeIsMsl ? (spanish ? 's. n. m.' : 'MSL') : (spanish ? 'elip.' : 'ellips.')}'));
          }
          break;
        case StampItem.accuracy:
          if (accuracy != null && hasLocation && !manual) {
            final String avg = averaged > 1 ? (spanish ? ' · promedio de $averaged' : ' · avg of $averaged') : '';
            out.add(StampLine(item, '${label('Precisión', 'Accuracy')}± ${accuracy!.toStringAsFixed(accuracy! < 10 ? 1 : 0)} m$avg'));
          }
          break;
        case StampItem.heading:
          if (heading != null) {
            final String magnetic = headingTrue ? '' : (spanish ? ' (magnético)' : ' (magnetic)');
            out.add(StampLine(item, '${label('Rumbo', 'Heading')}${heading!.toStringAsFixed(0)}° ${Coords.cardinal(heading!, spanish: spanish)}$magnetic${pitch != null ? ' · ${label('incl.', 'tilt')}${pitch!.toStringAsFixed(0)}°' : ''}'));
          }
          break;
        case StampItem.facade:
          if (heading != null) {
            final String magnetic = headingTrue ? '' : (spanish ? ' (magnética)' : ' (magnetic)');
            out.add(StampLine(item, '${label('Fachada', 'Facade')}${Coords.facade(heading!, spanish: spanish)}$magnetic'));
          }
          break;
        case StampItem.speed:
          if (speed != null && speed! > 0.5 && !locked && !manual) {
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
            final String? fieldLabel = fieldLabels[e.key];
            // Sin rótulo conocido no se escribe: la clave interna no dice nada.
            if (e.value.trim().isNotEmpty && fieldLabel != null && fieldLabel.trim().isNotEmpty) {
              out.add(StampLine(item, '$fieldLabel: ${e.value.trim()}'));
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

  String _positionNote() {
    if (manual) {
      return spanish ? ' (posición manual)' : ' (manual position)';
    }
    if (approximate) {
      // Las dos señales a la vez: aproximada y, si es vieja, de cuándo.
      if (staleFix) {
        return spanish ? ' (ubicación aproximada, lectura de ${_age(fixAgeSeconds, true)})' : ' (approximate location, reading from ${_age(fixAgeSeconds, false)})';
      }
      return spanish ? ' (ubicación aproximada)' : ' (approximate location)';
    }
    if (locked) {
      return spanish ? ' (fija)' : ' (locked)';
    }
    if (staleFix) {
      return spanish ? ' (lectura de ${_age(fixAgeSeconds, true)})' : ' (reading from ${_age(fixAgeSeconds, false)})';
    }
    return '';
  }

  static String _age(int seconds, bool spanish) {
    if (seconds < 90) {
      return spanish ? 'hace $seconds s' : '$seconds s ago';
    }
    final int minutes = (seconds / 60).round();
    if (minutes < 90) {
      return spanish ? 'hace $minutes min' : '$minutes min ago';
    }
    final int hours = (minutes / 60).round();
    return spanish ? 'hace $hours h' : '$hours h ago';
  }

  /// Rótulo del formato. Los formatos colombianos solo se rotulan como
  /// tales dentro de Colombia: afuera se escriben en grados y dicen "GPS".
  static String _coordLabel(CoordFormat f, bool inColombia) {
    switch (f) {
      case CoordFormat.dd:
      case CoordFormat.dms:
      case CoordFormat.ddm:
        return 'GPS';
      case CoordFormat.utm:
        return 'UTM';
      case CoordFormat.mgrs:
        return 'MGRS';
      case CoordFormat.plusCode:
        return 'Plus Code';
      case CoordFormat.ctm12:
        return inColombia ? 'CTM12' : 'GPS';
      case CoordFormat.magna:
        return inColombia ? 'MAGNA' : 'GPS';
    }
  }

  /// Texto plano con todos los datos (para EXIF, CSV y compartir).
  String summary(StampTemplate t) => lines(t).map((StampLine l) => l.text).join(' | ');

  /// Con la plantilla [t], el sello de [other] se ve igual que este: mismas
  /// líneas y la rosa de los vientos en el mismo grado. La vista previa solo
  /// se vuelve a dibujar cuando algo cambia de verdad.
  bool sameLookAs(StampData other, StampTemplate t) {
    if (heading?.round() != other.heading?.round()) {
      return false;
    }
    final List<StampLine> a = lines(t);
    final List<StampLine> b = other.lines(t);
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text || a[i].strong != b[i].strong) {
        return false;
      }
    }
    return true;
  }
}

class StampLine {
  const StampLine(this.item, this.text, {this.strong = false});

  final StampItem item;
  final String text;
  final bool strong;
}

/// Largo máximo, en bytes UTF-8, de la parte del nombre de archivo que sale
/// de la plantilla. Al nombre se le suman el id de la foto, "-orig.jpg" y
/// los sufijos de los temporales (unos 50 bytes); los sistemas de archivos
/// de Android e iOS admiten 255 bytes por nombre.
const int kMaxFileBaseBytes = 120;

/// Largo máximo del nombre del proyecto dentro del nombre de archivo: así la
/// fecha, la hora y el número caben aunque el contrato tenga un nombre largo.
const int kMaxFileProjectBytes = 60;

/// Recorta [s] a [maxBytes] bytes UTF-8 sin partir una letra y sin dejar
/// guiones sueltos al final.
String truncateUtf8(String s, int maxBytes) {
  if (utf8.encode(s).length <= maxBytes) {
    return s;
  }
  final StringBuffer b = StringBuffer();
  int used = 0;
  for (final int rune in s.runes) {
    final int size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > maxBytes) {
      break;
    }
    b.writeCharCode(rune);
    used += size;
  }
  return b.toString().replaceAll(RegExp(r'[_\-]+$'), '');
}

/// Nombre de archivo según la plantilla del proyecto.
String buildFileName(String pattern, {required String project, required DateTime time, double? lat, double? lon, required int n, bool approximate = false}) {
  String clean(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚáéíóúÑñ_\-]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  String two(int v) => v.toString().padLeft(2, '0');
  final String out = pattern
      .replaceAll('{proyecto}', truncateUtf8(clean(project.isEmpty ? 'foto' : project), kMaxFileProjectBytes))
      .replaceAll('{project}', truncateUtf8(clean(project.isEmpty ? 'photo' : project), kMaxFileProjectBytes))
      .replaceAll('{fecha}', '${time.year}${two(time.month)}${two(time.day)}')
      .replaceAll('{date}', '${time.year}${two(time.month)}${two(time.day)}')
      .replaceAll('{hora}', '${two(time.hour)}${two(time.minute)}${two(time.second)}')
      .replaceAll('{time}', '${two(time.hour)}${two(time.minute)}${two(time.second)}')
      .replaceAll('{lat}', lat == null ? 'x' : lat.toStringAsFixed(approximate ? 2 : 5))
      .replaceAll('{lon}', lon == null ? 'x' : lon.toStringAsFixed(approximate ? 2 : 5))
      .replaceAll('{n}', n.toString().padLeft(4, '0'));
  final String c = truncateUtf8(clean(out.replaceAll('.', 'p')), kMaxFileBaseBytes);
  return c.isEmpty ? 'foto_$n' : c;
}
