@Tags(<String>['screenshots'])
library;

// Capturas de tienda de Pilas (solo en español, como la app): inicio de un
// niño con su avance, la tienda, letras y sonidos, colorear por números,
// laberintos y el informe para la familia, en teléfono y tableta de Android y
// en iPhone y iPad. Se ejecutan con `flutter test --tags screenshots`.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/app.dart';
import 'package:pilas/content/coloring_pages.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/colorear/coloring_painter.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/parent/child_report_screen.dart';

import 'store/pilas_demo.dart';
import 'store/store_shots.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

/// Deja correr E/S real (recursos SVG e imágenes) entre cuadros.
Future<void> _realTime(WidgetTester tester, {int rounds = 5}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

NavigatorState _nav(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator).first);

Future<void> _open(WidgetTester tester, WidgetBuilder builder) async {
  unawaited(_nav(tester).push(MaterialPageRoute<void>(builder: builder)));
  await tester.pump();
  await _realTime(tester);
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  _nav(tester).pop();
  await _settle(tester);
}

Future<void> _openGame(WidgetTester tester, AppState state, String id, Profile p) async {
  final GameDef game = GameRegistry.all.firstWhere((GameDef g) => g.id == id);
  await tester.runAsync(() => state.selectProfile(p));
  await _open(tester, (BuildContext context) => game.build(context, GameLaunch(game: game, band: p.band, profile: p)));
  _diagnose(tester, game.nombre);
}

/// Registra qué hay en pantalla (para revisar capturas vacías en la CI).
void _diagnose(WidgetTester tester, String label) {
  final Finder title = find.text(label);
  final List<String> routes = <String>[];
  for (final Element e in find.byType(Scaffold, skipOffstage: false).evaluate()) {
    final ModalRoute<dynamic>? r = ModalRoute.of(e);
    final RenderBox? box = e.renderObject as RenderBox?;
    routes.add('${e.widget.runtimeType} route=${r?.runtimeType} anim=${r?.animation?.value.toStringAsFixed(2)} sec=${r?.secondaryAnimation?.value.toStringAsFixed(2)} current=${r?.isCurrent} offset=${box != null && box.hasSize ? box.localToGlobal(Offset.zero) : null} size=${box != null && box.hasSize ? box.size : null}');
  }
  debugPrint('[diagnóstico] "$label": ${title.evaluate().length} textos visibles; scaffolds: ${routes.join(' | ')}');
}

/// Pinta casi toda la lámina abierta con los colores de sus números (deja
/// [leave] zonas sin pintar para que se vea el modo por números).
Future<void> _colorIn(WidgetTester tester, {int leave = 3}) async {
  final Finder canvas = find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter is ColoringPainter);
  final CustomPaint paint = tester.widget<CustomPaint>(canvas.first);
  final ColoringLayout layout = (paint.painter! as ColoringPainter).layout;
  final RenderBox box = tester.renderObject<RenderBox>(canvas.first);
  final Size size = box.size;
  final Rect vb = layout.page.viewBox;
  final double scale = (size.width / vb.width) < (size.height / vb.height) ? size.width / vb.width : size.height / vb.height;
  final double dx = (size.width - vb.width * scale) / 2 - vb.left * scale;
  final double dy = (size.height - vb.height * scale) / 2 - vb.top * scale;
  final List<Color> palette = layout.page.palette;
  final int last = layout.page.regions.length - leave;
  for (int c = 0; c < palette.length; c++) {
    final Finder swatch = find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == 'color número ${c + 1}');
    if (swatch.evaluate().isEmpty) {
      continue;
    }
    await tester.tap(swatch.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    for (int i = 0; i < last; i++) {
      final ColoringRegion r = layout.page.regions[i];
      if (r.targetColor != palette[c]) {
        continue;
      }
      final Offset pagePoint = layout.labelPoint(r);
      final Offset local = Offset(pagePoint.dx * scale + dx, pagePoint.dy * scale + dy);
      await tester.tapAt(box.localToGlobal(local));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final StoreDevice device in StoreDevice.all) {
    testWidgets('Capturas de Pilas en ${device.id}', (WidgetTester tester) async {
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails d) {
        errors.add(d);
        previous?.call(d);
      };
      addTearDown(() => FlutterError.onError = previous);

      device.apply(tester);
      await loadStoreFonts(tester);
      final Directory dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('pilas_shots')))!;
      final AppSettings settings = AppSettings()
        ..voiceEnabled = false
        ..sfxEnabled = false
        ..sessionLimitMinutes = 0;
      final JsonStore store = JsonStore(root: dir);
      final AppState state = AppState(store);
      final PilasDemo demo = (await tester.runAsync(() async {
        await state.load();
        return seedPilasDemo(state, now: DateTime.now());
      }))!;
      final Services s = Services(settings: settings, voice: Voice(settings), sfx: Sfx(settings), store: store, state: state);

      await tester.pumpWidget(storeShotRoot(PilasApp(services: s)));
      await _realTime(tester);
      await _settle(tester);

      // 1. Inicio de Sofía (7 años): juegos de su edad con su avance.
      await tester.runAsync(() => state.selectProfile(demo.sofia));
      await _open(tester, (_) => const KidHomeScreen());
      await takeStoreShot(tester, device, 'es', '01-inicio');
      await _close(tester);

      // 2. La tienda: monedas y billetes.
      await _openGame(tester, state, 'tienda', demo.sofia);
      await takeStoreShot(tester, device, 'es', '02-tienda');
      await _close(tester);

      // 3. Sonidos y letras (Mateo, 5 años).
      await _openGame(tester, state, 'sonidos', demo.mateo);
      await takeStoreShot(tester, device, 'es', '03-letras');
      await _close(tester);

      // 4. Colorear por números, casi terminado.
      await _openGame(tester, state, 'colorear_numeros', demo.mateo);
      final Finder thumbs = find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter is ColoringPainter);
      for (int i = 0; i < 40 && thumbs.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      _diagnose(tester, 'Colorear por números');
      await tester.tap(thumbs.first);
      await _realTime(tester);
      await _settle(tester);
      await _colorIn(tester);
      await takeStoreShot(tester, device, 'es', '04-colorear');
      await _close(tester);

      // 5. Laberintos (Sofía).
      await _openGame(tester, state, 'laberintos', demo.sofia);
      await takeStoreShot(tester, device, 'es', '05-logica');
      await _close(tester);

      // 6. Informe para la familia (en la app está tras la puerta parental).
      await tester.runAsync(() => state.selectProfile(null));
      await _open(tester, (_) => ChildReportScreen(profile: demo.sofia));
      await takeStoreShot(tester, device, 'es', '06-informe');
      await _close(tester);

      await tester.runAsync(() => state.endSession());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => dir.delete(recursive: true));
      expect(errors, isEmpty, reason: errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n'));
    }, variant: TargetPlatformVariant.only(device.platform), timeout: const Timeout(Duration(minutes: 4)));
  }
}
