import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/app_scope.dart';
import 'package:rutinas/core/backup_io.dart';
import 'package:rutinas/core/cues.dart';
import 'package:rutinas/core/notifications.dart';
import 'package:rutinas/core/settings.dart';
import 'package:rutinas/core/storage.dart';
import 'package:rutinas/state/timer_controller.dart';

/// Servicios de la app con dobles de prueba: notificaciones en memoria, sin
/// sonido, sin pantalla encendida y sin hoja de compartir.
Services testServices(Directory dir, {String language = 'es', bool ios = false}) {
  final AppSettings settings = AppSettings(deviceLanguage: language)..themeMode = 'light';
  return Services.create(
    settings: settings,
    store: JsonStore(root: dir),
    gateway: FakeNotificationGateway(ios: ios),
    cues: SilentCuePlayer(),
    screen: FakeScreenWake(),
    io: FakeBackupIO(),
  );
}

extension TestDoubles on Services {
  FakeNotificationGateway get fakeGateway => notices.gateway as FakeNotificationGateway;
  SilentCuePlayer get silentCues => cues as SilentCuePlayer;
  FakeBackupIO get fakeIO => io as FakeBackupIO;
}

/// pumpAndSettle con tope corto: si algo anima sin parar, falla en segundos.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

/// Avanza [d] en pasos cortos (para pantallas con un temporizador en marcha,
/// que nunca quedan quietas).
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final int steps = (d.inMilliseconds / 100).ceil();
  for (int i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Espera con tiempo real a que termine una operación de disco y la interfaz
/// la refleje (nunca se espera dentro de runAsync un futuro de la zona falsa).
Future<void> waitFor(WidgetTester tester, bool Function() done, {int maxTenths = 60}) async {
  for (int i = 0; i < maxTenths && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'la operación no terminó');
}

/// Pone la vista de la prueba en [logical] dp con densidad 3.
void useScreen(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Falla si hubo una excepción (desbordes de layout incluidos).
void expectNoErrors(WidgetTester tester, String where) {
  final Object? e = tester.takeException();
  expect(e, isNull, reason: '$where: $e');
}

/// Comprueba que [finder] se ve y recibe toques: tiene tamaño y un toque en su
/// centro le llega de verdad (encontrar el widget no basta).
void expectHittable(WidgetTester tester, Finder finder, String reason) {
  expect(finder, findsWidgets, reason: '$reason: no está');
  final RenderBox box = tester.renderObject<RenderBox>(finder.first);
  expect(box.hasSize && !box.size.isEmpty, isTrue, reason: '$reason: sin tamaño');
  final Offset center = box.localToGlobal(box.size.center(Offset.zero));
  final HitTestResult result = tester.hitTestOnBinding(center);
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
    fail('$reason: un toque en el centro no le llega (caja $rect en pantalla ${tester.view.physicalSize / tester.view.devicePixelRatio}; el toque llega a: $path)');
  }
}

/// Destino de la barra de navegación (o del riel lateral en pantallas anchas).
Finder navDestination(String label) {
  final Finder bar = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  if (bar.evaluate().isNotEmpty) {
    return bar;
  }
  return find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
}

Future<void> goTab(WidgetTester tester, String label, {bool running = false}) async {
  final Finder f = navDestination(label);
  expectHittable(tester, f, 'pestaña $label');
  await tester.tap(f.first);
  if (running) {
    await pumpFor(tester, const Duration(milliseconds: 600));
  } else {
    await settle(tester);
  }
}

/// Vuelve atrás con la flecha (o la X de las pantallas de edición) de la barra
/// superior. `tester.pageBack` busca el texto "Back" y la app está en español.
Future<void> goBack(WidgetTester tester) async {
  Finder f = find.byType(BackButton);
  if (f.evaluate().isEmpty) {
    f = find.byType(CloseButton);
  }
  expect(f, findsOneWidget, reason: 'un botón para volver');
  await tester.tap(f);
  await settle(tester);
}

/// Lleva [finder] a la vista: si no está en pantalla, vuelve al principio de
/// la lista y baja hasta encontrarlo.
Future<void> reveal(WidgetTester tester, Finder finder, {Finder? scrollable}) async {
  if (finder.evaluate().isEmpty) {
    final Finder list = scrollable ?? verticalList();
    final ScrollableState st = tester.state<ScrollableState>(list);
    st.position.jumpTo(st.position.minScrollExtent);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 300, scrollable: list, maxScrolls: 300);
    }
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
}

/// Baja hasta el final de la lista de la pantalla.
Future<void> toBottom(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    final ScrollPosition pos = tester.state<ScrollableState>(verticalList()).position;
    if (pos.pixels >= pos.maxScrollExtent) {
      break;
    }
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pump();
  }
  await settle(tester);
}

/// Lleva [finder] a la vista y comprueba que recibe toques.
Future<void> expectReachable(WidgetTester tester, Finder finder, String reason) async {
  await reveal(tester, finder);
  expectHittable(tester, finder, reason);
}

/// Toca una pestaña de una barra de pestañas (que se desplaza con texto grande).
Future<void> tapTab(WidgetTester tester, String label) async {
  final Finder tab = find.descendant(of: find.byType(TabBar), matching: find.text(label));
  await tester.ensureVisible(tab);
  await tester.pump();
  expectHittable(tester, tab, 'pestaña $label');
  await tester.tap(tab);
  await settle(tester);
}

/// La lista vertical de la pantalla de arriba (sin contar el desplazamiento
/// interno de los campos de texto de varias líneas).
Finder verticalList() => find.byElementPredicate((Element e) {
      final Widget w = e.widget;
      return w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up) && e.findAncestorWidgetOfExactType<EditableText>() == null;
    }).last;

/// Desplaza la lista de la pantalla hasta [finder] y lo toca.
Future<void> scrollAndTap(WidgetTester tester, Finder finder, {bool running = false, Finder? scrollable}) async {
  await reveal(tester, finder, scrollable: scrollable);
  await tester.tap(finder.first);
  if (running) {
    await pumpFor(tester, const Duration(milliseconds: 600));
  } else {
    await settle(tester);
  }
}
