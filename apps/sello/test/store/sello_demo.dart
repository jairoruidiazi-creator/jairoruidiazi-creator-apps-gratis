// Datos de ejemplo de las capturas de tienda de Sello: dos proyectos ficticios
// en Chía (Cundinamarca) con fotos libres de Wikimedia Commons (ver
// photos/CREDITOS.md) selladas con la tubería real de la app.

import 'dart:io';

import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/geo/coords.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/stamp_data.dart';

/// Centro de los datos de ejemplo; las teselas de test/store/tiles lo cubren
/// (ver .github/workflows/store-assets.yml, tarea osm-tiles).
const double demoLat = 4.8545;
const double demoLon = -74.0665;

class _Shot {
  const _Shot(this.file, this.project, this.daysAgo, this.hour, this.minute, this.dLat, this.dLon, this.accuracy, this.altitude, this.heading, this.pitch, this.notesEs, this.notesEn, {this.fields = const <String, String>{}, this.tagsEs = const <String>[], this.tagsEn = const <String>[]});

  final String file;
  final String project;
  final int daysAgo;
  final int hour;
  final int minute;
  final double dLat;
  final double dLon;
  final double accuracy;
  final double altitude;
  final double heading;
  final double pitch;
  final String notesEs;
  final String notesEn;
  final Map<String, String> fields;
  final List<String> tagsEs;
  final List<String> tagsEn;
}

const List<_Shot> _shots = <_Shot>[
  _Shot('valle-obra.jpg', 'variante', 1, 8, 12, -0.0006, 0.0012, 4.8, 2571.3, 118, -6, 'Vista general del frente de obra desde el talud', 'Overview of the work front from the slope', fields: <String, String>{'abscisa': 'K3+240'}, tagsEs: <String>['avance'], tagsEn: <String>['progress']),
  _Shot('volqueta.jpg', 'variante', 1, 10, 47, -0.0003, 0.0009, 3.6, 2566.8, 205, -2, 'Volqueta con material de base granular', 'Dump truck with granular base material', fields: <String, String>{'abscisa': 'K3+180'}, tagsEs: <String>['materiales'], tagsEn: <String>['materials']),
  _Shot('via-curva.jpg', 'variante', 1, 11, 20, 0.0001, -0.0011, 4.1, 2565.2, 64, -3, 'Empalme con la vía existente, demarcación pendiente', 'Tie-in with the existing road, markings pending', fields: <String, String>{'abscisa': 'K3+120'}, tagsEs: <String>['pavimento'], tagsEn: <String>['pavement']),
  _Shot('via-puente.jpg', 'variante', 1, 15, 5, 0.0011, -0.0012, 5.2, 2563.9, 92, -1, 'Paso bajo el puente vehicular, cuneta despejada', 'Pass under the road bridge, ditch clear', fields: <String, String>{'abscisa': 'K3+060'}, tagsEs: <String>['drenaje'], tagsEn: <String>['drainage']),
  _Shot('cimentacion.jpg', 'mirador', 0, 8, 5, 0.0006, 0.0002, 6.1, 2562.4, 271, -18, 'Recalce de cimentación en el eje C', 'Foundation underpinning on axis C', fields: <String, String>{'elemento': 'Zapata C-4', 'inspector': 'L. Rojas'}, tagsEs: <String>['estructura'], tagsEn: <String>['structure']),
  _Shot('anden.jpg', 'mirador', 0, 8, 31, 0.0009, 0.0006, 3.9, 2561.7, 12, -4, 'Andén perimetral terminado, tramo norte', 'Perimeter sidewalk finished, north section', fields: <String, String>{'elemento': 'Andén norte', 'inspector': 'L. Rojas'}, tagsEs: <String>['acabados'], tagsEn: <String>['finishes']),
  _Shot('plataforma.jpg', 'mirador', 0, 9, 12, 0.0012, 0.0003, 4.4, 2562.0, 318, 9, 'Plataforma elevadora en la fachada occidental', 'Boom lift at the west facade', fields: <String, String>{'elemento': 'Fachada occidental', 'inspector': 'M. Peña'}, tagsEs: <String>['seguridad', 'fachada'], tagsEn: <String>['safety', 'facade']),
  _Shot('obra-grua.jpg', 'mirador', 0, 9, 41, 0.0008, 0.0009, 3.2, 2562.6, 337, 4, 'Montaje de la grúa torre, costado norte', 'Tower crane assembly, north side', fields: <String, String>{'elemento': 'Grúa torre G-1', 'inspector': 'M. Peña'}, tagsEs: <String>['seguridad'], tagsEn: <String>['safety']),
];

/// Crea proyectos, plantilla y fotos selladas en [state]. Devuelve el id de la
/// foto principal (la última tomada).
Future<String> seedSelloDemo({required AppState state, required JsonStore store, required AppSettings settings, required bool spanish, required DateTime now, required String photosDir, required String scratchDir}) async {
  String tr(String es, String en) => spanish ? es : en;
  settings
    ..language = spanish ? 'es' : 'en'
    ..saveToGallery = false
    ..keepOriginal = true;

  final StampTemplate interventoria = StampTemplate(
    id: 'interventoria',
    name: tr('Interventoría', 'Site supervision'),
    items: <StampItem>{StampItem.dateTime, StampItem.coords, StampItem.coords2, StampItem.altitude, StampItem.accuracy, StampItem.heading, StampItem.address, StampItem.project, StampItem.fields, StampItem.notes, StampItem.compass},
    coordFormat: CoordFormat.dd,
    coordFormat2: CoordFormat.ctm12,
    position: StampPosition.bottomBar,
  );
  final StampTemplate vias = StampTemplate(
    id: 'vias',
    name: tr('Vías', 'Roads'),
    items: <StampItem>{StampItem.dateTime, StampItem.coords, StampItem.coords2, StampItem.altitude, StampItem.heading, StampItem.project, StampItem.fields, StampItem.notes},
    coordFormat: CoordFormat.dms,
    coordFormat2: CoordFormat.utm,
  );
  state.templates
    ..removeWhere((StampTemplate t) => t.id != 'default')
    ..addAll(<StampTemplate>[interventoria, vias]);
  state.templates.first.name = tr('Estándar', 'Standard');
  final Project mirador = Project(
    id: 'mirador',
    name: tr('Edificio Mirador · Interventoría', 'Mirador Building · Supervision'),
    templateId: 'interventoria',
    fields: <FieldDef>[FieldDef('elemento', tr('Elemento', 'Element')), const FieldDef('inspector', 'Inspector')],
    fileNamePattern: '{proyecto}_{fecha}_{n}',
  );
  final Project variante = Project(
    id: 'variante',
    name: tr('Avenida Calle 2 · Tramo 3', 'Calle 2 Avenue · Section 3'),
    templateId: 'vias',
    fields: <FieldDef>[FieldDef('abscisa', tr('Abscisa', 'Station'))],
    fileNamePattern: '{proyecto}_{fecha}_{n}',
  );
  state.projects
    ..clear()
    ..addAll(<Project>[mirador, variante]);
  await state.saveProjects();

  final CapturePipeline pipeline = CapturePipeline(store: store, state: state, settings: settings);
  final DateTime day = DateTime(now.year, now.month, now.day);
  String lastId = '';
  for (final _Shot s in _shots) {
    final Project project = s.project == 'mirador' ? mirador : variante;
    final StampTemplate template = state.templateForProject(project);
    final DateTime d = day.subtract(Duration(days: s.daysAgo));
    final DateTime time = DateTime(d.year, d.month, d.day, s.hour, s.minute, 7 + s.minute % 50);
    final Map<String, String> fields = <String, String>{
      for (final MapEntry<String, String> e in s.fields.entries) e.key: e.key == 'elemento' && !spanish ? _elementEn(e.value) : e.value,
    };
    final StampData data = StampData(
      time: time,
      latitude: demoLat + s.dLat,
      longitude: demoLon + s.dLon,
      accuracy: s.accuracy,
      altitude: s.altitude,
      heading: s.heading,
      pitch: s.pitch,
      address: s.project == 'mirador' ? tr('Carrera 12, Chía, Cundinamarca', 'Carrera 12, Chía, Cundinamarca, Colombia') : tr('Avenida Calle 2, Chía, Cundinamarca', 'Avenida Calle 2, Chía, Cundinamarca, Colombia'),
      projectName: project.name,
      fields: fields,
      fieldLabels: <String, String>{for (final FieldDef f in project.fields) f.key: f.label},
      notes: spanish ? s.notesEs : s.notesEn,
      spanish: spanish,
    );
    final String temp = '$scratchDir/${s.file}';
    await File('$photosDir/${s.file}').copy(temp);
    final CaptureOutcome out = await pipeline.process(jpegPath: temp, project: project, template: template, data: data, fields: fields, notes: data.notes, tags: spanish ? s.tagsEs : s.tagsEn);
    lastId = out.record.id;
  }
  return lastId;
}

String _elementEn(String es) {
  switch (es) {
    case 'Zapata C-4':
      return 'Footing C-4';
    case 'Andén norte':
      return 'North sidewalk';
    case 'Fachada occidental':
      return 'West facade';
    case 'Grúa torre G-1':
      return 'Tower crane G-1';
  }
  return es;
}
