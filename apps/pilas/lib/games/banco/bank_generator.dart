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

  /// Pista propia de la pregunta. Nunca descarta opciones: orienta a pensar.
  final String? pista;
  final List<String>? emojis;

  /// Pictograma grande que acompaña a la pregunta.
  final String? promptEmoji;
  final String? promptCaption;
}

/// Generador de rondas a partir de un banco de preguntas. Elige preguntas del
/// tramo cuyo nivel esté cerca del nivel actual, evita repetir las últimas y
/// baraja las opciones (la respuesta no queda siempre en el mismo lugar).
class BankGenerator implements ChoiceGenerator {
  BankGenerator(this.questions, {this.shuffleOptions = true, this.pistaGeneral = const <AgeBand, String>{}});

  final List<BankQuestion> questions;
  final bool shuffleOptions;

  /// Pista para las preguntas sin pista propia, por tramo. Orienta a pensar
  /// sin decir cuál opción no es.
  final Map<AgeBand, String> pistaGeneral;
  final List<BankQuestion> _recent = <BankQuestion>[];

  static const String pistaPorDefecto = 'Vuelve a escuchar la pregunta y piensa en cada opción antes de tocar.';

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

  /// Pista de [q]: la propia o la general del tramo.
  String hintFor(BankQuestion q, AgeBand band) => q.pista ?? pistaGeneral[band] ?? pistaPorDefecto;

  ChoiceRound toRound(Rng rng, BankQuestion q, AgeBand band) {
    final List<int> idx = <int>[for (int i = 0; i < q.opciones.length; i++) i];
    if (shuffleOptions) {
      rng.shuffle(idx);
    }
    final bool lee = band.readsText;
    final bool conEmoji = q.emojis != null && q.emojis!.length == q.opciones.length;
    final List<ChoiceOption> options = <ChoiceOption>[];
    for (final int i in idx) {
      final String texto = q.opciones[i];
      final String? emoji = conEmoji ? q.emojis![i] : null;
      if (emoji != null && !lee) {
        options.add(Opt.emoji('o$i', emoji, texto));
      } else if (emoji != null) {
        options.add(Opt.textWithEmoji('o$i', texto, emoji));
      } else {
        options.add(Opt.sentence('o$i', texto, fontSize: texto.length > 30 ? 17 : 19));
      }
    }
    double aspect = 1.0;
    if (!conEmoji) {
      aspect = 3.2;
    } else if (lee) {
      aspect = 1.3;
    }
    return ChoiceRound(
      instruction: q.texto,
      options: options,
      correctId: 'o${q.correcta}',
      hint: hintFor(q, band),
      explain: q.explicacion,
      prompt: q.promptEmoji == null ? null : (BuildContext context) => BigPrompt(child: EmojiImage(q.promptEmoji!, size: 84), caption: q.promptCaption),
      readOptionsAloud: !lee,
      optionSize: lee ? 72 : 96,
      optionAspect: aspect,
    );
  }
}
