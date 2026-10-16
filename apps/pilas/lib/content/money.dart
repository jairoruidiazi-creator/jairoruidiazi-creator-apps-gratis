import 'package:flutter/material.dart';

/// Monedas y billetes de Colombia, estilizados (color y número, no el diseño real).
class Denominacion {
  const Denominacion(this.valor, this.esBillete, this.color, this.texto);

  final int valor;
  final bool esBillete;
  final Color color;
  final Color texto;

  String get nombre => esBillete ? 'billete de ${formatPesos(valor)}' : 'moneda de ${formatPesos(valor)}';

  static const List<Denominacion> todas = <Denominacion>[
    Denominacion(100, false, Color(0xFFB0BEC5), Color(0xFF263238)),
    Denominacion(200, false, Color(0xFFCFD8DC), Color(0xFF263238)),
    Denominacion(500, false, Color(0xFFD4AF37), Color(0xFF3E2723)),
    Denominacion(1000, false, Color(0xFFC9A227), Color(0xFF3E2723)),
    Denominacion(2000, true, Color(0xFF5C6BC0), Colors.white),
    Denominacion(5000, true, Color(0xFF8D6E63), Colors.white),
    Denominacion(10000, true, Color(0xFFE53935), Colors.white),
    Denominacion(20000, true, Color(0xFFFB8C00), Colors.white),
    Denominacion(50000, true, Color(0xFF8E24AA), Colors.white),
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

/// Cómo se dice un precio en voz alta: "tres mil quinientos pesos".
String pesosEnPalabras(int valor) {
  if (valor == 0) {
    return 'cero pesos';
  }
  if (valor == 1) {
    return 'un peso';
  }
  return '${_numeroEnPalabras(valor)} pesos';
}

String _numeroEnPalabras(int n) {
  const List<String> unidades = <String>['', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte'];
  const List<String> decenas = <String>['', '', 'veinte', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
  const List<String> centenas = <String>['', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];
  if (n <= 20) {
    return unidades[n];
  }
  if (n < 30) {
    return 'veinti${unidades[n - 20]}';
  }
  if (n < 100) {
    final int d = n ~/ 10;
    final int u = n % 10;
    return u == 0 ? decenas[d] : '${decenas[d]} y ${unidades[u]}';
  }
  if (n == 100) {
    return 'cien';
  }
  if (n < 1000) {
    final int c = n ~/ 100;
    final int r = n % 100;
    return r == 0 ? centenas[c] : '${centenas[c]} ${_numeroEnPalabras(r)}';
  }
  if (n < 1000000) {
    final int m = n ~/ 1000;
    final int r = n % 1000;
    final String miles = m == 1 ? 'mil' : '${_apocope(_numeroEnPalabras(m))} mil';
    return r == 0 ? miles : '$miles ${_numeroEnPalabras(r)}';
  }
  final int mm = n ~/ 1000000;
  final int r = n % 1000000;
  final String millones = mm == 1 ? 'un millón' : '${_numeroEnPalabras(mm)} millones';
  return r == 0 ? millones : '$millones ${_numeroEnPalabras(r)}';
}

/// "veintiuno mil" se dice "veintiún mil"; "treinta y uno mil", "treinta y un mil".
String _apocope(String s) {
  if (s.endsWith('veintiuno')) {
    return '${s.substring(0, s.length - 9)}veintiún';
  }
  if (s.endsWith('uno')) {
    return '${s.substring(0, s.length - 3)}un';
  }
  return s;
}

/// Dibujo de una moneda o billete.
class MoneyWidget extends StatelessWidget {
  const MoneyWidget({super.key, required this.denominacion, this.width = 96});

  final Denominacion denominacion;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Denominacion d = denominacion;
    final String label = formatPesos(d.valor, simbolo: false);
    if (d.esBillete) {
      return Container(
        width: width,
        height: width * 0.5,
        decoration: BoxDecoration(
          color: d.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: 2),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 6,
              top: 4,
              child: Container(width: width * 0.22, height: width * 0.22, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), shape: BoxShape.circle)),
            ),
            Center(child: Text(label, style: TextStyle(color: d.texto, fontSize: width * 0.17, fontWeight: FontWeight.w800))),
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
        border: Border.all(color: Colors.black.withValues(alpha: 0.3), width: 3),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 2))],
      ),
      child: Center(child: Text(label, style: TextStyle(color: d.texto, fontSize: size * 0.26, fontWeight: FontWeight.w800))),
    );
  }
}
