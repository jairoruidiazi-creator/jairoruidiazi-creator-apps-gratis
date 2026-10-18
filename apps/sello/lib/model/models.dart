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
}

/// Campo personalizado de un proyecto (por ejemplo "Lote", "Inspector").
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

/// Una foto tomada con la app: original, copia sellada y todos sus datos.
class PhotoRecord {
  PhotoRecord({
    required this.id,
    required this.projectId,
    required this.originalFile,
    required this.stampedFile,
    required this.takenAt,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeReference = 'msl',
    this.heading,
    this.pitch,
    this.speed,
    this.address = '',
    Map<String, String>? fields,
    this.notes = '',
    List<String>? tags,
    this.description = '',
    this.width = 0,
    this.height = 0,
  })  : fields = fields ?? <String, String>{},
        tags = tags ?? <String>[];

  final String id;
  String projectId;
  final String originalFile;
  String stampedFile;
  final DateTime takenAt;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? altitude;

  /// 'msl' (nivel del mar) o 'ellipsoid'.
  final String altitudeReference;
  final double? heading;
  final double? pitch;
  final double? speed;
  String address;
  final Map<String, String> fields;
  String notes;
  final List<String> tags;
  String description;
  int width;
  int height;

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'originalFile': originalFile,
        'stampedFile': stampedFile,
        'takenAt': takenAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'altitudeReference': altitudeReference,
        'heading': heading,
        'pitch': pitch,
        'speed': speed,
        'address': address,
        'fields': fields,
        'notes': notes,
        'tags': tags,
        'description': description,
        'width': width,
        'height': height,
      };

  static PhotoRecord fromJson(Map<String, dynamic> j) => PhotoRecord(
        id: j['id'] as String? ?? newId(),
        projectId: j['projectId'] as String? ?? '',
        originalFile: j['originalFile'] as String? ?? '',
        stampedFile: j['stampedFile'] as String? ?? '',
        takenAt: DateTime.tryParse(j['takenAt'] as String? ?? '') ?? DateTime.now(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        altitude: (j['altitude'] as num?)?.toDouble(),
        altitudeReference: j['altitudeReference'] as String? ?? 'msl',
        heading: (j['heading'] as num?)?.toDouble(),
        pitch: (j['pitch'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        address: j['address'] as String? ?? '',
        fields: ((j['fields'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
        notes: j['notes'] as String? ?? '',
        tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        description: j['description'] as String? ?? '',
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
      );
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

/// Desfase horario como "UTC−05:00".
String utcOffsetLabel(DateTime d) {
  final Duration o = d.timeZoneOffset;
  final String sign = o.isNegative ? '−' : '+';
  final int h = o.abs().inHours;
  final int m = o.abs().inMinutes % 60;
  return 'UTC$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
