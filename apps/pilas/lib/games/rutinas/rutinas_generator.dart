import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../shell/order_game_screen.dart';
import '../shell/tile_order_board.dart';
import '../shell/widgets.dart';

/// Un paso de una rutina.
class Paso {
  const Paso(this.id, this.texto, this.emoji);

  final String id;
  final String texto;
  final String emoji;
}

/// Una rutina: nombre y pasos en orden.
class Rutina {
  const Rutina(this.id, this.nombre, this.pasos, {this.porQue});

  final String id;
  final String nombre;
  final List<Paso> pasos;

  /// Por qué el orden importa (se dice al explicar).
  final String? porQue;
}

/// Banco de rutinas y secuencias cotidianas.
class RutinaBank {
  RutinaBank._();

  static const List<Rutina> all = <Rutina>[
    Rutina('manana', 'Levantarse', <Paso>[
      Paso('despertar', 'Despertar', '1f6cf'),
      Paso('banarse', 'Bañarse', '1f6bf'),
      Paso('vestirse', 'Vestirse', '1f455'),
      Paso('desayunar', 'Desayunar', '1f95e'),
      Paso('colegio', 'Ir al colegio', '1f392'),
    ], porQue: 'Primero nos bañamos y después nos vestimos, para no mojar la ropa limpia.'),
    Rutina('dientes', 'Lavarse los dientes', <Paso>[
      Paso('crema', 'Poner la crema', '1faa5'),
      Paso('cepillar', 'Cepillar', '1f9b7'),
      Paso('enjuagar', 'Enjuagar', '1f4a7'),
      Paso('sonreir', 'Sonreír limpio', '1f601'),
    ], porQue: 'La crema va antes de cepillar; enjuagamos al final.'),
    Rutina('manos', 'Lavarse las manos', <Paso>[
      Paso('mojar', 'Mojar', '1f6b0'),
      Paso('jabon', 'Jabón', '1f9fc'),
      Paso('frotar', 'Frotar', '1f450'),
      Paso('secar', 'Secar', '1f9fb'),
    ], porQue: 'Primero el agua, después el jabón y al final secamos.'),
    Rutina('noche', 'Ir a dormir', <Paso>[
      Paso('cenar', 'Cenar', '1f372'),
      Paso('pijama', 'Ponerse la pijama', '1f456'),
      Paso('dientes_n', 'Lavarse los dientes', '1faa5'),
      Paso('cuento', 'Leer un cuento', '1f4d6'),
      Paso('dormir', 'Dormir', '1f634'),
    ], porQue: 'Después de cenar nos lavamos los dientes para dormir con la boca limpia.'),
    Rutina('comida', 'La hora de comer', <Paso>[
      Paso('lavar_manos', 'Lavarse las manos', '1f9fc'),
      Paso('mesa', 'Poner la mesa', '1f37d'),
      Paso('comer', 'Comer', '1f35b'),
      Paso('recoger', 'Recoger el plato', '1f9fd'),
    ], porQue: 'Nos lavamos las manos antes de tocar la comida y recogemos al terminar.'),
    Rutina('semilla', 'Sembrar una planta', <Paso>[
      Paso('tierra', 'Poner tierra', '1fab4'),
      Paso('semilla', 'Poner la semilla', '1f330'),
      Paso('regar', 'Regar', '1f6b0'),
      Paso('sol', 'Dejar al sol', '2600'),
      Paso('flor', 'Crece la flor', '1f33b'),
    ], porQue: 'La semilla necesita tierra, agua y sol, en ese orden, para crecer.'),
    Rutina('arepa', 'Hacer arepas', <Paso>[
      Paso('masa', 'Amasar', '1f35e'),
      Paso('forma', 'Dar forma', '1f94f'),
      Paso('asar', 'Asar', '1f525'),
      Paso('comer_a', 'Comer', '1f60b'),
    ], porQue: 'Primero la masa, luego la forma y después se asa.'),
    Rutina('salir', 'Salir con lluvia', <Paso>[
      Paso('mirar', 'Mirar el cielo', '1f327'),
      Paso('botas', 'Ponerse botas', '1f462'),
      Paso('paraguas', 'Tomar el paraguas', '2602'),
      Paso('salir', 'Salir', '1f6b6'),
    ]),
    Rutina('colegio', 'En el colegio', <Paso>[
      Paso('saludar', 'Saludar', '1f44b'),
      Paso('clase', 'Clase', '1f4da'),
      Paso('descanso', 'Descanso', '26bd'),
      Paso('lonchera', 'Lonchera', '1f371'),
      Paso('casa', 'Volver a casa', '1f3e1'),
    ]),
    Rutina('herida', 'Si me raspo', <Paso>[
      Paso('avisar', 'Avisar a un adulto', '1f9d1'),
      Paso('lavar', 'Lavar con agua', '1f4a7'),
      Paso('curita', 'Poner una curita', '1fa79'),
      Paso('seguir', 'Seguir jugando', '1f600'),
    ], porQue: 'Siempre avisamos primero a un adulto y limpiamos la herida antes de taparla.'),
    Rutina('mariposa', 'De oruga a mariposa', <Paso>[
      Paso('huevo', 'Huevo', '1f95a'),
      Paso('oruga', 'Oruga', '1f41b'),
      Paso('capullo', 'Capullo', '1f9f6'),
      Paso('mariposa', 'Mariposa', '1f98b'),
    ], porQue: 'Del huevo sale la oruga, la oruga hace el capullo y del capullo sale la mariposa.'),
    Rutina('tarea', 'Hacer la tarea', <Paso>[
      Paso('merienda', 'Merienda', '1f34c'),
      Paso('cuaderno', 'Sacar el cuaderno', '1f4d3'),
      Paso('hacer', 'Hacer la tarea', '270f'),
      Paso('guardar', 'Guardar en la maleta', '1f392'),
      Paso('jugar', 'Jugar', '1f3ae'),
    ], porQue: 'Primero la tarea y después el juego: así jugamos tranquilos.'),
  ];
}

/// Ronda del tablero de rutinas: ordenar los pasos.
OrderRound rutinaRound(Rng rng, AgeBand band, int level) {
  // Niveles: 3 pasos, 4 pasos, 5 pasos (o todos), y en el último se quita el nombre del paso.
  final int maxPasos = level <= 1 ? 3 : (level == 2 ? 4 : 5);
  final Rutina r = rng.pick(RutinaBank.all);
  List<Paso> pasos = r.pasos;
  if (pasos.length > maxPasos) {
    // Se conservan el primero y el último, y se quitan pasos intermedios.
    final List<Paso> medio = pasos.sublist(1, pasos.length - 1);
    final List<Paso> elegidos = rng.sample(medio, maxPasos - 2)..sort((Paso a, Paso b) => medio.indexOf(a).compareTo(medio.indexOf(b)));
    pasos = <Paso>[pasos.first, ...elegidos, pasos.last];
  }
  final bool conTexto = level < 4 || band.readsText;
  Widget tile(Paso p, double size) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          EmojiImage(p.emoji, size: conTexto ? size * 0.62 : size * 0.85, semanticsLabel: p.texto),
          if (conTexto) ...<Widget>[
            const SizedBox(height: 2),
            SizedBox(width: size * 1.1, child: Text(p.texto, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PilasColors.tinta, height: 1.1))),
          ],
        ],
      );
  final List<OrderTile> ordered = <OrderTile>[
    for (final Paso p in pasos) OrderTile(id: p.id, label: p.texto, build: (BuildContext context, double size) => tile(p, size)),
  ];
  final List<OrderTile> shuffled = <OrderTile>[
    for (final Paso p in pasos) OrderTile(id: p.id, label: p.texto, build: (BuildContext context, double size) => tile(p, size)),
  ];
  rng.shuffle(shuffled);
  if (shuffled.first.id == ordered.first.id) {
    final OrderTile t = shuffled[0];
    shuffled[0] = shuffled[shuffled.length - 1];
    shuffled[shuffled.length - 1] = t;
  }
  final String secuencia = pasos.map((Paso p) => p.texto.toLowerCase()).join(', ');
  return OrderRound(
    instruction: '${r.nombre}: ¿qué va primero?',
    spoken: '${r.nombre}. Ordena los pasos: ¿qué hacemos primero, qué después y qué al final?',
    hint: 'Piensa qué pasa primero en la vida real. ¿Qué haces antes de ${pasos[1].texto.toLowerCase()}?',
    explain: 'El orden es: $secuencia. ${r.porQue ?? ''}',
    praise: '¡Así es! ${r.porQue ?? ''}',
    ordered: ordered,
    shuffled: shuffled,
    tileSize: pasos.length >= 5 ? 76 : 88,
    slotLabels: <String>[for (int i = 0; i < pasos.length; i++) '${i + 1}.º'],
    separator: const Icon(Icons.arrow_forward_rounded, color: PilasColors.tintaSuave, size: 20),
    sayOnPlaced: (OrderTile t, int i) => i == 0 ? 'Primero, ${t.label.toLowerCase()}.' : (i == pasos.length - 1 ? 'Al final, ${t.label.toLowerCase()}.' : 'Después, ${t.label.toLowerCase()}.'),
  );
}
