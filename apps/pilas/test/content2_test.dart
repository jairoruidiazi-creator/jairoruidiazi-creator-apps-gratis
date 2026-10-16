import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/cuentos.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/pixel/pixel_patterns.dart';
import 'package:pilas/games/rompecabezas/rompecabezas_screen.dart';
import 'package:pilas/games/trazo/trazo_screen.dart';
import 'package:pilas/games/trazo/trazo_templates.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/skill.dart';

void main() {
  test('Cada cuento tiene páginas, tres preguntas válidas y hay al menos tres por tramo', () {
    final Set<String> ids = <String>{};
    for (final Cuento c in CuentoBank.all) {
      expect(ids.add(c.id), isTrue, reason: 'id repetido ${c.id}');
      expect(c.paginas.length, greaterThanOrEqualTo(3), reason: c.id);
      expect(c.preguntas.length, 3, reason: c.id);
      for (final Pagina p in c.paginas) {
        expect(p.texto.trim(), isNotEmpty);
        expect(p.escena, isNotEmpty);
        expect(p.escena.length, lessThanOrEqualTo(3));
      }
      for (final PreguntaCuento q in c.preguntas) {
        expect(q.opciones.length, 3, reason: '${c.id}: ${q.texto}');
        expect(q.correcta, inInclusiveRange(0, 2));
        expect(q.explicacion.trim(), isNotEmpty);
        // En los cuentos para los que no leen, todas las opciones llevan pictograma.
        if (c.band == AgeBand.b3a4 || c.band == AgeBand.b5a6) {
          expect(q.opciones.every((OpcionCuento o) => o.emoji != null), isTrue, reason: '${c.id}: ${q.texto}');
        }
      }
    }
    for (final AgeBand b in AgeBand.values) {
      expect(CuentoBank.forBand(b).length, greaterThanOrEqualTo(3), reason: b.id);
    }
  });

  test('Las plantillas de trazo tienen ids únicos, puntos dentro del cuadro y se muestrean', () {
    final Set<String> ids = <String>{};
    final List<TraceTemplate> todas = <TraceTemplate>[...TraceCatalog.preescritura, ...TraceCatalog.mayusculas, ...TraceCatalog.minusculas, ...TraceCatalog.digitos];
    for (final TraceTemplate t in todas) {
      expect(ids.add(t.id), isTrue, reason: 'id repetido ${t.id}');
      expect(t.strokes, isNotEmpty, reason: t.id);
      for (final List<Offset> s in t.strokes) {
        for (final Offset p in s) {
          expect(p.dx, inInclusiveRange(-2, 102), reason: '${t.id} x=${p.dx}');
          expect(p.dy, inInclusiveRange(-2, 102), reason: '${t.id} y=${p.dy}');
        }
      }
      final List<Offset> pts = t.sample(3);
      expect(pts.length, greaterThanOrEqualTo(5), reason: t.id);
    }
    expect(TraceCatalog.mayusculas.length, 27);
    expect(TraceCatalog.digitos.length, 10);
    for (final AgeBand b in <AgeBand>[AgeBand.b3a4, AgeBand.b5a6]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 10; seed++) {
          expect(TraceCatalog.pick(Rng(seed), b, level).id, isNotEmpty);
        }
        expect(TraceCatalog.tolerance(b, level), greaterThan(4));
      }
    }
  });

  test('La evaluación del trazo premia seguir la guía y castiga el garabato', () {
    final TraceTemplate t = TraceCatalog.mayusculas.firstWhere((TraceTemplate x) => x.id == 'L');
    final List<Offset> guia = t.sample(3);
    // Trazo perfecto: los mismos puntos de la guía.
    final TraceScore perfecto = TraceScore.evaluate(guia, <List<Offset>>[guia], 10);
    expect(perfecto.coverage, 1.0);
    expect(perfecto.precision, 1.0);
    expect(perfecto.good, isTrue);
    // Trazo desplazado 4 unidades: sigue siendo bueno con tolerancia 10.
    final List<Offset> desplazado = guia.map((Offset p) => p + const Offset(4, 0)).toList();
    expect(TraceScore.evaluate(guia, <List<Offset>>[desplazado], 10).good, isTrue);
    // Medio trazo: la cobertura baja de 0,72.
    final TraceScore mitad = TraceScore.evaluate(guia, <List<Offset>>[guia.sublist(0, guia.length ~/ 2)], 10);
    expect(mitad.good, isFalse);
    // Garabato lejos de la guía.
    final List<Offset> lejos = <Offset>[for (int i = 0; i < 40; i++) Offset(90, 10.0 + i)];
    expect(TraceScore.evaluate(guia, <List<Offset>>[lejos], 10).good, isFalse);
  });

  test('Encajar y rompecabezas de imagen generan rondas resolubles', () {
    for (final AgeBand band in <AgeBand>[AgeBand.b3a4, AgeBand.b5a6]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 15; seed++) {
          final EncajeRound r = EncajeRound.generate(Rng(seed + level * 10), band, level);
          expect(r.targets, isNotEmpty);
          expect(r.tray.length, greaterThanOrEqualTo(r.targets.length));
          // Cada silueta tiene exactamente una pieza que encaja en la bandeja.
          for (final EncajePiece t in r.targets) {
            final int compatibles = r.tray.where((EncajePiece p) => p.kind == t.kind && p.scale == t.scale).length;
            expect(compatibles, 1, reason: '${band.id} nivel $level semilla $seed: ${t.nombre}');
          }
          expect(r.tray.map((EncajePiece p) => p.id).toSet().length, r.tray.length);
        }
      }
    }
    for (final AgeBand band in <AgeBand>[AgeBand.b7a8, AgeBand.b9a11]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 15; seed++) {
          final SwapPuzzle p = SwapPuzzle.generate(Rng(seed + level * 10), band, level);
          expect(p.n, SwapPuzzle.sizeFor(band, level));
          expect(p.order.toSet().length, p.n * p.n);
          expect(p.solved, isFalse);
          expect(p.minSwaps, greaterThan(0));
          expect(p.minSwaps, lessThanOrEqualTo(p.n * p.n));
        }
      }
    }
  });

  test('Todos los juegos del registro apuntan a habilidades existentes de su tramo y área', () {
    final Map<String, Skill> skills = <String, Skill>{for (final Skill s in SkillCatalog.all) s.id: s};
    final Set<String> ids = <String>{};
    for (final GameDef g in GameRegistry.all) {
      expect(ids.add(g.id), isTrue, reason: 'id de juego repetido ${g.id}');
      for (final AgeBand b in AgeBand.values) {
        final String? skillId = g.skillFor(b);
        if (g.supports(b)) {
          expect(skillId, isNotNull, reason: '${g.id} no tiene habilidad para ${b.id}');
          final Skill? s = skills[skillId];
          expect(s, isNotNull, reason: '${g.id}: habilidad $skillId no existe');
          expect(s!.band, b, reason: '${g.id}: $skillId no es del tramo ${b.id}');
        }
      }
    }
    expect(GameRegistry.all.length, greaterThanOrEqualTo(26));
  });

  test('Los patrones de pixel art son cuadrados, usan colores de la paleta y hay simétricos', () {
    final Set<String> ids = <String>{};
    for (final PixelPattern p in PixelPatterns.all) {
      expect(ids.add(p.id), isTrue, reason: p.id);
      for (final String row in p.rows) {
        expect(row.length, p.size, reason: '${p.id}: fila de largo distinto');
        for (final String ch in row.split('')) {
          expect(ch == '.' || PixelPalette.colors.containsKey(ch), isTrue, reason: '${p.id}: color desconocido $ch');
        }
      }
    }
    expect(PixelPatterns.symmetric.length, greaterThanOrEqualTo(6));
    expect(PixelPalette.order.toSet().length, PixelPalette.order.length);
    for (final String k in PixelPalette.order) {
      expect(PixelPalette.colors.containsKey(k), isTrue);
      expect(PixelPalette.names.containsKey(k), isTrue);
    }
  });
}
