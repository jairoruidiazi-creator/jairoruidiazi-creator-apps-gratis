import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/app.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/colorear/colorear_screen.dart';
import 'package:pilas/games/colorear/coloring_painter.dart';
import 'package:pilas/games/dibujo/dibujo_screen.dart';
import 'package:pilas/games/pixel/pixel_screen.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/area.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/model/progress.dart';
import 'package:pilas/model/skill.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/parent/report_data.dart';
import 'package:pilas/ui/parent/teacher_screen.dart';
import 'package:pilas/ui/profile_edit_screen.dart';

import 'support/harness.dart';

/// Deja avanzar las escrituras a disco (que no corren con el reloj falso de
/// las pruebas de widgets).
Future<void> dejarGuardar(WidgetTester tester) async {
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Informe, accesibilidad y juegos libres: lo que la auditoría pidió y no
/// cubren las otras pruebas.
void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  test('G5 y M14: el informe cuenta las habilidades del tramo actual y los aciertos sin juegos libres', () async {
    final Profile p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2018, birthMonth: 1, bandOverride: AgeBand.b7a8);
    final ProfileProgress prog = h.state.progressOf(p.id);
    final DateTime ahora = DateTime(2026, 10, 18, 9);
    // Una habilidad de un tramo anterior no cuenta entre las "logradas de
    // posibles" del tramo actual.
    prog.skillsAchieved['logica.5-6.memoria'] = ahora;
    prog.skillsAchieved['logica.7-8.memoria'] = ahora;
    prog.masteryFor('patrones', AgeBand.b7a8)
      ..roundsPlayed = 6
      ..roundsCorrect = 5;
    // Un juego libre no suma rondas ni aciertos aunque tuviera registro.
    prog.masteryFor('colorear', AgeBand.b7a8)
      ..roundsPlayed = 4
      ..roundsCorrect = 4;
    final ChildReport r = ChildReport(profile: p, progress: prog, now: ahora);
    expect(r.skillsDelTramo.length, SkillCatalog.forBand(AgeBand.b7a8).length);
    expect(r.skillsLogradasTramo, 1);
    expect(r.rondasTotal, 6);
    expect(r.aciertosTotal, 5);
    final AreaSummary logica = r.areas.firstWhere((AreaSummary a) => a.area == Area.logica);
    expect(logica.skillsLogradas, 1);
    expect(logica.skillsPosibles, SkillCatalog.forAreaAndBand(Area.logica, AgeBand.b7a8).length);
    expect(logica.logradasTexto, '1 de ${logica.skillsPosibles}');
    // En los tableros se informa "resueltos con eficiencia", no "al primer intento".
    prog.masteryFor('laberintos', AgeBand.b7a8)
      ..roundsPlayed = 3
      ..roundsCorrect = 2;
    final GameLevel lab = ChildReport(profile: p, progress: prog, now: ahora).areas.firstWhere((AreaSummary a) => a.area == Area.logica).juegos.firstWhere((GameLevel g) => g.game.id == 'laberintos');
    expect(lab.resumen, '3 tableros · 67\u00A0% resueltos con eficiencia');
  });

  test('M15: la tabla del grupo se abre bien en Excel', () async {
    final Profile p = await h.state.addProfile(nombre: 'Ana; María', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    final String csv = groupCsv(<ChildReport>[ChildReport(profile: p, progress: h.state.progressOf(p.id))]);
    expect(csv.startsWith('﻿'), isTrue, reason: 'sin BOM, Excel muestra mal las tildes');
    expect(csv.split('\r\n').first, contains('Niño;Edad;Tramo'));
    // M11 (tercera ronda): la columna dice que es un conteo, no un porcentaje.
    expect(csv.split('\r\n').first, contains('Rondas acertadas al primer intento'));
    expect(csv, contains('"Ana; María";'));
  });

  test('M3: borrar un perfil borra también sus dibujos', () async {
    final Profile p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    final File dibujo = await h.services.store.writeBytes('drawings/${p.id}/d1.png', <int>[1, 2, 3]);
    expect(dibujo.existsSync(), isTrue);
    await h.state.deleteProfile(p.id);
    expect(dibujo.existsSync(), isFalse);
    expect(h.state.profiles, isEmpty);
  });

  test('M5, N1 y N2: al borrar un perfil se borran todas sus copias, los respaldos de avisos y solo sus avisos', () async {
    final Profile beto = await h.state.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1);
    final Profile ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    final Profile anaMaria = await h.state.addProfile(nombre: 'Ana María', avatar: '1f430', birthYear: 2018, birthMonth: 2);
    final Profile anabel = await h.state.addProfile(nombre: 'Anabel', avatar: '1f42d', birthYear: 2017, birthMonth: 3);
    final String raiz = (await h.services.store.root()).path;
    File archivo(String rel, String texto) => File('$raiz/$rel')..createSync(recursive: true)..writeAsStringSync(texto);
    // Nombres que la app produce de verdad: readJsonSafe aparta el archivo
    // y su respaldo como `<archivo>.corrupto-<fecha>` y
    // `<archivo>.bak.corrupto-<fecha>`; _setAside, como
    // `<archivo>.corrupto-<milisegundos>`.
    final List<File> deAna = <File>[
      archivo('progress/${ana.id}.json', '{"mastery": {}}'),
      archivo('progress/${ana.id}.json.bak', '{"mastery": {}}'),
      archivo('progress/${ana.id}.json.corrupto-20261018-120000', '{"roto'),
      archivo('progress/${ana.id}.json.bak.corrupto-20261018-120000', '{"roto'),
      archivo('progress/${ana.id}.json.bak.corrupto-20261018-120000-2', '{"roto'),
      archivo('progress/${ana.id}.json.corrupto-1760000000000', '{"mastery": {}}'),
      archivo('profiles.json.corrupto-20261018-120001', '{"profiles": [{"id": "${ana.id}", "nombre": "Ana"'),
      archivo('profiles.json.bak.corrupto-20261018-120001', '{"profiles": [{"id": "${ana.id}", "nombre": "Ana", "birthYear": 2018'),
      archivo('groups.json.bak.corrupto-20261018-120002', '{"groups": [{"profileIds": ["${ana.id}"'),
      // N3: copias dañadas de los avisos (se borran siempre).
      archivo('avisos.json.corrupto-20261018-120006', '{"avisos": [{"texto": "No se pudo leer el avance de Ana: '),
      archivo('avisos.json.bak.corrupto-20261018-120006', '{"avisos": [{"texto": "Se recuperó el avance de Ana desde'),
    ];
    final List<File> deOtros = <File>[
      archivo('profiles.json.corrupto-20261018-120003', '{"profiles": [{"id": "${beto.id}"'),
      archivo('progress/${beto.id}.json.bak.corrupto-20261018-120004', '{'),
      archivo('progress/${anaMaria.id}.json.corrupto-20261018-120005', '{'),
    ];
    // Un aviso de Ana ya descartado: queda en el respaldo de avisos.json.
    await h.services.store.writeJson('avisos.json', <String, dynamic>{
      'avisos': <Map<String, dynamic>>[StorageNotice('No se pudo leer el avance de Ana: el archivo y su copia estaban dañados. Se empezó de cero.', DateTime(2026, 10, 18)).toJson()],
    });
    await h.state.dismissNotices();
    final String avisos = await h.services.store.absolutePath('avisos.json');
    expect(File('$avisos.bak').readAsStringSync(), contains('avance de Ana:'));
    // Avisos vigentes: con id (nuevos) y sin id (de antes de esta versión).
    h.state.notices
      ..add(StorageNotice('Se recuperó el avance de Ana desde la copia de seguridad, porque el archivo estaba dañado.', DateTime(2026, 10, 18), profileId: ana.id))
      ..add(StorageNotice('No se pudo interpretar el avance de Ana; el archivo se guardó aparte (x) y su avance empezó de cero.', DateTime(2026, 10, 18)))
      ..add(StorageNotice('No se pudo leer el avance de Ana María: el archivo y su copia estaban dañados. Se empezó de cero.', DateTime(2026, 10, 18)))
      ..add(StorageNotice('Se recuperó el avance de Ana María desde la copia de seguridad, porque el archivo estaba dañado.', DateTime(2026, 10, 18), profileId: anaMaria.id))
      ..add(StorageNotice('Se recuperó el avance de Anabel desde la copia de seguridad, porque el archivo estaba dañado.', DateTime(2026, 10, 18)))
      ..add(StorageNotice('Se recuperó el avance de Beto desde la copia de seguridad, porque el archivo estaba dañado.', DateTime(2026, 10, 18), profileId: beto.id));

    await h.state.deleteProfile(ana.id);

    for (final File f in deAna) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
    for (final File f in deOtros) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
    final List<String> textos = h.state.notices.map((StorageNotice n) => n.texto).toList();
    expect(textos.where((String t) => t.contains('avance de Ana desde') || t.contains('avance de Ana:') || t.contains('avance de Ana;')), isEmpty);
    // Ana María, Anabel y Beto conservan sus avisos.
    expect(textos.where((String t) => t.contains('Ana María')).length, 2);
    expect(textos.any((String t) => t.contains('Anabel')), isTrue);
    expect(textos.any((String t) => t.contains('Beto')), isTrue);
    expect(textos.any((String t) => t.contains('copias dañadas')), isTrue);
    // Ni avisos.json ni su respaldo nombran ya a Ana.
    for (final File f in <File>[File(avisos), File('$avisos.bak')]) {
      if (f.existsSync()) {
        expect(f.readAsStringSync(), isNot(contains('avance de Ana:')), reason: f.path);
        expect(f.readAsStringSync(), isNot(contains('avance de Ana;')), reason: f.path);
      }
    }
    expect(h.state.profiles.map((Profile p) => p.id), <String>[beto.id, anaMaria.id, anabel.id]);
  });

  test('N5: un aviso de Ana ya descartado, sin avisos vigentes ni copias dañadas, tampoco queda en el respaldo', () async {
    final Profile ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    await h.services.store.writeJson('avisos.json', <String, dynamic>{
      'avisos': <Map<String, dynamic>>[StorageNotice('Se recuperó el avance de Ana desde la copia de seguridad, porque el archivo estaba dañado.', DateTime(2026, 10, 18), profileId: ana.id).toJson()],
    });
    await h.state.dismissNotices();
    final String avisos = await h.services.store.absolutePath('avisos.json');
    expect(File('$avisos.bak').readAsStringSync(), contains('avance de Ana'));
    expect(h.state.notices, isEmpty);
    await h.state.deleteProfile(ana.id);
    for (final File f in <File>[File(avisos), File('$avisos.bak')]) {
      if (f.existsSync()) {
        expect(f.readAsStringSync(), isNot(contains('Ana')), reason: f.path);
      }
    }
    expect(h.state.notices, isEmpty);
  });

  test('N2: los avisos nuevos llevan el id del perfil y se reconocen por él', () {
    final StorageNotice n = StorageNotice('Se recuperó el avance de Ana desde la copia de seguridad.', DateTime(2026, 10, 18), profileId: 'p1');
    expect(StorageNotice.fromJson(n.toJson()).profileId, 'p1');
    expect(n.esDe('p1', 'Ana'), isTrue);
    expect(n.esDe('p2', 'Ana'), isFalse);
    final StorageNotice viejo = StorageNotice.fromJson(<String, dynamic>{'texto': 'No se pudo leer el avance de Ana María: …', 'fecha': '2026-10-18T00:00:00.000'});
    expect(viejo.profileId, isNull);
    expect(viejo.esDe('x', 'Ana'), isFalse);
    expect(viejo.esDe('x', 'Ana María'), isTrue);
  });

  test('M7 (tercera ronda): el perfil borrado no queda en el respaldo ni vuelve al recuperarlo', () async {
    await h.state.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1);
    final Profile p = await h.state.addProfile(nombre: 'Valentina', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    await h.state.deleteProfile(p.id);
    final String ruta = await h.services.store.absolutePath('profiles.json');
    final File bak = File('$ruta.bak');
    expect(bak.existsSync(), isTrue);
    expect(bak.readAsStringSync(), isNot(contains('Valentina')));
    // Si el archivo principal se daña, la recuperación no resucita el perfil.
    File(ruta).writeAsStringSync('{dañado');
    final JsonRead leido = await h.services.store.readJsonSafe('profiles.json');
    expect(leido.data.toString(), isNot(contains('Valentina')));
    expect(leido.data.toString(), contains('Beto'));
  });

  test('G18: la carrera guarda la marca propia y solo la cambia si se supera', () async {
    final Profile p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2018, birthMonth: 1);
    await h.state.selectProfile(p);
    expect(await h.state.saveRecord('carrera|7-8', 7), isTrue);
    expect(await h.state.saveRecord('carrera|7-8', 6), isFalse);
    expect(h.state.recordOf('carrera|7-8'), 7);
    expect(await h.state.saveRecord('carrera|7-8', 9), isTrue);
    expect(h.state.recordOf('carrera|7-8'), 9);
    // M2 (tercera ronda): una primera carrera sin aciertos se guarda, pero
    // no se celebra como «¡Nueva marca!».
    expect(await h.state.saveRecord('carrera|9-11', 0), isFalse);
    expect(h.state.recordOf('carrera|9-11'), 0);
    expect(await h.state.saveRecord('carrera|9-11', 1), isTrue);
    await h.state.pauseClock();
  });

  test('G17: texto grande multiplica la letra del sistema, con tope', () {
    double escala(double sistema, bool grande) => pilasTextScaler(TextScaler.linear(sistema), largeText: grande).scale(10) / 10;
    expect(escala(1.0, false), closeTo(1.0, 0.001));
    expect(escala(1.0, true), closeTo(1.25, 0.001));
    expect(escala(1.2, false), closeTo(1.2, 0.001));
    expect(escala(1.3, true), closeTo(1.625, 0.001));
    // M11: el tope es el doble (200 %), como pide la WCAG.
    expect(escala(1.6, true), closeTo(2.0, 0.001));
    expect(escala(2.0, false), closeTo(2.0, 0.001));
    expect(escala(3.1, false), closeTo(2.0, 0.001));
    expect(escala(0.5, false), closeTo(0.8, 0.001));
  });

  testWidgets('M12: los avatares tienen nombre para el lector de pantalla', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    await tester.pumpWidget(h.app(const ProfileEditScreen()));
    await tester.pump();
    for (final String a in Profile.avatares.take(4)) {
      expect(find.bySemanticsLabel(Profile.nombresAvatar[a]!), findsOneWidget, reason: a);
    }
    sem.dispose();
  });

  testWidgets('M19: sin voz en español, el inicio de los que no leen lo avisa', (WidgetTester tester) async {
    late Profile peque;
    late Profile grande;
    await tester.runAsync(() async {
      peque = await h.state.addProfile(nombre: 'Leo', avatar: '1f431', birthYear: 2022, birthMonth: 1, bandOverride: AgeBand.b3a4);
      grande = await h.state.addProfile(nombre: 'Sara', avatar: '1f436', birthYear: 2016, birthMonth: 1, bandOverride: AgeBand.b9a11);
    });
    h.services.settings.voiceEnabled = true;
    h.voice
      ..ready = true
      ..available = false;
    h.state.current = peque;
    await tester.pumpWidget(h.app(const KidHomeScreen(), navigatorKey: GlobalKey<NavigatorState>()));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('aviso-sin-voz')), findsOneWidget);
    expect(find.text(S.sinVozTitulo), findsOneWidget);
    // Con voz, o para los que ya leen, no hay aviso.
    h.voice
      ..available = true
      ..avisar();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('aviso-sin-voz')), findsNothing);
    h.voice.available = false;
    h.state.current = grande;
    await tester.pumpWidget(h.app(const KidHomeScreen(), navigatorKey: GlobalKey<NavigatorState>()));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('aviso-sin-voz')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => h.state.pauseClock());
  });

  testWidgets('G20: de 7 a 11 años, las zonas y la paleta llevan la misma letra', (WidgetTester tester) async {
    late Profile p;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Sara', avatar: '1f436', birthYear: 2018, birthMonth: 1, bandOverride: AgeBand.b7a8);
      await h.state.selectProfile(p);
    });
    final GameDef game = GameRegistry.byId('colorear_numeros')!;
    await tester.pumpWidget(h.app(ColorearScreen(launch: GameLaunch(game: game, band: AgeBand.b7a8, profile: p), porNumeros: true)));
    for (int i = 0; i < 40 && find.byType(GridView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.tap(find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lamina-')).first);
    await tester.pump();
    final CustomPaint lienzo = tester.widget<CustomPaint>(find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter is ColoringPainter).first);
    final ColoringPainter pintor = lienzo.painter! as ColoringPainter;
    expect(pintor.label!(1), 'A');
    expect(pintor.label!(3), 'C');
    expect(find.descendant(of: find.byKey(const ValueKey<String>('color-0')), matching: find.text('A')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('color-2')), matching: find.text('C')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => h.state.pauseClock());
  });

  testWidgets('G4: Dibujo y sellos no da nada por un lienzo vacío ni da habilidades', (WidgetTester tester) async {
    late Profile p;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Leo', avatar: '1f431', birthYear: 2020, birthMonth: 1, bandOverride: AgeBand.b5a6);
      await h.state.selectProfile(p);
    });
    final GameDef game = GameRegistry.byId('dibujo')!;
    await tester.pumpWidget(h.app(DibujoScreen(launch: GameLaunch(game: game, band: AgeBand.b5a6, profile: p))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('dibujo-termine')));
    await tester.pump();
    expect(h.voice.dicho, contains('Primero dibuja algo.'));
    expect(h.state.progressOf(p.id).live?.gameRounds['dibujo'], isNull);
    await tester.drag(find.byKey(const ValueKey<String>('dibujo-lienzo')), const Offset(120, 40));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('dibujo-termine')));
    await tester.pump();
    await dejarGuardar(tester);
    expect(h.state.progressOf(p.id).live?.gameRounds['dibujo'], 1);
    expect(h.state.progressOf(p.id).masteryIfAny('dibujo', AgeBand.b5a6), isNull);
    expect(h.state.progressOf(p.id).skillsAchieved, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => h.state.pauseClock());
  });

  testWidgets('M17: en pixel art, comparar marca lo que falta y no borra lo pintado', (WidgetTester tester) async {
    late Profile p;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Sara', avatar: '1f436', birthYear: 2018, birthMonth: 1, bandOverride: AgeBand.b7a8);
      await h.state.selectProfile(p);
    });
    final GameDef game = GameRegistry.byId('pixel')!;
    await tester.pumpWidget(h.app(PixelScreen(launch: GameLaunch(game: game, band: AgeBand.b7a8, profile: p))));
    await tester.pump();
    await tester.pump();
    final Finder tablero = find.byKey(const ValueKey<String>('tablero-6x6'));
    expect(tablero, findsOneWidget);
    String etiqueta() => tester.widget<Semantics>(find.ancestor(of: tablero, matching: find.byType(Semantics)).first).properties.label!;
    final Rect r = tester.getRect(tablero);
    await tester.tapAt(r.topLeft + Offset(r.width / 12, r.height / 12));
    await tester.pump();
    expect(etiqueta(), contains('1 casilla pintada'));
    await tester.tap(find.byKey(const ValueKey<String>('pixel-comparar')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('pista')), findsOneWidget);
    expect(etiqueta(), contains('1 casilla pintada'));
    expect(h.state.progressOf(p.id).masteryIfAny('pixel', AgeBand.b7a8)?.roundsPlayed ?? 0, 0);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => h.state.pauseClock());
  });
}
