import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/cuentos.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/laberinto/maze.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/oracion/oracion_generator.dart';
import 'package:pilas/games/palabra/palabra_round.dart';
import 'package:pilas/games/rutinas/rutinas_generator.dart';
import 'package:pilas/games/shell/order_game_screen.dart';
import 'package:pilas/games/shell/tile_order_board.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/ui/parent/family_guide_screen.dart';

import 'support/choice_generators.dart';

/// Palabras que terminan en s y aun así son singulares ("1 lunes", "1 mes").
const Set<String> _singularesConS = <String>{
  'mes', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'autobús', 'bus', 'compás', 'atlas', 'cactus', 'tórax',
  'virus', 'oasis', 'crisis', 'dosis', 'tos', 'país', 'gas', 'res', 'ciprés', 'anís', 'ananás', 'paraguas', 'cumpleaños',
  // No son sustantivos: "1 más 2", "el 1 es impar".
  'es', 'más', 'menos',
};

/// Revisa un texto que la app muestra o lee en voz alta. Devuelve los
/// problemas encontrados (vacío = bien).
List<String> problemas(String texto, {bool frase = true}) {
  final List<String> out = <String>[];
  final String t = texto.toLowerCase();
  void no(Pattern p, String que, {bool tal = false}) {
    final Iterable<Match> ms = p.allMatches(tal ? texto : t);
    if (ms.isNotEmpty) {
      out.add('$que: «${ms.first.group(0)}»');
    }
  }

  // Contracciones obligatorias: "al" y "del".
  no(RegExp(r'(^|[^a-záéíóúñü])a el\b'), 'falta contraer "al"');
  no(RegExp(r'(^|[^a-záéíóúñü])de el\b'), 'falta contraer "del"');
  // Número: "1 manzanas", "1 pasos".
  for (final Match m in RegExp(r'(^|[^0-9.,])1 ([a-záéíóúñü]+s)\b').allMatches(t)) {
    if (!_singularesConS.contains(m.group(2))) {
      out.add('plural después de 1: «${m.group(0)!.trim()}»');
    }
  }
  // Tildes de los números.
  no(RegExp(r'\b(veintidos|veintitres|veintiseis|dieciseis)\b'), 'número sin tilde');
  // Género de las figuras.
  no(RegExp(r'\b(el|un|del|al) estrellas?\b'), 'la estrella es femenina');
  no(RegExp(r'\bestrella pequeño\b'), 'la estrella es femenina');
  no(RegExp(r'\b(la|una) (círculo|cuadrado|triángulo|corazón|hexágono|rectángulo|óvalo|pentágono|octágono)\b'), 'figura masculina con artículo femenino');
  // La hora: "Es la una", "Son las tres".
  no(RegExp(r'\bson la una\b'), 'con la una el verbo va en singular');
  no(RegExp(r'\bes las (dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)\b'), 'con las demás horas el verbo va en plural');
  // Conjunciones: "e" delante de i, "u" delante de o.
  no(RegExp(r'(^|[^a-záéíóúñü])y (i|hi)(?!e|a|o)'), 'delante de "i" va "e"');
  no(RegExp(r'(^|[^a-záéíóúñü])o (o|ó|ho)'), 'delante de "o" va "u"');
  // Espacios y signos.
  no(RegExp(r'  '), 'doble espacio');
  no(RegExp(r' [,.;:?!]'), 'espacio antes de un signo');
  no(RegExp(r'[,;][^\s\d»"]'), 'falta espacio después de la coma');
  // Artículo y verbo con los sustantivos que van en plural (tijeras, uvas…).
  for (final VocabItem v in Vocab.all) {
    final String n = v.nombre.toLowerCase();
    if (v.plural) {
      no(RegExp('\\b(la|el|una|un|cada) ${RegExp.escape(n)}(?![a-záéíóúñü])'), 'artículo singular con "$n"');
      no(RegExp('\\b${RegExp.escape(n)} (cuesta|vale|vive|es|está|pesa) '), 'verbo singular con "$n"');
    } else if (!n.endsWith('s')) {
      // (No cuando cierra una lista: «el delfín y la tortuga viven en el mar».)
      no(RegExp('(?<!y )(?<!, )\\b(el|la) ${RegExp.escape(n)} (cuestan|valen|viven|pesan) '), 'verbo plural con "$n"');
    }
  }
  if (frase) {
    // Signos de apertura y cierre parejos.
    if ('¿'.allMatches(texto).length != '?'.allMatches(texto).length) {
      out.add('signos de pregunta sin pareja');
    }
    if ('¡'.allMatches(texto).length != '!'.allMatches(texto).length) {
      out.add('signos de exclamación sin pareja');
    }
    // Empieza con mayúscula (después de ¿, ¡ o comillas).
    final String inicio = texto.replaceFirst(RegExp(r'^[¿¡"«“ ]+'), '');
    if (inicio.isNotEmpty && RegExp(r'^[a-záéíóúñü]').hasMatch(inicio)) {
      out.add('empieza con minúscula');
    }
    // Después de un punto, mayúscula.
    // (Después de puntos suspensivos la oración puede seguir en minúscula.)
    no(RegExp(r'(?<![.…])[.!?] [a-záéíóúñü]'), 'minúscula después de un punto', tal: true);
    // Termina con un signo.
    if (!RegExp(r'[.!?…»")]$').hasMatch(texto.trim())) {
      out.add('no termina con punto ni signo');
    }
  }
  return out;
}

/// Problemas encontrados en la prueba en curso, por texto (los textos se
/// repiten en muchas semillas: basta con verlos una vez).
final Map<String, String> _hallazgos = <String, String>{};

void revisar(String texto, String donde, {bool frase = true}) {
  final List<String> p = problemas(texto, frase: frase);
  if (p.isNotEmpty) {
    _hallazgos.putIfAbsent(texto, () => '$donde: ${p.join('; ')}\n  «$texto»');
  }
}

/// Falla con todos los problemas encontrados (hasta 40) en lugar de solo el
/// primero, para poder corregirlos de una vez.
void sinHallazgos() {
  final List<String> h = _hallazgos.values.toList();
  _hallazgos.clear();
  expect(h, isEmpty, reason: '${h.length} textos con problemas:\n${h.take(40).join('\n')}');
}

void revisarRonda(ChoiceRound r, String donde) {
  revisar(r.instruction, '$donde (instrucción)');
  revisar(r.spokenInstruction, '$donde (voz)');
  revisar(r.hint, '$donde (pista)');
  revisar(r.explain, '$donde (explicación)');
  if (r.praise != null) {
    revisar(r.praise!, '$donde (felicitación)');
  }
  for (final ChoiceOption o in r.options) {
    revisar(o.label, '$donde (opción)', frase: false);
  }
}

void revisarOrden(OrderRound r, String donde) {
  revisar(r.instruction, '$donde (instrucción)');
  if (r.spoken != null) {
    revisar(r.spoken!, '$donde (voz)');
  }
  revisar(r.hint, '$donde (pista)');
  revisar(r.explain, '$donde (explicación)');
  if (r.praise != null) {
    revisar(r.praise!, '$donde (felicitación)');
  }
  for (final OrderTile t in r.ordered) {
    revisar(t.label, '$donde (ficha)', frase: false);
  }
}

void main() {
  test('Las reglas de la prueba detectan los errores que encontró la auditoría', () {
    expect(problemas('Lleva a el conejo hasta la zanahoria.'), isNotEmpty);
    expect(problemas('Hay 1 manzanas.'), isNotEmpty);
    expect(problemas('La tijeras cuesta diez mil pesos.'), isNotEmpty);
    expect(problemas('Cada uvas cuesta mil pesos.'), isNotEmpty);
    expect(problemas('¿Cuál es el estrella?'), isNotEmpty);
    expect(problemas('Veintidos.'), isNotEmpty);
    expect(problemas('Son la una en punto.'), isNotEmpty);
    expect(problemas('pinta la zona.'), isNotEmpty);
    expect(problemas('Las tijeras cuestan diez mil pesos y pagas con un billete de veinte mil pesos. ¿Cuánto te devuelven?'), isEmpty);
    expect(problemas('Lleva al conejo hasta la zanahoria.'), isEmpty);
    expect(problemas('Es la una y media.'), isEmpty);
    // Mayúscula después de un punto (pero no tras puntos suspensivos).
    expect(problemas('Muy bien. pinta otra zona.'), isNotEmpty);
    expect(problemas('Le preguntó a su perro Max. Max movió la cola.'), isEmpty);
    expect(problemas('Los monos trajeron hojas... y entre todos apagaron el fuego.'), isEmpty);
    // Concordancia con sujetos compuestos.
    expect(problemas('El camarón, el delfín y la tortuga viven en el mar.'), isEmpty);
    expect(problemas('La tortuga viven en el mar.'), isNotEmpty);
  });

  test('Barrido de gramática: miles de rondas de todos los juegos de elegir', () {
    int rondas = 0;
    for (final GeneratorCase c in choiceGeneratorCases()) {
      for (final AgeBand band in AgeBand.values) {
        if (!c.game.supports(band)) {
          continue;
        }
        for (int level = 1; level <= c.game.levelsFor(band); level++) {
          final ChoiceGenerator g = c.generator();
          for (int seed = 0; seed < 60; seed++) {
            revisarRonda(g.next(Rng(seed * 7919 + level * 13 + band.index), band, level), '${c.gameId} ${band.id} nivel $level semilla $seed');
            rondas += 1;
          }
        }
      }
    }
    expect(rondas, greaterThan(5000));
    sinHallazgos();
  });

  test('La tienda concuerda en número: «Las tijeras cuestan…»', () {
    final TiendaGenerator g = TiendaGenerator();
    bool vistoTijeras = false;
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= GameRegistry.byId('tienda')!.levelsFor(band); level++) {
        for (int seed = 0; seed < 150; seed++) {
          final TiendaRound r = g.next(Rng(seed * 104729 + level), band, level);
          if (r.choice != null) {
            revisarRonda(r.choice!, 'tienda ${band.id} nivel $level semilla $seed');
          } else {
            revisar(r.pago!.instruction, 'tienda (pagar) ${band.id} nivel $level semilla $seed');
          }
        }
      }
    }
    // Una ronda de vueltas con las tijeras, buscada a propósito.
    final VocabItem tijeras = Vocab.all.firstWhere((VocabItem v) => v.id == 'tijeras');
    expect(TiendaGenerator.productos, contains(tijeras));
    for (int seed = 0; seed < 4000 && !vistoTijeras; seed++) {
      final ChoiceRound r = g.vueltas(Rng(seed), 1000, 9000, 500, <int>[10000, 20000]);
      if (r.instruction.contains('tijeras')) {
        vistoTijeras = true;
        expect(r.instruction, startsWith('Las tijeras cuestan '));
        revisarRonda(r, 'tienda: vueltas con tijeras');
      }
    }
    expect(vistoTijeras, isTrue, reason: 'no salió ninguna ronda con las tijeras');
    sinHallazgos();
  });

  test('Juegos de ordenar, memoria y laberintos', () {
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 40; seed++) {
          final Rng rng = Rng(seed * 31 + level);
          if (GameRegistry.byId('palabra')!.supports(band)) {
            revisarOrden(palabraRound(rng, band, level), 'palabra ${band.id} nivel $level');
          }
          if (GameRegistry.byId('oracion')!.supports(band)) {
            revisarOrden(oracionRound(rng, band, level), 'oración ${band.id} nivel $level');
          }
          if (GameRegistry.byId('rutinas')!.supports(band)) {
            revisarOrden(rutinaRound(rng, band, level), 'rutinas ${band.id} nivel $level');
          }
          final MemoryBoard m = MemoryBoard.generate(rng, band, level);
          revisar(m.descripcion, 'memoria ${band.id} nivel $level');
          for (final MemoryCard c in m.cards) {
            revisar(c.label, 'memoria ${band.id} nivel $level (carta)', frase: false);
          }
        }
      }
    }
    for (final MazeTheme t in MazeTheme.all) {
      revisar('Lleva ${t.aHeroe} hasta ${t.metaConArticulo}.', 'laberinto ${t.heroeNombre}');
      revisar('${Es.cap(t.heroeConArticulo)} llegó ${t.aMeta}.', 'laberinto ${t.heroeNombre}');
    }
    sinHallazgos();
  });

  test('Cuentos, emociones y textos fijos', () {
    for (final Cuento c in CuentoBank.all) {
      revisar(c.titulo, 'cuento ${c.id} (título)', frase: false);
      for (final Pagina p in c.paginas) {
        revisar(p.texto, 'cuento ${c.id}');
      }
      for (final PreguntaCuento q in c.preguntas) {
        revisar(q.texto, 'cuento ${c.id} (pregunta)');
        revisar(q.explicacion, 'cuento ${c.id} (explicación)');
        if (q.pista != null) {
          revisar(q.pista!, 'cuento ${c.id} (pista)');
        }
        for (final OpcionCuento o in q.opciones) {
          revisar(o.texto, 'cuento ${c.id} (opción)', frase: false);
        }
      }
    }
    for (final String s in <String>[
      S.descansoTexto,
      S.limiteDetalle,
      S.altoContrasteDetalle,
      S.textoGrandeDetalle,
      S.zurdoDetalle,
      S.sinVozTexto,
      S.comoSeLogra,
      S.soloJuegoLibre,
      S.soporteTexto,
      S.cambiarConDescanso,
      S.acertasteDe(0, 10),
      S.acertasteDe(1, 10),
      S.acertasteDe(7, 10),
      S.acertasteDe(10, 10),
    ]) {
      revisar(s, 'texto fijo');
    }
    for (final GuideSection sec in FamilyGuideScreen.secciones) {
      revisar(sec.titulo, 'guía para familias (título)', frase: false);
      for (final String p in sec.parrafos) {
        revisar(p, 'guía para familias');
      }
    }
    for (int seed = 0; seed < 200; seed++) {
      for (final AgeBand band in <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8]) {
        revisarRonda(EmocionesGenerator().next(Rng(seed), band, 1 + seed % 4), 'emociones ${band.id}');
      }
    }
    sinHallazgos();
  });
}
