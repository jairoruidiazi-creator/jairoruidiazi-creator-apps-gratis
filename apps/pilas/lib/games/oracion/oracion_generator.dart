import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../shell/order_game_screen.dart';
import '../shell/tile_order_board.dart';
import '../shell/widgets.dart';

/// Una oración del banco: las palabras en orden y, si aplica, un pictograma.
class Oracion {
  const Oracion(this.palabras, {this.emoji, this.regla});

  final List<String> palabras;
  final String? emoji;

  /// Regla gramatical que se nombra al explicar (por ejemplo, "primero quién, luego qué hace").
  final String? regla;

  String get texto => palabras.join(' ');
}

/// Banco de oraciones por tramo. Todas son originales y hablan de la vida
/// cotidiana de un niño en Colombia y América Latina.
class OracionBank {
  OracionBank._();

  static const String reglaSujeto = 'Primero va quién lo hace y después qué hace.';
  static const String reglaMayuscula = 'La oración empieza con mayúscula y termina con punto.';
  static const String reglaComplemento = 'Después del verbo va lo que completa la idea: qué, dónde o cuándo.';
  static const String reglaConector = 'Las palabras como "porque", "pero" y "cuando" unen dos ideas: lo que va antes y lo que va después tienen que tener sentido.';

  static const List<Oracion> b5a6 = <Oracion>[
    Oracion(<String>['El', 'gato', 'duerme.'], emoji: '1f408', regla: reglaSujeto),
    Oracion(<String>['Mamá', 'cocina', 'arepas.'], emoji: '1f469-200d-1f373', regla: reglaSujeto),
    Oracion(<String>['El', 'perro', 'corre.'], emoji: '1f415', regla: reglaSujeto),
    Oracion(<String>['Yo', 'como', 'mango.'], emoji: '1f96d', regla: reglaSujeto),
    Oracion(<String>['La', 'luna', 'brilla.'], emoji: '1f319', regla: reglaSujeto),
    Oracion(<String>['Papá', 'lee', 'un', 'cuento.'], emoji: '1f4d6', regla: reglaComplemento),
    Oracion(<String>['El', 'sol', 'sale', 'temprano.'], emoji: '2600', regla: reglaComplemento),
    Oracion(<String>['Mi', 'abuela', 'teje', 'una', 'ruana.'], emoji: '1f9f6', regla: reglaComplemento),
    Oracion(<String>['Los', 'niños', 'juegan', 'fútbol.'], emoji: '26bd', regla: reglaSujeto),
    Oracion(<String>['La', 'vaca', 'da', 'leche.'], emoji: '1f404', regla: reglaSujeto),
    Oracion(<String>['Yo', 'me', 'lavo', 'las', 'manos.'], emoji: '1f9fc', regla: reglaComplemento),
    Oracion(<String>['El', 'pez', 'nada', 'en', 'el', 'río.'], emoji: '1f41f', regla: reglaComplemento),
  ];

  static const List<Oracion> b7a8 = <Oracion>[
    Oracion(<String>['Mi', 'hermana', 'monta', 'en', 'bicicleta', 'los', 'domingos.'], emoji: '1f6b2', regla: reglaComplemento),
    Oracion(<String>['El', 'colibrí', 'bebe', 'el', 'néctar', 'de', 'las', 'flores.'], emoji: '1f33a', regla: reglaComplemento),
    Oracion(<String>['Hoy', 'llovió', 'mucho', 'en', 'la', 'tarde.'], emoji: '1f327', regla: reglaMayuscula),
    Oracion(<String>['En', 'la', 'finca', 'hay', 'gallinas', 'y', 'conejos.'], emoji: '1f414', regla: reglaMayuscula),
    Oracion(<String>['Nosotros', 'sembramos', 'una', 'mata', 'de', 'tomate.'], emoji: '1f345', regla: reglaSujeto),
    Oracion(<String>['La', 'profesora', 'nos', 'leyó', 'una', 'leyenda.'], emoji: '1f469-200d-1f3eb', regla: reglaSujeto),
    Oracion(<String>['Mi', 'primo', 'vive', 'cerca', 'del', 'mar.'], emoji: '1f30a', regla: reglaComplemento),
    Oracion(<String>['El', 'bus', 'pasa', 'por', 'el', 'parque', 'a', 'las', 'siete.'], emoji: '1f68c', regla: reglaComplemento),
    Oracion(<String>['Ayer', 'comimos', 'sancocho', 'en', 'casa', 'de', 'mi', 'tía.'], emoji: '1f372', regla: reglaMayuscula),
    Oracion(<String>['Las', 'tortugas', 'ponen', 'sus', 'huevos', 'en', 'la', 'arena.'], emoji: '1f422', regla: reglaSujeto),
    Oracion(<String>['Me', 'gusta', 'dibujar', 'animales', 'con', 'colores.'], emoji: '1f58d', regla: reglaComplemento),
    Oracion(<String>['El', 'río', 'baja', 'desde', 'la', 'montaña.'], emoji: '26f0', regla: reglaComplemento),
  ];

  static const List<Oracion> b9a11 = <Oracion>[
    Oracion(<String>['Cuando', 'llueve,', 'las', 'ranas', 'cantan', 'toda', 'la', 'noche.'], emoji: '1f438', regla: reglaConector),
    Oracion(<String>['Llevé', 'paraguas', 'porque', 'el', 'cielo', 'estaba', 'nublado.'], emoji: '2602', regla: reglaConector),
    Oracion(<String>['Quería', 'jugar', 'afuera,', 'pero', 'tenía', 'que', 'terminar', 'la', 'tarea.'], emoji: '1f4dd', regla: reglaConector),
    Oracion(<String>['Los', 'páramos', 'guardan', 'el', 'agua', 'que', 'beben', 'las', 'ciudades.'], emoji: '1f3d4', regla: reglaComplemento),
    Oracion(<String>['Aunque', 'era', 'pequeña,', 'la', 'hormiga', 'cargó', 'una', 'hoja', 'enorme.'], emoji: '1f41c', regla: reglaConector),
    Oracion(<String>['Mi', 'abuelo', 'cuenta', 'que', 'antes', 'no', 'había', 'celulares.'], emoji: '1f474', regla: reglaConector),
    Oracion(<String>['Si', 'reciclamos', 'el', 'plástico,', 'el', 'mar', 'estará', 'más', 'limpio.'], emoji: '267b', regla: reglaConector),
    Oracion(<String>['El', 'cóndor', 'vuela', 'muy', 'alto', 'sobre', 'los', 'Andes.'], emoji: '1f985', regla: reglaComplemento),
    Oracion(<String>['Después', 'del', 'partido,', 'todos', 'celebramos', 'con', 'jugo', 'de', 'lulo.'], emoji: '1f9c3', regla: reglaComplemento),
    Oracion(<String>['La', 'biblioteca', 'abre', 'temprano', 'y', 'cierra', 'al', 'anochecer.'], emoji: '1f4da', regla: reglaConector),
    Oracion(<String>['Nadie', 'sabía', 'quién', 'había', 'dejado', 'la', 'puerta', 'abierta.'], emoji: '1f6aa', regla: reglaComplemento),
    Oracion(<String>['Primero', 'mezclamos', 'la', 'harina', 'y', 'luego', 'agregamos', 'el', 'queso.'], emoji: '1f9c0', regla: reglaConector),
  ];

  static List<Oracion> forBand(AgeBand band) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        return b5a6;
      case AgeBand.b7a8:
        return b7a8;
      case AgeBand.b9a11:
        return b9a11;
    }
  }
}

/// Ronda de "Ordena la oración" para el tablero de ordenar.
OrderRound oracionRound(Rng rng, AgeBand band, int level) {
  final List<Oracion> banco = OracionBank.forBand(band);
  // Los niveles bajos usan las oraciones más cortas del banco.
  final List<Oracion> ordenadas = List<Oracion>.from(banco)..sort((Oracion a, Oracion b) => a.palabras.length.compareTo(b.palabras.length));
  final int tramo = (ordenadas.length / 4).ceil();
  final int inicio = ((level - 1) * tramo).clamp(0, ordenadas.length - 1).toInt();
  final int fin = (inicio + tramo + 2).clamp(1, ordenadas.length).toInt();
  final Oracion o = rng.pick(ordenadas.sublist(inicio, fin));

  final List<OrderTile> ordered = <OrderTile>[
    for (int i = 0; i < o.palabras.length; i++)
      OrderTile(id: 'w$i', value: o.palabras[i].toLowerCase(), label: o.palabras[i], build: (BuildContext context, double size) => textTile(o.palabras[i], fontSize: size * 0.36)),
  ];
  final List<OrderTile> shuffled = <OrderTile>[
    for (int i = 0; i < o.palabras.length; i++)
      OrderTile(id: 's$i', value: o.palabras[i].toLowerCase(), label: o.palabras[i], build: (BuildContext context, double size) => textTile(o.palabras[i], fontSize: size * 0.36)),
  ];
  rng.shuffle(shuffled);
  if (shuffled.first.value == ordered.first.value && shuffled.length > 1) {
    final OrderTile t = shuffled[0];
    shuffled[0] = shuffled[1];
    shuffled[1] = t;
  }
  final bool lee = band.readsText;
  final String spoken = lee ? 'Ordena las palabras para formar la oración.' : 'Ordena las palabras para formar la oración: ${o.texto}';
  return OrderRound(
    instruction: lee ? 'Ordena las palabras para formar una oración.' : 'Ordena: ${o.texto}',
    spoken: spoken,
    hint: lee
        ? 'Busca la palabra que empieza con mayúscula: esa va primero. La que termina en punto va al final. ${o.regla ?? ''}'
        : 'Escucha otra vez: ${o.texto} ¿Cuál palabra va ahora?',
    explain: 'La oración es: ${o.texto} ${o.regla ?? ''}',
    praise: o.texto,
    ordered: ordered,
    shuffled: shuffled,
    tileSize: o.palabras.length > 7 ? 72 : 84,
    prompt: o.emoji == null ? null : (BuildContext context) => EmojiImage(o.emoji!, size: 56),
    sayOnPlaced: (OrderTile t, int i) => t.label,
  );
}
