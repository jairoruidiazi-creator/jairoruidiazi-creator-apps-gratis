import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Pregunta de un banco: tramo, nivel (1 a 4), texto, opciones y explicación.
/// Si [emojis] está presente, cada opción lleva su pictograma (obligatorio
/// para los tramos que no leen).
class BankQuestion {
  const BankQuestion(
    this.band,
    this.level,
    this.texto,
    this.opciones,
    this.correcta,
    this.explicacion, {
    this.pista,
    this.emojis,
    this.promptEmoji,
    this.promptCaption,
  });

  final AgeBand band;
  final int level;
  final String texto;
  final List<String> opciones;
  final int correcta;
  final String explicacion;
  final String? pista;
  final List<String>? emojis;

  /// Pictograma grande que acompaña a la pregunta.
  final String? promptEmoji;
  final String? promptCaption;
}

/// Generador de rondas a partir de un banco de preguntas. Elige preguntas del
/// tramo cuyo nivel esté cerca del nivel actual y evita repetir las últimas.
class BankGenerator implements ChoiceGenerator {
  BankGenerator(this.questions, {this.shuffleOptions = true});

  final List<BankQuestion> questions;
  final bool shuffleOptions;
  final List<BankQuestion> _recent = <BankQuestion>[];

  List<BankQuestion> poolFor(AgeBand band, int level) {
    List<BankQuestion> pool = questions.where((BankQuestion q) => q.band == band && (q.level - level).abs() <= 1).toList();
    if (pool.length < 4) {
      pool = questions.where((BankQuestion q) => q.band == band).toList();
    }
    if (pool.isEmpty) {
      // Tramo sin preguntas propias: usa el tramo vecino más cercano.
      final List<AgeBand> vecinos = <AgeBand>[if (band.previous != null) band.previous!, if (band.next != null) band.next!];
      for (final AgeBand v in vecinos) {
        pool = questions.where((BankQuestion q) => q.band == v).toList();
        if (pool.isNotEmpty) {
          break;
        }
      }
    }
    return pool;
  }

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    final List<BankQuestion> pool = poolFor(band, level);
    List<BankQuestion> frescas = pool.where((BankQuestion q) => !_recent.contains(q)).toList();
    if (frescas.isEmpty) {
      _recent.clear();
      frescas = pool;
    }
    final BankQuestion q = rng.pick(frescas);
    _recent.add(q);
    if (_recent.length > 6) {
      _recent.removeAt(0);
    }
    return toRound(rng, q, band);
  }

  ChoiceRound toRound(Rng rng, BankQuestion q, AgeBand band) {
    final List<int> idx = <int>[for (int i = 0; i < q.opciones.length; i++) i];
    if (shuffleOptions) {
      rng.shuffle(idx);
    }
    final bool lee = band.readsText;
    final List<ChoiceOption> options = <ChoiceOption>[];
    for (final int i in idx) {
      final String texto = q.opciones[i];
      final String? emoji = q.emojis != null && i < q.emojis!.length ? q.emojis![i] : null;
      if (emoji != null && !lee) {
        options.add(Opt.emoji('o$i', emoji, texto));
      } else if (emoji != null) {
        options.add(Opt.textWithEmoji('o$i', texto, emoji));
      } else if (texto.length > 18) {
        options.add(Opt.sentence('o$i', texto));
      } else {
        options.add(Opt.text('o$i', texto, fontSize: 22));
      }
    }
    final bool largas = q.opciones.any((String o) => o.length > 22);
    return ChoiceRound(
      instruction: q.texto,
      options: options,
      correctId: 'o${q.correcta}',
      hint: q.pista ?? 'Piensa otra vez. ${_pistaGenerica(q)}',
      explain: q.explicacion,
      prompt: q.promptEmoji == null ? null : (BuildContext context) => BigPrompt(child: EmojiImage(q.promptEmoji!, size: 84), caption: q.promptCaption),
      columns: largas && lee ? 1 : 0,
      readOptionsAloud: !lee,
      optionSize: lee ? 72 : 96,
    );
  }

  String _pistaGenerica(BankQuestion q) {
    // Descarta en voz alta una opción incorrecta para reducir a dos.
    for (int i = 0; i < q.opciones.length; i++) {
      if (i != q.correcta) {
        return 'No es "${q.opciones[i]}".';
      }
    }
    return '';
  }
}
