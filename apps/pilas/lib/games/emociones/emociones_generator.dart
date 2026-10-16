import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

class Emocion {
  const Emocion(this.id, this.nombre, this.emoji, this.basica);

  final String id;
  final String nombre;
  final String emoji;

  /// Las cuatro básicas se trabajan desde los 3 años.
  final bool basica;
}

class Situacion {
  const Situacion(this.texto, this.emocion, this.minBand);

  final String texto;
  final String emocion;
  final AgeBand minBand;
}

class Accion {
  const Accion(this.texto, this.emoji, this.ayuda);

  final String texto;
  final String emoji;

  /// true si es una forma sana de regularse.
  final bool ayuda;
}

/// ¿Qué siento?: reconocer emociones y elegir qué hacer con ellas.
class EmocionesGenerator implements ChoiceGenerator {
  static const List<Emocion> emociones = <Emocion>[
    Emocion('feliz', 'feliz', '1f600', true),
    Emocion('triste', 'triste', '1f622', true),
    Emocion('enojado', 'enojado', '1f620', true),
    Emocion('asustado', 'asustado', '1f628', true),
    Emocion('sorprendido', 'sorprendido', '1f632', false),
    Emocion('asco', 'con asco', '1f922', false),
    Emocion('cansado', 'cansado', '1f634', false),
    Emocion('tranquilo', 'tranquilo', '1f60c', false),
    Emocion('orgulloso', 'orgulloso', '1f60e', false),
    Emocion('avergonzado', 'avergonzado', '1f633', false),
    Emocion('nervioso', 'nervioso', '1f62c', false),
    Emocion('carinoso', 'cariñoso', '1f970', false),
  ];

  static const List<Situacion> situaciones = <Situacion>[
    Situacion('Mateo recibió un regalo que quería mucho.', 'feliz', AgeBand.b3a4),
    Situacion('A Sara se le rompió su juguete favorito.', 'triste', AgeBand.b3a4),
    Situacion('Juan quería jugar y su hermano le quitó el balón.', 'enojado', AgeBand.b3a4),
    Situacion('Se fue la luz y la casa quedó oscura.', 'asustado', AgeBand.b3a4),
    Situacion('Lucía va a ir al parque con su abuela.', 'feliz', AgeBand.b3a4),
    Situacion('El perro de Nico se perdió.', 'triste', AgeBand.b3a4),
    Situacion('Ana hizo una torre y alguien la tumbó a propósito.', 'enojado', AgeBand.b3a4),
    Situacion('Un perro grande ladró muy fuerte cerca de Tomás.', 'asustado', AgeBand.b3a4),
    Situacion('Valentina encontró una sorpresa dentro de su maleta.', 'sorprendido', AgeBand.b5a6),
    Situacion('Daniel olió la basura que llevaba días sin sacar.', 'asco', AgeBand.b5a6),
    Situacion('Camila corrió toda la tarde y ya no puede más.', 'cansado', AgeBand.b5a6),
    Situacion('Después de respirar hondo, Samuel se sintió en calma.', 'tranquilo', AgeBand.b5a6),
    Situacion('Es la primera vez que Emma duerme fuera de casa y no para de pensar en eso.', 'nervioso', AgeBand.b5a6),
    Situacion('Martín terminó solo un rompecabezas muy difícil.', 'orgulloso', AgeBand.b5a6),
    Situacion('Sofía se cayó delante de todos sus compañeros.', 'avergonzado', AgeBand.b5a6),
    Situacion('La abuela abrazó a Pablo cuando llegó de visita.', 'carinoso', AgeBand.b5a6),
    Situacion('Isabela estudió mucho y sacó la nota que quería.', 'orgulloso', AgeBand.b7a8),
    Situacion('Mañana Andrés presenta un baile frente al colegio y le tiembla la voz.', 'nervioso', AgeBand.b7a8),
    Situacion('Gabriela dijo algo equivocado en voz alta y todos la miraron.', 'avergonzado', AgeBand.b7a8),
    Situacion('Santiago no fue invitado al cumpleaños de su mejor amigo.', 'triste', AgeBand.b7a8),
    Situacion('Alguien tomó el cuaderno de Mariana sin pedir permiso.', 'enojado', AgeBand.b7a8),
    Situacion('David ayudó a su vecina a cargar el mercado y ella le dio las gracias.', 'feliz', AgeBand.b7a8),
    Situacion('Laura escuchó un ruido raro en la noche.', 'asustado', AgeBand.b7a8),
    Situacion('Felipe abrió la puerta y todos gritaron "¡feliz cumpleaños!".', 'sorprendido', AgeBand.b7a8),
  ];

  static const List<Accion> acciones = <Accion>[
    Accion('Respirar hondo tres veces', '1f32c', true),
    Accion('Contar hasta diez', '1f522', true),
    Accion('Pedir ayuda a un adulto', '1f9d1-200d-1f3eb', true),
    Accion('Decir cómo me siento', '1f5e3', true),
    Accion('Pedir un abrazo', '1f917', true),
    Accion('Esperar un momento y volver a intentar', '23f3', true),
    Accion('Tomar agua y descansar', '1f4a7', true),
    Accion('Gritarle al otro', '1f4e2', false),
    Accion('Pegar o empujar', '1f44a', false),
    Accion('Romper algo', '1f4a5', false),
    Accion('Esconderse y no decir nada', '1f648', false),
    Accion('Burlarse de los demás', '1f61d', false),
  ];

  static Emocion byId(String id) => emociones.firstWhere((Emocion e) => e.id == id);

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band == AgeBand.b3a4 && level == 1) {
      return _tocaLaCara(rng, 3);
    }
    if (band == AgeBand.b3a4 && level == 2) {
      return _tocaLaCara(rng, 4);
    }
    final bool regulacion = (band == AgeBand.b3a4 && level == 4) || (band != AgeBand.b3a4 && (level >= 3 && rng.chance(0.5) || level == 4));
    if (regulacion) {
      return _queHacer(rng, band);
    }
    return _situacionACara(rng, band, level);
  }

  ChoiceRound _tocaLaCara(Rng rng, int count) {
    final List<Emocion> pool = emociones.where((Emocion e) => e.basica).toList();
    final List<Emocion> elegidas = rng.sample(pool, count);
    final Emocion correcta = rng.pick(elegidas);
    final List<ChoiceOption> options = <ChoiceOption>[for (final Emocion e in elegidas) Opt.emoji(e.id, e.emoji, e.nombre)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Toca la cara que está ${correcta.nombre}.',
      options: options,
      correctId: correcta.id,
      hint: 'Mira los ojos y la boca. ¿Cuál cara se ve ${correcta.nombre}?',
      explain: 'Esta cara está ${correcta.nombre}.',
      praise: 'Esa cara está ${correcta.nombre}.',
      optionSize: 100,
    );
  }

  ChoiceRound _situacionACara(Rng rng, AgeBand band, int level) {
    final List<Situacion> pool = situaciones.where((Situacion s) => s.minBand.index <= band.index).toList();
    final Situacion s = rng.pick(pool);
    final Emocion correcta = byId(s.emocion);
    final int count = band == AgeBand.b3a4 ? 3 : (level <= 2 ? 3 : 4);
    final List<Emocion> otras = emociones.where((Emocion e) => e.id != correcta.id && (band != AgeBand.b3a4 || e.basica)).toList();
    final List<Emocion> elegidas = <Emocion>[correcta, ...rng.sample(otras, count - 1)];
    final List<ChoiceOption> options = <ChoiceOption>[for (final Emocion e in elegidas) Opt.emoji(e.id, e.emoji, e.nombre, showLabel: band.readsText)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${s.texto} ¿Cómo se siente?',
      prompt: (BuildContext context) => BigPrompt(
        child: const Mascot(size: 64),
        caption: s.texto,
      ),
      options: options,
      correctId: correcta.id,
      hint: '¿Qué sentirías tú si te pasara eso? Piensa en tu cara.',
      explain: 'Se siente ${correcta.nombre}. Está bien sentirse así.',
      praise: 'Se siente ${correcta.nombre}.',
      optionSize: 90,
    );
  }

  ChoiceRound _queHacer(Rng rng, AgeBand band) {
    final List<Situacion> pool = situaciones.where((Situacion s) => s.minBand.index <= band.index && s.emocion != 'feliz' && s.emocion != 'tranquilo' && s.emocion != 'orgulloso' && s.emocion != 'carinoso' && s.emocion != 'sorprendido').toList();
    final Situacion s = rng.pick(pool);
    final Emocion emo = byId(s.emocion);
    final Accion buena = rng.pick(acciones.where((Accion a) => a.ayuda).toList());
    final List<Accion> malas = rng.sample(acciones.where((Accion a) => !a.ayuda).toList(), 2);
    final List<ChoiceOption> options = <ChoiceOption>[
      Opt.textWithEmoji('ok', buena.texto, buena.emoji),
      for (int i = 0; i < malas.length; i++) Opt.textWithEmoji('m$i', malas[i].texto, malas[i].emoji),
    ];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${s.texto} Está ${emo.nombre}. ¿Qué le ayuda?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(emo.emoji, size: 72), caption: s.texto),
      options: options,
      correctId: 'ok',
      hint: 'Piensa cuál de esas cosas calma y no lastima a nadie.',
      explain: '${buena.texto} ayuda a calmarse. ${malas.first.texto} no ayuda.',
      praise: '${buena.texto} ayuda.',
      readOptionsAloud: !band.readsText,
      columns: 1,
      optionSize: 72,
    );
  }
}
