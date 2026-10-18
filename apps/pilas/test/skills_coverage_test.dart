import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/skill.dart';

/// El informe solo puede mostrar habilidades que algún juego evalúa: cada
/// habilidad de un tramo la evalúa al menos un juego de ese tramo, y cada
/// juego apunta a habilidades que existen, de su tramo y de su área.
void main() {
  test('Cada habilidad del mapa la evalúa al menos un juego de su tramo', () {
    for (final Skill s in SkillCatalog.all) {
      final List<GameDef> evaluan = GameRegistry.all.where((GameDef g) => g.supports(s.band) && g.skillFor(s.band) == s.id).toList();
      expect(evaluan, isNotEmpty, reason: 'Nadie evalúa ${s.id} (${s.nombre})');
      for (final GameDef g in evaluan) {
        expect(g.area, s.area, reason: '${g.id} evalúa ${s.id}, que es de otra área');
        expect(g.roundBased, isTrue, reason: '${g.id} es juego libre y no puede dar habilidades');
      }
    }
  });

  test('Cada juego apunta a habilidades existentes de su tramo y área', () {
    final Map<String, Skill> skills = <String, Skill>{for (final Skill s in SkillCatalog.all) s.id: s};
    final Set<String> ids = <String>{};
    for (final GameDef g in GameRegistry.all) {
      expect(ids.add(g.id), isTrue, reason: 'id de juego repetido ${g.id}');
      g.skills.forEach((AgeBand b, String id) {
        expect(g.supports(b), isTrue, reason: '${g.id} declara una habilidad para ${b.id}, que no cubre');
        final Skill? s = skills[id];
        expect(s, isNotNull, reason: '${g.id}: la habilidad $id no existe');
        expect(s!.band, b, reason: '${g.id}: $id no es del tramo ${b.id}');
        expect(s.area, g.area, reason: '${g.id}: $id no es de su área');
      });
      if (!g.roundBased) {
        expect(g.skills, isEmpty, reason: '${g.id} es juego libre: no evalúa habilidades');
        expect(g.levels, 1, reason: '${g.id} es juego libre: no tiene niveles');
      }
    }
  });

  test('Ninguna habilidad la evalúan dos juegos del mismo tramo', () {
    // Así "logradas de posibles" mide lo mismo para todos los niños.
    for (final AgeBand b in AgeBand.values) {
      final Map<String, String> quien = <String, String>{};
      for (final GameDef g in GameRegistry.forBand(b)) {
        final String? s = g.skillFor(b);
        if (s == null) {
          continue;
        }
        expect(quien.containsKey(s), isFalse, reason: '$s la evalúan ${quien[s]} y ${g.id} en ${b.id}');
        quien[s] = g.id;
      }
    }
  });

  test('La ficha y el registro tienen 26 juegos y los nombres que se anuncian', () {
    expect(GameRegistry.all.length, 26);
    final Set<String> nombres = GameRegistry.all.map((GameDef g) => g.nombre).toSet();
    expect(nombres.length, 26);
    // Nada de nombres que prometen lo que el juego no hace (auditoría G18).
    for (final String n in nombres) {
      expect(n.toLowerCase().contains('tangram'), isFalse);
      expect(n.toLowerCase().contains('arma el cuerpo'), isFalse);
      expect(n.toLowerCase().contains('constructor'), isFalse);
    }
    // Los íconos del inicio no se repiten.
    expect(GameRegistry.all.map((GameDef g) => g.emoji).toSet().length, 26);
  });
}
