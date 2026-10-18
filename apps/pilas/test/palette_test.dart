import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/theme.dart';
import 'package:pilas/model/area.dart';

double contraste(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Contraste de las dos paletas (WCAG 2.2): texto 4,5:1 y objetos gráficos
/// que informan 3:1 en la normal; 7:1 y 4,5:1 en la de alto contraste.
void main() {
  void revisar(PilasPalette p, {required double texto, required double objeto}) {
    final String n = p.altoContraste ? 'alto contraste' : 'normal';
    final Map<String, Color> fondos = <String, Color>{
      'fondo': p.fondo,
      'fondoSuave': p.fondoSuave,
      'tarjeta': p.tarjeta,
      'acentoClaro': p.acentoClaro,
      'correctoClaro': p.correctoClaro,
      'errorClaro': p.errorClaro,
      'pistaClaro': p.pistaClaro,
    };
    fondos.forEach((String nombre, Color bg) {
      expect(contraste(p.tinta, bg), greaterThanOrEqualTo(texto), reason: '$n: tinta sobre $nombre');
      expect(contraste(p.tintaSuave, bg), greaterThanOrEqualTo(texto), reason: '$n: tinta suave sobre $nombre');
    });
    final List<List<Object>> pares = <List<Object>>[
      <Object>['sobreAcento/acento', p.sobreAcento, p.acento],
      <Object>['acento/tarjeta', p.acento, p.tarjeta],
      <Object>['acento/fondo', p.acento, p.fondo],
      <Object>['correcto/correctoClaro', p.correcto, p.correctoClaro],
      <Object>['correcto/tarjeta', p.correcto, p.tarjeta],
      <Object>['error/errorClaro', p.error, p.errorClaro],
      <Object>['error/tarjeta', p.error, p.tarjeta],
      <Object>['pista/pistaClaro', p.pista, p.pistaClaro],
      <Object>['pista/tarjeta', p.pista, p.tarjeta],
    ];
    for (final List<Object> par in pares) {
      expect(contraste(par[1] as Color, par[2] as Color), greaterThanOrEqualTo(texto), reason: '$n: ${par[0]}');
    }
    for (final Area a in Area.values) {
      expect(contraste(p.areaTexto(a), p.fondo), greaterThanOrEqualTo(texto), reason: '$n: título de ${a.nombre}');
      expect(contraste(p.areaTexto(a), p.tarjeta), greaterThanOrEqualTo(texto), reason: '$n: título de ${a.nombre}');
    }
    // Guía del trazo, siluetas de encajar, cuadrículas y bordes de casillas.
    final Map<String, Color> objetos = <String, Color>{'guía': p.guia, 'silueta': p.silueta, 'cuadrícula': p.cuadricula, 'borde fuerte': p.bordeFuerte};
    objetos.forEach((String nombre, Color c) {
      expect(contraste(c, p.tarjeta), greaterThanOrEqualTo(objeto), reason: '$n: $nombre sobre tarjeta');
      expect(contraste(c, p.fondo), greaterThanOrEqualTo(objeto), reason: '$n: $nombre sobre fondo');
    });
  }

  test('Paleta normal', () => revisar(PilasPalette.normal, texto: 4.5, objeto: 3));
  test('Paleta de alto contraste', () => revisar(PilasPalette.alto, texto: 7, objeto: 4.5));

  testWidgets('El alto contraste llega al tema de toda la app', (WidgetTester tester) async {
    late PilasPalette vista;
    await tester.pumpWidget(MaterialApp(
      theme: PilasTheme.light(highContrast: true),
      home: Builder(builder: (BuildContext context) {
        vista = PilasPalette.of(context);
        return const SizedBox.shrink();
      }),
    ));
    expect(vista.altoContraste, isTrue);
    expect(PilasTheme.light(highContrast: true).scaffoldBackgroundColor, PilasPalette.alto.fondo);
  });
}
