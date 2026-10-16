import 'package:flutter/material.dart';

import '../../content/money.dart';
import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Un producto en la tienda.
class Producto {
  const Producto(this.item, this.precio, {this.cantidad = 1});

  final VocabItem item;
  final int precio;
  final int cantidad;

  int get total => precio * cantidad;
}

/// Ronda de pagar: el niño arma el total con monedas y billetes.
class PagoRound {
  const PagoRound({required this.productos, required this.denominaciones, required this.instruction});

  final List<Producto> productos;
  final List<Denominacion> denominaciones;
  final String instruction;

  int get total => productos.fold<int>(0, (int s, Producto p) => s + p.total);
}

/// Una ronda de la tienda es de elegir o de pagar.
class TiendaRound {
  const TiendaRound.choice(this.choice) : pago = null;

  const TiendaRound.pago(this.pago) : choice = null;

  final ChoiceRound? choice;
  final PagoRound? pago;
}

/// La tienda: contar, comparar, pagar exacto, dar vueltas y presupuestar,
/// siempre con pesos colombianos.
class TiendaGenerator {
  static List<VocabItem> get _productos => Vocab.all.where((VocabItem v) => (v.has('comida') || v.has('juguete') || v.has('escuela')) && !v.nombre.contains(' ')).toList();

  TiendaRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        if (level == 1) {
          return TiendaRound.choice(_contar(rng, 1, 5));
        }
        if (level == 2) {
          return TiendaRound.choice(_contar(rng, 3, 10));
        }
        if (level == 3) {
          return TiendaRound.pago(_pagoMonedasIguales(rng));
        }
        return TiendaRound.choice(_masMenos(rng));
      case AgeBand.b5a6:
        if (level == 1) {
          return TiendaRound.pago(_pago(rng, <int>[100, 200, 500], 100, 900, 1));
        }
        if (level == 2) {
          return TiendaRound.pago(_pago(rng, <int>[100, 200, 500, 1000], 100, 2000, 1));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(_totalDeDos(rng, 100, 900, 100)) : TiendaRound.pago(_pago(rng, <int>[100, 200, 500, 1000], 100, 2000, 2));
        }
        return rng.chance(0.5) ? TiendaRound.choice(_sumaResta20(rng)) : TiendaRound.choice(_totalDeDos(rng, 100, 1000, 100));
      case AgeBand.b7a8:
        if (level == 1) {
          return TiendaRound.pago(_pago(rng, <int>[500, 1000, 2000, 5000], 500, 9500, 1));
        }
        if (level == 2) {
          return TiendaRound.choice(_vueltas(rng, 1000, 9000, 500, <int>[5000, 10000]));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(_totalDeDos(rng, 500, 12000, 500)) : TiendaRound.choice(_vueltas(rng, 2000, 18000, 500, <int>[10000, 20000]));
        }
        return rng.chance(0.5) ? TiendaRound.choice(_multiplicar(rng)) : TiendaRound.pago(_pago(rng, <int>[500, 1000, 2000, 5000, 10000], 1000, 24000, 2));
      case AgeBand.b9a11:
        if (level == 1) {
          return rng.chance(0.5) ? TiendaRound.choice(_multiplicar(rng, max: 12)) : TiendaRound.choice(_vueltas(rng, 5000, 45000, 100, <int>[20000, 50000]));
        }
        if (level == 2) {
          return TiendaRound.choice(_presupuesto(rng));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(_precioUnitario(rng)) : TiendaRound.choice(_presupuesto(rng));
        }
        return rng.chance(0.5) ? TiendaRound.choice(_descuento(rng)) : TiendaRound.choice(_precioUnitario(rng));
    }
  }

  // ------------------------------------------------------------ contar y comparar

  ChoiceRound _contar(Rng rng, int min, int max) {
    final VocabItem item = rng.pick(Vocab.withTag('fruta'));
    final int n = rng.range(min, max);
    final Set<int> opciones = <int>{n};
    while (opciones.length < 3) {
      final int d = rng.range(min, max);
      opciones.add(d);
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.number(o)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿${_cuantos(item)} ${_pluralNombre(item)} hay?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: n > 6 ? 40 : 52)],
        ),
      ),
      options: options,
      correctId: 'n$n',
      hint: 'Toca cada una con el dedo y cuenta despacio: uno, dos, tres...',
      explain: 'Hay $n ${_pluralNombre(item)}.',
      praise: 'Hay $n ${_pluralNombre(item)}.',
    );
  }

  ChoiceRound _masMenos(Rng rng) {
    final VocabItem item = rng.pick(Vocab.withTag('fruta'));
    final int a = rng.range(1, 7);
    int b = rng.range(1, 7);
    while (b == a) {
      b = rng.range(1, 7);
    }
    final bool pedirMas = rng.chance(0.5);
    final String correcto = pedirMas ? (a > b ? 'izq' : 'der') : (a < b ? 'izq' : 'der');
    Widget canasta(int n) => Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: 34)],
        );
    final List<ChoiceOption> options = <ChoiceOption>[
      ChoiceOption(id: 'izq', label: '$a ${_pluralNombre(item)}', build: (BuildContext context, double size) => canasta(a)),
      ChoiceOption(id: 'der', label: '$b ${_pluralNombre(item)}', build: (BuildContext context, double size) => canasta(b)),
    ];
    return ChoiceRound(
      instruction: pedirMas ? '¿Dónde hay más ${_pluralNombre(item)}?' : '¿Dónde hay menos ${_pluralNombre(item)}?',
      options: options,
      correctId: correcto,
      hint: 'Cuenta las de cada lado: $a y $b.',
      explain: pedirMas ? 'Aquí hay ${a > b ? a : b}, que es más que ${a > b ? b : a}.' : 'Aquí hay ${a < b ? a : b}, que es menos que ${a < b ? b : a}.',
      columns: 2,
    );
  }

  ChoiceRound _sumaResta20(Rng rng) {
    final VocabItem item = rng.pick(Vocab.withTag('fruta'));
    final bool suma = rng.chance(0.6);
    final int a = rng.range(2, 12);
    final int b = rng.range(1, suma ? 8 : a);
    final int r = suma ? a + b : a - b;
    final Set<int> opciones = <int>{r};
    while (opciones.length < 3) {
      final int d = r + rng.range(-3, 3);
      if (d >= 0) {
        opciones.add(d);
      }
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.number(o)];
    rng.shuffle(options);
    final String texto = suma ? 'Tenías $a ${_pluralNombre(item)} y compraste $b más. ¿${_cuantos(item)} tienes?' : 'Tenías $a ${_pluralNombre(item)} y regalaste $b. ¿${_cuantos(item)} te quedan?';
    return ChoiceRound(
      instruction: texto,
      prompt: (BuildContext context) => BigPrompt(
        child: Text(suma ? '$a + $b = ?' : '$a − $b = ?', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
      ),
      options: options,
      correctId: 'n$r',
      hint: suma ? 'Empieza en $a y cuenta $b más con los dedos.' : 'Empieza en $a y quita $b con los dedos.',
      explain: suma ? '$a más $b es $r.' : '$a menos $b es $r.',
    );
  }

  // ------------------------------------------------------------ pagar

  PagoRound _pagoMonedasIguales(Rng rng) {
    final VocabItem item = rng.pick(_productos);
    final int n = rng.range(1, 5);
    return PagoRound(
      productos: <Producto>[Producto(item, 100 * n)],
      denominaciones: <Denominacion>[Denominacion.of(100)],
      instruction: '${_cap(item.conArticulo)} vale $n ${n == 1 ? 'moneda' : 'monedas'}. Pon las monedas y paga.',
    );
  }

  PagoRound _pago(Rng rng, List<int> denoms, int min, int max, int cuantos) {
    final int paso = denoms.first;
    final List<Producto> productos = <Producto>[];
    final List<VocabItem> items = rng.sample(_productos, cuantos);
    for (final VocabItem it in items) {
      final int precio = (rng.range(min ~/ paso, max ~/ paso)) * paso;
      productos.add(Producto(it, precio < paso ? paso : precio));
    }
    final int total = productos.fold<int>(0, (int s, Producto p) => s + p.total);
    final String lista = productos.map((Producto p) => '${p.item.conArticulo} cuesta ${pesosEnPalabras(p.precio)}').join(' y ');
    return PagoRound(
      productos: productos,
      denominaciones: denoms.map(Denominacion.of).toList(),
      instruction: cuantos == 1 ? '$lista. Paga el precio exacto.' : '$lista. En total son ${pesosEnPalabras(total)}. Paga exacto.',
    );
  }

  // ------------------------------------------------------------ cálculos con precios

  ChoiceRound _totalDeDos(Rng rng, int min, int max, int paso) {
    final List<VocabItem> items = rng.sample(_productos, 2);
    final int a = rng.range(min ~/ paso, max ~/ paso) * paso;
    final int b = rng.range(min ~/ paso, max ~/ paso) * paso;
    final int total = a + b;
    final List<int> opciones = _opcionesCerca(rng, total, paso);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Compras ${items[0].conArticulo} y ${items[1].conArticulo}. ¿Cuánto pagas en total?',
      prompt: (BuildContext context) => _dosPrecios(items[0], a, items[1], b),
      options: options,
      correctId: 'n$total',
      hint: 'Suma los dos precios: ${formatPesos(a)} más ${formatPesos(b)}.',
      explain: '${formatPesos(a)} más ${formatPesos(b)} son ${formatPesos(total)}.',
    );
  }

  ChoiceRound _vueltas(Rng rng, int min, int max, int paso, List<int> billetes) {
    final VocabItem item = rng.pick(_productos);
    final int precio = rng.range(min ~/ paso, max ~/ paso) * paso;
    final int billete = billetes.where((int b) => b > precio).isEmpty ? billetes.last : billetes.firstWhere((int b) => b > precio);
    final int vuelta = billete - precio;
    final List<int> opciones = _opcionesCerca(rng, vuelta, paso);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${_cap(item.conArticulo)} cuesta ${pesosEnPalabras(precio)} y pagas con un billete de ${pesosEnPalabras(billete)}. ¿Cuánto te devuelven?',
      prompt: (BuildContext context) => BigPrompt(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmojiImage(item.emoji, size: 64),
            const SizedBox(width: 10),
            Text(formatPesos(precio), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
            const SizedBox(width: 18),
            MoneyWidget(denominacion: Denominacion.of(billete), width: 110),
          ],
        ),
      ),
      options: options,
      correctId: 'n$vuelta',
      hint: 'Cuenta desde ${formatPesos(precio)} hasta llegar a ${formatPesos(billete)}.',
      explain: '${formatPesos(billete)} menos ${formatPesos(precio)} son ${formatPesos(vuelta)}.',
    );
  }

  ChoiceRound _multiplicar(Rng rng, {int max = 9}) {
    final VocabItem item = rng.pick(_productos);
    final int precio = rng.pick(<int>[500, 1000, 1500, 2000, 2500, 3000]);
    final int n = rng.range(2, max);
    final int total = precio * n;
    final List<int> opciones = _opcionesCerca(rng, total, 500);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada ${item.nombre} cuesta ${pesosEnPalabras(precio)}. ¿Cuánto cuestan $n?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: 40)],
        ),
        caption: '$n × ${formatPesos(precio)}',
      ),
      options: options,
      correctId: 'n$total',
      hint: 'Multiplica: $n veces ${formatPesos(precio)}. Puedes sumar de a ${formatPesos(precio)}.',
      explain: '$n por ${formatPesos(precio)} son ${formatPesos(total)}.',
    );
  }

  ChoiceRound _presupuesto(Rng rng) {
    final List<VocabItem> items = rng.sample(_productos, 2);
    final int a = rng.range(2, 18) * 500;
    final int b = rng.range(2, 18) * 500;
    final int presupuesto = rng.pick(<int>[10000, 20000, 30000]);
    final int gasto = a + b;
    final bool alcanza = gasto <= presupuesto;
    final int correcto = alcanza ? presupuesto - gasto : gasto - presupuesto;
    final List<int> opciones = _opcionesCerca(rng, correcto, 500);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: alcanza
          ? 'Tienes ${pesosEnPalabras(presupuesto)}. Compras ${items[0].conArticulo} y ${items[1].conArticulo}. ¿Cuánto te sobra?'
          : 'Tienes ${pesosEnPalabras(presupuesto)}. Quieres ${items[0].conArticulo} y ${items[1].conArticulo}. ¿Cuánto te falta?',
      prompt: (BuildContext context) => _dosPrecios(items[0], a, items[1], b, extra: 'Tienes ${formatPesos(presupuesto)}'),
      options: options,
      correctId: 'n$correcto',
      hint: 'Primero suma los dos precios: ${formatPesos(gasto)}. Luego compara con ${formatPesos(presupuesto)}.',
      explain: alcanza ? '${formatPesos(presupuesto)} menos ${formatPesos(gasto)} son ${formatPesos(correcto)}: te sobra.' : '${formatPesos(gasto)} menos ${formatPesos(presupuesto)} son ${formatPesos(correcto)}: te falta.',
    );
  }

  ChoiceRound _precioUnitario(Rng rng) {
    final VocabItem item = rng.pick(_productos);
    final int n = rng.range(2, 6);
    final int unitario = rng.range(2, 12) * 500;
    final int total = unitario * n;
    final List<int> opciones = _opcionesCerca(rng, unitario, 500);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '$n ${_pluralNombre(item)} cuestan ${pesosEnPalabras(total)}. ¿Cuánto cuesta cada ${item.genero == 'f' ? 'una' : 'uno'}?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(spacing: 4, alignment: WrapAlignment.center, children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: 40)]),
        caption: '$n por ${formatPesos(total)}',
      ),
      options: options,
      correctId: 'n$unitario',
      hint: 'Reparte ${formatPesos(total)} entre $n partes iguales.',
      explain: '${formatPesos(total)} dividido entre $n son ${formatPesos(unitario)} cada ${item.genero == 'f' ? 'una' : 'uno'}.',
    );
  }

  ChoiceRound _descuento(Rng rng) {
    final VocabItem item = rng.pick(_productos);
    final int precio = rng.range(4, 40) * 1000;
    final int pct = rng.pick(<int>[10, 25, 50]);
    final int final_ = precio - precio * pct ~/ 100;
    final List<int> opciones = _opcionesCerca(rng, final_, 500);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${_cap(item.conArticulo)} cuesta ${pesosEnPalabras(precio)} y tiene $pct por ciento de descuento. ¿Cuánto pagas?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(item.emoji, size: 64), caption: '${formatPesos(precio)}  −$pct %'),
      options: options,
      correctId: 'n$final_',
      hint: pct == 50 ? 'Cincuenta por ciento es la mitad.' : (pct == 25 ? 'Veinticinco por ciento es la cuarta parte.' : 'Diez por ciento es dividir entre diez.'),
      explain: 'El descuento es ${formatPesos(precio * pct ~/ 100)}; pagas ${formatPesos(final_)}.',
    );
  }

  // ------------------------------------------------------------ ayudas

  Widget _dosPrecios(VocabItem a, int pa, VocabItem b, int pb, {String? extra}) {
    return BigPrompt(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _etiqueta(a, pa),
          const SizedBox(width: 12),
          const Text('+', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
          const SizedBox(width: 12),
          _etiqueta(b, pb),
        ],
      ),
      caption: extra,
    );
  }

  Widget _etiqueta(VocabItem v, int precio) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EmojiImage(v.emoji, size: 56),
        Text(formatPesos(precio), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
      ],
    );
  }

  List<int> _opcionesCerca(Rng rng, int correcto, int paso) {
    final Set<int> s = <int>{correcto};
    int guard = 0;
    while (s.length < 3 && guard < 50) {
      guard += 1;
      final int d = correcto + rng.range(-4, 4) * paso;
      if (d > 0 && d != correcto) {
        s.add(d);
      }
    }
    while (s.length < 3) {
      s.add(correcto + paso * s.length);
    }
    return s.toList();
  }

  static String _pluralNombre(VocabItem v) {
    final String n = v.nombre;
    if (v.has('plural')) {
      return n;
    }
    if (n.endsWith('z')) {
      return '${n.substring(0, n.length - 1)}ces';
    }
    if (n.endsWith('ón')) {
      return '${n.substring(0, n.length - 2)}ones';
    }
    if (n.endsWith('a') || n.endsWith('e') || n.endsWith('o') || n.endsWith('i') || n.endsWith('u')) {
      return '${n}s';
    }
    return '${n}es';
  }

  static String _cuantos(VocabItem v) => v.genero == 'f' ? 'Cuántas' : 'Cuántos';

  static String _cap(String s) => s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);
}
