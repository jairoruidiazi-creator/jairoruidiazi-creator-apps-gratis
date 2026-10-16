import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/coloring_pages.dart';
import 'package:pilas/content/money.dart';
import 'package:pilas/content/svg_path.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/parental_gate.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/skill.dart';

void main() {
  test('formato de pesos', () {
    expect(formatPesos(0), '\$ 0');
    expect(formatPesos(500), '\$ 500');
    expect(formatPesos(1000), '\$ 1.000');
    expect(formatPesos(12500), '\$ 12.500');
    expect(formatPesos(1250000, simbolo: false), '1.250.000');
  });

  test('pesos en palabras', () {
    expect(pesosEnPalabras(1), 'un peso');
    expect(pesosEnPalabras(100), 'cien pesos');
    expect(pesosEnPalabras(500), 'quinientos pesos');
    expect(pesosEnPalabras(1500), 'mil quinientos pesos');
    expect(pesosEnPalabras(21000), 'veintiún mil pesos');
    expect(pesosEnPalabras(31000), 'treinta y un mil pesos');
    expect(pesosEnPalabras(3500), 'tres mil quinientos pesos');
    expect(pesosEnPalabras(12000), 'doce mil pesos');
  });

  test('el parser de paths cierra figuras y detecta puntos dentro', () {
    final Path p = parseSvgPath('M10 10L90 10L90 90L10 90Z');
    expect(p.contains(const Offset(50, 50)), isTrue);
    expect(p.contains(const Offset(5, 5)), isFalse);
    final Path c = parseSvgPath('M60 50C60 55.52 55.52 60 50 60C44.48 60 40 55.52 40 50C40 44.48 44.48 40 50 40C55.52 40 60 44.48 60 50Z');
    expect(c.contains(const Offset(50, 50)), isTrue);
    expect(c.contains(const Offset(70, 50)), isFalse);
    final Path rel = parseSvgPath('m0 0l10 0l0 10l-10 0z');
    expect(rel.contains(const Offset(5, 5)), isTrue);
  });

  test('las láminas se leen desde JSON', () {
    final ColoringPage page = ColoringPage.fromJson(<String, dynamic>{
      'id': 'prueba',
      'nombre': 'Prueba',
      'vb': <int>[0, 0, 100, 100],
      'regions': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'd': 'M0 0L50 0L50 50L0 50Z', 'n': 1, 'c': '#FF0000'},
        <String, dynamic>{'id': 'b', 'd': 'M50 50L100 50L100 100L50 100Z', 'n': 2, 'c': '#00FF00'},
      ],
      'lines': <Map<String, dynamic>>[],
    });
    expect(page.regions.length, 2);
    expect(page.palette.length, 2);
    expect(page.regions.first.targetColor, const Color(0xFFFF0000));
  });

  test('el vocabulario es consistente', () {
    final Set<String> ids = <String>{};
    for (final VocabItem v in Vocab.all) {
      expect(ids.add(v.id), isTrue, reason: 'id repetido ${v.id}');
      expect(v.silabas, isNotEmpty, reason: v.id);
      expect(v.genero == 'm' || v.genero == 'f', isTrue, reason: v.id);
      expect(v.emoji, matches(RegExp(r'^[0-9a-f-]+$')), reason: v.id);
    }
    expect(Vocab.startingWith('m'), isNotEmpty);
    expect(Vocab.withSyllables(3), isNotEmpty);
    expect(Vocab.withTag('animal').length, greaterThan(40));
  });

  test('el catálogo de habilidades cubre todas las áreas y tramos', () {
    for (final AgeBand b in AgeBand.values) {
      for (final Skill s in SkillCatalog.all) {
        expect(s.id, isNotEmpty);
      }
      expect(SkillCatalog.all.where((Skill s) => s.band == b).length, greaterThan(10), reason: b.id);
    }
    expect(SkillCatalog.all.map((Skill s) => s.id).toSet().length, SkillCatalog.all.length);
  });

  test('la puerta parental acepta solo la respuesta correcta', () {
    final GateChallenge g = GateChallenge.random();
    expect(g.check('${g.answer}'), isTrue);
    expect(g.check('${g.answer + 1}'), isFalse);
    expect(g.check('abc'), isFalse);
    expect(g.answer, greaterThanOrEqualTo(36));
  });

  test('tramos por edad', () {
    expect(AgeBandX.forAge(3), AgeBand.b3a4);
    expect(AgeBandX.forAge(4), AgeBand.b3a4);
    expect(AgeBandX.forAge(5), AgeBand.b5a6);
    expect(AgeBandX.forAge(8), AgeBand.b7a8);
    expect(AgeBandX.forAge(11), AgeBand.b9a11);
    expect(AgeBandX.fromId('7-8'), AgeBand.b7a8);
  });
}
