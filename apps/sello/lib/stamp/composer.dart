import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// La copia sellada se limita a este número de píxeles: las fotos más
/// grandes (sensores de 48–200 MP) se decodifican reducidas a la mitad (o a
/// un cuarto) directamente desde el JPEG, sin pasar por el tamaño completo.
/// El original se conserva con su resolución.
const int kMaxStampedPixels = 26000000;

/// Datos que viajan al isolate de composición.
class ComposeJob {
  const ComposeJob({
    required this.originalPath,
    required this.outputPath,
    required this.quality,
    this.scale = 1,
    this.expectedWidth = 0,
    this.expectedHeight = 0,
    this.overlayPng,
    this.overlayLeft = 0,
    this.overlayTop = 0,
    this.latitude,
    this.longitude,
    this.altitudeMsl,
    this.heading,
    this.headingTrue = true,
    this.accuracy,
    this.positionMethod = '',
    this.takenAt,
    this.utcOffsetMinutes,
    this.description = '',
    this.software = 'Sello',
  });

  final String originalPath;
  final String outputPath;
  final int quality;

  /// Reducción al decodificar (1, 2, 4 u 8; ver [planStamped]).
  final int scale;

  /// Tamaño (ya orientado) para el que se dibujó el sello; 0 si no se sabe.
  final int expectedWidth;
  final int expectedHeight;

  /// Capa del sello (PNG con transparencia) y su posición en la foto.
  final Uint8List? overlayPng;
  final int overlayLeft;
  final int overlayTop;
  final double? latitude;
  final double? longitude;

  /// Altitud sobre el nivel del mar: es la única que el EXIF sabe expresar.
  final double? altitudeMsl;
  final double? heading;

  /// Falso si el rumbo es magnético (GPSImgDirectionRef = M).
  final bool headingTrue;

  /// Radio de error horizontal (m): GPSHPositioningError (EXIF 2.31).
  final double? accuracy;

  /// GPSProcessingMethod: '' (GPS), [kExifApproximate] o [kExifManual].
  /// Marca legible por máquina que el reindexado recupera.
  final String positionMethod;

  /// Instante de la foto y desfase horario del teléfono al tomarla.
  final DateTime? takenAt;
  final int? utcOffsetMinutes;
  final String description;
  final String software;
}

class ComposeResult {
  const ComposeResult({required this.width, required this.height, required this.bytes});

  final int width;
  final int height;
  final int bytes;
}

/// Tamaño que tendrá la copia sellada de un JPEG: orientado según su EXIF y
/// reducido por [scale] si pasa de [maxPixels].
class StampedPlan {
  const StampedPlan({required this.scale, required this.width, required this.height, required this.orientation});

  final int scale;
  final int width;
  final int height;
  final int orientation;
}

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

StampedPlan? planStamped(Uint8List jpeg, {int maxPixels = kMaxStampedPixels}) {
  final JpegDims? d = jpegSize(jpeg);
  if (d == null || d.width <= 0 || d.height <= 0) {
    return null;
  }
  int scale = 1;
  while (scale < 8 && _ceilDiv(d.width, scale) * _ceilDiv(d.height, scale) > maxPixels) {
    scale *= 2;
  }
  int w = _ceilDiv(d.width, scale);
  int h = _ceilDiv(d.height, scale);
  final int orientation = exifOrientation(jpeg);
  if (orientation >= 5) {
    final int tmp = w;
    w = h;
    h = tmp;
  }
  return StampedPlan(scale: scale, width: w, height: h, orientation: orientation);
}

/// Compone la copia sellada en un isolate: decodifica el JPEG original,
/// aplica la orientación EXIF, superpone el sello, escribe los datos en el
/// EXIF (GPS, descripción, fecha) y guarda de forma atómica.
Future<ComposeResult> composeStamped(ComposeJob job) => Isolate.run(() => composeStampedSync(job));

/// Versión síncrona (la usan el isolate y las pruebas).
ComposeResult composeStampedSync(ComposeJob job) {
  final Uint8List original = File(job.originalPath).readAsBytesSync();
  img.Image? decoded = img.decodeJpg(original, scale: job.scale);
  if (decoded == null) {
    throw StateError('No se pudo leer la foto');
  }
  final int orientation = decoded.exif.imageIfd.orientation ?? 1;
  // Con orientación 1 no hace falta copiar la imagen.
  final img.Image photo = orientation == 1 ? decoded : img.bakeOrientation(decoded);
  final img.ExifData cameraExif = decoded.exif;
  decoded = null;
  photo.exif = _stampExif(cameraExif, job, photo.width, photo.height);
  final Uint8List? png = job.overlayPng;
  if (png != null) {
    img.Image? overlay = img.decodePng(png);
    if (overlay == null) {
      throw StateError('No se pudo leer el sello');
    }
    int left = job.overlayLeft;
    int top = job.overlayTop;
    // Si la foto no salió del tamaño previsto, el sello se ajusta en
    // proporción (no debería pasar; es una salvaguarda).
    if (job.expectedWidth > 0 && job.expectedHeight > 0 && (photo.width != job.expectedWidth || photo.height != job.expectedHeight)) {
      final double fx = photo.width / job.expectedWidth;
      final double fy = photo.height / job.expectedHeight;
      overlay = img.copyResize(overlay, width: (overlay.width * fx).round().clamp(1, photo.width), height: (overlay.height * fy).round().clamp(1, photo.height), interpolation: img.Interpolation.linear);
      left = (left * fx).round();
      top = (top * fy).round();
    }
    img.compositeImage(photo, overlay, dstX: left, dstY: top);
  }
  final Uint8List out = img.encodeJpg(photo, quality: job.quality, chroma: img.JpegChroma.yuv420);
  final File target = File(job.outputPath);
  final File tmp = File('${job.outputPath}.tmp-compose');
  tmp.writeAsBytesSync(out, flush: true);
  tmp.renameSync(target.path);
  return ComposeResult(width: photo.width, height: photo.height, bytes: out.length);
}

/// Etiquetas de la cámara que se conservan (exposición y equipo). Todo lo
/// demás del EXIF de la cámara se descarta, en especial la miniatura (IFD1),
/// que mostraría la foto sin sello.
const List<int> _cameraImageTags = <int>[0x010F, 0x0110]; // Make, Model
const List<int> _cameraExifTags = <int>[
  0x829A, // ExposureTime
  0x829D, // FNumber
  0x8822, // ExposureProgram
  0x8827, // ISO
  0x9204, // ExposureBiasValue
  0x9207, // MeteringMode
  0x9209, // Flash
  0x920A, // FocalLength
  0xA403, // WhiteBalance
  0xA405, // FocalLengthIn35mmFilm
  0xA433, // LensMake
  0xA434, // LensModel
];

img.ExifData _stampExif(img.ExifData camera, ComposeJob job, int width, int height) {
  // Las etiquetas se escriben con valores IfdValue explícitos: el paquete
  // `image` solo convierte tipos simples para las etiquetas con tipo
  // declarado, y las de GPS no lo tienen.
  final img.ExifData exif = img.ExifData();
  for (final int tag in _cameraImageTags) {
    final img.IfdValue? v = camera.imageIfd[tag];
    if (v != null) {
      exif.imageIfd[tag] = v.clone();
    }
  }
  for (final int tag in _cameraExifTags) {
    final img.IfdValue? v = camera.exifIfd[tag];
    if (v != null) {
      exif.exifIfd[tag] = v.clone();
    }
  }
  // Etiquetas que EXIF exige en un JPEG (las pide `exiftool -validate`):
  // versión 2.32 (GPSHPositioningError y OffsetTime son de 2.31), sRGB,
  // componentes Y Cb Cr, tamaño en píxeles de la foto sellada y 72 ppp.
  exif.imageIfd[0x011A] = img.IfdValueRational(72, 1); // XResolution
  exif.imageIfd[0x011B] = img.IfdValueRational(72, 1); // YResolution
  exif.imageIfd[0x0128] = img.IfdValueShort(2); // ResolutionUnit: pulgadas
  exif.imageIfd[0x0213] = img.IfdValueShort(1); // YCbCrPositioning: centrado
  exif.exifIfd[0x9000] = img.IfdValueUndefined.list(Uint8List.fromList(ascii.encode('0232'))); // ExifVersion
  exif.exifIfd[0x9101] = img.IfdValueUndefined.list(Uint8List.fromList(<int>[1, 2, 3, 0])); // ComponentsConfiguration
  exif.exifIfd[0xA000] = img.IfdValueUndefined.list(Uint8List.fromList(ascii.encode('0100'))); // FlashpixVersion
  exif.exifIfd[0xA001] = img.IfdValueShort(1); // ColorSpace: sRGB
  exif.exifIfd[0xA002] = img.IfdValueLong(width); // PixelXDimension
  exif.exifIfd[0xA003] = img.IfdValueLong(height); // PixelYDimension
  exif.imageIfd['Software'] = img.IfdValueAscii(job.software);
  if (job.description.isNotEmpty) {
    // ImageDescription en UTF-8 (es lo que leen Android, Lightroom y
    // exiftool); UserComment con juego de caracteres sin definir y UTF-8;
    // XPTitle/XPComment en UTF-16 para el Explorador de Windows.
    exif.imageIfd['ImageDescription'] = img.IfdValueAscii(String.fromCharCodes(utf8.encode(job.description)));
    exif.exifIfd['UserComment'] = img.IfdValueUndefined.list(Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 0, ...utf8.encode(job.description)]));
    exif.imageIfd['XPTitle'] = img.IfdByteValue.list(_utf16le(job.software));
    exif.imageIfd['XPComment'] = img.IfdByteValue.list(_utf16le(job.description));
  }
  final DateTime? taken = job.takenAt;
  if (taken != null) {
    // Hora local de la foto (en su zona) y su desfase (EXIF 2.31).
    final int offset = job.utcOffsetMinutes ?? taken.timeZoneOffset.inMinutes;
    final DateTime t = taken.toUtc().add(Duration(minutes: offset));
    final String s = '${t.year}:${_two(t.month)}:${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    exif.imageIfd['DateTime'] = img.IfdValueAscii(s);
    exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(s);
    exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(s);
    final String o = '${offset < 0 ? '-' : '+'}${_two(offset.abs() ~/ 60)}:${_two(offset.abs() % 60)}';
    exif.exifIfd[0x9010] = img.IfdValueAscii(o); // OffsetTime
    exif.exifIfd[0x9011] = img.IfdValueAscii(o); // OffsetTimeOriginal
    exif.exifIfd[0x9012] = img.IfdValueAscii(o); // OffsetTimeDigitized
  }
  final double? lat = job.latitude;
  final double? lon = job.longitude;
  if (lat != null && lon != null) {
    final img.IfdDirectory gps = exif.gpsIfd;
    gps['GPSVersionID'] = img.IfdByteValue.list(Uint8List.fromList(<int>[2, 3, 0, 0]));
    gps['GPSLatitudeRef'] = img.IfdValueAscii(lat >= 0 ? 'N' : 'S');
    gps['GPSLatitude'] = _dmsRational(lat.abs());
    gps['GPSLongitudeRef'] = img.IfdValueAscii(lon >= 0 ? 'E' : 'W');
    gps['GPSLongitude'] = _dmsRational(lon.abs());
    final double? alt = job.altitudeMsl;
    if (alt != null && alt.isFinite) {
      // GPSAltitude es altitud respecto al nivel del mar (0 = encima, 1 = debajo).
      gps['GPSAltitudeRef'] = img.IfdByteValue(alt >= 0 ? 0 : 1);
      gps['GPSAltitude'] = img.IfdValueRational((alt.abs() * 100).round(), 100);
    }
    final double? acc = job.accuracy;
    if (acc != null && acc.isFinite && acc >= 0) {
      gps[0x001F] = img.IfdValueRational((acc * 100).round(), 100); // GPSHPositioningError
    }
    if (job.positionMethod.isNotEmpty) {
      // UNDEFINED con el prefijo de juego de caracteres "ASCII\0\0\0".
      gps[0x001B] = img.IfdValueUndefined.list(Uint8List.fromList(<int>[...ascii.encode('ASCII'), 0, 0, 0, ...ascii.encode(job.positionMethod)])); // GPSProcessingMethod
    }
    final double? h = job.heading;
    if (h != null && h.isFinite) {
      gps['GPSImgDirectionRef'] = img.IfdValueAscii(job.headingTrue ? 'T' : 'M');
      gps['GPSImgDirection'] = img.IfdValueRational(((h % 360) * 100).round(), 100);
    }
    if (taken != null) {
      final DateTime u = taken.toUtc();
      // GPSDateStamp por número: el paquete `image` la llama «GPSDate» y con
      // el nombre «GPSDateStamp» no se escribía.
      gps[0x001D] = img.IfdValueAscii('${u.year}:${_two(u.month)}:${_two(u.day)}');
      gps['GPSTimeStamp'] = _rationals(<List<int>>[<int>[u.hour, 1], <int>[u.minute, 1], <int>[u.second, 1]]);
    }
  }
  _sortTags(exif);
  return exif;
}

Uint8List _utf16le(String text) {
  final List<int> out = <int>[];
  for (final int unit in text.codeUnits) {
    out.add(unit & 0xFF);
    out.add((unit >> 8) & 0xFF);
  }
  out.addAll(<int>[0, 0]);
  return Uint8List.fromList(out);
}

img.IfdValueRational _dmsRational(double v) {
  final List<int> p = exifDms(v);
  return _rationals(<List<int>>[<int>[p[0], 1], <int>[p[1], 1], <int>[p[2], 10000]]);
}

/// Grados, minutos y diezmilésimas de segundo (sin signo) de un ángulo para
/// el EXIF. Se redondea una sola vez, en diezmilésimas de segundo, y de ahí
/// salen los minutos y los grados: así 4,6° da 4°36'0" y nunca 4°35'60".
List<int> exifDms(double v) {
  final int total = (v.abs() * 36000000).round();
  return <int>[total ~/ 36000000, total % 36000000 ~/ 600000, total % 600000];
}

/// Pone las etiquetas de cada directorio en orden ascendente, como piden
/// TIFF 6.0 y EXIF (el paquete `image` las escribe en el orden en que se
/// insertaron). Los punteros a los subdirectorios EXIF y GPS se reservan aquí
/// para que también queden en su sitio: al escribir, el paquete solo les
/// cambia el valor.
void _sortTags(img.ExifData exif) {
  final img.IfdDirectory ifd0 = exif.imageIfd;
  if (ifd0.sub.containsKey('exif')) {
    ifd0.data[0x8769] = img.IfdValueLong(0); // ExifOffset
  }
  if (ifd0.sub.containsKey('gps')) {
    ifd0.data[0x8825] = img.IfdValueLong(0); // GPSInfo
  }
  void sortDir(img.IfdDirectory d) {
    final List<MapEntry<int, img.IfdValue>> entries = d.data.entries.toList()..sort((MapEntry<int, img.IfdValue> a, MapEntry<int, img.IfdValue> b) => a.key.compareTo(b.key));
    d.data
      ..clear()
      ..addEntries(entries);
  }

  sortDir(ifd0);
  for (final String name in ifd0.sub.keys.toList()) {
    sortDir(ifd0.sub[name]);
  }
}

/// Lista de racionales EXIF. El paquete `image` no exporta su clase
/// `Rational`, así que se construye desde los bytes (numerador/denominador
/// de 32 bits, big-endian).
img.IfdValueRational _rationals(List<List<int>> pairs) {
  final ByteData d = ByteData(pairs.length * 8);
  for (int i = 0; i < pairs.length; i++) {
    d.setUint32(i * 8, pairs[i][0]);
    d.setUint32(i * 8 + 4, pairs[i][1]);
  }
  return img.IfdValueRational.data(img.InputBuffer(d.buffer.asUint8List(), bigEndian: true), pairs.length);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Datos que Sello escribió en el EXIF de una foto sellada (para recuperar
/// su ficha si el índice se perdió).
/// GPSProcessingMethod de una posición aproximada (permiso del sistema).
const String kExifApproximate = 'APPROXIMATE';

/// GPSProcessingMethod de una posición escrita a mano.
const String kExifManual = 'MANUAL';

class StampExif {
  const StampExif({this.takenAt, this.utcOffsetMinutes, this.latitude, this.longitude, this.altitudeMsl, this.heading, this.headingTrue = true, this.description = '', this.accuracy, this.positionMethod = ''});

  /// GPSHPositioningError, si se escribió.
  final double? accuracy;

  /// GPSProcessingMethod sin el prefijo de juego de caracteres.
  final String positionMethod;

  bool get approximate => positionMethod == kExifApproximate;
  bool get manual => positionMethod == kExifManual;

  final DateTime? takenAt;
  final int? utcOffsetMinutes;
  final double? latitude;
  final double? longitude;
  final double? altitudeMsl;
  final double? heading;
  final bool headingTrue;
  final String description;
}

StampExif readStampExif(Uint8List jpeg) {
  final img.ExifData? exif = img.decodeJpgExif(jpeg);
  if (exif == null) {
    return const StampExif();
  }
  int? offset;
  final String? o = exif.exifIfd[0x9011]?.toString().trim();
  final RegExpMatch? om = o == null ? null : RegExp(r'^([+-])(\d{2}):(\d{2})').firstMatch(o);
  if (om != null) {
    offset = (int.parse(om.group(2)!) * 60 + int.parse(om.group(3)!)) * (om.group(1) == '-' ? -1 : 1);
  }
  DateTime? taken;
  final String? dt = exif.exifIfd['DateTimeOriginal']?.toString().trim();
  final RegExpMatch? m = dt == null ? null : RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(dt);
  if (m != null) {
    final List<int> v = <int>[for (int i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    taken = offset == null ? DateTime(v[0], v[1], v[2], v[3], v[4], v[5]) : DateTime.utc(v[0], v[1], v[2], v[3], v[4], v[5]).subtract(Duration(minutes: offset));
  }
  double? coord(String valueTag, String refTag, String negative) {
    final img.IfdValue? v = exif.gpsIfd[valueTag];
    if (v == null || v.length < 3) {
      return null;
    }
    final double deg = v.toDouble(0) + v.toDouble(1) / 60 + v.toDouble(2) / 3600;
    return exif.gpsIfd[refTag]?.toString().trim() == negative ? -deg : deg;
  }

  final double? lat = coord('GPSLatitude', 'GPSLatitudeRef', 'S');
  final double? lon = coord('GPSLongitude', 'GPSLongitudeRef', 'W');
  double? alt;
  final img.IfdValue? a = exif.gpsIfd['GPSAltitude'];
  if (a != null) {
    alt = a.toDouble();
    if (exif.gpsIfd['GPSAltitudeRef']?.toInt() == 1) {
      alt = -alt;
    }
  }
  final img.IfdValue? h = exif.gpsIfd['GPSImgDirection'];
  String description = '';
  final img.IfdValue? d = exif.imageIfd['ImageDescription'];
  if (d != null) {
    description = utf8.decode(d.toData(), allowMalformed: true).replaceAll('\u0000', '').trim();
  }
  final img.IfdValue? hpe = exif.gpsIfd[0x001F];
  String method = '';
  final img.IfdValue? pm = exif.gpsIfd[0x001B];
  if (pm != null) {
    final List<int> raw = pm.toData();
    method = String.fromCharCodes(raw.length > 8 ? raw.sublist(8) : raw).replaceAll('\u0000', '').trim();
  }
  return StampExif(
    accuracy: hpe?.toDouble(),
    positionMethod: method,
    takenAt: taken,
    utcOffsetMinutes: offset,
    latitude: lat,
    longitude: lon,
    altitudeMsl: alt,
    heading: h?.toDouble(),
    headingTrue: exif.gpsIfd['GPSImgDirectionRef']?.toString().trim() != 'M',
    description: description,
  );
}

/// Dimensiones de un JPEG.
class JpegDims {
  const JpegDims(this.width, this.height);

  final int width;
  final int height;
}

/// Lee el ancho y alto de un JPEG sin decodificarlo del todo.
JpegDims? jpegSize(Uint8List bytes) {
  final img.JpegDecoder dec = img.JpegDecoder();
  final img.DecodeInfo? info = dec.startDecode(bytes);
  if (info == null) {
    return null;
  }
  return JpegDims(info.width, info.height);
}

/// Lee la etiqueta de orientación EXIF (1 si no hay).
int exifOrientation(Uint8List bytes) {
  try {
    final ByteData d = ByteData.sublistView(bytes);
    int i = 2;
    while (i + 4 < bytes.length) {
      if (bytes[i] != 0xFF) {
        return 1;
      }
      final int marker = bytes[i + 1];
      final int len = d.getUint16(i + 2);
      if (marker == 0xE1 && i + 10 < bytes.length && bytes[i + 4] == 0x45 && bytes[i + 5] == 0x78) {
        final int tiff = i + 10;
        final bool little = bytes[tiff] == 0x49;
        final Endian e = little ? Endian.little : Endian.big;
        final int ifd = tiff + d.getUint32(tiff + 4, e);
        final int count = d.getUint16(ifd, e);
        for (int k = 0; k < count; k++) {
          final int entry = ifd + 2 + k * 12;
          if (d.getUint16(entry, e) == 0x0112) {
            return d.getUint16(entry + 8, e);
          }
        }
        return 1;
      }
      if (marker == 0xDA) {
        return 1;
      }
      i += 2 + len;
    }
  } catch (_) {}
  return 1;
}

/// Segmento APP1 mínimo con solo la etiqueta de orientación.
Uint8List _orientationApp1(int orientation) {
  final BytesBuilder b = BytesBuilder();
  // Marcador y largo (incluye los 2 bytes del largo): 2 + 6 + 8 + 2 + 12 + 4 = 34.
  b.add(<int>[0xFF, 0xE1, 0x00, 34]);
  b.add(<int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00]); // "Exif\0\0"
  b.add(<int>[0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]); // TIFF big-endian, IFD0 en 8
  b.add(<int>[0x00, 0x01]); // una entrada
  b.add(<int>[0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, (orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00]);
  b.add(<int>[0x00, 0x00, 0x00, 0x00]); // sin IFD siguiente
  return b.toBytes();
}

/// Copia del JPEG sin metadatos (quita los segmentos APP1 Exif/XMP, APP13 y
/// COM), sin recomprimir la imagen. Para compartir sin ubicación ni fecha.
/// Si la imagen dependía de la etiqueta de orientación (una original de la
/// cámara), se deja solo esa etiqueta para que no se vea de lado.
Uint8List stripMetadata(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return bytes;
  }
  final int orientation = exifOrientation(bytes);
  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(<int>[0xFF, 0xD8]);
  if (orientation > 1 && orientation <= 8) {
    out.add(_orientationApp1(orientation));
  }
  int i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) {
      break;
    }
    final int marker = bytes[i + 1];
    if (marker == 0xDA) {
      // Inicio de los datos comprimidos: el resto se copia tal cual.
      out.add(Uint8List.sublistView(bytes, i));
      return out.toBytes();
    }
    final int len = (bytes[i + 2] << 8) | bytes[i + 3];
    final int end = i + 2 + len;
    if (end > bytes.length) {
      break;
    }
    final bool drop = marker == 0xE1 || marker == 0xED || marker == 0xFE; // Exif/XMP, Photoshop/IPTC, comentarios (el perfil de color APP2 se conserva)
    if (!drop) {
      out.add(Uint8List.sublistView(bytes, i, end));
    }
    i = end;
  }
  out.add(Uint8List.sublistView(bytes, i));
  return out.toBytes();
}
