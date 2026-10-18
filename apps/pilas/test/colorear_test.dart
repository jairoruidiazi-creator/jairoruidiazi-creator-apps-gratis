import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/coloring_pages.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/engine/mastery.dart';
import 'package:pilas/games/colorear/colorear_screen.dart';
import 'package:pilas/games/colorear/coloring_painter.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

import 'support/harness.dart';

Future<void> dejarGuardar(WidgetTester tester) async {
  // Cada escritura encadena varias operaciones de disco (temporal, copia,
  // renombrar): cada vuelta deja avanzar una.
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Toca la zona [r] de la lámina en pantalla, en su punto de etiqueta.
Future<void> tocarZona(WidgetTester tester, ColoringPage page, ColoringRegion r) async {
  final Finder lienzo = find.byKey(const ValueKey<String>('colorear-lienzo'));
  final RenderBox box = tester.renderObject<RenderBox>(lienzo);
  final Offset local = ColoringLayout.toCanvas(page.viewBox, box.size, ColoringLayout.of(page).labelPoint(r));
  await tester.tapAt(box.localToGlobal(local));
  await tester.pump();
}

void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  test('B2: el blanco es un color y la goma borra, en los dos modos', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final List<ColoringPage> pages = await ColoringLibrary.load();
    final ColoringPage pez = pages.firstWhere((ColoringPage p) => p.id == 'pez');
    final ColoringRegion blanca = pez.regions.firstWhere((ColoringRegion r) => r.targetColor == Colors.white);
    final ColoringSession s = ColoringSession(pez, porNumeros: true);
    expect(s.paint(blanca, Colors.white), isTrue);
    expect(s.fills[blanca.id], Colors.white);
    expect(s.erase(blanca), isTrue);
    expect(s.fills.containsKey(blanca.id), isFalse);
    // Un color equivocado no se pone y cuenta como error.
    final ColoringRegion otra = pez.regions.firstWhere((ColoringRegion r) => r.targetColor != Colors.white);
    expect(s.paint(otra, Colors.white), isFalse);
    expect(s.errors, 1);
    // Cada lámina se completa pintando cada zona con el color de su número.
    for (final ColoringPage p in pages) {
      final ColoringSession x = ColoringSession(p, porNumeros: true);
      final List<Color> paleta = ColoringSession.numberPalette(p);
      for (final ColoringRegion r in p.regions) {
        expect(paleta[r.number - 1], r.targetColor, reason: '${p.id}: el número ${r.number} no corresponde a su color');
        expect(x.paint(r, paleta[r.number - 1]), isTrue);
      }
      expect(x.complete, isTrue, reason: p.id);
      expect(x.errors, 0);
    }
    expect(pages.length, 12);
  });

  testWidgets('B2: las 12 láminas por números se terminan en pantalla y cada una registra su ronda', (WidgetTester tester) async {
    late Profile p;
    late List<ColoringPage> pages;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
      await h.state.selectProfile(p);
      pages = await ColoringLibrary.load();
    });
    final GameDef game = GameRegistry.byId('colorear_numeros')!;
    await tester.pumpWidget(h.app(ColorearScreen(launch: GameLaunch(game: game, band: AgeBand.b5a6, profile: p), porNumeros: true)));
    // Las láminas se leen de los recursos de la app: se espera el catálogo.
    for (int i = 0; i < 40 && find.byType(GridView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byType(GridView), findsOneWidget);
    int hechas = 0;
    for (final ColoringPage page in pages.where((ColoringPage x) => x.minBand <= AgeBand.b5a6.index)) {
      final Finder lamina = find.byKey(ValueKey<String>('lamina-${page.id}'));
      // Se arrastra el catálogo, como lo haría un niño, hasta que la lámina
      // quede a la vista.
      final Rect area = tester.getRect(find.byType(GridView));
      for (int i = 0; i < 30; i++) {
        if (lamina.evaluate().isNotEmpty) {
          final double y = tester.getCenter(lamina).dy;
          if (y > area.top + 30 && y < area.bottom - 30) {
            break;
          }
        }
        await tester.drag(find.byType(GridView), const Offset(0, -150));
        await tester.pumpAndSettle();
      }
      final double y = tester.getCenter(lamina).dy;
      expect(y > area.top && y < area.bottom, isTrue, reason: '${page.id}: el catálogo no deja llegar a la lámina (centro en $y, lista de ${area.top} a ${area.bottom})');
      await tester.tap(lamina);
      await tester.pump();
      final List<Color> paleta = ColoringSession.numberPalette(page);
      for (int i = 0; i < paleta.length; i++) {
        await tester.tap(find.byKey(ValueKey<String>('color-$i')));
        await tester.pump();
        for (final ColoringRegion r in page.regions.where((ColoringRegion r) => r.number == i + 1)) {
          await tocarZona(tester, page, r);
        }
      }
      hechas += 1;
      await dejarGuardar(tester);
      final MasteryState? m = h.state.progressOf(p.id).masteryIfAny('colorear_numeros', AgeBand.b5a6);
      expect(m?.roundsPlayed, hechas, reason: '${page.id} no se terminó');
      // Termina la celebración y vuelve al catálogo.
      await tester.pump(const Duration(seconds: 3));
      await dejarGuardar(tester);
      await tester.pump(const Duration(seconds: 3));
      for (int i = 0; i < 40 && find.byType(GridView).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }
    expect(hechas, 12);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('G4: colorear libre no guarda una lámina en blanco ni da habilidades', (WidgetTester tester) async {
    late Profile p;
    late List<ColoringPage> pages;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
      await h.state.selectProfile(p);
      pages = await ColoringLibrary.load();
    });
    final GameDef game = GameRegistry.byId('colorear')!;
    await tester.pumpWidget(h.app(ColorearScreen(launch: GameLaunch(game: game, band: AgeBand.b5a6, profile: p))));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey<String>('lamina-${pages.first.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('colorear-listo')));
    await tester.pump();
    expect(h.voice.dicho, contains('Primero pinta alguna zona.'));
    expect(h.state.progressOf(p.id).live?.gameRounds['colorear'], isNull);
    await tocarZona(tester, pages.first, pages.first.regions.first);
    await tester.tap(find.byKey(const ValueKey<String>('colorear-listo')));
    await tester.pump();
    await dejarGuardar(tester);
    expect(h.state.progressOf(p.id).live?.gameRounds['colorear'], 1);
    expect(h.state.progressOf(p.id).masteryIfAny('colorear', AgeBand.b5a6), isNull);
    expect(h.state.progressOf(p.id).skillsAchieved, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
