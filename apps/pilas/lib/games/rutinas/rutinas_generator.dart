import 'package:flutter/material.dart';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../shell/order_game_screen.dart';
import '../shell/tile_order_board.dart';
import '../shell/widgets.dart';

/// Un paso de una rutina. [antes] son los pasos que tienen que ir antes de
/// este; los que no dependen entre sí se pueden hacer en cualquier orden
/// (vestirse y desayunar, ponerse las botas y tomar el paraguas).
class Paso {
  const Paso(this.id, this.texto, this.emoji, {this.antes = const <String>[]});

  final String id;
  final String texto;
  final String emoji;
  final List<String> antes;
}

/// Una rutina: nombre, pasos en un orden posible y por qué el orden importa.
class Rutina {
  const Rutina(this.id, this.nombre, this.pasos, {this.porQue});

  final String id;
  final String nombre;
  final List<Paso> pasos;

  /// Por qué el orden importa (se dice al explicar).
  final String? porQue;

  /// Todos los órdenes válidos de [elegidos] (los ids de los pasos de la
  /// ronda), respetando quién va antes de quién.
  List<List<String>> ordenesValidos(List<Paso> elegidos) {
    final Set<String> ids = elegidos.map((Paso p) => p.id).toSet();
    // "Antes" transitivo entre los pasos elegidos: si se quitó un paso del
    // medio, su orden se sigue respetando.
    final Map<String, Set<String>> previos = <String, Set<String>>{};
    Set<String> todosLosAntes(String id, Set<String> visto) {
      final Paso p = pasos.firstWhere((Paso x) => x.id == id);
      final Set<String> out = <String>{};
      for (final String a in p.antes) {
        if (visto.add(a)) {
          out.add(a);
          out.addAll(todosLosAntes(a, visto));
        }
      }
      return out;
    }

    for (final Paso p in elegidos) {
      previos[p.id] = todosLosAntes(p.id, <String>{}).intersection(ids);
    }
    final List<List<String>> out = <List<String>>[];
    void armar(List<String> hecho) {
      if (hecho.length == elegidos.length) {
        out.add(List<String>.from(hecho));
        return;
      }
      for (final Paso p in elegidos) {
        if (hecho.contains(p.id)) {
          continue;
        }
        if (previos[p.id]!.every(hecho.contains)) {
          hecho.add(p.id);
          armar(hecho);
          hecho.removeLast();
        }
      }
    }

    armar(<String>[]);
    return out;
  }
}

/// Banco de rutinas y secuencias cotidianas. Cada pictograma muestra lo que
/// dice el paso (revisados contra el nombre de cada pictograma).
class RutinaBank {
  RutinaBank._();

  static const List<Rutina> all = <Rutina>[
    Rutina('manana', 'Por la mañana', <Paso>[
      Paso('despertar', 'Despertarse', '23f0'),
      Paso('banarse', 'Bañarse', '1f6bf', antes: <String>['despertar']),
      Paso('vestirse', 'Vestirse', '1f455', antes: <String>['banarse']),
      Paso('desayunar', 'Desayunar', '1f95e', antes: <String>['despertar']),
      Paso('colegio', 'Ir al colegio', '1f392', antes: <String>['vestirse', 'desayunar']),
    ], porQue: 'Primero nos bañamos y después nos vestimos, para no mojar la ropa limpia. El desayuno puede ir antes o después de vestirse.'),
    Rutina('dientes', 'Lavarse los dientes', <Paso>[
      Paso('crema', 'Poner la crema en el cepillo', '1faa5'),
      Paso('cepillar', 'Cepillar los dientes', '1f9b7', antes: <String>['crema']),
      Paso('enjuagar', 'Enjuagarse la boca', '1f4a7', antes: <String>['cepillar']),
      Paso('sonreir', 'Sonreír con los dientes limpios', '1f601', antes: <String>['enjuagar']),
    ], porQue: 'La crema va antes de cepillar, y nos enjuagamos al final.'),
    Rutina('manos', 'Lavarse las manos', <Paso>[
      Paso('mojar', 'Mojarse las manos', '1f6b0'),
      Paso('jabon', 'Echarse jabón', '1f9fc', antes: <String>['mojar']),
      Paso('frotar', 'Frotar bien', '1f450', antes: <String>['jabon']),
      Paso('enjuagar_m', 'Enjuagarse', '1f4a7', antes: <String>['frotar']),
      Paso('secar', 'Secarse con papel', '1f9fb', antes: <String>['enjuagar_m']),
    ], porQue: 'Primero el agua, después el jabón; se frota, se enjuaga y al final nos secamos.'),
    Rutina('noche', 'Ir a dormir', <Paso>[
      Paso('banarse_n', 'Bañarse', '1f6c1'),
      Paso('cenar', 'Comer', '1f372'),
      Paso('dientes_n', 'Lavarse los dientes', '1faa5', antes: <String>['cenar']),
      Paso('cuento', 'Leer un cuento', '1f4d6', antes: <String>['dientes_n', 'banarse_n']),
      Paso('dormir', 'Dormir', '1f634', antes: <String>['cuento']),
    ], porQue: 'Después de comer nos lavamos los dientes, para dormir con la boca limpia. El baño puede ir antes o después de comer.'),
    Rutina('comida', 'La hora de comer', <Paso>[
      Paso('lavar_manos', 'Lavarse las manos', '1f9fc'),
      Paso('mesa', 'Poner la mesa', '1f37d'),
      Paso('comer', 'Comer', '1f35b', antes: <String>['lavar_manos', 'mesa']),
      Paso('lavar_plato', 'Lavar el plato', '1f9fd', antes: <String>['comer']),
    ], porQue: 'Nos lavamos las manos antes de tocar la comida y lavamos el plato al terminar. Lavarse las manos y poner la mesa pueden ir en cualquier orden.'),
    Rutina('semilla', 'Sembrar una planta', <Paso>[
      Paso('sembrar', 'Enterrar la semilla', '1f330'),
      Paso('regar', 'Regarla', '1f4a7', antes: <String>['sembrar']),
      Paso('sol', 'Dejarla al sol', '2600', antes: <String>['sembrar']),
      Paso('brote', 'Sale un brote', '1f331', antes: <String>['regar', 'sol']),
      Paso('flor', 'Crece la flor', '1f33b', antes: <String>['brote']),
    ], porQue: 'La semilla necesita tierra, agua y sol para crecer: primero sale un brote y después la flor.'),
    Rutina('arepa', 'Hacer arepas', <Paso>[
      Paso('mezclar', 'Mezclar la harina con agua', '1f963'),
      Paso('amasar', 'Amasar', '1f450', antes: <String>['mezclar']),
      Paso('forma', 'Darles forma', '1fad3', antes: <String>['amasar']),
      Paso('asar', 'Asarlas', '1f525', antes: <String>['forma']),
      Paso('comer_a', 'Comer', '1f60b', antes: <String>['asar']),
    ], porQue: 'Primero se hace la masa, luego se les da forma y después se asan.'),
    Rutina('salir', 'Salir con lluvia', <Paso>[
      Paso('mirar', 'Mirar el cielo', '1f327'),
      Paso('botas', 'Ponerse las botas', '1f97e', antes: <String>['mirar']),
      Paso('paraguas', 'Tomar el paraguas', '2602', antes: <String>['mirar']),
      Paso('salir', 'Salir', '1f6b6', antes: <String>['botas', 'paraguas']),
    ], porQue: 'Antes de salir miramos si llueve; las botas y el paraguas pueden ir en cualquier orden.'),
    Rutina('herida', 'Si me raspo', <Paso>[
      Paso('avisar', 'Avisar a un adulto', '1f9d1'),
      Paso('lavar', 'Lavar con agua', '1f4a7', antes: <String>['avisar']),
      Paso('curita', 'Poner una curita', '1fa79', antes: <String>['lavar']),
      Paso('seguir', 'Seguir jugando', '1f600', antes: <String>['curita']),
    ], porQue: 'Siempre avisamos primero a un adulto, y la herida se limpia antes de taparla.'),
    Rutina('mariposa', 'De oruga a mariposa', <Paso>[
      Paso('huevo', 'Un huevo en una hoja', '1f95a'),
      Paso('oruga', 'Sale la oruga', '1f41b', antes: <String>['huevo']),
      Paso('come', 'La oruga come hojas y crece', '1f343', antes: <String>['oruga']),
      Paso('mariposa', 'Sale la mariposa', '1f98b', antes: <String>['come']),
    ], porQue: 'Del huevo sale la oruga; la oruga come y crece, se envuelve en un capullo y de ahí sale la mariposa.'),
    Rutina('tarea', 'Hacer la tarea', <Paso>[
      Paso('cuaderno', 'Sacar el cuaderno', '1f4d3'),
      Paso('hacer', 'Hacer la tarea', '270f', antes: <String>['cuaderno']),
      Paso('guardar', 'Guardarlo en la maleta', '1f392', antes: <String>['hacer']),
      Paso('jugar', 'Salir a jugar', '26bd', antes: <String>['guardar']),
    ], porQue: 'Primero la tarea y después el juego: así jugamos tranquilos.'),
  ];
}

/// Ronda del tablero de rutinas: ordenar los pasos. Niveles: 3, 4 y 5 pasos;
/// en el último, los que todavía no leen ven solo los dibujos.
OrderRound rutinaRound(Rng rng, AgeBand band, int level) {
  final int maxPasos = level <= 1 ? 3 : (level == 2 ? 4 : 5);
  final Rutina r = rng.pick(RutinaBank.all);
  List<Paso> pasos = r.pasos;
  if (pasos.length > maxPasos) {
    // Se conservan el primero y el último, y se quitan pasos del medio.
    final List<Paso> medio = pasos.sublist(1, pasos.length - 1);
    final List<Paso> elegidos = rng.sample(medio, maxPasos - 2)..sort((Paso a, Paso b) => medio.indexOf(a).compareTo(medio.indexOf(b)));
    pasos = <Paso>[pasos.first, ...elegidos, pasos.last];
  }
  final List<List<String>> ordenes = r.ordenesValidos(pasos);
  final List<String> principal = ordenes.first;
  final List<Paso> enOrden = <Paso>[for (final String id in principal) pasos.firstWhere((Paso p) => p.id == id)];
  final bool conTexto = level < 4 || band.readsText;
  Widget tile(BuildContext context, Paso p, double size) {
    final PilasPalette pal = PilasPalette.of(context);
    // Con letra grande el texto ocupa más líneas: el conjunto se achica para
    // caber en la ficha en lugar de desbordarse.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          EmojiImage(p.emoji, size: conTexto ? size * 0.55 : size * 0.85, semanticsLabel: p.texto),
          if (conTexto) ...<Widget>[
            const SizedBox(height: 2),
            SizedBox(
              width: size * 1.25,
              child: Text(p.texto, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.tinta, height: 1.1)),
            ),
          ],
        ],
      ),
    );
  }

  OrderTile ficha(Paso p) => OrderTile(id: p.id, label: p.texto, widthFactor: conTexto ? 1.3 : 1.0, build: (BuildContext context, double size) => tile(context, p, size));
  final List<OrderTile> ordered = <OrderTile>[for (final Paso p in enOrden) ficha(p)];
  final List<OrderTile> shuffled = <OrderTile>[for (final Paso p in pasos) ficha(p)];
  rng.shuffle(shuffled);
  if (shuffled.first.id == ordered.first.id && shuffled.length > 1) {
    final OrderTile t = shuffled[0];
    shuffled[0] = shuffled[shuffled.length - 1];
    shuffled[shuffled.length - 1] = t;
  }
  final String secuencia = Es.listaY(enOrden.map((Paso p) => p.texto.toLowerCase()).toList());
  return OrderRound(
    instruction: '${r.nombre}: ¿qué va primero?',
    spoken: '${r.nombre}. Ordena los pasos: ¿qué va primero, qué después y qué al final?',
    hint: 'Piensa qué pasa primero en la vida real. ¿Qué haces antes de ${enOrden[1].texto.toLowerCase()}?',
    explain: 'Un orden correcto es: $secuencia. ${r.porQue ?? ''}',
    praise: '¡Así es! ${r.porQue ?? ''}',
    ordered: ordered,
    alternatives: ordenes.sublist(1),
    shuffled: shuffled,
    tileSize: pasos.length >= 5 ? 78 : 90,
    slotLabels: <String>[for (int i = 0; i < pasos.length; i++) Es.ordinalCorto(i + 1)],
    separator: Builder(builder: (BuildContext context) => Icon(Icons.arrow_forward_rounded, color: PilasPalette.of(context).tintaSuave, size: 20)),
    sayOnPlaced: (OrderTile t, int i) => i == 0 ? 'Primero, ${t.label.toLowerCase()}.' : (i == pasos.length - 1 ? 'Al final, ${t.label.toLowerCase()}.' : 'Después, ${t.label.toLowerCase()}.'),
  );
}
