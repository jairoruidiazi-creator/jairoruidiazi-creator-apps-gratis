import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/option_builders.dart';
import '../shell/order_game_screen.dart';
import '../shell/tile_order_board.dart';
import '../shell/widgets.dart';
import 'palabra_generator.dart';

final PalabraGenerator _generator = PalabraGenerator();

/// Convierte una ronda de letras en una ronda del tablero de ordenar.
OrderRound palabraRound(Rng rng, AgeBand band, int level) {
  final PalabraRound p = _generator.next(rng, band, level);
  final List<OrderTile> ordered = <OrderTile>[
    for (int i = 0; i < p.letras.length; i++)
      OrderTile(id: 'l$i', value: p.letras[i], label: p.letras[i], build: (BuildContext context, double size) => textTile(p.letras[i], fontSize: size * 0.6, color: band.readsText ? null : letterColor(p.letras[i]))),
  ];
  final List<OrderTile> shuffled = <OrderTile>[
    for (int i = 0; i < p.fichas.length; i++)
      OrderTile(id: 'f$i', value: p.fichas[i], label: p.fichas[i], build: (BuildContext context, double size) => textTile(p.fichas[i], fontSize: size * 0.6, color: band.readsText ? null : letterColor(p.fichas[i]))),
  ];
  final bool lee = band.readsText;
  return OrderRound(
    instruction: lee ? 'Arma la palabra del dibujo.' : 'Arma la palabra: ${p.palabra}.',
    spoken: 'Arma la palabra: ${p.palabra}.',
    hint: p.pista,
    explain: '${_cap(p.palabra)} se escribe: ${p.letras.join(', ')}.',
    praise: '¡${_cap(p.palabra)}!',
    ordered: ordered,
    shuffled: shuffled,
    tileSize: p.letras.length > 8 ? 46 : (p.letras.length > 6 ? 54 : 64),
    prompt: (BuildContext context) => BigPrompt(
      child: EmojiImage(p.item.emoji, size: 88, semanticsLabel: p.palabra),
      caption: p.mostrarModelo ? p.palabra : null,
    ),
    sayOnPlaced: (OrderTile t, int i) {
      // Al terminar una sílaba se dice la sílaba completa, para unir sonido y letra.
      int acumulado = 0;
      for (final String s in p.item.silabas) {
        acumulado += s.length;
        if (acumulado == i + 1) {
          return s;
        }
      }
      return '';
    },
  );
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Color de las fichas de vocal, para distinguirlas en los primeros niveles.
Color letterColor(String l) => 'aeiouáéíóú'.contains(l) ? PilasColors.rosa : PilasColors.tinta;
