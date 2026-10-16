import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/app.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/model/progress.dart';

void main() {
  late Directory tmp;
  late Services services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pilas_test');
    final AppSettings settings = AppSettings();
    final JsonStore store = JsonStore(root: tmp);
    final AppState state = AppState(store);
    await state.load();
    services = Services(settings: settings, voice: Voice(settings), sfx: Sfx(settings), store: store, state: state);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('los perfiles y el progreso se guardan en disco', () async {
    final Profile p = await services.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2020, birthMonth: 3);
    expect(services.state.profiles.length, 1);
    final ProfileProgress prog = await services.state.progressFor(p.id);
    prog.skillsAchieved['logica.3-4.emparejar'] = DateTime(2026, 10, 1);
    await services.state.saveProgress(p.id);

    final AppState again = AppState(JsonStore(root: tmp));
    await again.load();
    expect(again.profiles.single.nombre, 'Ana');
    final ProfileProgress back = await again.progressFor(p.id);
    expect(back.skillsAchieved.containsKey('logica.3-4.emparejar'), isTrue);
  });

  test('exportar e importar conserva perfiles y grupos', () async {
    final Profile p = await services.state.addProfile(nombre: 'Luis', avatar: '1f436', birthYear: 2018, birthMonth: 6, bandOverride: AgeBand.b9a11);
    await services.state.addGroup('Transición A');
    final Map<String, dynamic> data = await services.state.exportAll();
    final Directory tmp2 = await Directory.systemTemp.createTemp('pilas_test2');
    final AppState other = AppState(JsonStore(root: tmp2));
    await other.load();
    final int n = await other.importAll(data);
    expect(n, 1);
    expect(other.profileById(p.id)?.bandOverride, AgeBand.b9a11);
    expect(other.groups.single.nombre, 'Transición A');
    await tmp2.delete(recursive: true);
  });

  testWidgets('la app arranca en la pantalla de perfiles', (WidgetTester tester) async {
    await tester.pumpWidget(PilasApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('¿Quién va a jugar?'), findsOneWidget);
    expect(find.text('Nuevo perfil'), findsOneWidget);
  });
}
