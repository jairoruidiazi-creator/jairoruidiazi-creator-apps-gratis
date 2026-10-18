import 'package:flutter/material.dart';

import '../../content/money.dart';
import '../../content/vocab.dart';
import '../../core/es.dart';
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
/// siempre con pesos colombianos. Artículos, verbos y plurales concuerdan con
/// cada producto: "las tijeras cuestan", "una manzana", "tres manzanas".
class TiendaGenerator {
  /// Productos de la tienda (palabras sueltas).
  static List<VocabItem> get productos => Vocab.all.where((VocabItem v) => (v.has('comida') || v.has('juguete') || v.has('escuela')) && !v.nombre.contains(' ')).toList();

  /// Productos que se cuentan uno por uno ("cada manzana", "tres balones"):
  /// solo los que tienen un pictograma de un solo objeto entero
  /// ([Vocab.unObjeto]), porque las rondas dibujan uno por cada unidad.
  static List<VocabItem> get contables => productos.where((VocabItem v) => Vocab.unObjeto.contains(v.id)).toList();

  /// Precio razonable de cada producto en pesos colombianos (mínimo y máximo,
  /// por unidad o por la porción del dibujo), para que la tienda no venda una
  /// fresa por catorce mil pesos ni un libro por doscientos. Los precios de
  /// los primeros niveles son de monedas de 100: ahí salen las cosas baratas.
  static const Map<String, List<int>> rangoPrecio = <String, List<int>>{
    // Frutas y verduras.
    'banano': <int>[200, 1000], 'fresa': <int>[200, 1000], 'cereza': <int>[500, 3000], 'limon': <int>[200, 1000],
    'manzana': <int>[800, 3000], 'naranja': <int>[500, 2000], 'pera': <int>[800, 3000], 'durazno': <int>[800, 3000],
    'kiwi': <int>[800, 3000], 'mango': <int>[1000, 4000], 'uvas': <int>[3000, 9000], 'coco': <int>[2500, 7000],
    'pina': <int>[3000, 9000], 'melon': <int>[3000, 9000], 'sandia': <int>[6000, 18000],
    'zanahoria': <int>[300, 1500], 'cebolla': <int>[500, 2500], 'tomate': <int>[300, 1500], 'papa': <int>[300, 1500],
    'pepino': <int>[500, 2500], 'brocoli': <int>[2000, 6000], 'lechuga': <int>[1500, 5000], 'berenjena': <int>[1500, 5000],
    'aji': <int>[100, 800], 'aguacate': <int>[1500, 6000], 'maiz': <int>[1000, 4000],
    // Otras comidas.
    'huevo': <int>[300, 1000], 'pan': <int>[300, 3000], 'arepa': <int>[1000, 4000], 'galleta': <int>[200, 2000],
    'chocolate': <int>[1000, 6000], 'helado': <int>[1500, 9000], 'leche': <int>[3000, 8000], 'jugo': <int>[1500, 6000],
    'queso': <int>[4000, 15000], 'arroz': <int>[3000, 9000], 'sopa': <int>[4000, 15000], 'miel': <int>[8000, 25000],
    'pollo': <int>[10000, 35000], 'pizza': <int>[12000, 45000], 'torta': <int>[15000, 60000],
    // Escuela.
    'lapiz': <int>[500, 3000], 'crayon': <int>[300, 2000], 'regla': <int>[1000, 5000], 'pincel': <int>[1000, 6000],
    'tijeras': <int>[2000, 9000], 'libro': <int>[8000, 60000], 'libros': <int>[15000, 90000], 'maleta': <int>[30000, 150000],
    // Juguetes.
    'globo': <int>[100, 2000], 'dado': <int>[300, 3000], 'yoyo': <int>[2000, 9000], 'cometa': <int>[5000, 25000],
    'rompecabezas': <int>[8000, 50000], 'balon': <int>[10000, 70000], 'patineta': <int>[40000, 150000],
  };

  /// Un producto que de verdad podría costar [precio] (de [entre], o de todos
  /// los productos), sin repetir los de [sin]. Si ninguno cuesta justo eso, el
  /// de precio más cercano.
  static VocabItem productoPara(Rng rng, int precio, {List<VocabItem>? entre, Set<String> sin = const <String>{}}) {
    final List<VocabItem> lista = (entre ?? productos).where((VocabItem v) => !sin.contains(v.id) && rangoPrecio.containsKey(v.id)).toList();
    final List<VocabItem> caben = lista.where((VocabItem v) => precio >= rangoPrecio[v.id]![0] && precio <= rangoPrecio[v.id]![1]).toList();
    if (caben.isNotEmpty) {
      return rng.pick(caben);
    }
    VocabItem mejor = lista.first;
    double distancia = double.infinity;
    for (final VocabItem v in lista) {
      final List<int> r = rangoPrecio[v.id]!;
      final double d = precio < r[0] ? r[0] / precio : (precio > r[1] ? precio / r[1] : 1.0);
      if (d < distancia) {
        distancia = d;
        mejor = v;
      }
    }
    return mejor;
  }

  /// Frutas que se cuentan una por una en el dibujo: cada pictograma es una
  /// fruta entera (no las uvas ni las cerezas, ni una tajada de sandía).
  static List<VocabItem> get frutasContables => Vocab.contables.where((VocabItem v) => v.has('fruta')).toList();

  TiendaRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        if (level == 1) {
          return TiendaRound.choice(contar(rng, 1, 5));
        }
        if (level == 2) {
          return TiendaRound.choice(contar(rng, 3, 10));
        }
        if (level == 3) {
          return TiendaRound.pago(pagoMonedasIguales(rng));
        }
        return TiendaRound.choice(masMenos(rng));
      case AgeBand.b5a6:
        if (level == 1) {
          return TiendaRound.pago(pago(rng, <int>[100, 200, 500], 100, 900, 1));
        }
        if (level == 2) {
          return TiendaRound.pago(pago(rng, <int>[100, 200, 500, 1000], 100, 2000, 1));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(totalDeDos(rng, 100, 900, 100)) : TiendaRound.pago(pago(rng, <int>[100, 200, 500, 1000], 100, 2000, 2));
        }
        return rng.chance(0.5) ? TiendaRound.choice(sumaResta20(rng)) : TiendaRound.choice(totalDeDos(rng, 100, 1000, 100));
      case AgeBand.b7a8:
        if (level == 1) {
          return TiendaRound.pago(pago(rng, <int>[500, 1000, 2000, 5000], 500, 9500, 1));
        }
        if (level == 2) {
          return TiendaRound.choice(vueltas(rng, 1000, 9000, 500, <int>[5000, 10000]));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(totalDeDos(rng, 500, 12000, 500)) : TiendaRound.choice(vueltas(rng, 2000, 18000, 500, <int>[10000, 20000]));
        }
        return rng.chance(0.5) ? TiendaRound.choice(multiplicar(rng)) : TiendaRound.pago(pago(rng, <int>[500, 1000, 2000, 5000, 10000], 1000, 24000, 2));
      case AgeBand.b9a11:
        if (level == 1) {
          return rng.chance(0.5) ? TiendaRound.choice(multiplicar(rng, max: 12)) : TiendaRound.choice(vueltas(rng, 5000, 45000, 100, <int>[20000, 50000]));
        }
        if (level == 2) {
          return TiendaRound.choice(presupuesto(rng));
        }
        if (level == 3) {
          return rng.chance(0.5) ? TiendaRound.choice(precioUnitario(rng)) : TiendaRound.choice(presupuesto(rng));
        }
        return rng.chance(0.5) ? TiendaRound.choice(descuento(rng)) : TiendaRound.choice(precioUnitario(rng));
    }
  }

  static String _cuantos(VocabItem v) => v.genero == 'f' ? 'Cuántas' : 'Cuántos';

  // ------------------------------------------------------------ contar y comparar

  ChoiceRound contar(Rng rng, int min, int max) {
    final VocabItem item = rng.pick(frutasContables);
    final int n = rng.range(min, max);
    final Set<int> opciones = <int>{n};
    while (opciones.length < 3) {
      opciones.add(rng.range(min, max));
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.number(o)];
    rng.shuffle(options);
    final String hay = 'Hay ${Es.cantidadEnPalabras(n, item.nombre, genero: item.genero)}.';
    return ChoiceRound(
      instruction: '¿${_cuantos(item)} ${item.nombrePlural} hay?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: n > 6 ? 40 : 52, semanticsLabel: i == 0 ? Es.cantidadEnPalabras(n, item.nombre, genero: item.genero) : null)],
        ),
      ),
      options: options,
      correctId: 'n$n',
      hint: 'Toca cada una con el dedo y cuenta despacio: uno, dos, tres...',
      explain: hay,
      praise: hay,
      readOptionsAloud: true,
    );
  }

  /// Tres canastas con distinta cantidad: ¿dónde hay más (o menos)?
  ChoiceRound masMenos(Rng rng) {
    final VocabItem item = rng.pick(frutasContables);
    final List<int> cantidades = rng.sample(<int>[1, 2, 3, 4, 5, 6, 7], 3);
    final bool pedirMas = rng.chance(0.5);
    final List<int> orden = List<int>.from(cantidades)..sort();
    final int objetivo = pedirMas ? orden.last : orden.first;
    Widget canasta(int n, double size) => SizedBox(
          width: size * 1.3,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: size * 0.36)],
          ),
        );
    final List<ChoiceOption> options = <ChoiceOption>[
      for (final int c in cantidades)
        ChoiceOption(id: 'c$c', label: Es.cantidadEnPalabras(c, item.nombre, genero: item.genero), build: (BuildContext context, double size) => canasta(c, size)),
    ];
    rng.shuffle(options);
    final String cuantas = Es.cantidadEnPalabras(objetivo, item.nombre, genero: item.genero);
    return ChoiceRound(
      instruction: pedirMas ? '¿Dónde hay más ${item.nombrePlural}?' : '¿Dónde hay menos ${item.nombrePlural}?',
      options: options,
      correctId: 'c$objetivo',
      hint: 'Cuenta ${Es.articulo(item.genero, plural: true)} ${item.nombrePlural} de cada lado.',
      explain: pedirMas ? 'Aquí hay $cuantas: es donde hay más.' : 'Aquí hay $cuantas: es donde hay menos.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound sumaResta20(Rng rng) {
    final VocabItem item = rng.pick(frutasContables);
    final bool suma = rng.chance(0.6);
    final int a = rng.range(2, 12);
    final int b = rng.range(1, suma ? 8 : a - 1);
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
    final bool f = item.genero == 'f';
    final String tenias = Es.cantidadEnPalabras(a, item.nombre, genero: item.genero);
    final String texto = suma
        ? 'Tenías $tenias y compraste ${Es.numero(b, femenino: f)} más. ¿${_cuantos(item)} tienes ahora?'
        : 'Tenías $tenias y regalaste ${Es.numero(b, femenino: f)}. ¿${_cuantos(item)} te quedan?';
    return ChoiceRound(
      instruction: texto,
      prompt: (BuildContext context) => BigPrompt(
        child: Text(suma ? '$a + $b = ?' : '$a − $b = ?', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
      ),
      options: options,
      correctId: 'n$r',
      hint: suma ? 'Empieza en $a y cuenta $b más con los dedos.' : 'Empieza en $a y quita $b con los dedos.',
      explain: suma ? '$a más $b es $r.' : '$a menos $b es $r.',
      readOptionsAloud: true,
    );
  }

  // ------------------------------------------------------------ pagar

  PagoRound pagoMonedasIguales(Rng rng) {
    final int n = rng.range(1, 5);
    final VocabItem item = productoPara(rng, 100 * n);
    return PagoRound(
      productos: <Producto>[Producto(item, 100 * n)],
      denominaciones: <Denominacion>[Denominacion.of(100)],
      instruction: '${Es.cap(item.conArticulo)} ${item.verbo('vale', 'valen')} ${Es.cantidadEnPalabras(n, 'moneda', genero: 'f')}. Pon las monedas y paga.',
    );
  }

  PagoRound pago(Rng rng, List<int> denoms, int min, int max, int cuantos) {
    final int paso = denoms.first;
    final List<Producto> lista = <Producto>[];
    for (int i = 0; i < cuantos; i++) {
      final int sorteado = rng.range(min ~/ paso, max ~/ paso) * paso;
      final int precio = sorteado < paso ? paso : sorteado;
      final VocabItem it = productoPara(rng, precio, sin: <String>{for (final Producto p in lista) p.item.id});
      lista.add(Producto(it, precio));
    }
    final int total = lista.fold<int>(0, (int s, Producto p) => s + p.total);
    final String frase = Es.listaY(lista.map((Producto p) => '${p.item.conArticulo} ${p.item.verbo('cuesta', 'cuestan')} ${pesosEnPalabras(p.precio)}').toList());
    return PagoRound(
      productos: lista,
      denominaciones: denoms.map(Denominacion.of).toList(),
      instruction: cuantos == 1 ? '${Es.cap(frase)}. Paga el precio exacto.' : '${Es.cap(frase)}. En total son ${pesosEnPalabras(total)}. Paga el precio exacto.',
    );
  }

  // ------------------------------------------------------------ cálculos con precios

  List<ChoiceOption> _opcionesPesos(Rng rng, int correcto, int paso) {
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in _opcionesCerca(rng, correcto, paso)) Opt.text('n$o', formatPesos(o), fontSize: 30, label: pesosEnPalabras(o))];
    rng.shuffle(options);
    return options;
  }

  ChoiceRound totalDeDos(Rng rng, int min, int max, int paso) {
    final int a = rng.range(min ~/ paso, max ~/ paso) * paso;
    final int b = rng.range(min ~/ paso, max ~/ paso) * paso;
    final VocabItem primero = productoPara(rng, a);
    final List<VocabItem> items = <VocabItem>[primero, productoPara(rng, b, sin: <String>{primero.id})];
    final int total = a + b;
    return ChoiceRound(
      instruction: 'Compras ${Es.listaY(<String>[items[0].conArticulo, items[1].conArticulo])}. ¿Cuánto pagas en total?',
      prompt: (BuildContext context) => _dosPrecios(context, items[0], a, items[1], b),
      options: _opcionesPesos(rng, total, paso),
      correctId: 'n$total',
      hint: 'Suma los dos precios.',
      explain: '${formatPesos(a)} más ${formatPesos(b)} son ${formatPesos(total)}.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound vueltas(Rng rng, int min, int max, int paso, List<int> billetes) {
    final int precio = rng.range(min ~/ paso, max ~/ paso) * paso;
    final VocabItem item = productoPara(rng, precio);
    final int billete = billetes.where((int b) => b > precio).isEmpty ? billetes.last : billetes.firstWhere((int b) => b > precio);
    final int vuelta = billete - precio;
    return ChoiceRound(
      instruction: '${Es.cap(item.conArticulo)} ${item.verbo('cuesta', 'cuestan')} ${pesosEnPalabras(precio)} y pagas con un billete de ${pesosEnPalabras(billete)}. ¿Cuánto te devuelven?',
      prompt: (BuildContext context) => BigPrompt(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmojiImage(item.emoji, size: 64, semanticsLabel: item.nombre),
            const SizedBox(width: 10),
            Text(formatPesos(precio), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
            const SizedBox(width: 18),
            MoneyWidget(denominacion: Denominacion.of(billete), width: 110),
          ],
        ),
      ),
      options: _opcionesPesos(rng, vuelta, paso),
      correctId: 'n$vuelta',
      hint: 'Cuenta desde ${formatPesos(precio)} hasta llegar a ${formatPesos(billete)}.',
      explain: '${formatPesos(billete)} menos ${formatPesos(precio)} son ${formatPesos(vuelta)}.',
    );
  }

  ChoiceRound multiplicar(Rng rng, {int max = 9}) {
    final int precio = rng.pick(<int>[500, 1000, 1500, 2000, 2500, 3000]);
    final VocabItem item = productoPara(rng, precio, entre: contables);
    final int n = rng.range(2, max);
    final int total = precio * n;
    return ChoiceRound(
      instruction: 'Cada ${item.nombre} cuesta ${pesosEnPalabras(precio)}. ¿Cuánto cuestan ${Es.numero(n, femenino: item.genero == 'f')}?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: 40)],
        ),
        caption: '$n × ${formatPesos(precio)}',
      ),
      options: _opcionesPesos(rng, total, 500),
      correctId: 'n$total',
      hint: 'Multiplica $n por ${formatPesos(precio)}. También puedes sumar ${formatPesos(precio)} $n veces.',
      explain: '$n por ${formatPesos(precio)} son ${formatPesos(total)}.',
    );
  }

  ChoiceRound presupuesto(Rng rng) {
    final int a = rng.range(2, 18) * 500;
    final int b = rng.range(2, 18) * 500;
    final VocabItem primero = productoPara(rng, a);
    final List<VocabItem> items = <VocabItem>[primero, productoPara(rng, b, sin: <String>{primero.id})];
    final int tope = rng.pick(<int>[10000, 20000, 30000]);
    final int gasto = a + b;
    final bool alcanza = gasto <= tope;
    final int correcto = alcanza ? tope - gasto : gasto - tope;
    final String cosas = Es.listaY(<String>[items[0].conArticulo, items[1].conArticulo]);
    if (correcto == 0) {
      // Justo alcanza: se pregunta cuánto sobra (nada no es una buena opción).
      return totalDeDos(rng, 500, 9000, 500);
    }
    return ChoiceRound(
      instruction: alcanza ? 'Tienes ${pesosEnPalabras(tope)}. Compras $cosas. ¿Cuánto te sobra?' : 'Tienes ${pesosEnPalabras(tope)}. Quieres $cosas. ¿Cuánto te falta?',
      prompt: (BuildContext context) => _dosPrecios(context, items[0], a, items[1], b, extra: 'Tienes ${formatPesos(tope)}'),
      options: _opcionesPesos(rng, correcto, 500),
      correctId: 'n$correcto',
      hint: 'Primero suma los dos precios. Luego compara con lo que tienes.',
      explain: alcanza ? '${formatPesos(tope)} menos ${formatPesos(gasto)} son ${formatPesos(correcto)}: te sobra eso.' : '${formatPesos(gasto)} menos ${formatPesos(tope)} son ${formatPesos(correcto)}: te falta eso.',
    );
  }

  ChoiceRound precioUnitario(Rng rng) {
    final int n = rng.range(2, 6);
    final int unitario = rng.range(2, 12) * 500;
    final VocabItem item = productoPara(rng, unitario, entre: contables);
    final int total = unitario * n;
    final String cadaUno = item.genero == 'f' ? 'cada una' : 'cada uno';
    return ChoiceRound(
      instruction: '${Es.cap(Es.cantidadEnPalabras(n, item.nombre, genero: item.genero))} cuestan ${pesosEnPalabras(total)}. ¿Cuánto cuesta $cadaUno?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(spacing: 4, alignment: WrapAlignment.center, children: <Widget>[for (int i = 0; i < n; i++) EmojiImage(item.emoji, size: 40)]),
        caption: '$n por ${formatPesos(total)}',
      ),
      options: _opcionesPesos(rng, unitario, 500),
      correctId: 'n$unitario',
      hint: 'Reparte ${formatPesos(total)} en $n partes iguales.',
      explain: '${formatPesos(total)} dividido entre $n son ${formatPesos(unitario)} $cadaUno.',
    );
  }

  ChoiceRound descuento(Rng rng) {
    final int precio = rng.range(4, 40) * 1000;
    final VocabItem item = productoPara(rng, precio);
    final int pct = rng.pick(<int>[10, 25, 50]);
    final int rebaja = precio * pct ~/ 100;
    final int pagas = precio - rebaja;
    return ChoiceRound(
      instruction: '${Es.cap(item.conArticulo)} ${item.verbo('cuesta', 'cuestan')} ${pesosEnPalabras(precio)} y ${item.verbo('tiene', 'tienen')} un descuento del ${Es.numero(pct)} por ciento. ¿Cuánto pagas?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(item.emoji, size: 64, semanticsLabel: item.nombre), caption: '${formatPesos(precio)}  −$pct\u00A0%'),
      options: _opcionesPesos(rng, pagas, 500),
      correctId: 'n$pagas',
      hint: pct == 50 ? 'El cincuenta por ciento es la mitad.' : (pct == 25 ? 'El veinticinco por ciento es la cuarta parte.' : 'El diez por ciento es dividir entre diez.'),
      explain: 'El descuento es de ${formatPesos(rebaja)}; pagas ${formatPesos(pagas)}.',
    );
  }

  // ------------------------------------------------------------ ayudas

  Widget _dosPrecios(BuildContext context, VocabItem a, int pa, VocabItem b, int pb, {String? extra}) {
    return BigPrompt(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _etiqueta(context, a, pa),
          const SizedBox(width: 12),
          Text('+', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
          const SizedBox(width: 12),
          _etiqueta(context, b, pb),
        ],
      ),
      caption: extra,
    );
  }

  Widget _etiqueta(BuildContext context, VocabItem v, int precio) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EmojiImage(v.emoji, size: 56, semanticsLabel: v.nombre),
        Text(formatPesos(precio), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
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
    int k = 1;
    while (s.length < 3) {
      s.add(correcto + paso * k);
      k += 1;
    }
    return s.toList();
  }
}
