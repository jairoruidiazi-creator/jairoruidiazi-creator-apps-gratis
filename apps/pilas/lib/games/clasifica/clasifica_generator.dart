import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

class _Grupo {
  const _Grupo(this.id, this.tag, this.nombre, this.emoji, this.pregunta, this.articulo);

  final String id;
  final String tag;
  final String nombre;
  final String emoji;

  /// Cómo se pregunta por el grupo: "vive en el mar", "es un mamífero".
  final String pregunta;
  final String articulo;
}

/// Clasifica seres vivos: hábitats para los pequeños, grupos de animales
/// después y cómo se mueven o qué los distingue en primaria.
class ClasificaGenerator implements ChoiceGenerator {
  static const List<_Grupo> _habitats = <_Grupo>[
    _Grupo('granja', 'granja', 'la granja', '1f69c', 'vive en la granja', 'en'),
    _Grupo('mar', 'mar', 'el mar', '1f30a', 'vive en el mar', 'en'),
    _Grupo('selva', 'selva', 'la selva', '1f334', 'vive en la selva', 'en'),
    _Grupo('bosque', 'bosque', 'el bosque', '1f332', 'vive en el bosque', 'en'),
    _Grupo('rio', 'rio', 'el río', '1f3de', 'vive en el río', 'en'),
    _Grupo('jardin', 'jardin', 'el jardín', '1f33c', 'vive en el jardín', 'en'),
    _Grupo('casa', 'casa', 'la casa', '1f3e1', 'vive en la casa', 'en'),
  ];

  static const List<_Grupo> _grupos = <_Grupo>[
    _Grupo('mamifero', 'mamifero', 'mamífero', '1f404', 'es un mamífero', 'un'),
    _Grupo('ave', 'ave', 'ave', '1f426', 'es un ave', 'un'),
    _Grupo('pez', 'pez', 'pez', '1f41f', 'es un pez', 'un'),
    _Grupo('reptil', 'reptil', 'reptil', '1f98e', 'es un reptil', 'un'),
    _Grupo('anfibio', 'anfibio', 'anfibio', '1f438', 'es un anfibio', 'un'),
    _Grupo('insecto', 'insecto', 'insecto', '1f41c', 'es un insecto', 'un'),
  ];

  static const List<_Grupo> _movimiento = <_Grupo>[
    _Grupo('vuela', 'vuela', 'vuela', '1f985', 'vuela', ''),
    _Grupo('nada', 'nada', 'nada', '1f42c', 'nada', ''),
    _Grupo('camina', 'camina', 'camina', '1f418', 'camina', ''),
    _Grupo('repta', 'repta', 'repta', '1f40d', 'se arrastra', ''),
    _Grupo('salta', 'salta', 'salta', '1f998', 'salta', ''),
  ];

  static const Map<String, String> datosGrupo = <String, String>{
    'mamifero': 'Los mamíferos toman leche de su mamá cuando nacen.',
    'ave': 'Las aves tienen plumas y ponen huevos.',
    'pez': 'Los peces respiran bajo el agua con branquias.',
    'reptil': 'Los reptiles tienen escamas y ponen huevos.',
    'anfibio': 'Los anfibios nacen en el agua y luego viven en la tierra.',
    'insecto': 'Los insectos tienen seis patas.',
  };

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        return _dondeVive(rng, level <= 2 ? 2 : 3);
      case AgeBand.b5a6:
        if (level <= 2) {
          return _dondeVive(rng, level == 1 ? 3 : 4);
        }
        return _queEs(rng, level == 3 ? 3 : 4, band);
      case AgeBand.b7a8:
        if (level <= 2) {
          return rng.chance(0.5) ? _queEs(rng, 4, band) : _cualEs(rng, _grupos, 4);
        }
        return rng.chance(0.5) ? _cualEs(rng, _movimiento, 4) : _cualEs(rng, _grupos, level == 3 ? 5 : 6);
      case AgeBand.b9a11:
        return rng.chance(0.5) ? _cualEs(rng, _grupos, 6) : _queEs(rng, 6, band);
    }
  }

  /// "¿Dónde vive el delfín?" con hábitats como opciones.
  ChoiceRound _dondeVive(Rng rng, int count) {
    for (int attempt = 0; attempt < 30; attempt++) {
      final List<_Grupo> elegidos = rng.sample(_habitats, count);
      final _Grupo correcto = rng.pick(elegidos);
      final List<VocabItem> animales = Vocab.all.where((VocabItem v) {
        if (!v.esAnimal || !v.has(correcto.tag)) {
          return false;
        }
        // Debe pertenecer solo a uno de los hábitats mostrados.
        for (final _Grupo g in elegidos) {
          if (g.id != correcto.id && v.has(g.tag)) {
            return false;
          }
        }
        return true;
      }).toList();
      if (animales.isEmpty) {
        continue;
      }
      final VocabItem animal = rng.pick(animales);
      final List<ChoiceOption> options = <ChoiceOption>[for (final _Grupo g in elegidos) Opt.textWithEmoji(g.id, g.nombre, g.emoji)];
      rng.shuffle(options);
      return ChoiceRound(
        instruction: '¿Dónde vive ${animal.conArticulo}?',
        prompt: (BuildContext context) => BigPrompt(child: EmojiImage(animal.emoji, size: 96), caption: animal.nombre),
        options: options,
        correctId: correcto.id,
        hint: 'Piensa dónde has visto ${animal.articuloIndef} ${animal.nombre}: ¿en el agua, en el campo, en los árboles?',
        explain: '${_cap(animal.conArticulo)} ${correcto.pregunta}.',
        praise: '${_cap(animal.conArticulo)} ${correcto.pregunta}.',
        readOptionsAloud: true,
      );
    }
    return _dondeVive(rng, 2);
  }

  /// "¿Qué es la rana?" con grupos de animales como opciones.
  ChoiceRound _queEs(Rng rng, int count, AgeBand band) {
    final List<_Grupo> elegidos = rng.sample(_grupos, count);
    final _Grupo correcto = rng.pick(elegidos);
    final List<VocabItem> animales = Vocab.all.where((VocabItem v) => v.esAnimal && v.has(correcto.tag) && !v.nombre.contains(' ')).toList();
    if (animales.isEmpty) {
      return _dondeVive(rng, 3);
    }
    final VocabItem animal = rng.pick(animales);
    final List<ChoiceOption> options = <ChoiceOption>[for (final _Grupo g in elegidos) Opt.textWithEmoji(g.id, g.nombre, g.emoji)];
    rng.shuffle(options);
    final String dato = datosGrupo[correcto.id] ?? '';
    return ChoiceRound(
      instruction: '¿Qué tipo de animal es ${animal.conArticulo}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(animal.emoji, size: 96), caption: animal.nombre),
      options: options,
      correctId: correcto.id,
      hint: '¿Tiene plumas, pelo, escamas o seis patas? Eso te dice el grupo.',
      explain: '${_cap(animal.conArticulo)} ${correcto.pregunta}. $dato',
      praise: '${_cap(animal.conArticulo)} ${correcto.pregunta}.',
      readOptionsAloud: !band.readsText,
    );
  }

  /// "¿Cuál es un reptil?" o "¿Cuál vuela?" con animales como opciones.
  ChoiceRound _cualEs(Rng rng, List<_Grupo> familia, int count) {
    for (int attempt = 0; attempt < 30; attempt++) {
      final _Grupo g = rng.pick(familia);
      final List<VocabItem> dentro = Vocab.all.where((VocabItem v) => v.esAnimal && v.has(g.tag) && !v.nombre.contains(' ')).toList();
      final List<VocabItem> fuera = Vocab.all.where((VocabItem v) => v.esAnimal && !v.has(g.tag) && !v.nombre.contains(' ')).toList();
      if (dentro.isEmpty || fuera.length < count - 1) {
        continue;
      }
      final VocabItem correcto = rng.pick(dentro);
      final List<VocabItem> otros = rng.sample(fuera, count - 1);
      final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcto), for (final VocabItem v in otros) Opt.vocab(v)];
      rng.shuffle(options);
      final String dato = datosGrupo[g.id] ?? '';
      return ChoiceRound(
        instruction: '¿Cuál ${g.pregunta}?',
        options: options,
        correctId: correcto.id,
        hint: dato.isEmpty ? 'Imagina a cada animal moviéndose. ¿Cuál ${g.pregunta}?' : dato,
        explain: '${_cap(correcto.conArticulo)} ${g.pregunta}. $dato',
        praise: '${_cap(correcto.conArticulo)} ${g.pregunta}.',
      );
    }
    return _dondeVive(rng, 3);
  }

  static String _cap(String s) => s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);
}
