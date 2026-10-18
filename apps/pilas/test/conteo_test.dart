import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/cuentos.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/theme.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/cocina/cocina_generator.dart';
import 'package:pilas/games/shell/widgets.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';

/// Pictogramas permitidos para contar: cada uno muestra exactamente un objeto
/// entero. Se revisaron rasterizando el SVG de Twemoji (como hizo la
/// auditoría con cairosvg). Si se agrega uno, hay que mirarlo antes.
const Set<String> permitidos = <String>{
  // Frutas: manzana, banano, naranja, fresa, piña, mango, pera, limón, durazno.
  '1f34e', '1f34c', '1f34a', '1f353', '1f34d', '1f96d', '1f350', '1f34b', '1f351',
  // Verduras: zanahoria, maíz, tomate, papa, cebolla, brócoli, ají, berenjena, pepino.
  '1f955', '1f33d', '1f345', '1f954', '1f9c5', '1f966', '1f336', '1f346', '1f952',
  // Comidas: pan, huevo, helado, galleta, torta, chocolate, arepa.
  '1f35e', '1f95a', '1f366', '1f36a', '1f382', '1f36b', '1fad3',
  // Escuela y juguetes: lápiz, regla, crayón, libro, pincel, maleta, balón,
  // cometa, globo, dado, yoyó, patineta.
  '270f', '1f4cf', '1f58d', '1f4d6', '1f58c', '1f392', '26bd', '1fa81', '1f388', '1f3b2', '1fa80', '1f6f9',
};

/// Pictogramas que NO sirven para contar, y por qué.
const Map<String, String> noContables = <String, String>{
  '1f352': 'trae dos cerezas',
  '1f347': 'es un racimo de uvas',
  '1f4da': 'es una pila de libros',
  '1f349': 'es una tajada de sandía',
  '1f355': 'es una tajada de pizza',
  '1f965': 'es un coco partido',
  '1f95d': 'es un kiwi partido',
  '1f951': 'es un aguacate partido',
  '1f357': 'es una presa de pollo',
  '1f9c0': 'es un pedazo de queso',
  '1f96c': 'son hojas sueltas',
  '1f348': 'el melón se confunde con un repollo',
  '1f9e9': 'es una sola ficha del rompecabezas',
  '1f375': 'es un tazón de té, no una taza de harina',
};

/// Códigos de los pictogramas que dibuja [builder].
Future<List<String>> dibujados(WidgetTester tester, Widget Function(BuildContext context) builder) async {
  await tester.pumpWidget(MaterialApp(
    theme: PilasTheme.light(highContrast: false),
    home: Scaffold(body: Center(child: SingleChildScrollView(child: Builder(builder: builder)))),
  ));
  return tester.widgetList<EmojiImage>(find.byType(EmojiImage)).map((EmojiImage e) => e.code).toList();
}

int _numeroDe(String id) => int.parse(id.replaceAll(RegExp(r'[^0-9]'), ''));

void main() {
  test('La lista de pictogramas para contar es la misma del código y no trae ninguno múltiple', () {
    expect(<String>{for (final VocabItem v in Vocab.contables) v.emoji}, permitidos);
    for (final String code in noContables.keys) {
      expect(permitidos.contains(code), isFalse, reason: '$code ${noContables[code]}');
    }
    for (final VocabItem v in TiendaGenerator.frutasContables) {
      expect(permitidos, contains(v.emoji), reason: v.nombre);
    }
    for (final VocabItem v in TiendaGenerator.contables) {
      expect(permitidos, contains(v.emoji), reason: v.nombre);
    }
    expect(permitidos, contains(CocinaGenerator.huevo));
    // Las cerezas van en plural, como su dibujo.
    final VocabItem cereza = Vocab.all.firstWhere((VocabItem v) => v.id == 'cereza');
    expect(cereza.plural, isTrue);
    expect(cereza.conArticulo, 'las cerezas');
  });

  testWidgets('«¿Cuántas hay?»: se dibujan exactamente las que dice la respuesta', (WidgetTester tester) async {
    final TiendaGenerator g = TiendaGenerator();
    for (int seed = 0; seed < 60; seed++) {
      final ChoiceRound r = g.contar(Rng(seed), 1, 10);
      final List<String> codes = await dibujados(tester, r.prompt!);
      expect(codes.length, _numeroDe(r.correctId), reason: r.instruction);
      expect(permitidos.containsAll(codes), isTrue, reason: '${r.instruction} $codes');
    }
  });

  testWidgets('«¿Dónde hay más?»: cada canasta trae las que dice su nombre', (WidgetTester tester) async {
    final TiendaGenerator g = TiendaGenerator();
    for (int seed = 0; seed < 40; seed++) {
      final ChoiceRound r = g.masMenos(Rng(seed));
      for (final ChoiceOption o in r.options) {
        final List<String> codes = await dibujados(tester, (BuildContext context) => o.build(context, 120));
        expect(codes.length, _numeroDe(o.id), reason: o.label);
        expect(permitidos.containsAll(codes), isTrue, reason: '${o.label} $codes');
      }
    }
  });

  testWidgets('Multiplicar y precio por unidad: un pictograma entero por cada unidad', (WidgetTester tester) async {
    final TiendaGenerator g = TiendaGenerator();
    for (int seed = 0; seed < 60; seed++) {
      final ChoiceRound m = g.multiplicar(Rng(seed), max: 12);
      final List<String> cm = await dibujados(tester, m.prompt!);
      final int n = <int>[for (int k = 2; k <= 12; k++) k].firstWhere(
        (int k) => m.instruction.endsWith('cuestan ${Es.numero(k, femenino: true)}?') || m.instruction.endsWith('cuestan ${Es.numero(k)}?'),
      );
      expect(cm.length, n, reason: m.instruction);
      expect(permitidos.containsAll(cm), isTrue, reason: '${m.instruction} $cm');

      final ChoiceRound p = g.precioUnitario(Rng(seed));
      final List<String> cp = await dibujados(tester, p.prompt!);
      expect(permitidos.containsAll(cp), isTrue, reason: '${p.instruction} $cp');
      expect(p.instruction, startsWith('${Es.cap(Es.numero(cp.length))} '), reason: p.instruction);
    }
  });

  testWidgets('Cocina: los huevos que van al tazón son los de la respuesta', (WidgetTester tester) async {
    final CocinaGenerator g = CocinaGenerator();
    for (int seed = 0; seed < 30; seed++) {
      final ChoiceRound r = g.cuantosHuevos(Rng(seed));
      final List<String> codes = await dibujados(tester, r.prompt!);
      expect(codes.where((String c) => c == CocinaGenerator.huevo).length, _numeroDe(r.correctId));
      expect(codes.where((String c) => c != CocinaGenerator.huevo).toList(), <String>['1f963']);
    }
  });

  test('Cuentos: si el texto dice cuántos hay, la escena muestra esos mismos', () {
    const Map<String, int> numeros = <String, int>{'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5};
    int revisadas = 0;
    for (final Cuento c in CuentoBank.all) {
      for (final Pagina p in c.paginas) {
        for (final Match m in RegExp(r'\b(dos|tres|cuatro|cinco) ([a-záéíóúñ]+)').allMatches(p.texto.toLowerCase())) {
          final Iterable<VocabItem> v = Vocab.all.where((VocabItem v) => v.nombrePlural == m.group(2));
          if (v.isEmpty || !p.escena.contains(v.first.emoji)) {
            continue;
          }
          revisadas += 1;
          expect(p.escena.where((String e) => e == v.first.emoji).length, numeros[m.group(1)], reason: '${c.id}: ${p.texto}');
        }
      }
    }
    expect(revisadas, greaterThan(0));
    // La gallina Pepa: tres pollitos en la escena y opciones con el número.
    final Cuento gallina = CuentoBank.all.firstWhere((Cuento c) => c.id == 'gallina_lluvia');
    expect(gallina.paginas.first.escena.where((String e) => e == '1f425').length, 3);
    expect(gallina.paginas.last.escena.where((String e) => e == '1f425').length, 3);
    // Pepa tapa a los pollitos con sus alas: la escena no muestra un paraguas.
    expect(gallina.paginas[2].escena, isNot(contains('2614')));
    expect(gallina.preguntas.first.opciones.map((OpcionCuento o) => o.emoji), <String>['33-20e3', '32-20e3', '35-20e3']);
  });
}
