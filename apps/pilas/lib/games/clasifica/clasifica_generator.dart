import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/es.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Un lugar donde viven animales.
class Habitat {
  const Habitat(this.id, this.nombre, this.emoji);

  final String id;

  /// Con artículo: "la granja", "el mar".
  final String nombre;

  /// Pictograma del lugar, o null si Twemoji no tiene uno fiel (la sabana):
  /// ese lugar solo sale en preguntas escritas, para los que leen.
  final String? emoji;

  /// "vive en la granja".
  String get vive => 'vive en $nombre';

  String get viven => 'viven en $nombre';
}

/// Un grupo de animales.
class GrupoAnimal {
  const GrupoAnimal(this.id, this.nombre, this.plural, this.genero, this.emoji, this.dato);

  final String id;
  final String nombre;
  final String plural;
  final String genero;

  /// Pictograma de la opción: muestra lo que distingue al grupo y nunca es el
  /// mismo pictograma del animal que se pregunta.
  final String emoji;

  /// Un dato verdadero que distingue al grupo.
  final String dato;

  /// "es un mamífero", "es un ave".
  String get esUn => 'es ${Es.con(genero, nombre, definido: false)}';
}

/// Clasifica seres vivos: dónde viven (3 a 6 años), a qué grupo pertenecen y
/// cómo se mueven (5 a 8), y ecosistemas y animales que confunden (9 a 11).
///
/// Las etiquetas del vocabulario son listas completas: si un animal no tiene
/// la etiqueta de un hábitat, no vive ahí; si no tiene "mov:" ni "no:" de un
/// movimiento, es dudoso y queda fuera de esa pregunta. Así siempre hay una
/// sola respuesta correcta (test/semantica_test.dart lo prueba miles de veces).
class ClasificaGenerator implements ChoiceGenerator {
  static const Map<String, Habitat> habitats = <String, Habitat>{
    'granja': Habitat('granja', 'la granja', '1f69c'),
    'casa': Habitat('casa', 'la casa', '1f3e1'),
    'selva': Habitat('selva', 'la selva', '1f334'),
    'sabana': Habitat('sabana', 'la sabana', null),
    'bosque': Habitat('bosque', 'el bosque', '1f332'),
    'desierto': Habitat('desierto', 'el desierto', '1f3dc'),
    'mar': Habitat('mar', 'el mar', '1f30a'),
    'rio': Habitat('rio', 'el río', '1f3de'),
    'polo': Habitat('polo', 'el polo', '2744'),
    'montana': Habitat('montana', 'la montaña', '26f0'),
    'jardin': Habitat('jardin', 'el jardín', '1f33c'),
  };

  /// Hábitats con pictograma (todos menos la sabana): los de las preguntas
  /// para los que todavía no leen.
  static List<String> get habitatsConDibujo => habitats.keys.where((String k) => habitats[k]!.emoji != null).toList();

  /// Hábitats que los más pequeños reconocen sin dudar.
  static const List<String> habitatsFaciles = <String>['granja', 'mar', 'selva', 'casa', 'bosque', 'jardin', 'rio'];

  static const Map<String, GrupoAnimal> grupos = <String, GrupoAnimal>{
    'mamifero': GrupoAnimal('mamifero', 'mamífero', 'mamíferos', 'm', '1f37c', 'Los mamíferos, de bebés, toman leche de su mamá, y casi todos tienen pelo.'),
    'ave': GrupoAnimal('ave', 'ave', 'aves', 'f', '1fab6', 'Las aves tienen plumas y pico, y ponen huevos.'),
    'pez': GrupoAnimal('pez', 'pez', 'peces', 'm', '1f41f', 'Los peces viven en el agua y respiran con branquias.'),
    'reptil': GrupoAnimal('reptil', 'reptil', 'reptiles', 'm', '1f40a', 'Los reptiles tienen la piel cubierta de escamas o placas, y la mayoría pone huevos.'),
    'anfibio': GrupoAnimal('anfibio', 'anfibio', 'anfibios', 'm', '1f4a7', 'Los anfibios, como la rana, nacen en el agua y de adultos también viven en la tierra.'),
    'insecto': GrupoAnimal('insecto', 'insecto', 'insectos', 'm', '1f41c', 'Los insectos tienen seis patas y el cuerpo dividido en tres partes.'),
  };

  static const Map<String, String> preguntaMovimiento = <String, String>{
    'vuela': '¿Cuál vuela?',
    'nada': '¿Cuál nada?',
    'camina': '¿Cuál camina?',
    'salta': '¿Cuál salta?',
    'repta': '¿Cuál se arrastra?',
    'trepa': '¿Cuál trepa?',
  };

  static const Map<String, String> verboMovimiento = <String, String>{
    'vuela': 'vuela',
    'nada': 'nada',
    'camina': 'camina',
    'salta': 'salta',
    'repta': 'se arrastra',
    'trepa': 'trepa',
  };

  /// Animales que confunden y por qué (9 a 11 años).
  static const Map<String, String> trampas = <String, String>{
    'ballena': 'La ballena es un mamífero aunque vive en el mar: respira aire con pulmones y, de bebé, toma leche de su mamá.',
    'delfin': 'El delfín es un mamífero: sale a respirar aire y, de bebé, toma leche de su mamá.',
    'murcielago': 'El murciélago es un mamífero aunque vuela: tiene pelo y, de bebé, toma leche de su mamá.',
    'foca': 'La foca es un mamífero: tiene pelo, respira aire y, de bebé, toma leche de su mamá.',
    'nutria': 'La nutria es un mamífero aunque pasa mucho tiempo en el agua: tiene pelo y, de bebé, toma leche de su mamá.',
    'pinguino': 'El pingüino es un ave aunque no vuela: tiene plumas y pico, y pone huevos.',
  };

  static List<VocabItem> get animales => Vocab.all.where((VocabItem v) => v.esAnimal).toList();

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        if (level == 1) {
          return dondeVive(rng, 3, habitatsFaciles);
        }
        if (level == 2) {
          return dondeVive(rng, 3, habitatsConDibujo);
        }
        if (level == 3) {
          return dondeVive(rng, 4, habitatsFaciles);
        }
        return cualVive(rng, 3, habitatsFaciles);
      case AgeBand.b5a6:
        if (level == 1) {
          return dondeVive(rng, 4, habitatsConDibujo);
        }
        if (level == 2) {
          return queEs(rng, 3);
        }
        if (level == 3) {
          return rng.chance(0.5) ? queEs(rng, 4) : cualEsGrupo(rng, 3);
        }
        return rng.chance(0.5) ? cualMueve(rng, 3) : queEs(rng, 4);
      case AgeBand.b7a8:
        if (level == 1) {
          return queEs(rng, 4);
        }
        if (level == 2) {
          return cualEsGrupo(rng, 4);
        }
        if (level == 3) {
          return cualMueve(rng, 4);
        }
        final int t = rng.nextInt(3);
        return t == 0 ? queEs(rng, 6) : (t == 1 ? cualEsGrupo(rng, 4) : cualMueve(rng, 4));
      case AgeBand.b9a11:
        if (level == 1) {
          return queEs(rng, 6);
        }
        if (level == 2) {
          return dondeVive(rng, 5, habitats.keys.toList());
        }
        if (level == 3) {
          return rng.chance(0.5) ? cualEsGrupo(rng, 5) : cualMueve(rng, 5);
        }
        return rng.chance(0.6) ? trampa(rng, 4) : dondeVive(rng, 6, habitats.keys.toList());
    }
  }

  /// Opción de lugar: con pictograma, o solo escrita si alguno de los lugares
  /// de la ronda no tiene un pictograma fiel ([soloTexto]).
  ChoiceOption _habitatOpt(Habitat h, {bool soloTexto = false}) =>
      soloTexto || h.emoji == null ? Opt.text(h.id, Es.cap(h.nombre), fontSize: 24) : Opt.textWithEmoji(h.id, Es.cap(h.nombre), h.emoji!);

  /// "¿Dónde vive el delfín?" con lugares como opciones. Solo se pregunta por
  /// animales que viven en un único lugar, para que no haya dos respuestas.
  ChoiceRound dondeVive(Rng rng, int count, List<String> lugares) {
    final List<VocabItem> pool = animales.where((VocabItem v) => v.habitats.length == 1 && lugares.contains(v.habitats.first)).toList();
    final VocabItem animal = rng.pick(pool);
    final Habitat correcto = habitats[animal.habitats.first]!;
    final List<String> otros = lugares.where((String h) => h != correcto.id && !animal.tambienVive.contains(h)).toList();
    final List<Habitat> elegidos = <Habitat>[correcto, for (final String h in rng.sample(otros, count - 1)) habitats[h]!];
    final bool soloTexto = elegidos.any((Habitat h) => h.emoji == null);
    final List<ChoiceOption> options = <ChoiceOption>[for (final Habitat h in elegidos) _habitatOpt(h, soloTexto: soloTexto)];
    rng.shuffle(options);
    final String frase = '${Es.cap(animal.conArticulo)} ${animal.verbo('vive', 'viven')} en ${correcto.nombre}.';
    return ChoiceRound(
      instruction: '¿Dónde ${animal.verbo('vive', 'viven')} ${animal.conArticulo}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(animal.emoji, size: 96, semanticsLabel: animal.nombre), caption: animal.nombre),
      options: options,
      correctId: correcto.id,
      hint: 'Piensa dónde has visto ${animal.conArticulo}: ¿en el agua, en el campo, entre los árboles?',
      explain: frase,
      praise: frase,
      readOptionsAloud: true,
      optionAspect: 1.2,
    );
  }

  /// "¿Cuál vive en el mar?" con animales como opciones: los distractores no
  /// viven en ese lugar.
  ChoiceRound cualVive(Rng rng, int count, List<String> lugares) {
    final String lugar = rng.pick(lugares);
    final Habitat h = habitats[lugar]!;
    final List<VocabItem> dentro = animales.where((VocabItem v) => v.habitats.contains(lugar)).toList();
    final List<VocabItem> fuera = animales.where((VocabItem v) => v.habitats.isNotEmpty && !v.habitats.contains(lugar) && !v.tambienVive.contains(lugar)).toList();
    final VocabItem correcto = rng.pick(dentro);
    final List<VocabItem> otros = rng.sample(fuera, count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcto), for (final VocabItem v in otros) Opt.vocab(v)];
    rng.shuffle(options);
    final String frase = '${Es.cap(correcto.conArticulo)} ${correcto.verbo('vive', 'viven')} en ${h.nombre}.';
    return ChoiceRound(
      instruction: '¿Cuál ${h.vive}?',
      prompt: h.emoji == null ? null : (BuildContext context) => BigPrompt(child: EmojiImage(h.emoji!, size: 84, semanticsLabel: h.nombre), caption: Es.cap(h.nombre)),
      options: options,
      correctId: correcto.id,
      hint: 'Imagina ${h.nombre}. ¿Cuál de estos animales encontrarías ahí?',
      explain: frase,
      praise: frase,
      readOptionsAloud: true,
    );
  }

  /// Animales que se pueden preguntar por su grupo: con grupo y cuyo
  /// pictograma no es el de ninguna opción de grupo.
  static List<VocabItem> get _conGrupo {
    final Set<String> iconos = grupos.values.map((GrupoAnimal g) => g.emoji).toSet();
    return animales.where((VocabItem v) => v.grupo != null && !iconos.contains(v.emoji)).toList();
  }

  /// "¿Qué tipo de animal es la rana?" con grupos como opciones.
  ChoiceRound queEs(Rng rng, int count) {
    final VocabItem animal = rng.pick(_conGrupo);
    final GrupoAnimal correcto = grupos[animal.grupo!]!;
    final List<GrupoAnimal> otros = rng.sample(grupos.values.where((GrupoAnimal g) => g.id != correcto.id).toList(), count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[
      for (final GrupoAnimal g in <GrupoAnimal>[correcto, ...otros]) Opt.textWithEmoji(g.id, Es.cap(g.nombre), g.emoji),
    ];
    rng.shuffle(options);
    final String frase = '${Es.cap(animal.conArticulo)} ${correcto.esUn}.';
    return ChoiceRound(
      instruction: '¿Qué tipo de animal es ${animal.conArticulo}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(animal.emoji, size: 96, semanticsLabel: animal.nombre), caption: animal.nombre),
      options: options,
      correctId: correcto.id,
      hint: '¿Tiene pelo, plumas, escamas o seis patas? ¿Toma leche de su mamá cuando es bebé?',
      explain: '$frase ${correcto.dato}',
      praise: frase,
      readOptionsAloud: true,
      optionAspect: 1.2,
    );
  }

  /// "¿Cuál es un reptil?" con animales como opciones: ningún distractor es de
  /// ese grupo.
  ChoiceRound cualEsGrupo(Rng rng, int count) {
    final GrupoAnimal g = rng.pick(grupos.values.toList());
    final List<VocabItem> dentro = animales.where((VocabItem v) => v.grupo == g.id).toList();
    final List<VocabItem> fuera = animales.where((VocabItem v) => v.grupo != g.id).toList();
    final VocabItem correcto = rng.pick(dentro);
    final List<VocabItem> otros = rng.sample(fuera, count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcto), for (final VocabItem v in otros) Opt.vocab(v)];
    rng.shuffle(options);
    final String frase = '${Es.cap(correcto.conArticulo)} ${g.esUn}.';
    return ChoiceRound(
      instruction: '¿Cuál ${g.esUn}?',
      options: options,
      correctId: correcto.id,
      hint: g.dato,
      explain: '$frase ${g.dato}',
      praise: frase,
      readOptionsAloud: true,
    );
  }

  /// "¿Cuál salta?": el correcto se mueve así y los distractores claramente no.
  ChoiceRound cualMueve(Rng rng, int count) {
    for (int intento = 0; intento < 40; intento++) {
      final String mov = rng.pick(preguntaMovimiento.keys.toList());
      final List<VocabItem> si = animales.where((VocabItem v) => v.mueve(mov) == true).toList();
      final List<VocabItem> no = animales.where((VocabItem v) => v.mueve(mov) == false).toList();
      if (si.isEmpty || no.length < count - 1) {
        continue;
      }
      final VocabItem correcto = rng.pick(si);
      final List<VocabItem> otros = rng.sample(no, count - 1);
      final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcto), for (final VocabItem v in otros) Opt.vocab(v)];
      rng.shuffle(options);
      final String verbo = verboMovimiento[mov]!;
      final String frase = '${Es.cap(correcto.conArticulo)} $verbo.';
      return ChoiceRound(
        instruction: preguntaMovimiento[mov]!,
        options: options,
        correctId: correcto.id,
        hint: 'Imagina a cada animal moviéndose. ¿Cuál $verbo?',
        explain: '$frase Los demás no se mueven así.',
        praise: frase,
        readOptionsAloud: true,
      );
    }
    return queEs(rng, count);
  }

  /// Animales que confunden: "¿Cuál es un mamífero?" con la ballena entre
  /// peces y aves, o "¿Cuál es un ave?" con el pingüino entre mamíferos y peces.
  ChoiceRound trampa(Rng rng, int count) {
    final String id = rng.pick(trampas.keys.toList());
    final VocabItem correcto = Vocab.item(id);
    final GrupoAnimal g = grupos[correcto.grupo!]!;
    final List<VocabItem> parecidos = animales.where((VocabItem v) {
      if (v.grupo == g.id || v.grupo == null) {
        return false;
      }
      // Distractores que viven en el agua o vuelan, como el animal que confunde.
      return v.mueve('nada') == true || v.mueve('vuela') == true;
    }).toList();
    final List<VocabItem> otros = rng.sample(parecidos, count - 1);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.vocab(correcto), for (final VocabItem v in otros) Opt.vocab(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál ${g.esUn}?',
      options: options,
      correctId: correcto.id,
      hint: '${g.dato} No te fijes solo en dónde vive o en si vuela.',
      explain: trampas[id]!,
      praise: '${Es.cap(correcto.conArticulo)} ${g.esUn}.',
      readOptionsAloud: true,
    );
  }
}
