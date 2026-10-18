import 'dart:math' as math;

import '../geo/coords.dart';

int _idCounter = 0;
final math.Random _idRandom = math.Random();

/// Identificador único: microsegundos reales + contador + azar (dos llamadas
/// en el mismo microsegundo no chocan).
String newId() {
  _idCounter = (_idCounter + 1) % 1679616; // 36^4
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter.toRadixString(36).padLeft(4, '0')}${_idRandom.nextInt(46656).toRadixString(36)}';
}

/// Posición del sello dentro de la foto.
enum StampPosition { bottomLeft, bottomRight, topLeft, topRight, bottomBar }

/// Elementos que puede llevar el sello, en el orden en que se dibujan.
enum StampItem { dateTime, utc, coords, coords2, altitude, accuracy, heading, facade, speed, address, project, fields, notes, compass }

/// Plantilla de sello: qué se muestra y cómo.
class StampTemplate {
  StampTemplate({
    required this.id,
    required this.name,
    Set<StampItem>? items,
    this.position = StampPosition.bottomLeft,
    this.coordFormat = CoordFormat.dd,
    this.coordFormat2 = CoordFormat.utm,
    this.dateFormat = 'dd/MM/yyyy HH:mm:ss',
    this.textScale = 1.0,
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0xFF000000,
    this.backgroundOpacity = 0.55,
    this.logoPath,
    this.logoScale = 1.0,
    this.logoOpacity = 1.0,
    this.logoPosition = StampPosition.topRight,
    this.showLabels = true,
  }) : items = items ?? <StampItem>{StampItem.dateTime, StampItem.coords, StampItem.altitude, StampItem.accuracy, StampItem.heading, StampItem.address, StampItem.project, StampItem.notes};

  final String id;
  String name;
  Set<StampItem> items;
  StampPosition position;
  CoordFormat coordFormat;
  CoordFormat coordFormat2;
  String dateFormat;
  double textScale;
  int textColor;
  int backgroundColor;
  double backgroundOpacity;
  String? logoPath;
  double logoScale;
  double logoOpacity;
  StampPosition logoPosition;
  bool showLabels;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'items': items.map((StampItem i) => i.name).toList(),
        'position': position.name,
        'coordFormat': coordFormat.name,
        'coordFormat2': coordFormat2.name,
        'dateFormat': dateFormat,
        'textScale': textScale,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
        'backgroundOpacity': backgroundOpacity,
        'logoPath': logoPath,
        'logoScale': logoScale,
        'logoOpacity': logoOpacity,
        'logoPosition': logoPosition.name,
        'showLabels': showLabels,
      };

  static StampTemplate fromJson(Map<String, dynamic> j) => StampTemplate(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        items: ((j['items'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic n) => StampItem.values.where((StampItem i) => i.name == n).firstOrNull).whereType<StampItem>().toSet(),
        position: StampPosition.values.firstWhere((StampPosition p) => p.name == j['position'], orElse: () => StampPosition.bottomLeft),
        coordFormat: CoordFormat.values.firstWhere((CoordFormat f) => f.name == j['coordFormat'], orElse: () => CoordFormat.dd),
        coordFormat2: CoordFormat.values.firstWhere((CoordFormat f) => f.name == j['coordFormat2'], orElse: () => CoordFormat.utm),
        dateFormat: j['dateFormat'] as String? ?? 'dd/MM/yyyy HH:mm:ss',
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
        textColor: (j['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        backgroundColor: (j['backgroundColor'] as num?)?.toInt() ?? 0xFF000000,
        backgroundOpacity: (j['backgroundOpacity'] as num?)?.toDouble() ?? 0.55,
        logoPath: j['logoPath'] as String?,
        logoScale: (j['logoScale'] as num?)?.toDouble() ?? 1.0,
        logoOpacity: (j['logoOpacity'] as num?)?.toDouble() ?? 1.0,
        logoPosition: StampPosition.values.firstWhere((StampPosition p) => p.name == j['logoPosition'], orElse: () => StampPosition.topRight),
        showLabels: j['showLabels'] as bool? ?? true,
      );

  static StampTemplate defaultTemplate() => StampTemplate(id: 'default', name: 'Estándar');

  /// Nombre visible. La plantilla de fábrica sigue el idioma de la app
  /// mientras el usuario no la renombre.
  String displayName({required bool spanish}) {
    if (id == 'default' && (name == 'Estándar' || name == 'Standard')) {
      return spanish ? 'Estándar' : 'Standard';
    }
    return name;
  }
}

/// Campo personalizado de un proyecto (por ejemplo "Lote", "Inspector").
/// La clave es interna; lo que ve el usuario (y lo que va a las
/// exportaciones) es el rótulo.
class FieldDef {
  const FieldDef(this.key, this.label, {this.defaultValue = ''});

  final String key;
  final String label;
  final String defaultValue;

  Map<String, dynamic> toJson() => <String, dynamic>{'key': key, 'label': label, 'default': defaultValue};

  static FieldDef fromJson(Map<String, dynamic> j) => FieldDef(j['key'] as String? ?? newId(), j['label'] as String? ?? '', defaultValue: j['default'] as String? ?? '');
}

/// Proyecto: agrupa fotos, define campos y la plantilla del sello.
class Project {
  Project({required this.id, required this.name, List<FieldDef>? fields, this.templateId = 'default', this.notes = '', this.fileNamePattern = '{proyecto}_{fecha}_{hora}', this.emoji = ''}) : fields = fields ?? <FieldDef>[];

  final String id;
  String name;
  final List<FieldDef> fields;
  String templateId;
  String notes;

  /// Plantilla del nombre de archivo: {proyecto} {fecha} {hora} {lat} {lon} {n}.
  String fileNamePattern;
  String emoji;

  /// Rótulo de un campo por su clave, o null si el proyecto ya no lo tiene.
  String? labelOf(String key) {
    for (final FieldDef f in fields) {
      if (f.key == key) {
        return f.label;
      }
    }
    return null;
  }

  /// Copia independiente (para editar sin tocar el proyecto vivo).
  Project copy() => Project.fromJson(toJson());

  /// Toma los valores editables de [other] (mismo id).
  void assignFrom(Project other) {
    name = other.name;
    fields
      ..clear()
      ..addAll(other.fields);
    templateId = other.templateId;
    notes = other.notes;
    fileNamePattern = other.fileNamePattern;
    emoji = other.emoji;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'fields': fields.map((FieldDef f) => f.toJson()).toList(),
        'templateId': templateId,
        'notes': notes,
        'fileNamePattern': fileNamePattern,
        'emoji': emoji,
      };

  static Project fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        fields: ((j['fields'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(FieldDef.fromJson).toList(),
        templateId: j['templateId'] as String? ?? 'default',
        notes: j['notes'] as String? ?? '',
        fileNamePattern: j['fileNamePattern'] as String? ?? '{proyecto}_{fecha}_{hora}',
        emoji: j['emoji'] as String? ?? '',
      );
}

/// Estado de la copia sellada de una foto.
enum PhotoStatus {
  /// Sellada y guardada.
  ok,

  /// Guardada (el original y sus datos) y en la cola de sellado.
  pending,

  /// El sellado falló: queda el original y se puede reintentar.
  failed,
}

/// De dónde salió la posición de una foto.
enum PositionSource {
  /// Lectura del GPS en ese momento.
  gps,

  /// Posición fijada a mano desde una lectura anterior (interiores).
  locked,

  /// Promedio de varias lecturas, fijado al terminar.
  averaged,

  /// Coordenadas escritas a mano: sin precisión ni altitud.
  manual,
}

/// Una foto tomada con la app: original, copia sellada y todos sus datos.
class PhotoRecord {
  PhotoRecord({
    required this.id,
    required this.projectId,
    required this.originalFile,
    required this.stampedFile,
    required DateTime takenAt,
    int? utcOffsetMinutes,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeReference = 'msl',
    this.altitudeMsl,
    this.heading,
    this.headingTrue = true,
    this.pitch,
    this.speed,
    this.positionSource = PositionSource.gps,
    this.averagedSamples = 0,
    this.fixAgeSeconds = 0,
    this.address = '',
    Map<String, String>? fields,
    Map<String, String>? fieldLabels,
    this.notes = '',
    List<String>? tags,
    this.description = '',
    this.width = 0,
    this.height = 0,
    this.status = PhotoStatus.ok,
    this.error = '',
    this.templateId,
    this.frontCamera = false,
    this.version = 0,
  })  : takenAt = takenAt.toUtc(),
        utcOffsetMinutes = utcOffsetMinutes ?? takenAt.timeZoneOffset.inMinutes,
        fields = fields ?? <String, String>{},
        fieldLabels = fieldLabels ?? <String, String>{},
        tags = tags ?? <String>[];

  final String id;
  String projectId;
  final String originalFile;
  String stampedFile;

  /// Instante de la foto, en UTC.
  final DateTime takenAt;

  /// Desfase horario del teléfono al tomarla (minutos). Con él la hora local
  /// de la foto no cambia aunque el teléfono cambie de zona horaria.
  final int utcOffsetMinutes;
  final double? latitude;
  final double? longitude;

  /// Radio de error horizontal (m); null si la posición se escribió a mano.
  final double? accuracy;

  /// Altitud en la referencia [altitudeReference] (la que se eligió para el sello).
  final double? altitude;

  /// 'msl' (nivel del mar) o 'ellipsoid'.
  final String altitudeReference;

  /// Altitud sobre el nivel del mar (EGM96), la que va al EXIF.
  final double? altitudeMsl;
  final double? heading;

  /// Verdadero si el rumbo es respecto al norte verdadero; falso si es
  /// magnético (sin GPS no se conoce la declinación).
  final bool headingTrue;
  final double? pitch;
  final double? speed;
  final PositionSource positionSource;
  final int averagedSamples;

  /// Antigüedad de la lectura del GPS al tomar la foto (segundos).
  final int fixAgeSeconds;
  String address;

  /// Valores de los campos del proyecto, por clave interna.
  final Map<String, String> fields;

  /// Rótulo de cada campo al tomar la foto (por clave).
  final Map<String, String> fieldLabels;
  String notes;
  final List<String> tags;
  String description;
  int width;
  int height;
  PhotoStatus status;

  /// Motivo del último fallo de sellado (vacío si no hay).
  String error;

  /// Plantilla con la que se selló o se va a sellar.
  String? templateId;

  /// Tomada con la cámara frontal.
  final bool frontCamera;

  /// Sube cada vez que la copia sellada cambia (para refrescar miniaturas).
  int version;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isPending => status == PhotoStatus.pending;

  bool get isFailed => status == PhotoStatus.failed;

  /// Hora local de la foto (en la zona horaria en que se tomó). Es un
  /// DateTime en UTC cuyos campos son los de esa hora local: sirve para
  /// formatear, no para comparar instantes.
  DateTime get wallTime => wallClock(takenAt, utcOffsetMinutes);

  /// "UTC−05:00" de la foto.
  String get offsetLabel => formatUtcOffset(utcOffsetMinutes);

  /// Rótulo de un campo: el guardado con la foto o, si falta, el del
  /// proyecto. Null si no se conoce (la clave interna no se muestra).
  String? labelFor(String key, [Project? project]) {
    final String? own = fieldLabels[key];
    if (own != null && own.trim().isNotEmpty) {
      return own;
    }
    final String? fromProject = project?.labelOf(key);
    return (fromProject == null || fromProject.trim().isEmpty) ? null : fromProject;
  }

  /// Campos con su rótulo, en el orden en que se guardaron, sin los vacíos
  /// ni los que no tienen rótulo conocido.
  List<MapEntry<String, String>> labeledFields([Project? project]) => <MapEntry<String, String>>[
        for (final MapEntry<String, String> e in fields.entries)
          if (e.value.trim().isNotEmpty && labelFor(e.key, project) != null) MapEntry<String, String>(labelFor(e.key, project)!, e.value.trim()),
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'originalFile': originalFile,
        'stampedFile': stampedFile,
        'takenAt': takenAt.toIso8601String(),
        'utcOffset': utcOffsetMinutes,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'altitudeReference': altitudeReference,
        'altitudeMsl': altitudeMsl,
        'heading': heading,
        'headingTrue': headingTrue,
        'pitch': pitch,
        'speed': speed,
        'positionSource': positionSource.name,
        'averagedSamples': averagedSamples,
        'fixAgeSeconds': fixAgeSeconds,
        'address': address,
        'fields': fields,
        'fieldLabels': fieldLabels,
        'notes': notes,
        'tags': tags,
        'description': description,
        'width': width,
        'height': height,
        'status': status.name,
        'error': error,
        'templateId': templateId,
        'frontCamera': frontCamera,
        'version': version,
      };

  static PhotoRecord fromJson(Map<String, dynamic> j) {
    final DateTime taken = DateTime.tryParse(j['takenAt'] as String? ?? '') ?? DateTime.now();
    return PhotoRecord(
      id: j['id'] as String? ?? newId(),
      projectId: j['projectId'] as String? ?? '',
      originalFile: j['originalFile'] as String? ?? '',
      stampedFile: j['stampedFile'] as String? ?? '',
      takenAt: taken,
      // Sin desfase guardado se usa el de la zona actual en ese instante.
      utcOffsetMinutes: (j['utcOffset'] as num?)?.toInt() ?? taken.toLocal().timeZoneOffset.inMinutes,
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      accuracy: (j['accuracy'] as num?)?.toDouble(),
      altitude: (j['altitude'] as num?)?.toDouble(),
      altitudeReference: j['altitudeReference'] as String? ?? 'msl',
      altitudeMsl: (j['altitudeMsl'] as num?)?.toDouble(),
      heading: (j['heading'] as num?)?.toDouble(),
      headingTrue: j['headingTrue'] as bool? ?? true,
      pitch: (j['pitch'] as num?)?.toDouble(),
      speed: (j['speed'] as num?)?.toDouble(),
      positionSource: PositionSource.values.firstWhere((PositionSource s) => s.name == j['positionSource'], orElse: () => PositionSource.gps),
      averagedSamples: (j['averagedSamples'] as num?)?.toInt() ?? 0,
      fixAgeSeconds: (j['fixAgeSeconds'] as num?)?.toInt() ?? 0,
      address: j['address'] as String? ?? '',
      fields: ((j['fields'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
      fieldLabels: ((j['fieldLabels'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
      notes: j['notes'] as String? ?? '',
      tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
      description: j['description'] as String? ?? '',
      width: (j['width'] as num?)?.toInt() ?? 0,
      height: (j['height'] as num?)?.toInt() ?? 0,
      status: PhotoStatus.values.firstWhere((PhotoStatus s) => s.name == j['status'], orElse: () => PhotoStatus.ok),
      error: j['error'] as String? ?? '',
      templateId: j['templateId'] as String?,
      frontCamera: j['frontCamera'] as bool? ?? false,
      version: (j['version'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Hora local en una zona con [offsetMinutes] de desfase, como DateTime UTC
/// cuyos campos (año, mes, día, hora…) son los de esa hora local.
DateTime wallClock(DateTime instant, int offsetMinutes) => instant.toUtc().add(Duration(minutes: offsetMinutes));

/// Desfase horario como "UTC−05:00".
String formatUtcOffset(int minutes) {
  final String sign = minutes < 0 ? '−' : '+';
  final int abs = minutes.abs();
  return 'UTC$sign${(abs ~/ 60).toString().padLeft(2, '0')}:${(abs % 60).toString().padLeft(2, '0')}';
}

/// Desfase para el EXIF (OffsetTimeOriginal): "-05:00".
String exifUtcOffset(int minutes) {
  final String sign = minutes < 0 ? '-' : '+';
  final int abs = minutes.abs();
  return '$sign${(abs ~/ 60).toString().padLeft(2, '0')}:${(abs % 60).toString().padLeft(2, '0')}';
}

/// Formato de fecha sencillo con los tokens dd, MM, yyyy, HH, mm, ss, EEE.
String formatDate(DateTime d, String pattern, {bool spanish = true}) {
  const List<String> diasEs = <String>['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const List<String> diasEn = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String two(int v) => v.toString().padLeft(2, '0');
  return pattern
      .replaceAll('yyyy', d.year.toString())
      .replaceAll('MM', two(d.month))
      .replaceAll('dd', two(d.day))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute))
      .replaceAll('ss', two(d.second))
      .replaceAll('EEE', (spanish ? diasEs : diasEn)[d.weekday - 1]);
}

/// Desfase horario de un DateTime local como "UTC−05:00".
String utcOffsetLabel(DateTime d) => formatUtcOffset(d.timeZoneOffset.inMinutes);
