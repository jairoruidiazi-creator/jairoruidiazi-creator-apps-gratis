import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/clasifica/clasifica_generator.dart';
import 'package:pilas/games/cocina/cocina_generator.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/intruso/intruso_generator.dart';
import 'package:pilas/games/patrones/patrones_generator.dart';
import 'package:pilas/model/age_band.dart';

VocabItem _v(String id) => Vocab.all.firstWhere((VocabItem v) => v.id == id);

List<VocabItem> _distractores(ChoiceRound r) => <VocabItem>[for (final ChoiceOption o in r.options) if (o.id != r.correctId) _v(o.id)];

/// Que las preguntas tengan una sola respuesta defendible: los distractores
/// nunca cumplen lo que se pregunta (auditoría G8 y G9). Cada prueba genera
/// miles de rondas.
void main() {
  final ClasificaGenerator clasifica = ClasificaGenerator();
  const int semillas = 600;

  test('Clasifica: ¿dónde vive? tiene una sola respuesta', () {
    for (int seed = 0; seed < semillas; seed++) {
      final ChoiceRound r = clasifica.dondeVive(Rng(seed), 3 + seed % 4, ClasificaGenerator.habitats.keys.toList());
      final VocabItem animal = ClasificaGenerator.animales.firstWhere((VocabItem a) => r.instruction == '¿Dónde ${a.verbo('vive', 'viven')} ${a.conArticulo}?');
      expect(animal.habitats, <String>{r.correctId}, reason: r.instruction);
      for (final ChoiceOption o in r.options) {
        if (o.id != r.correctId) {
          expect(animal.tambienVive.contains(o.id), isFalse, reason: '${r.instruction}: ${o.id} también sería correcto');
        }
      }
    }
  });

  test('Clasifica: ¿cuál vive en…? ningún distractor vive ahí', () {
    for (int seed = 0; seed < semillas; seed++) {
      final ChoiceRound r = clasifica.cualVive(Rng(seed), 3 + seed % 2, ClasificaGenerator.habitatsFaciles);
      final Habitat h = ClasificaGenerator.habitats.values.firstWhere((Habitat x) => r.instruction == '¿Cuál ${x.vive}?');
      expect(_v(r.correctId).habitats.contains(h.id), isTrue, reason: r.instruction);
      for (final VocabItem d in _distractores(r)) {
        expect(d.habitats.contains(h.id) || d.tambienVive.contains(h.id), isFalse, reason: '${r.instruction}: ${d.nombre} también vive ahí');
      }
    }
    // Lo que la auditoría encontró: no existía la sabana y el león vivía en la selva.
    expect(_v('leon').habitats, contains('sabana'));
    expect(_v('leon').habitats.contains('selva'), isFalse);
  });

  test('Clasifica: grupos de animales sin distractores del mismo grupo', () {
    for (int seed = 0; seed < semillas; seed++) {
      final ChoiceRound q = clasifica.queEs(Rng(seed), 3 + seed % 4);
      final VocabItem animal = ClasificaGenerator.animales.firstWhere((VocabItem a) => q.instruction == '¿Qué tipo de animal es ${a.conArticulo}?');
      expect(q.correctId, animal.grupo, reason: q.instruction);
      final ChoiceRound c = seed.isEven ? clasifica.cualEsGrupo(Rng(seed), 3 + seed % 3) : clasifica.trampa(Rng(seed), 4);
      final GrupoAnimal g = ClasificaGenerator.grupos.values.firstWhere((GrupoAnimal x) => c.instruction == '¿Cuál ${x.esUn}?');
      expect(_v(c.correctId).grupo, g.id, reason: c.instruction);
      for (final VocabItem d in _distractores(c)) {
        expect(d.grupo == g.id, isFalse, reason: '${c.instruction}: ${d.nombre} también lo es');
      }
    }
  });

  test('Clasifica: ¿cuál salta? los distractores claramente no se mueven así', () {
    for (int seed = 0; seed < semillas; seed++) {
      final ChoiceRound r = clasifica.cualMueve(Rng(seed), 3 + seed % 3);
      final String? mov = ClasificaGenerator.preguntaMovimiento.entries.where((MapEntry<String, String> e) => e.value == r.instruction).map((MapEntry<String, String> e) => e.key).firstOrNull;
      if (mov == null) {
        continue; // cayó en "¿qué tipo de animal es?"
      }
      expect(_v(r.correctId).mueve(mov), isTrue, reason: r.instruction);
      for (final VocabItem d in _distractores(r)) {
        expect(d.mueve(mov), isFalse, reason: '${r.instruction}: ${d.nombre} no está marcado como que no lo hace');
      }
    }
    // El conejo salta y el pato camina (la auditoría los vio marcados mal).
    expect(_v('conejo').mueve('salta'), isTrue);
    expect(_v('pato').mueve('camina'), isTrue);
  });

  test('El intruso: el intruso no es del grupo, los demás sí, y no hay otro intruso posible', () {
    final IntrusoGenerator g = IntrusoGenerator();
    final List<CriterioIntruso> todos = <CriterioIntruso>[...IntrusoGenerator.b3a4, ...IntrusoGenerator.b5a6, ...IntrusoGenerator.b7a8];
    int rondas = 0;
    for (final CriterioIntruso c in todos) {
      for (int seed = 0; seed < 120; seed++) {
        final ChoiceRound? r = g.roundFor(Rng(seed), c, 3 + seed % 4);
        if (r == null) {
          continue;
        }
        rondas += 1;
        final VocabItem intruso = _v(r.correctId);
        expect(c.intruso(intruso) && !c.enGrupo(intruso), isTrue, reason: '${c.id}: ${intruso.nombre}');
        final List<VocabItem> todosItems = <VocabItem>[for (final ChoiceOption o in r.options) _v(o.id)];
        for (final VocabItem d in _distractores(r)) {
          expect(c.enGrupo(d) && !c.intruso(d), isTrue, reason: '${c.id}: ${d.nombre} no es del grupo');
        }
        expect(IntrusoGenerator.ambiguo(todosItems, intruso), isFalse, reason: '${c.id}: hay otro intruso posible entre ${todosItems.map((VocabItem v) => v.nombre).join(', ')}');
      }
    }
    expect(rondas, greaterThan(1000));
  });

  test('¿Qué siento?: concordancia de género y distractores que no también valdrían', () {
    final EmocionesGenerator g = EmocionesGenerator();
    final List<String> masculinas = <String>[for (final Emocion e in EmocionesGenerator.emociones) if (e.masculino != e.femenino) e.masculino];
    for (int seed = 0; seed < 2000; seed++) {
      final AgeBand band = <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8][seed % 3];
      final ChoiceRound r = g.next(Rng(seed), band, 1 + (seed ~/ 3) % 4);
      final Situacion? s = EmocionesGenerator.situaciones.where((Situacion x) => r.instruction.startsWith(x.texto)).firstOrNull;
      if (s == null) {
        continue;
      }
      final String todo = <String>[r.instruction, r.explain, r.praise ?? '', r.hint, ...r.options.map((ChoiceOption o) => o.label)].join(' ');
      if (s.genero == 'f') {
        for (final String m in masculinas) {
          expect(RegExp('\\b$m\\b').hasMatch(todo), isFalse, reason: '«$m» con ${s.quien}: $todo');
        }
      }
      // En "¿cómo se siente?" las opciones son emociones: ninguna incorrecta
      // está entre las que también tendrían sentido.
      if (r.options.every((ChoiceOption o) => EmocionesGenerator.emociones.any((Emocion e) => e.id == o.id))) {
        expect(r.correctId, s.emocion, reason: s.texto);
        for (final ChoiceOption o in r.options) {
          if (o.id != r.correctId) {
            expect(s.tambien.contains(o.id), isFalse, reason: '${s.texto}: ${o.id} también sería razonable');
          }
        }
      }
    }
  });

  test('M9: el intruso numérico tiene una sola respuesta y ¿Qué sigue? no ofrece negativos', () {
    final IntrusoGenerator intruso = IntrusoGenerator();
    int vistas = 0;
    for (int seed = 0; seed < 400; seed++) {
      final ChoiceRound r = intruso.numbersRound(Rng(seed));
      if (r.instruction != '¿Qué número no va con los demás?') {
        continue;
      }
      vistas += 1;
      final List<int> numeros = <int>[for (final ChoiceOption o in r.options) int.parse(o.id.substring(1))];
      final int elIntruso = int.parse(r.correctId.substring(1));
      expect(IntrusoGenerator.numerosAmbiguos(numeros, elIntruso), isFalse, reason: '$numeros con intruso $elIntruso');
    }
    expect(vistas, greaterThan(300));
    final PatronesGenerator patrones = PatronesGenerator();
    for (int level = 1; level <= 4; level++) {
      for (int seed = 0; seed < 300; seed++) {
        final ChoiceRound r = patrones.next(Rng(seed * 7 + level), AgeBand.b9a11, level);
        for (final ChoiceOption o in r.options) {
          final int? n = int.tryParse(o.label);
          if (n != null) {
            expect(n, greaterThanOrEqualTo(0), reason: 'nivel $level semilla $seed');
          }
        }
      }
    }
  });

  test('M10: la balanza compara cosas distintas y dice cuál pesa más de verdad', () {
    final CocinaGenerator cocina = CocinaGenerator();
    int pesoDe(String nombre) => CocinaGenerator.pesos[Vocab.all.firstWhere((VocabItem v) => v.nombre == nombre).id]!;
    for (int seed = 0; seed < 600; seed++) {
      final ChoiceRound r = cocina.balanza(Rng(seed));
      final String izq = r.options.firstWhere((ChoiceOption o) => o.id == 'izq').label;
      final String der = r.options.firstWhere((ChoiceOption o) => o.id == 'der').label;
      expect(izq, isNot(der), reason: 'semilla $seed');
      final int pa = pesoDe(izq);
      final int pb = pesoDe(der);
      final double razon = pa > pb ? pa / pb : pb / pa;
      if (r.correctId == 'igual') {
        expect(razon, lessThanOrEqualTo(1.2), reason: '$izq y $der no pesan lo mismo');
        continue;
      }
      expect(razon, greaterThanOrEqualTo(4), reason: '$izq y $der pesan casi lo mismo');
      final bool mas = r.instruction == '¿Qué pesa más?';
      final String elegido = r.correctId == 'izq' ? izq : der;
      final String otro = r.correctId == 'izq' ? der : izq;
      expect(mas ? pesoDe(elegido) > pesoDe(otro) : pesoDe(elegido) < pesoDe(otro), isTrue, reason: '${r.instruction} $izq ($pa g) o $der ($pb g)');
    }
  });
}
