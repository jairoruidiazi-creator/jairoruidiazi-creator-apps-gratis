import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/core/theme.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/shell/widgets.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/profiles_screen.dart';

/// Comprueba que [finder] se ve y recibe toques: tiene tamaño y un toque en su
/// centro llega a él. Encontrar el widget no basta: un Stack de tamaño cero
/// dejó los juegos invisibles sin que ninguna prueba fallara.
void expectHittable(WidgetTester tester, Finder finder, String reason) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  expect(box.hasSize && !box.size.isEmpty, isTrue, reason: '$reason: sin tamaño');
  final Offset center = box.localToGlobal(box.size.center(Offset.zero));
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect((Offset.zero & screen).contains(center), isTrue, reason: '$reason: queda fuera de la pantalla ($center en $screen)');
  final HitTestResult result = tester.hitTestOnBinding(center);
  // RenderTransform (la raíz de OptionTile) no se agrega a sí mismo al
  // resultado, solo a sus hijos: basta con que el toque llegue a algo dentro.
  bool inside(RenderObject o) {
    RenderObject? p = o;
    while (p != null) {
      if (identical(p, box)) {
        return true;
      }
      p = p.parent;
    }
    return false;
  }

  final bool hit = result.path.any((HitTestEntry e) => e.target is RenderObject && inside(e.target as RenderObject));
  if (!hit) {
    final Rect rect = box.localToGlobal(Offset.zero) & box.size;
    final String path = result.path.take(14).map((HitTestEntry e) => e.target.runtimeType.toString()).join(' > ');
    fail('$reason: un toque en el centro no le llega (caja $rect en pantalla $screen; el toque llega a: $path)');
  }
}

/// Un tamaño de pantalla y de letra en el que todo tiene que caber.
class Config {
  const Config(this.w, this.h, this.texto);

  final double w;
  final double h;
  final double texto;

  @override
  String toString() => '${w.toInt()}×${h.toInt()} letra ×$texto';
}

/// Teléfono de 360 × 740 dp de pie y acostado, tableta de 1024 × 768, con la
/// letra normal, la del ajuste "Texto grande" con la del sistema (×1,3) y el
/// tope (×1,5). Las casillas de los tableros deben medir 24 dp o más hasta
/// ×1,3; con ×1,5 basta con que nada se desborde.
const List<Config> configs = <Config>[
  Config(360, 740, 1.0),
  Config(740, 360, 1.0),
  Config(1024, 768, 1.0),
  Config(360, 740, 1.3),
  Config(740, 360, 1.3),
  Config(360, 740, 1.5),
];

/// Abre cada juego en cada tramo y nivel, en varios tamaños de pantalla y de
/// letra, y comprueba que no haya desbordes ni excepciones, que el marco, las
/// opciones y los tableros se vean y reciban toques, que las casillas midan
/// al menos 24 dp y que la pista no tape las opciones.
void main() {
  late Directory tmp;
  late Services services;
  final Map<AgeBand, Profile> profiles = <AgeBand, Profile>{};

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pilas_smoke');
    final AppSettings settings = AppSettings()
      ..voiceEnabled = false
      ..sfxEnabled = false
      ..sessionLimitMinutes = 0;
    final JsonStore store = JsonStore(root: tmp);
    final AppState state = AppState(store);
    await state.load();
    services = Services(settings: settings, voice: Voice(settings), sfx: Sfx(settings), store: store, state: state);
    for (final AgeBand b in AgeBand.values) {
      profiles[b] = await state.addProfile(nombre: 'Peque ${b.id}', avatar: '1f431', birthYear: 2020, birthMonth: 1, bandOverride: b);
    }
  });

  tearDownAll(() async {
    services.state.dispose();
    await tmp.delete(recursive: true);
  });

  Widget host(GameDef game, AgeBand band, double texto, Key key) {
    return AppScope(
      services: services,
      state: services.state,
      child: MaterialApp(
        theme: PilasTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(texto)),
          child: child!,
        ),
        home: Builder(key: key, builder: (BuildContext context) => game.build(context, GameLaunch(game: game, band: band, profile: profiles[band]!))),
      ),
    );
  }

  for (final GameDef game in GameRegistry.all) {
    for (final AgeBand band in AgeBand.values) {
      if (!game.supports(band)) {
        continue;
      }
      testWidgets('${game.id} cabe y responde en ${band.id}, en todos sus niveles', (WidgetTester tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Se guardan los errores completos (con el widget que los causa) en
        // lugar de solo el mensaje que deja takeException, y se siguen
        // pasando al manejador de la prueba.
        final List<String> errors = <String>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) {
          errors.add(d.toString());
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);
        services.state.current = profiles[band];
        tester.view.devicePixelRatio = 3;

        for (int level = 1; level <= game.levelsFor(band); level++) {
          services.state.progressOf(profiles[band]!.id).masteryFor(game.id, band).level = level;
          for (final Config c in configs) {
            final String donde = '${game.id} ${band.id} nivel $level, $c';
            void expectNoErrors(String when) {
              if (errors.isNotEmpty) {
                final String text = errors.join('\n----\n');
                errors.clear();
                fail('$donde: errores $when:\n$text');
              }
            }

            tester.view.physicalSize = Size(c.w * 3, c.h * 3);
            await tester.pumpWidget(host(game, band, c.texto, ValueKey<String>('$level-$c')));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expectNoErrors('al abrir');
            expect(find.text(game.nombre), findsWidgets, reason: donde);
            expectHittable(tester, find.byWidgetPredicate((Widget w) => w is RoundIconButton && w.tooltip == S.salir).first, '$donde: botón de salir');

            // Todas las opciones se ven y reciben toques sin desplazar nada.
            // Solo el catálogo de láminas de colorear es una lista que se
            // desplaza: ahí basta con que se vean las primeras tarjetas.
            final Finder tiles = find.byType(OptionTile);
            for (int i = 0; i < tiles.evaluate().length; i++) {
              final Widget w = tester.widget(tiles.at(i));
              final bool catalogo = w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lamina-');
              if (catalogo && i >= 2) {
                continue;
              }
              expectHittable(tester, tiles.at(i), '$donde: opción ${i + 1}');
            }
            // Los tableros caben con casillas de 24 dp o más.
            final Finder tableros = find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tablero-'));
            for (final Element e in tableros.evaluate()) {
              final String k = (e.widget.key! as ValueKey<String>).value;
              final List<String> partes = k.substring('tablero-'.length).split('x');
              final int cols = int.parse(partes[0]);
              final int rows = int.parse(partes[1]);
              final RenderBox box = e.renderObject! as RenderBox;
              if (c.texto <= 1.3) {
                expect(box.size.width / cols, greaterThanOrEqualTo(Dim.minCell - 0.01), reason: '$donde: casillas de ${(box.size.width / cols).toStringAsFixed(1)} dp de ancho en $k');
                expect(box.size.height / rows, greaterThanOrEqualTo(Dim.minCell - 0.01), reason: '$donde: casillas de ${(box.size.height / rows).toStringAsFixed(1)} dp de alto en $k');
              }
              expectHittable(tester, find.byWidget(e.widget), '$donde: tablero');
            }

            // En el teléfono de pie: se responde una vez. Si sale la pista,
            // va en la barra de arriba y las opciones siguen a mano.
            if (c.w == 360 && c.texto == 1.0 && tiles.evaluate().isNotEmpty) {
              await tester.tap(tiles.first);
              await tester.pump(const Duration(milliseconds: 200));
              expectNoErrors('al responder');
              if (find.byKey(const ValueKey<String>('pista')).evaluate().isNotEmpty) {
                expectHittable(tester, find.byKey(const ValueKey<String>('pista')), '$donde: pista');
                final Finder quedan = find.byType(OptionTile);
                for (int i = 1; i < quedan.evaluate().length; i++) {
                  expectHittable(tester, quedan.at(i), '$donde: opción ${i + 1} con la pista a la vista');
                }
              }
              await tester.pump(const Duration(seconds: 3));
              await tester.pump(const Duration(seconds: 3));
              expectNoErrors('después de responder');
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (errors.isNotEmpty) {
          fail('${game.id} ${band.id}: errores al cerrar:\n${errors.join('\n----\n')}');
        }
      });
    }
  }

  testWidgets('G13: la pantalla de perfiles cabe en un teléfono con letra grande', (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 3;
    services.state.current = null;
    for (final Config c in configs) {
      tester.view.physicalSize = Size(c.w * 3, c.h * 3);
      await tester.pumpWidget(AppScope(
        services: services,
        state: services.state,
        child: MaterialApp(
          key: ValueKey<String>('perfiles-$c'),
          theme: PilasTheme.light(),
          builder: (BuildContext context, Widget? child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.texto)), child: child!),
          home: const ProfilesScreen(),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'perfiles $c');
      // skipOffstage: false; que se vea y reciba toques lo comprueba
      // expectHittable (centro dentro de la pantalla y toque que le llega).
      final Finder primero = find.byKey(ValueKey<String>('perfil-${profiles[AgeBand.b3a4]!.id}'), skipOffstage: false);
      String donde(Finder f) => f.evaluate().isEmpty ? '-' : tester.getRect(f.first).toString();
      expectHittable(tester, primero, 'perfiles $c: primera tarjeta (título ${donde(find.text(S.appName, skipOffstage: false))}, adulto ${donde(find.byKey(const ValueKey<String>('soy-adulto'), skipOffstage: false))}, pregunta ${donde(find.text(S.quienJuega, skipOffstage: false))})');
      expectHittable(tester, find.byKey(const ValueKey<String>('soy-adulto'), skipOffstage: false), 'perfiles $c: soy adulto');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('G13: en el inicio de los niños los pictogramas no se achican', (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 3;
    for (final AgeBand band in AgeBand.values) {
      for (final Config c in <Config>[const Config(360, 740, 1.5), const Config(740, 360, 1.3)]) {
        tester.view.physicalSize = Size(c.w * 3, c.h * 3);
        services.state.current = profiles[band];
        await tester.pumpWidget(AppScope(
          services: services,
          state: services.state,
          child: MaterialApp(
            theme: PilasTheme.light(),
            builder: (BuildContext context, Widget? child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.texto)), child: child!),
            home: const KidHomeScreen(),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${band.id} $c');
        final Finder primera = find.byKey(ValueKey<String>('juego-${GameRegistry.forBand(band).first.id}'));
        final Finder emoji = find.descendant(of: primera, matching: find.byType(EmojiImage));
        expect(tester.getSize(emoji.first).width, greaterThanOrEqualTo(56), reason: '${band.id} $c');
        expectHittable(tester, primera, '${band.id} $c: primera tarjeta');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
