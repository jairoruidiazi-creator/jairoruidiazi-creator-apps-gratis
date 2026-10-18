import 'package:flutter/material.dart';

import '../../content/fonemas.dart';
import '../../content/vocab.dart';
import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Sonidos y letras: conciencia fonológica en el español de Colombia.
///
/// - Se compara por sonido, no por letra (ver [Fonema]): con seseo, "zapato"
///   empieza como "sol"; con yeísmo, "llave" como "yoyó"; la hache no suena,
///   así que "hormiga" empieza como "oso".
/// - La voz nunca dice una letra sola (los motores de voz leen el nombre de la
///   letra, "eme", y no su sonido): el sonido se nombra con una palabra
///   modelo, "¿cuál empieza con el mismo sonido que manzana?".
/// - Las rondas de letra muestran la letra escrita y la voz dice "esta
///   letra"; lo que se ve y lo que se oye coinciden.
/// - Los distractores nunca empiezan con el mismo sonido, ni con uno que se le
///   parece mucho (m y n, p y b, t y d, k y g, g y j, l y r, y y ch).
class SonidosGenerator implements ChoiceGenerator {
  /// Palabra modelo de cada sonido (debe estar en el vocabulario).
  static const Map<String, String> modelo = <String, String>{
    'a': 'avion', 'e': 'elefante', 'i': 'isla', 'o': 'oso', 'u': 'uvas',
    'm': 'manzana', 'p': 'pato', 's': 'sol', 'l': 'luna', 't': 'tomate', 'n': 'nube',
    'b': 'barco', 'k': 'casa', 'd': 'dado', 'g': 'gato', 'x': 'jirafa', 'r': 'raton', 'f': 'fresa', 'ch': 'chocolate', 'y': 'llave',
  };

  /// Más palabras modelo para los sonidos que tienen pocas palabras en el
  /// vocabulario: con la u, el modelo cambia entre uvas, uñas, unicornio y
  /// uniforme, y la respuesta correcta no es siempre la misma.
  static const Map<String, List<String>> otrosModelos = <String, List<String>>{
    'u': <String>['unas', 'unicornio', 'uniforme'],
  };

  /// La palabra modelo de una ronda.
  static VocabItem modeloDe(Rng rng, String f) {
    final List<String> ids = <String>[modelo[f]!, ...?otrosModelos[f]];
    return Vocab.item(ids.length == 1 ? ids.first : rng.pick(ids));
  }

  /// Letras de las rondas de escritura: al principio de palabra suenan siempre
  /// igual (la a de "avión", la eme de "mango"...).
  static const List<String> letrasClaras = <String>['a', 'e', 'i', 'o', 'u', 'm', 'p', 't', 'n', 'l', 'f', 'd'];

  static const List<List<String>> _parecidos = <List<String>>[
    <String>['m', 'n'],
    <String>['p', 'b'],
    <String>['t', 'd'],
    <String>['k', 'g'],
    <String>['g', 'x'],
    <String>['l', 'r'],
    <String>['y', 'ch'],
  ];

  static bool seParecen(String a, String b) {
    if (a == b) {
      return true;
    }
    for (final List<String> p in _parecidos) {
      if (p.contains(a) && p.contains(b)) {
        return true;
      }
    }
    return false;
  }

  static bool esVocal(String f) => Fonema.vocales.contains(f);

  /// Palabras sueltas del vocabulario (sin espacios), con su sonido inicial.
  static final List<VocabItem> palabras = Vocab.all.where((VocabItem v) => !v.nombre.contains(' ')).toList();

  static String sonidoDe(VocabItem v) => Fonema.inicial(v.nombre);

  static String primeraLetra(VocabItem v) {
    const Map<String, String> sin = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};
    final String c = v.nombre.substring(0, 1).toLowerCase();
    return sin[c] ?? c;
  }

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band == AgeBand.b3a4) {
      // Solo vocales. Niveles: 3 opciones con distractores que empiezan con
      // consonante; 3 con cualquiera; 4 con consonantes; 4 con otras vocales.
      final String v = rng.pick(Fonema.vocales);
      switch (level) {
        case 1:
          return sonido(rng, v, 3, distractores: Distractores.consonantes);
        case 2:
          return sonido(rng, v, 3, distractores: Distractores.cualquiera);
        case 3:
          return sonido(rng, v, 4, distractores: Distractores.consonantes);
        default:
          return sonido(rng, v, 4, distractores: Distractores.vocales);
      }
    }
    // 5 a 6 años.
    switch (level) {
      case 1:
        return sonido(rng, rng.pick(Fonema.vocales), 4, distractores: Distractores.cualquiera);
      case 2:
        return sonido(rng, rng.pick(Fonema.consonantesFaciles), 3, distractores: Distractores.cualquiera);
      case 3:
        if (rng.chance(0.4)) {
          return silabas(rng, <int>[2, 3]);
        }
        return sonido(rng, rng.pick(<String>[...Fonema.consonantesFaciles, ...Fonema.consonantesMas]), 3, distractores: Distractores.cualquiera);
      default:
        if (rng.chance(0.5)) {
          return silabas(rng, <int>[1, 2, 3, 4]);
        }
        return letra(rng, rng.pick(letrasClaras), 3);
    }
  }

  /// "¿Cuál empieza con el mismo sonido que oso?"
  ChoiceRound sonido(Rng rng, String f, int count, {required Distractores distractores}) {
    final VocabItem modeloItem = modeloDe(rng, f);
    final List<VocabItem> correctas = palabras.where((VocabItem v) => v.id != modeloItem.id && sonidoDe(v) == f).toList();
    final List<VocabItem> otras = palabras.where((VocabItem v) {
      final String g = sonidoDe(v);
      if (g == 'w' || g.isEmpty || seParecen(f, g) || v.id == modeloItem.id) {
        return false;
      }
      switch (distractores) {
        case Distractores.consonantes:
          return !esVocal(g);
        case Distractores.vocales:
          return esVocal(g);
        case Distractores.cualquiera:
          return true;
      }
    }).toList();
    final VocabItem correcta = rng.pick(correctas);
    final List<VocabItem> elegidas = _distintas(rng, otras, count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcta), for (final VocabItem v in elegidas) Opt.vocab(v)];
    rng.shuffle(options);
    final String nota = _nota(correcta, modeloItem);
    return ChoiceRound(
      instruction: '¿Cuál empieza con el mismo sonido que ${modeloItem.nombre}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(modeloItem.emoji, size: 96, semanticsLabel: modeloItem.nombre), caption: modeloItem.nombre),
      options: options,
      correctId: correcta.id,
      hint: 'Escucha cómo empieza ${modeloItem.nombre}. Di cada palabra despacio y busca la que empieza igual.',
      explain: '${Es.cap(correcta.nombre)} empieza con el mismo sonido que ${modeloItem.nombre}$nota.',
      praise: '${Es.cap(correcta.nombre)} empieza como ${modeloItem.nombre}.',
      readOptionsAloud: true,
    );
  }

  /// Explicación de por qué suenan igual aunque se escriban distinto.
  static String _nota(VocabItem correcta, VocabItem modeloItem) {
    if (correcta.nombre.toLowerCase().startsWith('h')) {
      return ': la hache no suena';
    }
    if (!Fonema.mismaLetraInicial(correcta.nombre, modeloItem.nombre)) {
      return ': suenan igual aunque se escriben con letras distintas';
    }
    return '';
  }

  /// "¿Cuál palabra empieza con esta letra?" con la letra escrita.
  ChoiceRound letra(Rng rng, String l, int count) {
    final VocabItem modeloItem = modeloDe(rng, l);
    final List<VocabItem> correctas = palabras.where((VocabItem v) => v.id != modeloItem.id && primeraLetra(v) == l && sonidoDe(v) == l).toList();
    final List<VocabItem> otras = palabras.where((VocabItem v) {
      final String g = sonidoDe(v);
      return g != 'w' && g.isNotEmpty && !seParecen(l, g) && primeraLetra(v) != l && v.id != modeloItem.id;
    }).toList();
    final VocabItem correcta = rng.pick(correctas);
    final List<VocabItem> elegidas = _distintas(rng, otras, count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcta), for (final VocabItem v in elegidas) Opt.vocab(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál palabra empieza con esta letra?',
      prompt: (BuildContext context) => BigPrompt(
        child: Semantics(
          label: 'Letra ${l.toUpperCase()}',
          child: Text('${l.toUpperCase()} $l', style: TextStyle(fontFamily: 'Andika', fontSize: 72, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
        ),
      ),
      options: options,
      correctId: correcta.id,
      hint: 'Esta letra suena como al principio de ${modeloItem.nombre}. Di cada palabra despacio.',
      explain: '${Es.cap(correcta.nombre)} empieza con esta letra, que suena como al principio de ${modeloItem.nombre}.',
      praise: '${Es.cap(correcta.nombre)} empieza con esta letra.',
      readOptionsAloud: true,
    );
  }

  /// Contar sílabas: "¿cuál palabra tiene tres sílabas?".
  ChoiceRound silabas(Rng rng, List<int> posibles) {
    final int target = rng.pick(posibles);
    final List<VocabItem> conTarget = Vocab.withSyllables(target);
    final List<VocabItem> otras = palabras.where((VocabItem v) => v.silabas.length != target).toList();
    final VocabItem correcta = rng.pick(conTarget);
    final List<VocabItem> distractores = _distintas(rng, otras, 2, porSilabas: true, evitar: target);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcta), for (final VocabItem v in distractores) Opt.vocab(v)];
    rng.shuffle(options);
    final String cuantas = Es.cantidadEnPalabras(target, 'sílaba', genero: 'f');
    final String palmas = correcta.silabas.join(', ');
    return ChoiceRound(
      instruction: '¿Cuál palabra tiene $cuantas?',
      prompt: (BuildContext context) {
        final PilasPalette pal = PilasPalette.of(context);
        return BigPrompt(
          child: Semantics(
            label: cuantas,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < target; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(width: 44, height: 44, decoration: BoxDecoration(color: pal.destacado, shape: BoxShape.circle, border: Border.all(color: pal.tinta, width: 2))),
                  ),
              ],
            ),
          ),
          caption: 'Aplaude cada sílaba',
        );
      },
      options: options,
      correctId: correcta.id,
      hint: 'Di cada palabra despacio y aplaude una vez por cada sílaba.',
      explain: '${Es.cap(correcta.nombre)} tiene $cuantas: $palmas.',
      praise: '${Es.cap(correcta.nombre)}: $palmas.',
      readOptionsAloud: true,
    );
  }

  /// [n] palabras distintas entre sí (por sonido inicial, o por número de
  /// sílabas si [porSilabas]), para que ningún distractor se repita.
  static List<VocabItem> _distintas(Rng rng, List<VocabItem> pool, int n, {bool porSilabas = false, int evitar = -1}) {
    final List<VocabItem> mezcla = rng.shuffled(pool);
    final List<VocabItem> out = <VocabItem>[];
    final Set<String> vistos = <String>{};
    for (final VocabItem v in mezcla) {
      final String clave = porSilabas ? '${v.silabas.length}' : sonidoDe(v);
      if (porSilabas && v.silabas.length == evitar) {
        continue;
      }
      if (vistos.contains(clave)) {
        continue;
      }
      vistos.add(clave);
      out.add(v);
      if (out.length == n) {
        return out;
      }
    }
    // Si no alcanzan claves distintas, se completa sin repetir palabras.
    for (final VocabItem v in mezcla) {
      if (out.length == n) {
        break;
      }
      if (!out.contains(v)) {
        out.add(v);
      }
    }
    return out;
  }
}

/// Con qué empiezan los distractores de una ronda de sonido vocal.
enum Distractores { consonantes, vocales, cualquiera }
