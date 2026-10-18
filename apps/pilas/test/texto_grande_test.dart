import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/parent/family_guide_screen.dart';
import 'package:pilas/ui/parent/parent_panel.dart';
import 'package:pilas/ui/parent/settings_screen.dart';
import 'package:pilas/ui/parent/teacher_screen.dart';
import 'package:pilas/ui/profile_edit_screen.dart';
import 'package:pilas/ui/profiles_screen.dart';
import 'package:pilas/ui/stickers_screen.dart';

import 'support/harness.dart';

/// M11: con la letra al doble (el tope de la app, 200 %), las pantallas
/// fuera de los juegos caben en un teléfono de 360 dp, de pie y acostado,
/// sin desbordes. (Los juegos los revisa test/games_smoke_test.dart.)
void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  final Map<String, Widget Function()> pantallas = <String, Widget Function()>{
    'perfiles': () => const ProfilesScreen(),
    'inicio del niño': () => const KidHomeScreen(),
    'pegatinas': () => const StickersScreen(),
    'editar perfil': () => const ProfileEditScreen(),
    'panel de adultos': () => const ParentPanel(),
    'ajustes': () => const SettingsScreen(),
    'modo docente': () => const TeacherScreen(),
    'guía para familias': () => const FamilyGuideScreen(),
  };

  for (final Size tamano in <Size>[const Size(360, 740), const Size(740, 360)]) {
    pantallas.forEach((String nombre, Widget Function() pantalla) {
      testWidgets('$nombre cabe con la letra al doble en ${tamano.width.toInt()} × ${tamano.height.toInt()}', (WidgetTester tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final List<String> errores = <String>[];
        final FlutterExceptionHandler? antes = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) => errores.add(d.toString());
        addTearDown(() => FlutterError.onError = antes);
        late Profile p;
        await tester.runAsync(() async {
          p = await h.state.addProfile(nombre: 'Valentina', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
        });
        h.state.current = p;
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(tamano.width * 3, tamano.height * 3);
        await tester.pumpWidget(h.app(pantalla(), textScale: 2.0, navigatorKey: GlobalKey<NavigatorState>()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => h.state.pauseClock());
        FlutterError.onError = antes;
        expect(errores, isEmpty, reason: errores.join('\n----\n'));
      });
    });
  }
}
