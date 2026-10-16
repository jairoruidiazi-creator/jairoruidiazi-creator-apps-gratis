import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Datos que viajan al isolate de composición.
class ComposeJob {
  const ComposeJob({
    required this.originalPath,
    required this.outputPath,
    required this.overlayPng,
    required this.overlayWidth,
    required this.overlayHeight,
    required this.quality,
    this.latitude,
    this.longitude,
    this.altitude,
    this.heading,
    this.takenAt,
    this.description = '',
    this.software = 'Sello',
  });

  final String originalPath;
  final String outputPath;

  /// Capa del sello (PNG con transparencia) dibujada a [overlayWidth] px; se
  /// escala al ancho real de la foto ya orientada.
  final Uint8List overlayPng;
  final int overlayWidth;
  final int overlayHeight;
  final int quality;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? heading;
  final DateTime? takenAt;
  final String description;
  final String software;
}

class ComposeResult {
  const ComposeResult({required this.width, required this.height, required this.bytes});

  final int width;
  final int height;
  final int bytes;
}

/// Compone la copia sellada en un isolate: decodifica el JPEG original,
/// aplica la orientación EXIF, superpone el sello escalado al ancho de la
/// foto, escribe los datos en el EXIF (GPS, descripción, fecha) y guarda.
Future<ComposeResult> composeStamped(ComposeJob job) => Isolate.run(() => composeStampedSync(job));

/// Versión síncrona (la usan el isolate y las pruebas).
ComposeResult composeStampedSync(ComposeJob job) {
  final Uint8List original = File(job.originalPath).readAsBytesSync();
  img.Image? photo = img.decodeJpg(original);
  if (photo == null) {
    throw StateError('No se pudo leer la foto');
  }
  photo = img.bakeOrientation(photo);
  final img.Image? overlay = img.decodePng(job.overlayPng);
  if (overlay == null) {
    throw StateError('No se pudo leer el sello');
  }
  // La capa se dibujó con la misma proporción que la foto; se ajusta al ancho real.
  img.Image layer = overlay;
  if (overlay.width != photo.width || overlay.height != photo.height) {
    layer = img.copyResize(overlay, width: photo.width, height: photo.height, interpolation: img.Interpolation.linear);
  }
  img.compositeImage(photo, layer);
  _writeExif(photo, job);
  final Uint8List out = img.encodeJpg(photo, quality: job.quality, chroma: img.JpegChroma.yuv420);
  File(job.outputPath).writeAsBytesSync(out, flush: true);
  return ComposeResult(width: photo.width, height: photo.height, bytes: out.length);
}

void _writeExif(img.Image photo, ComposeJob job) {
  // Las etiquetas se escriben con valores IfdValue explícitos: el paquete
  // `image` solo convierte tipos simples para las etiquetas con tipo
  // declarado, y las de GPS no lo tienen.
  final img.ExifData exif = photo.exif;
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
  final DateTime? t = job.takenAt;
  if (t != null) {
    final String s = '${t.year}:${_two(t.month)}:${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    exif.imageIfd['DateTime'] = img.IfdValueAscii(s);
    exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(s);
    exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(s);
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
    final double? alt = job.altitude;
    if (alt != null && alt.isFinite) {
      gps['GPSAltitudeRef'] = img.IfdByteValue(alt >= 0 ? 0 : 1);
      gps['GPSAltitude'] = img.IfdValueRational((alt.abs() * 100).round(), 100);
    }
    final double? h = job.heading;
    if (h != null && h.isFinite) {
      gps['GPSImgDirectionRef'] = img.IfdValueAscii('T');
      gps['GPSImgDirection'] = img.IfdValueRational(((h % 360) * 100).round(), 100);
    }
    if (t != null) {
      final DateTime u = t.toUtc();
      gps['GPSDateStamp'] = img.IfdValueAscii('${u.year}:${_two(u.month)}:${_two(u.day)}');
      gps['GPSTimeStamp'] = img.IfdValueRational.list(<img.Rational>[img.Rational(u.hour, 1), img.Rational(u.minute, 1), img.Rational(u.second, 1)]);
    }
  }
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
  final int d = v.floor();
  final double mFull = (v - d) * 60;
  final int m = mFull.floor();
  final double s = (mFull - m) * 60;
  return img.IfdValueRational.list(<img.Rational>[img.Rational(d, 1), img.Rational(m, 1), img.Rational((s * 10000).round(), 10000)]);
}

String _two(int v) => v.toString().padLeft(2, '0');

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

/// Copia del JPEG sin metadatos (quita los segmentos APP1 Exif/XMP, APP13 y COM),
/// sin recomprimir la imagen. Para compartir sin ubicación.
Uint8List stripMetadata(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return bytes;
  }
  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(<int>[0xFF, 0xD8]);
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
