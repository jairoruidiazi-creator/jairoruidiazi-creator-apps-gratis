import 'package:flutter/material.dart';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../../model/area.dart';
import '../choice/option_builders.dart';
import '../shell/order_game_screen.dart';
import '../shell/tile_order_board.dart';
import '../shell/widgets.dart';
import 'palabra_generator.dart';

final PalabraGenerator _generator = PalabraGenerator();

/// Convierte una ronda de letras en una ronda del tablero de ordenar.
OrderRound palabraRound(Rng rng, AgeBand band, int level) {
  final PalabraRound p = _generator.next(rng, band, level);
  final bool lee = band.readsText;
  OrderTile ficha(String id, String letra) => OrderTile(
        id: id,
        value: letra,
        label: 'letra ${letra.toUpperCase()}',
        build: (BuildContext context, double size) => textTile(context, letra, fontSize: size * 0.6, color: lee ? null : letterColor(context, letra)),
      );
  final List<OrderTile> ordered = <OrderTile>[for (int i = 0; i < p.letras.length; i++) ficha('l$i', p.letras[i])];
  final List<OrderTile> shuffled = <OrderTile>[for (int i = 0; i < p.fichas.length; i++) ficha('f$i', p.fichas[i])];
  return OrderRound(
    instruction: lee ? 'Arma la palabra del dibujo.' : 'Arma la palabra: ${p.palabra}.',
    spoken: 'Arma la palabra: ${p.palabra}.',
    hint: p.pista,
    explain: '${Es.cap(p.palabra)} se escribe así: ${p.letras.join(' ').toUpperCase()}.',
    praise: '¡${Es.cap(p.palabra)}!',
    ordered: ordered,
    shuffled: shuffled,
    tileSize: p.letras.length > 8 ? 52 : (p.letras.length > 6 ? 58 : 68),
    prompt: (BuildContext context) => BigPrompt(
      child: EmojiImage(p.item.emoji, size: 88, semanticsLabel: p.palabra),
      caption: p.mostrarModelo ? p.palabra : null,
    ),
    sayOnPlaced: (OrderTile t, int i) {
      // Al terminar una sílaba se dice la sílaba completa, para unir sonido y
      // letra. Las sílabas de una sola letra no se dicen solas: la voz las
      // leería como el nombre de la letra.
      int acumulado = 0;
      for (final String s in p.item.silabas) {
        acumulado += s.length;
        if (acumulado == i + 1) {
          return s.length > 1 ? s : '';
        }
      }
      return '';
    },
  );
}

/// Color de las fichas de vocal, para distinguirlas en los primeros niveles
/// (el texto cumple el contraste en las dos paletas).
Color letterColor(BuildContext context, String l) {
  final PilasPalette pal = PilasPalette.of(context);
  return 'aeiouáéíóú'.contains(l) ? pal.areaTexto(Area.creatividad) : pal.tinta;
}
