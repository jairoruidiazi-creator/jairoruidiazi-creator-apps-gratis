import 'package:flutter/material.dart';

import '../core/es.dart';
import '../core/theme.dart';

/// Monedas y billetes de Colombia, estilizados (color y número, no el diseño real).
class Denominacion {
  const Denominacion(this.valor, this.esBillete, this.color, this.texto);

  final int valor;
  final bool esBillete;
  final Color color;
  final Color texto;

  String get nombre => esBillete ? 'billete de ${pesosEnPalabras(valor)}' : 'moneda de ${pesosEnPalabras(valor)}';

  static const List<Denominacion> todas = <Denominacion>[
    Denominacion(100, false, Color(0xFFB0BEC5), Color(0xFF263238)),
    Denominacion(200, false, Color(0xFFCFD8DC), Color(0xFF263238)),
    Denominacion(500, false, Color(0xFFD4AF37), Color(0xFF3E2723)),
    Denominacion(1000, false, Color(0xFFC9A227), Color(0xFF3E2723)),
    Denominacion(2000, true, Color(0xFF5C6BC0), Color(0xFF1F2954)),
    Denominacion(5000, true, Color(0xFF8D6E63), Color(0xFF1F2954)),
    Denominacion(10000, true, Color(0xFFE53935), Color(0xFF1F2954)),
    Denominacion(20000, true, Color(0xFFFB8C00), Color(0xFF1F2954)),
    Denominacion(50000, true, Color(0xFF8E24AA), Color(0xFF1F2954)),
  ];

  static Denominacion of(int valor) => todas.firstWhere((Denominacion d) => d.valor == valor);
}

/// Formato colombiano: punto de miles y sin centavos. 12000 → "$ 12.000".
String formatPesos(int valor, {bool simbolo = true}) {
  final String s = valor.abs().toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final int fromEnd = s.length - i;
    b.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      b.write('.');
    }
  }
  final String num = (valor < 0 ? '-' : '') + b.toString();
  return simbolo ? '\$ $num' : num;
}

/// Cómo se dice un precio en voz alta: "tres mil quinientos pesos",
/// "veintiún mil pesos", "un peso", "un millón de pesos".
String pesosEnPalabras(int valor) {
  if (valor == 1) {
    return 'un peso';
  }
  final String n = Es.numero(valor, apocope: true);
  if (valor >= 1000000 && valor % 1000000 == 0) {
    return '$n de pesos';
  }
  return '$n pesos';
}

/// Dibujo de una moneda o billete. El valor va siempre en tinta oscura sobre
/// un fondo claro (contraste de texto suficiente en cualquier color de billete).
class MoneyWidget extends StatelessWidget {
  const MoneyWidget({super.key, required this.denominacion, this.width = 96});

  final Denominacion denominacion;
  final double width;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final Denominacion d = denominacion;
    final String label = formatPesos(d.valor, simbolo: false);
    if (d.esBillete) {
      return Container(
        width: width,
        height: width * 0.5,
        decoration: BoxDecoration(
          color: d.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pal.altoContraste ? pal.tinta : Colors.black.withValues(alpha: 0.25), width: 2),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 6,
              top: 4,
              child: Container(width: width * 0.22, height: width * 0.22, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), shape: BoxShape.circle)),
            ),
            Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: width * 0.06, vertical: width * 0.01),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: TextStyle(color: d.texto, fontSize: width * 0.16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
    }
    final double size = width * 0.62;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: d.color,
        shape: BoxShape.circle,
        border: Border.all(color: pal.altoContraste ? pal.tinta : Colors.black.withValues(alpha: 0.3), width: 3),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 2))],
      ),
      child: Center(child: Text(label, style: TextStyle(color: d.texto, fontSize: size * 0.26, fontWeight: FontWeight.w800))),
    );
  }
}
