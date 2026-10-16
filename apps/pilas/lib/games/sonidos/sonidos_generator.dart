import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';

/// Sonidos y letras: conciencia fonológica. Se nombra el sonido ("mmm"), no
/// el nombre de la letra ("eme"), y las sílabas van antes que las letras.
class SonidosGenerator implements ChoiceGenerator {
  static const List<String> vocales = <String>['a', 'e', 'i', 'o', 'u'];
  static const List<String> consonantesFaciles = <String>['m', 'p', 's', 'l', 't', 'n'];
  static const List<String> consonantesMas = <String>['d', 'c', 'b', 'g', 'r', 'f', 'j', 'v', 'z'];

  /// Cómo suena cada letra, para la voz.
  static const Map<String, String> sonido = <String, String>{
    'a': 'a', 'e': 'e', 'i': 'i', 'o': 'o', 'u': 'u',
    'm': 'mmm', 'p': 'p', 's': 'sss', 'l': 'lll', 't': 't', 'n': 'nnn',
    'd': 'd', 'c': 'k', 'b': 'b', 'g': 'g', 'r': 'rrr', 'f': 'fff', 'j': 'j', 'v': 'b', 'z': 'sss',
  };

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band != AgeBand.b3a4 && level >= 3 && rng.chance(0.5)) {
      return _silabasRound(rng, level);
    }
    List<String> letras;
    int count;
    if (band == AgeBand.b3a4) {
      letras = vocales;
      count = level <= 2 ? 3 : 4;
    } else {
      letras = level <= 1 ? vocales : (level == 2 ? consonantesFaciles : <String>[...consonantesFaciles, ...consonantesMas]);
      count = level <= 2 ? 3 : 4;
    }
    for (int attempt = 0; attempt < 30; attempt++) {
      final String letra = rng.pick(letras);
      final List<VocabItem> con = Vocab.startingWith(letra);
      if (con.isEmpty) {
        continue;
      }
      final VocabItem correcta = rng.pick(con);
      final List<VocabItem> otras = Vocab.all.where((VocabItem v) {
        if (v.nombre.contains(' ')) {
          return false;
        }
        final String ini = _plain(v.nombre.substring(0, 1));
        if (ini == letra) {
          return false;
        }
        // Evita vocales distintas pero confundibles para los más pequeños.
        return true;
      }).toList();
      if (otras.length < count - 1) {
        continue;
      }
      final List<VocabItem> distractores = rng.sample(otras, count - 1);
      final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcta), for (final VocabItem v in distractores) Opt.vocab(v)];
      rng.shuffle(options);
      final String mayus = letra.toUpperCase();
      final String snd = sonido[letra] ?? letra;
      return ChoiceRound(
        instruction: '¿Cuál empieza con $snd?',
        prompt: (BuildContext context) => BigPrompt(
          child: Text('$mayus $letra', style: const TextStyle(fontFamily: 'Andika', fontSize: 72, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
        ),
        options: options,
        correctId: correcta.id,
        hint: 'Escucha el principio: ${_silabaInicial(correcta)}... ${correcta.nombre}.',
        explain: '${_cap(correcta.nombre)} empieza con $snd: ${_silabaInicial(correcta)}, ${correcta.nombre}.',
        praise: '${_cap(correcta.nombre)} empieza con $snd.',
      );
    }
    return _silabasRound(rng, level);
  }

  /// Contar sílabas: "¿cuál tiene tres sílabas?".
  ChoiceRound _silabasRound(Rng rng, int level) {
    final int target = rng.pick(level >= 4 ? <int>[1, 2, 3, 4] : <int>[2, 3]);
    final List<VocabItem> conTarget = Vocab.withSyllables(target);
    final List<VocabItem> otras = Vocab.all.where((VocabItem v) => v.silabas.length != target && !v.nombre.contains(' ')).toList();
    if (conTarget.isEmpty) {
      return _silabasRound(rng, 1);
    }
    final VocabItem correcta = rng.pick(conTarget);
    final List<VocabItem> distractores = rng.sample(otras, 2);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcta), for (final VocabItem v in distractores) Opt.vocab(v)];
    rng.shuffle(options);
    final String palabra = _enLetras(target);
    final String palmas = correcta.silabas.join(', ');
    return ChoiceRound(
      instruction: '¿Cuál palabra tiene $palabra ${target == 1 ? 'sílaba' : 'sílabas'}?',
      prompt: (BuildContext context) => BigPrompt(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < target; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: PilasColors.amarillo, shape: BoxShape.circle)),
              ),
          ],
        ),
        caption: 'Aplaude cada sílaba',
      ),
      options: options,
      correctId: correcta.id,
      hint: 'Aplaude despacio: $palmas. ¿Cuántas palmas?',
      explain: '${_cap(correcta.nombre)} tiene $palabra ${target == 1 ? 'sílaba' : 'sílabas'}: $palmas.',
    );
  }

  static String _silabaInicial(VocabItem v) => v.silabas.first;

  static String _enLetras(int n) {
    const List<String> nombres = <String>['cero', 'una', 'dos', 'tres', 'cuatro', 'cinco'];
    return n < nombres.length ? nombres[n] : '$n';
  }

  static String _plain(String s) {
    const Map<String, String> m = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    final String low = s.toLowerCase();
    return m[low] ?? low;
  }

  static String _cap(String s) => s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);
}
