import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Una emoción con su cara y sus formas en masculino y femenino.
class Emocion {
  const Emocion(this.id, this.masculino, this.femenino, this.emoji, this.basica, {this.conEstar = true});

  final String id;
  final String masculino;
  final String femenino;
  final String emoji;

  /// Las cuatro básicas se trabajan desde los 3 años.
  final bool basica;

  /// "Está enojada" (true) o "Siente asco" (false).
  final bool conEstar;

  String nombre(String genero) => genero == 'f' ? femenino : masculino;

  /// "está feliz", "está enojada", "siente asco".
  String estado(String genero) => conEstar ? 'está ${nombre(genero)}' : 'siente ${nombre(genero)}';

  /// "se siente feliz", "siente asco".
  String seSiente(String genero) => conEstar ? 'se siente ${nombre(genero)}' : 'siente ${nombre(genero)}';
}

/// Una situación con su protagonista (con género) y la emoción que causa.
/// [tambien] son otras emociones razonables en esa situación: nunca salen
/// como opción incorrecta.
class Situacion {
  const Situacion(this.quien, this.genero, this.texto, this.emocion, this.minBand, {this.tambien = const <String>[]});

  final String quien;

  /// 'm' o 'f'.
  final String genero;

  /// La situación, escrita con el nombre del protagonista.
  final String texto;
  final String emocion;
  final AgeBand minBand;
  final List<String> tambien;
}

/// Algo que se puede hacer con una emoción.
class Accion {
  const Accion(this.texto, this.emoji, this.ayudaCon);

  final String texto;
  final String emoji;

  /// Emociones con las que esta acción ayuda a calmarse; vacía si no ayuda
  /// con ninguna (pegar, gritar, romper...).
  final List<String> ayudaCon;

  bool get ayuda => ayudaCon.isNotEmpty;
}

/// ¿Qué siento?: reconocer emociones y elegir qué hacer con ellas.
class EmocionesGenerator implements ChoiceGenerator {
  static const List<Emocion> emociones = <Emocion>[
    Emocion('feliz', 'feliz', 'feliz', '1f600', true),
    Emocion('triste', 'triste', 'triste', '1f622', true),
    Emocion('enojado', 'enojado', 'enojada', '1f620', true),
    Emocion('asustado', 'asustado', 'asustada', '1f628', true),
    Emocion('sorprendido', 'sorprendido', 'sorprendida', '1f632', false),
    Emocion('asco', 'asco', 'asco', '1f922', false, conEstar: false),
    Emocion('cansado', 'cansado', 'cansada', '1f62b', false),
    Emocion('tranquilo', 'tranquilo', 'tranquila', '1f60c', false),
    Emocion('orgulloso', 'orgulloso', 'orgullosa', '1f60e', false),
    Emocion('avergonzado', 'avergonzado', 'avergonzada', '1f633', false),
    Emocion('nervioso', 'nervioso', 'nerviosa', '1f630', false),
    Emocion('carinoso', 'cariñoso', 'cariñosa', '1f970', false),
  ];

  static const List<Situacion> situaciones = <Situacion>[
    Situacion('Mateo', 'm', 'Mateo recibió el regalo que quería.', 'feliz', AgeBand.b3a4, tambien: <String>['sorprendido', 'carinoso']),
    Situacion('Sara', 'f', 'A Sara se le rompió su juguete favorito.', 'triste', AgeBand.b3a4, tambien: <String>['enojado', 'sorprendido']),
    Situacion('Juan', 'm', 'Juan estaba jugando y su hermano le quitó el balón.', 'enojado', AgeBand.b3a4, tambien: <String>['triste', 'sorprendido']),
    Situacion('Tomás', 'm', 'Se fue la luz y Tomás quedó solo en un cuarto oscuro.', 'asustado', AgeBand.b3a4, tambien: <String>['sorprendido', 'nervioso', 'triste']),
    Situacion('Lucía', 'f', 'Lucía va a ir al parque con su abuela.', 'feliz', AgeBand.b3a4, tambien: <String>['carinoso', 'tranquilo']),
    Situacion('Nico', 'm', 'El perro de Nico se perdió.', 'triste', AgeBand.b3a4, tambien: <String>['asustado', 'nervioso']),
    Situacion('Ana', 'f', 'Ana hizo una torre y alguien se la tumbó a propósito.', 'enojado', AgeBand.b3a4, tambien: <String>['triste', 'sorprendido']),
    Situacion('Pedro', 'm', 'Un perro grande le ladró muy fuerte a Pedro.', 'asustado', AgeBand.b3a4, tambien: <String>['sorprendido', 'nervioso']),
    Situacion('Valentina', 'f', 'Valentina encontró una sorpresa dentro de su maleta.', 'sorprendido', AgeBand.b5a6, tambien: <String>['feliz']),
    Situacion('Daniel', 'm', 'Daniel olió la basura que llevaba días sin sacar.', 'asco', AgeBand.b5a6),
    Situacion('Camila', 'f', 'Camila corrió toda la tarde y ya no puede más.', 'cansado', AgeBand.b5a6, tambien: <String>['feliz', 'tranquilo']),
    Situacion('Samuel', 'm', 'Samuel respiró hondo después de la pelea y ya no tiene el corazón acelerado.', 'tranquilo', AgeBand.b5a6, tambien: <String>['cansado', 'triste', 'enojado']),
    Situacion('Emma', 'f', 'Es la primera vez que Emma va a dormir fuera de casa y no para de pensar en eso.', 'nervioso', AgeBand.b5a6, tambien: <String>['asustado', 'feliz', 'sorprendido', 'triste']),
    Situacion('Martín', 'm', 'Martín terminó solo un rompecabezas muy difícil.', 'orgulloso', AgeBand.b5a6, tambien: <String>['feliz', 'tranquilo']),
    Situacion('Sofía', 'f', 'Sofía se cayó delante de todos sus compañeros.', 'avergonzado', AgeBand.b5a6, tambien: <String>['triste', 'sorprendido', 'asustado', 'nervioso', 'enojado']),
    Situacion('Pablo', 'm', 'La abuela de Pablo llegó de visita y él corrió a abrazarla.', 'carinoso', AgeBand.b5a6, tambien: <String>['feliz', 'sorprendido']),
    Situacion('Isabela', 'f', 'Isabela estudió mucho y sacó la nota que quería.', 'orgulloso', AgeBand.b7a8, tambien: <String>['feliz', 'tranquilo', 'sorprendido']),
    Situacion('Andrés', 'm', 'Mañana Andrés presenta un baile frente a todo el colegio y le tiembla la voz.', 'nervioso', AgeBand.b7a8, tambien: <String>['asustado', 'avergonzado', 'feliz']),
    Situacion('Gabriela', 'f', 'Gabriela dijo algo equivocado en voz alta y todos la miraron.', 'avergonzado', AgeBand.b7a8, tambien: <String>['nervioso', 'triste', 'asustado']),
    Situacion('Santiago', 'm', 'Santiago no fue invitado al cumpleaños de su mejor amigo.', 'triste', AgeBand.b7a8, tambien: <String>['enojado', 'sorprendido', 'avergonzado']),
    Situacion('Mariana', 'f', 'Alguien tomó el cuaderno de Mariana sin pedirle permiso.', 'enojado', AgeBand.b7a8, tambien: <String>['triste', 'sorprendido']),
    Situacion('David', 'm', 'David ayudó a su vecina a cargar el mercado y ella le dio las gracias.', 'feliz', AgeBand.b7a8, tambien: <String>['orgulloso', 'tranquilo', 'carinoso']),
    Situacion('Laura', 'f', 'Laura escuchó un ruido raro en la noche.', 'asustado', AgeBand.b7a8, tambien: <String>['nervioso', 'sorprendido']),
    Situacion('Felipe', 'm', 'Felipe abrió la puerta y todos gritaron "¡feliz cumpleaños!".', 'sorprendido', AgeBand.b7a8, tambien: <String>['feliz', 'carinoso']),
  ];

  static const List<Accion> acciones = <Accion>[
    Accion('Respirar hondo tres veces', '1f32c', <String>['enojado', 'asustado', 'nervioso', 'avergonzado', 'triste']),
    Accion('Contar despacio hasta diez', '1f522', <String>['enojado', 'nervioso']),
    Accion('Pedir ayuda a un adulto', '1f9d1-200d-1f3eb', <String>['asustado', 'triste', 'enojado', 'nervioso']),
    Accion('Decir con palabras cómo me siento', '1f5e3', <String>['enojado', 'triste', 'avergonzado', 'nervioso']),
    Accion('Pedir un abrazo', '1f917', <String>['triste', 'asustado', 'nervioso']),
    Accion('Tomar agua y descansar', '1f4a7', <String>['cansado']),
    Accion('Alejarse y lavarse las manos', '1f9fc', <String>['asco']),
    Accion('Gritarle a otra persona', '1f4e2', <String>[]),
    Accion('Pegar o empujar', '1f44a', <String>[]),
    Accion('Romper algo', '1f4a5', <String>[]),
    Accion('Esconderse y no contarle a nadie', '1f648', <String>[]),
    Accion('Burlarse de los demás', '1f61d', <String>[]),
  ];

  static Emocion byId(String id) => emociones.firstWhere((Emocion e) => e.id == id);

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band == AgeBand.b3a4) {
      if (level == 1) {
        return tocaLaCara(rng, 3);
      }
      if (level == 2) {
        return tocaLaCara(rng, 4);
      }
      if (level == 3) {
        return situacionACara(rng, band, 3);
      }
      return queHacer(rng, band);
    }
    if (level <= 2) {
      return situacionACara(rng, band, level == 1 ? 3 : 4);
    }
    if (level == 3) {
      return rng.chance(0.5) ? situacionACara(rng, band, 4) : queHacer(rng, band);
    }
    return queHacer(rng, band);
  }

  /// "Toca la cara que está enojada" (la cara es femenina).
  ChoiceRound tocaLaCara(Rng rng, int count) {
    final List<Emocion> pool = emociones.where((Emocion e) => e.basica).toList();
    final List<Emocion> elegidas = rng.sample(pool, count);
    final Emocion correcta = rng.pick(elegidas);
    final List<ChoiceOption> options = <ChoiceOption>[for (final Emocion e in elegidas) Opt.emoji(e.id, e.emoji, 'cara ${e.nombre('f')}')];
    rng.shuffle(options);
    final String estado = correcta.estado('f');
    return ChoiceRound(
      instruction: 'Toca la cara que $estado.',
      options: options,
      correctId: correcta.id,
      hint: 'Mira los ojos y la boca de cada cara. ¿Cuál $estado?',
      explain: 'Esta cara $estado.',
      praise: 'Esa cara $estado.',
      optionSize: 100,
    );
  }

  /// Una situación y las caras: los distractores nunca son emociones que
  /// también tendrían sentido en esa situación.
  ChoiceRound situacionACara(Rng rng, AgeBand band, int count) {
    final List<Situacion> pool = situaciones.where((Situacion s) => s.minBand.index <= band.index).toList();
    for (int intento = 0; intento < 40; intento++) {
      final Situacion s = rng.pick(pool);
      final Emocion correcta = byId(s.emocion);
      final List<Emocion> otras = emociones.where((Emocion e) => e.id != correcta.id && !s.tambien.contains(e.id) && (band != AgeBand.b3a4 || e.basica)).toList();
      if (otras.length < count - 1) {
        continue;
      }
      final List<Emocion> elegidas = <Emocion>[correcta, ...rng.sample(otras, count - 1)];
      final List<ChoiceOption> options = <ChoiceOption>[for (final Emocion e in elegidas) Opt.emoji(e.id, e.emoji, e.nombre(s.genero), showLabel: band.readsText)];
      rng.shuffle(options);
      final String como = s.genero == 'f' ? '¿Cómo se siente ella?' : '¿Cómo se siente él?';
      return ChoiceRound(
        instruction: '${s.texto} $como',
        prompt: (BuildContext context) => BigPrompt(child: const Mascot(size: 64), caption: s.texto),
        options: options,
        correctId: correcta.id,
        hint: '¿Qué sentirías tú si te pasara eso? Piensa en tu cara.',
        explain: '${s.quien} ${correcta.seSiente(s.genero)}. Está bien sentirse así.',
        praise: '${s.quien} ${correcta.seSiente(s.genero)}.',
        readOptionsAloud: !band.readsText,
        optionSize: 90,
      );
    }
    return tocaLaCara(rng, 3);
  }

  /// "¿Qué le ayuda?": una acción que de verdad ayuda con esa emoción y dos
  /// que no ayudan con ninguna.
  ChoiceRound queHacer(Rng rng, AgeBand band) {
    final Set<String> conAyuda = <String>{for (final Accion a in acciones) ...a.ayudaCon};
    final List<Situacion> pool = situaciones.where((Situacion s) => s.minBand.index <= band.index && conAyuda.contains(s.emocion)).toList();
    final Situacion s = rng.pick(pool);
    final Emocion emo = byId(s.emocion);
    final Accion buena = rng.pick(acciones.where((Accion a) => a.ayudaCon.contains(emo.id)).toList());
    final List<Accion> malas = rng.sample(acciones.where((Accion a) => !a.ayuda).toList(), 2);
    final List<ChoiceOption> options = <ChoiceOption>[
      Opt.textWithEmoji('ok', buena.texto, buena.emoji),
      for (int i = 0; i < malas.length; i++) Opt.textWithEmoji('m$i', malas[i].texto, malas[i].emoji),
    ];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${s.texto} ${s.quien} ${emo.estado(s.genero)}. ¿Qué puede hacer para sentirse mejor?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(emo.emoji, size: 72, semanticsLabel: emo.nombre(s.genero)), caption: s.texto),
      options: options,
      correctId: 'ok',
      hint: 'Piensa cuál de esas cosas calma y no lastima a nadie.',
      explain: '${buena.texto} ayuda a sentirse mejor. ${malas.first.texto} no ayuda: puede lastimar o empeorar las cosas.',
      praise: '${buena.texto} ayuda.',
      readOptionsAloud: !band.readsText,
      optionAspect: band.readsText ? 2.4 : 1.2,
    );
  }
}
