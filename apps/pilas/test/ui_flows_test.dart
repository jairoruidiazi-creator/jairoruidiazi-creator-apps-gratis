import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/parental_gate.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/share.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/carrera/carrera_generator.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/profile_edit_screen.dart';
import 'package:pilas/ui/profiles_screen.dart';
import 'package:pilas/ui/rest_screen.dart';
import 'package:share_plus/share_plus.dart';

import 'support/harness.dart';

/// Deja avanzar las escrituras a disco (que no corren con el reloj falso de
/// las pruebas de widgets).
Future<void> dejarGuardar(WidgetTester tester) async {
  // Cada escritura encadena varias operaciones de disco (temporal, copia,
  // renombrar): cada vuelta deja avanzar una.
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  group('G14: puerta para adultos', () {
    test('Pide una multiplicación de dos números de 13 a 39 sin múltiplos de 5, en palabras', () {
      expect(GateChallenge.factores, <int>[13, 14, 16, 17, 18, 19, 21, 22, 23, 24, 26, 27, 28, 29, 31, 32, 33, 34, 36, 37, 38, 39]);
      final Map<int, int> veces = <int, int>{};
      const int n = 20000;
      for (int seed = 0; seed < n; seed++) {
        final GateChallenge g = GateChallenge.random(Random(seed));
        for (final int f in <int>[g.a, g.b]) {
          expect(f, inInclusiveRange(13, 39));
          expect(f % 5, isNot(0), reason: '${g.a} × ${g.b}');
          veces[f] = (veces[f] ?? 0) + 1;
        }
        expect(GateChallenge.valido(g.a, g.b), isTrue);
        // Nada trivial: el resultado tiene tres cifras y no termina en 0.
        expect(g.answer, inInclusiveRange(169, 1521));
        expect(g.answer % 10, isNot(0), reason: '${g.a} × ${g.b}');
        expect(g.question, isNot(matches(RegExp(r'\d'))), reason: 'la pregunta va en palabras');
        expect(g.check('${g.answer}'), isTrue);
        expect(g.check('${g.answer + 1}'), isFalse);
      }
      // Los 22 factores salen parejo (cada uno, cerca de 2 × n / 22 veces).
      expect(veces.keys.toSet(), GateChallenge.factores.toSet());
      final double esperado = 2 * n / GateChallenge.factores.length;
      for (final int f in GateChallenge.factores) {
        expect(veces[f]!, inInclusiveRange((esperado * 0.85).round(), (esperado * 1.15).round()), reason: 'factor $f');
      }
      expect(GateChallenge.random(Random(1)).check('abc'), isFalse);
    });

    test('Ninguna multiplicación que entrenan la tienda o la carrera puede salir en la puerta', () {
      // Barrido: miles de rondas de los dos juegos que multiplican; se leen
      // los factores de sus textos («7 × 8», «12 por $ 1.500») y, en la
      // tienda, también contados en centenas (1.500 = 15).
      final Set<String> pares = <String>{};
      void anotar(int a, int b) {
        pares.add('$a×$b');
        if (b % 100 == 0) {
          pares.add('$a×${b ~/ 100}');
        }
      }

      void leer(String texto) {
        for (final RegExpMatch m in RegExp(r'(\d+) × (\d+)').allMatches(texto)) {
          anotar(int.parse(m.group(1)!), int.parse(m.group(2)!));
        }
        for (final RegExpMatch m in RegExp(r'(\d+) (?:por|×) \$ ([\d.]+)').allMatches(texto)) {
          anotar(int.parse(m.group(1)!), int.parse(m.group(2)!.replaceAll('.', '')));
        }
      }

      final CarreraGenerator carrera = CarreraGenerator();
      final TiendaGenerator tienda = TiendaGenerator();
      for (final AgeBand band in AgeBand.values) {
        for (int level = 1; level <= 4; level++) {
          for (int seed = 0; seed < 300; seed++) {
            if (GameRegistry.byId('carrera')!.supports(band) && level <= GameRegistry.byId('carrera')!.levelsFor(band)) {
              final ChoiceRound r = carrera.next(Rng(seed * 17 + level), band, level);
              leer('${r.instruction} ${r.explain} ${r.hint}');
            }
            if (level <= GameRegistry.byId('tienda')!.levelsFor(band)) {
              final ChoiceRound? r = tienda.next(Rng(seed * 19 + level), band, level).choice;
              if (r != null) {
                leer('${r.instruction} ${r.explain} ${r.hint}');
              }
            }
          }
        }
      }
      expect(pares.length, greaterThan(50));
      for (final String par in pares) {
        final List<int> ab = par.split('×').map(int.parse).toList();
        expect(GateChallenge.valido(ab[0], ab[1]) || GateChallenge.valido(ab[1], ab[0]), isFalse, reason: 'la app entrena $par');
        expect(GateChallenge.entrenado(ab[0], ab[1]), isTrue, reason: par);
      }
    });

    test('M9: el contador de errores vuelve a cero tras 15 minutos sin errores', () {
      final DateTime ahora = DateTime(2026, 10, 18, 12);
      expect(GateLock.vigentes(3, ahora.subtract(const Duration(minutes: 5)), ahora), 3);
      expect(GateLock.vigentes(3, ahora.subtract(const Duration(minutes: 15)), ahora), 0);
      expect(GateLock.vigentes(5, ahora.subtract(const Duration(days: 2)), ahora), 0);
      expect(GateLock.vigentes(2, null, ahora), 0);
      // El bloqueo más largo (15 min) termina cuando el contador ya volvió a cero.
      expect(GateLock.waitAfter(99), lessThanOrEqualTo(GateLock.reinicio));
    });

    test('Dos errores sin espera; desde el tercero, 60 s, luego 120 s, 240 s…', () {
      expect(GateLock.waitAfter(1), Duration.zero);
      expect(GateLock.waitAfter(2), Duration.zero);
      expect(GateLock.waitAfter(3), const Duration(seconds: 60));
      expect(GateLock.waitAfter(4), const Duration(seconds: 120));
      expect(GateLock.waitAfter(5), const Duration(seconds: 240));
      expect(GateLock.waitAfter(20), const Duration(seconds: 900));
    });

    testWidgets('Avisa por voz, no ofrece menú de texto y se bloquea tras varios errores', (WidgetTester tester) async {
      await tester.pumpWidget(h.app(Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showParentalGate(context, reason: 'Prueba'), child: const Text('abrir'))),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(h.voice.dicho, contains(S.esParaUnAdulto));
      final TextField campo = tester.widget<TextField>(find.byKey(const ValueKey<String>('puerta-respuesta')));
      expect(campo.contextMenuBuilder, isNull);
      expect(campo.enableInteractiveSelection, isFalse);
      // La puerta dice que se puede usar la calculadora.
      expect(find.text(S.puertaCalculadora), findsOneWidget);
      // Pedir otra operación cuenta como intento fallido y cambia la pregunta.
      String pregunta() => tester.widget<Text>(find.byKey(const ValueKey<String>('puerta-pregunta'))).data!;
      final String antes = pregunta();
      await tester.tap(find.byKey(const ValueKey<String>('puerta-otra')));
      await tester.pump();
      expect(h.services.settings.gateFails, 1);
      expect(pregunta(), isNot(antes));
      await tester.tap(find.byKey(const ValueKey<String>('puerta-otra')));
      await tester.pump();
      expect(h.services.settings.gateFails, 2);
      // El tercer intento fallido ya espera, sea una respuesta o «Otra operación».
      await tester.enterText(find.byKey(const ValueKey<String>('puerta-respuesta')), '1');
      await tester.tap(find.text(S.entrar));
      await tester.pump();
      expect(find.textContaining('Demasiados intentos'), findsOneWidget);
      expect(h.services.settings.gateFails, 3);
      expect(h.services.settings.gateLastFail, isNotNull);
      expect(find.byKey(const ValueKey<String>('puerta-otra')), findsNothing);
      // Se cierra el diálogo para no dejar el temporizador corriendo.
      await tester.tap(find.text(S.cancelar));
      await tester.pumpAndSettle();
    });

    testWidgets('M1 (cuarta ronda): cerrar y abrir la puerta muestra la misma operación', (WidgetTester tester) async {
      await tester.pumpWidget(h.app(Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showParentalGate(context), child: const Text('abrir'))),
        ),
      )));
      String pregunta() => tester.widget<Text>(find.byKey(const ValueKey<String>('puerta-pregunta'))).data!;
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      final String primera = pregunta();
      expect(h.services.settings.gatePendiente, isNotNull);
      for (int i = 0; i < 3; i++) {
        // Cancelar y tocar fuera no cambian la operación ni cuentan intento.
        if (i.isEven) {
          await tester.tap(find.text(S.cancelar));
        } else {
          await tester.tapAt(const Offset(4, 4));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(pregunta(), primera);
        expect(h.services.settings.gateFails, 0);
      }
      // «Otra operación» sí la cambia (y cuenta), y la nueva queda pendiente.
      await tester.tap(find.byKey(const ValueKey<String>('puerta-otra')));
      await tester.pump();
      final String segunda = pregunta();
      expect(segunda, isNot(primera));
      expect(h.services.settings.gateFails, 1);
      await tester.tap(find.text(S.cancelar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(pregunta(), segunda);
      // Al acertar se olvida la pendiente.
      int? respuesta;
      for (final int a in GateChallenge.factores) {
        for (final int b in GateChallenge.factores) {
          if (segunda == '¿Cuánto es ${Es.numero(a)} por ${Es.numero(b)}?') {
            respuesta = a * b;
          }
        }
      }
      await tester.enterText(find.byKey(const ValueKey<String>('puerta-respuesta')), '$respuesta');
      await tester.tap(find.text(S.entrar));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('puerta-pregunta')), findsNothing);
      expect(h.services.settings.gatePendiente, isNull);
      expect(h.services.settings.gateFails, 0);
    });

    testWidgets('M3: dos toques seguidos en «Entrar» cierran solo la puerta', (WidgetTester tester) async {
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      bool? resultado;
      await tester.pumpWidget(h.app(const Scaffold(body: Text('inicio')), navigatorKey: nav));
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          body: Center(child: TextButton(onPressed: () async => resultado = await showParentalGate(context), child: const Text('abrir'))),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      final String q = tester.widget<Text>(find.byKey(const ValueKey<String>('puerta-pregunta'))).data!;
      int? respuesta;
      for (final int a in GateChallenge.factores) {
        for (final int b in GateChallenge.factores) {
          if (q == '¿Cuánto es ${Es.numero(a)} por ${Es.numero(b)}?') {
            respuesta = a * b;
          }
        }
      }
      expect(respuesta, isNotNull, reason: q);
      await tester.enterText(find.byKey(const ValueKey<String>('puerta-respuesta')), '$respuesta');
      final Finder entrar = find.text(S.entrar);
      await tester.tap(entrar);
      await tester.tap(entrar, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(resultado, isTrue);
      // La pantalla que abrió la puerta sigue ahí (no hubo un segundo pop).
      expect(find.text('abrir'), findsOneWidget);
      expect(find.text('inicio'), findsNothing);
    });
  });

  testWidgets('G15: el nombre del perfil no ofrece menú de texto', (WidgetTester tester) async {
    await tester.pumpWidget(h.app(const ProfileEditScreen()));
    await tester.pump();
    final TextField campo = tester.widget<TextField>(find.byKey(const ValueKey<String>('perfil-nombre')));
    expect(campo.contextMenuBuilder, isNull);
    expect(campo.enableInteractiveSelection, isFalse);
  });

  group('Pantalla de perfiles', () {
    testWidgets('M1: el primer perfil también pasa por la puerta', (WidgetTester tester) async {
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('nuevo-perfil')));
      await tester.pumpAndSettle();
      expect(find.text(S.paraAdultos), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsNothing);
    });

    testWidgets('G1: cambiar de jugador mientras otro descansa pide la puerta', (WidgetTester tester) async {
      late Profile ana;
      late Profile beto;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        beto = await h.state.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1);
      });
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 5));
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey<String>('perfil-${beto.id}')));
      await tester.pumpAndSettle();
      expect(find.text(S.cambiarConDescanso), findsOneWidget);
      expect(find.byType(KidHomeScreen), findsNothing);
      await tester.tap(find.text(S.cancelar));
      await tester.pumpAndSettle();
    });

    testWidgets('G1: el jugador que está en su descanso ve el descanso', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 5));
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey<String>('perfil-${ana.id}')));
      await dejarGuardar(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RestScreen), findsOneWidget);
      expect(find.byType(KidHomeScreen), findsNothing);
    });

    testWidgets('M5: un toque doble abre el inicio una sola vez', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      final Finder tile = find.byKey(ValueKey<String>('perfil-${ana.id}'));
      await tester.tap(tile);
      await tester.tap(tile, warnIfMissed: false);
      await dejarGuardar(tester);
      await tester.pumpAndSettle();
      expect(find.byType(KidHomeScreen), findsOneWidget);
      // Se detiene el reloj de la sesión antes de terminar la prueba.
      await tester.runAsync(() => h.state.pauseClock());
    });
  });

  group('G2: el descanso no se cierra con atrás', () {
    testWidgets('El botón atrás de Android no saca la pantalla de descanso', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 10));
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(h.app(const Scaffold(body: Text('juego')), navigatorKey: nav));
      nav.currentState!.push(RestScreen.route());
      await tester.pumpAndSettle();
      expect(find.byType(RestScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RestScreen), findsOneWidget);
      // El temporizador de la cuenta regresiva se detiene al cerrar la prueba.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('M5: el lector de pantalla oye los minutos, no cada segundo', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 9, seconds: 30));
      await tester.pumpWidget(h.app(const RestScreen()));
      await tester.pump();
      final SemanticsNode n = tester.getSemantics(find.byKey(const ValueKey<String>('descanso-cuenta')));
      expect(n.label, S.quedanMinutos(570));
      expect(n.label, 'Faltan diez minutos de descanso.');
      expect(n.label, isNot(contains(':')));
      expect(S.quedanMinutos(600), 'Faltan diez minutos de descanso.');
      expect(S.quedanMinutos(61), 'Faltan dos minutos de descanso.');
      expect(S.quedanMinutos(60), 'Falta un minuto de descanso.');
      expect(S.quedanMinutos(59), 'Falta menos de un minuto de descanso.');
      await tester.pumpWidget(const SizedBox.shrink());
      sem.dispose();
    });

    test('M4: durante el descanso la voz no lee el juego que quedó debajo', () async {
      final Profile ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 10));
      h.voice.dicho.clear();
      h.voice.sayLater('¿Cuál es el círculo?');
      await h.voice.say('¡Excelente!');
      expect(h.voice.dicho, isEmpty);
      // La pantalla de descanso y la puerta sí hablan.
      h.voice.sayAlways(S.horaDeDescansar);
      expect(h.voice.dicho, <String>[S.horaDeDescansar]);
      // Al volver, se dice lo último que se calló.
      h.state.progressOf(ana.id).restUntil = null;
      h.voice.soltarRetenido();
      expect(h.voice.dicho.last, '¡Excelente!');
      h.voice.sayLater('¿Cuál es el cuadrado?');
      expect(h.voice.dicho.last, '¿Cuál es el cuadrado?');
    });
  });

  testWidgets('M6: salir de un juego con atrás calla la voz', (WidgetTester tester) async {
    late Profile ana;
    await tester.runAsync(() async {
      ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
    });
    h.state.current = ana;
    final GameDef g = GameRegistry.byId('patrones')!;
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(h.app(const Scaffold(body: Text('inicio')), navigatorKey: nav));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (BuildContext context) => g.build(context, GameLaunch(game: g, band: AgeBand.b5a6, profile: ana))));
    await tester.pumpAndSettle();
    final int antes = h.voice.paradas;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('inicio'), findsOneWidget);
    expect(h.voice.paradas, greaterThan(antes));
  });

  group('B3: compartir', () {
    testWidgets('Pasa siempre el rectángulo del botón tocado como origen', (WidgetTester tester) async {
      ShareParams? recibido;
      final Sharer sharer = Sharer(share: (ShareParams p) async {
        recibido = p;
        return const ShareResult('ok', ShareResultStatus.success);
      });
      await tester.pumpWidget(h.app(Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext b) => TextButton(
              key: const ValueKey<String>('compartir'),
              onPressed: () => sharer.shareFiles(b, <XFile>[XFile('dibujo.png')]),
              child: const Text('Compartir'),
            ),
          ),
        ),
      )));
      await tester.tap(find.byKey(const ValueKey<String>('compartir')));
      await tester.pump();
      expect(recibido, isNotNull);
      final Rect boton = tester.getRect(find.byKey(const ValueKey<String>('compartir')));
      expect(recibido!.sharePositionOrigin, boton);
      expect(boton.isEmpty, isFalse);
    });

    testWidgets('Si la hoja de compartir falla, avisa en pantalla', (WidgetTester tester) async {
      final Sharer sharer = Sharer(share: (ShareParams p) async => throw Exception('sin hoja'));
      bool? resultado;
      await tester.pumpWidget(h.app(Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext b) => TextButton(onPressed: () async => resultado = await sharer.shareFiles(b, <XFile>[XFile('x.png')]), child: const Text('Compartir')),
          ),
        ),
      )));
      await tester.tap(find.text('Compartir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(resultado, isFalse);
      expect(find.textContaining('No se pudo abrir la hoja de compartir'), findsOneWidget);
    });

    test('Los nombres de archivo quedan seguros', () {
      expect(Sharer.safeFileName('Grupo 2/B: Martín'), 'grupo-2-b-martin');
      expect(Sharer.safeFileName('///'), 'pilas');
    });
  });
}
