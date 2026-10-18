import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/cuentos.dart';
import 'package:pilas/content/fonemas.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/cuentos/cuentos_screen.dart';
import 'package:pilas/games/shell/widgets.dart';
import 'package:pilas/games/sonidos/sonidos_generator.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

import 'support/harness.dart';

VocabItem _v(String id) => Vocab.all.firstWhere((VocabItem v) => v.id == id);

void main() {
  group('G7: sonidos como suenan en Colombia', () {
    test('El sonido inicial se compara por fonema, no por letra', () {
      final Map<String, String> casos = <String, String>{
        'cebra': 's', 'cereza': 's', 'zapato': 's', 'sol': 's', 'casa': 'k', 'queso': 'k', 'kiwi': 'k', 'koala': 'k',
        'vaca': 'b', 'burro': 'b', 'llave': 'y', 'yoyo': 'y', 'hormiga': 'o', 'helado': 'e', 'huevo': 'w', 'gato': 'g',
        'girasol': 'x', 'jirafa': 'x', 'chocolate': 'ch', 'uvas': 'u', 'iguana': 'i', 'ratón': 'r',
      };
      casos.forEach((String palabra, String fonema) {
        expect(Fonema.inicial(palabra), fonema, reason: palabra);
      });
    });

    test('Las rondas de sonido aceptan solo palabras con ese sonido y nunca marcan mal una correcta', () {
      final SonidosGenerator g = SonidosGenerator();
      final List<String> fonemas = <String>[...Fonema.vocales, ...Fonema.consonantesFaciles, ...Fonema.consonantesMas];
      for (final String f in fonemas) {
        for (int seed = 0; seed < 80; seed++) {
          final ChoiceRound r = g.sonido(Rng(seed), f, 3 + seed % 2, distractores: Distractores.cualquiera);
          expect(Fonema.inicial(_v(r.correctId).nombre), f, reason: r.instruction);
          for (final ChoiceOption o in r.options) {
            if (o.id != r.correctId) {
              final String otro = Fonema.inicial(_v(o.id).nombre);
              expect(otro == f, isFalse, reason: '${r.instruction}: ${_v(o.id).nombre} también empieza con ese sonido');
              expect(SonidosGenerator.seParecen(f, otro), isFalse, reason: '${r.instruction}: ${_v(o.id).nombre} suena parecido');
            }
          }
          // Si la correcta se escribe con otra letra, la explicación lo dice.
          if (!Fonema.mismaLetraInicial(_v(r.correctId).nombre, _v(SonidosGenerator.modelo[f]!).nombre)) {
            expect(r.explain, anyOf(contains('letras distintas'), contains('hache no suena')));
          }
        }
      }
    });

    test('Las rondas de letra usan letras que suenan siempre igual al principio', () {
      final SonidosGenerator g = SonidosGenerator();
      for (final String l in SonidosGenerator.letrasClaras) {
        for (int seed = 0; seed < 40; seed++) {
          final ChoiceRound r = g.letra(Rng(seed), l, 3);
          final VocabItem c = _v(r.correctId);
          expect(SonidosGenerator.primeraLetra(c), l);
          expect(Fonema.inicial(c.nombre), l);
          for (final ChoiceOption o in r.options) {
            if (o.id != r.correctId) {
              expect(SonidosGenerator.primeraLetra(_v(o.id)) == l, isFalse);
            }
          }
        }
      }
    });
  });

  group('G6: cuentos', () {
    late Harness h;
    setUp(() async {
      h = await Harness.create();
    });
    tearDown(() async {
      await h.dispose();
    });

    testWidgets('La pantalla baraja las opciones: la correcta cambia de lugar', (WidgetTester tester) async {
      late Profile p;
      await tester.runAsync(() async {
        p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b7a8);
      });
      h.state.current = p;
      final GameDef game = GameRegistry.byId('cuentos')!;
      final Set<int> lugares = <int>{};
      for (int seed = 0; seed < 12; seed++) {
        await tester.pumpWidget(h.app(CuentosScreen(key: ValueKey<int>(seed), launch: GameLaunch(game: game, band: AgeBand.b7a8, profile: p), rng: Rng(seed))));
        await tester.pump();
        // Pasa las páginas hasta las preguntas.
        for (int i = 0; i < 10 && find.byKey(const ValueKey<String>('cuento-preguntas')).evaluate().isEmpty; i++) {
          await tester.tap(find.byKey(const ValueKey<String>('cuento-siguiente')));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.tap(find.byKey(const ValueKey<String>('cuento-preguntas')));
        await tester.pump(const Duration(milliseconds: 300));
        final List<OptionTile> tiles = tester.widgetList<OptionTile>(find.byType(OptionTile)).toList();
        expect(tiles.length, 3);
        // La opción correcta es la de la primera pregunta del cuento abierto.
        final Cuento c = CuentoBank.forBand(AgeBand.b7a8).firstWhere((Cuento x) => find.textContaining(x.preguntas.first.texto).evaluate().isNotEmpty);
        final int correcta = c.preguntas.first.correcta;
        final int lugar = tiles.indexWhere((OptionTile t) => (t.key! as ValueKey<String>).value == 'opcion-$correcta');
        lugares.add(lugar);
      }
      expect(lugares.length, greaterThan(1), reason: 'la respuesta correcta quedó siempre en el mismo lugar');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  test('Cada pictograma que usa la app existe en assets/emoji', () {
    final Set<String> codigos = <String>{};
    final RegExp re = RegExp(r"'([0-9a-f]{2,5}(?:-[0-9a-f]{2,5})+|[0-9a-f]{4,5})'");
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        for (final RegExpMatch m in re.allMatches(f.readAsStringSync())) {
          final String c = m.group(1)!;
          // Solo códigos de pictogramas (no colores ni números sueltos).
          if (RegExp(r'^(1f|2|3|a9|ae)').hasMatch(c)) {
            codigos.add(c);
          }
        }
      }
    }
    expect(codigos.length, greaterThan(300));
    final List<String> faltan = codigos.where((String c) => !File('assets/emoji/$c.svg').existsSync()).toList()..sort();
    expect(faltan, isEmpty, reason: 'Faltan pictogramas: ${faltan.join(', ')}');
  });

  test('G11: datos corregidos de figuras, rutinas y luna', () {
    final String figuras = File('lib/games/figuras/figuras_generator.dart').readAsStringSync();
    // La señal de pare es un octágono.
    expect(RegExp(r"'1f6d1', '[^']*pare[^']*', '[mf]', ShapeKind\.octagon").hasMatch(figuras), isTrue);
    // La luna llena es la 1f315, no la creciente (1f319).
    expect(figuras.contains("'1f319', 'luna llena'"), isFalse);
  });
}
