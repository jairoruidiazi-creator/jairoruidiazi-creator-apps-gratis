import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/cuentos.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/clasifica/clasifica_generator.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/figuras/figuras_generator.dart';
import 'package:pilas/games/laberinto/maze.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/oracion/oracion_generator.dart';
import 'package:pilas/games/palabra/palabra_round.dart';
import 'package:pilas/games/rutinas/rutinas_generator.dart';
import 'package:pilas/games/shell/order_game_screen.dart';
import 'package:pilas/games/shell/tile_order_board.dart';
import 'package:pilas/games/shell/widgets.dart';
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

/// Palabras que empiezan con *a* tónica pero no son sustantivos: con ellas
/// "la" y "una" sí van ("la alta montaña", "la ata a la silla").
const Set<String> _aTonicaNoSustantivos = <String>{
  'alta', 'altas', 'ancha', 'agria', 'árida', 'ávida', 'áspera', 'ágil', 'árabe', 'ácida', 'ata', 'alza', 'asa', 'ama', 'abre', 'arma', 'anda', 'habla',
  'ha', 'has', 'han', 'hay', 'hace', 'hago', 'hacen', 'halla',
};

/// Género de los sustantivos de la app (vocabulario, figuras, objetos y
/// grupos de animales), para revisar artículos y demostrativos.
final Map<String, String> generos = () {
  final Map<String, String> g = <String, String>{'agua': 'f', 'hada': 'f', 'hacha': 'f', 'ala': 'f', 'arpa': 'f', 'aula': 'f', 'hambre': 'f'};
  for (final VocabItem v in Vocab.all) {
    if (!v.plural) {
      g[v.nombre.toLowerCase()] = v.genero;
    }
  }
  for (final ShapeKind k in ShapeKind.values) {
    g[nombreForma(k)] = generoForma(k);
  }
  for (final ObjetoForma o in FigurasGenerator.objetos) {
    g[o.nombre] = o.genero;
  }
  for (final GrupoAnimal a in ClasificaGenerator.grupos.values) {
    g[a.nombre] = a.genero;
  }
  return g;
}();

/// Reglas de concordancia que valen también para pedazos de texto (los
/// literales del código, que se completan con otros datos): artículos,
/// demostrativos, contracciones y la *a* tónica.
List<String> concordancia(String texto) {
  final List<String> out = <String>[];
  final String t = texto.toLowerCase();
  void no(Pattern p, String que) {
    final Iterable<Match> ms = p.allMatches(t);
    if (ms.isNotEmpty) {
      out.add('$que: «${ms.first.group(0)}»');
    }
  }

  const String l = 'a-záéíóúñü';
  // Contracciones obligatorias: "al" y "del".
  no(RegExp('(^|[^$l])a el\\b'), 'falta contraer "al"');
  no(RegExp('(^|[^$l])de el\\b'), 'falta contraer "del"');
  // Femeninos con a tónica: "el águila", "un ave" (no "la águila", "una ave").
  for (final Match m in RegExp('(^|[^$l])(la|una) (h?[aá][$l]*)').allMatches(t)) {
    final String w = m.group(3)!;
    if (Es.aTonica(w) && !_aTonicaNoSustantivos.contains(w)) {
      out.add('ante "a" tónica va "el" o "un": «${m.group(0)!.trim()}»');
    }
  }
  // El demostrativo concuerda con el sustantivo: "Esta es la estrella".
  no(RegExp('(^|[^$l])(este|ese|aquel) (es|era|fue) (la|una|las|unas)(?![$l])'), 'demostrativo masculino con un sustantivo femenino');
  no(RegExp('(^|[^$l])(estos|esos|aquellos) (son|eran) (la|las|una|unas)(?![$l])'), 'demostrativo masculino con un sustantivo femenino');
  no(RegExp('(^|[^$l])(estas|esas|aquellas) (son|eran) (el|los|un|unos)(?![$l])'), 'demostrativo femenino con un sustantivo masculino');
  for (final Match m in RegExp('(^|[^$l])(esta|esa|aquella|este|ese|aquel) (es|era|fue) (el|un) ([$l]+)').allMatches(t)) {
    final bool demFem = m.group(2)!.endsWith('a');
    final String w = m.group(5)!;
    final String? g = generos[w];
    final bool nombreFem = g == 'f';
    if (g == null && demFem && !Es.aTonica(w)) {
      out.add('demostrativo femenino con un sustantivo masculino: «${m.group(0)!.trim()}»');
    } else if (g != null && demFem != nombreFem) {
      out.add('el demostrativo no concuerda con "$w": «${m.group(0)!.trim()}»');
    }
  }
  // Artículos y demostrativos pegados a un sustantivo conocido.
  for (final MapEntry<String, String> e in generos.entries) {
    final String n = RegExp.escape(e.key);
    const String fin = '(?![$l])';
    if (e.value == 'f' && Es.aTonica(e.key)) {
      no(RegExp('(^|[^$l])(la|una|este|ese|aquel) $n$fin'), '"${e.key}" lleva "el" o "un" y demostrativo femenino');
    } else if (e.value == 'f') {
      no(RegExp('(^|[^$l])(el|un|del|al|este|ese|aquel) $n$fin'), '"${e.key}" es femenino');
    } else {
      no(RegExp('(^|[^$l])(la|una|esta|esa|aquella) $n$fin'), '"${e.key}" es masculino');
    }
  }
  return out;
}

/// Revisa un texto que la app muestra o lee en voz alta. Devuelve los
/// problemas encontrados (vacío = bien).
List<String> problemas(String texto, {bool frase = true}) {
  final List<String> out = concordancia(texto);
  final String t = texto.toLowerCase();
  void no(Pattern p, String que, {bool tal = false}) {
    final Iterable<Match> ms = p.allMatches(tal ? texto : t);
    if (ms.isNotEmpty) {
      out.add('$que: «${ms.first.group(0)}»');
    }
  }

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

/// Anota un hallazgo ya revisado (una sola vez por texto).
void revisarHallazgo(String texto, String detalle) {
  _hallazgos.putIfAbsent(texto, () => '$detalle\n  «$texto»');
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
    // Demostrativos y a tónica (segunda ronda de la auditoría).
    expect(problemas('Este es la estrella.'), isNotEmpty);
    expect(problemas('Esta es la estrella.'), isEmpty);
    expect(problemas('Este es el círculo.'), isEmpty);
    expect(problemas('Esta es el círculo.'), isNotEmpty);
    expect(problemas('Estos son las estrellas.'), isNotEmpty);
    expect(problemas('¿Cuál es una ave?'), isNotEmpty);
    expect(problemas('El pato es un ave.'), isEmpty);
    expect(problemas('La águila es un ave.'), isNotEmpty);
    expect(problemas('El águila vuela alto.'), isEmpty);
    expect(problemas('Esta es el águila.'), isEmpty);
    expect(problemas('Este es el águila.'), isNotEmpty);
    expect(problemas('Las águilas vuelan y la abeja también.'), isEmpty);
    expect(problemas('El abeja vuela.'), isNotEmpty);
    expect(problemas('La gato duerme.'), isNotEmpty);
    expect(problemas('Lleva al águila hasta su nido.'), isEmpty);
    expect(problemas('Subimos a la alta montaña.'), isEmpty);
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
      S.letraLectoresDetalle,
      S.quedanMinutos(1),
      S.quedanMinutos(7),
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

  test('Es pone «el» y «un» ante la a tónica, y el demostrativo según el género', () {
    for (final String w in <String>['águila', 'ave', 'agua', 'hacha', 'hada', 'aula', 'hambre', 'ala', 'alma', 'arpa', 'área', 'ancla', 'haba']) {
      expect(Es.aTonica(w), isTrue, reason: w);
    }
    for (final String w in <String>['abeja', 'araña', 'arepa', 'aguja', 'ambulancia', 'ardilla', 'arena', 'harina', 'hamaca', 'aldea', 'hormiga', 'a', 'hache', 'Ana', 'acción', 'abuela']) {
      expect(Es.aTonica(w), isFalse, reason: w);
    }
    expect(Es.con('f', 'águila'), 'el águila');
    expect(Es.con('f', 'ave', definido: false), 'un ave');
    expect(Es.con('f', 'águilas', plural: true), 'las águilas');
    expect(Es.con('f', 'abeja'), 'la abeja');
    expect(Es.aEl('f', 'águila'), 'al águila');
    expect(Es.deEl('f', 'águila'), 'del águila');
    expect(Es.cantidadEnPalabras(1, 'ave', genero: 'f'), 'un ave');
    expect(Es.cantidadEnPalabras(2, 'ave', genero: 'f'), 'dos aves');
    expect(Es.este('f'), 'esta');
    expect(Es.este('m'), 'este');
    expect(Es.este('f', plural: true), 'estas');
    final VocabItem aguila = Vocab.all.firstWhere((VocabItem v) => v.id == 'aguila');
    expect(aguila.conArticulo, 'el águila');
    expect(aguila.aEl, 'al águila');
    expect(ClasificaGenerator.grupos['ave']!.esUn, 'es un ave');
  });

  test('Barrido de los textos escritos en el código: artículos, demostrativos y contracciones', () {
    // Cada literal de lib/ (sin comentarios ni el propio motor de gramática)
    // se parte donde lleva datos (\$x, \${…}) y cada pedazo pasa por las reglas
    // de concordancia. Así se revisan también los textos que ningún generador
    // de las pruebas produce (tableros, ajustes, panel de adultos).
    final RegExp literal = RegExp(r'''(?<![rA-Za-z0-9_])'((?:[^'\\\n]|\\.)*)'|(?<![rA-Za-z0-9_])"((?:[^"\\\n]|\\.)*)"''');
    final RegExp dato = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_.]*');
    int literales = 0;
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.endsWith('core/es.dart')) {
        continue;
      }
      final List<String> lineas = f.readAsLinesSync();
      for (int i = 0; i < lineas.length; i++) {
        final String linea = lineas[i].trimLeft();
        if (linea.startsWith('//')) {
          continue;
        }
        for (final Match m in literal.allMatches(linea)) {
          final String texto = (m.group(1) ?? m.group(2) ?? '').replaceAll(r"\'", "'");
          for (final String pedazo in texto.split(dato)) {
            literales += 1;
            final List<String> p = concordancia(pedazo);
            if (p.isNotEmpty) {
              revisarHallazgo(pedazo, '${f.path}:${i + 1}: ${p.join('; ')}');
            }
          }
        }
      }
    }
    expect(literales, greaterThan(3000));
    sinHallazgos();
  });
}
