import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/capture_session.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/model/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState st;
  late AppSettings settings;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_session');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await testSettings();
    st = await testState(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('Al cambiar de proyecto por cualquier vía los campos vuelven a sus valores iniciales (G8)', () async {
    final Project a = await st.addProject('A');
    a.fields.add(const FieldDef('k1', 'Lote', defaultValue: '1'));
    final Project b = await st.addProject('B');
    b.fields.add(const FieldDef('k2', 'Inspector', defaultValue: 'Ana'));
    await st.saveProjects();
    settings.currentProjectId = a.id;
    final CaptureSession s = CaptureSession(state: st, settings: settings, logoDecoder: (File f) async => null);
    expect(s.fields, <String, String>{'k1': '1'});
    s.setField('k1', '7');
    s.notes = 'Muro norte';
    // Activado desde la pestaña Proyectos (cambia el ajuste, no la hoja de datos).
    settings.currentProjectId = b.id;
    settings.refresh();
    expect(s.project.id, b.id);
    expect(s.fields, <String, String>{'k2': 'Ana'});
    // De vuelta en A: el 7 no reaparece.
    await s.selectProject(a.id);
    expect(s.fields, <String, String>{'k1': '1'});
    // Un campo nuevo en el proyecto activo aparece con su valor inicial; uno quitado desaparece.
    a.fields
      ..clear()
      ..add(const FieldDef('k3', 'Nivel', defaultValue: '2'));
    await st.saveProjects();
    expect(s.fields, <String, String>{'k3': '2'});
    // Borrar el proyecto activo deja el primero de la lista, sin arrastrar valores.
    await st.deleteProject(a.id);
    expect(s.project.id, 'general');
    expect(s.fields, isEmpty);
    s.dispose();
  });

  test('El logo se recarga si cambia en la plantilla o cambia la plantilla del proyecto (G6)', () async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
    final ui.Image image = await rec.endRecording().toImage(2, 2);
    final List<String> decoded = <String>[];
    Future<ui.Image?> decoder(File f) async {
      decoded.add(f.uri.pathSegments.last);
      return image;
    }

    for (final String name in <String>['a.png', 'b.png', 'c.png']) {
      await st.store.writeBytes('logos/$name', <int>[1, 2, 3]);
    }
    final CaptureSession s = CaptureSession(state: st, settings: settings, logoDecoder: decoder);
    await s.logoReady();
    expect(s.logo, isNull);
    final StampTemplate def = st.templateById('default');
    def.logoPath = 'logos/a.png';
    await st.saveProjects();
    await s.logoReady();
    expect(decoded, <String>['a.png']);
    expect(s.logo, isNotNull);
    // Cambiar el logo de la plantilla.
    def.logoPath = 'logos/b.png';
    await st.saveProjects();
    await s.logoReady();
    expect(decoded, <String>['a.png', 'b.png']);
    // Cambiar la plantilla del proyecto activo.
    final StampTemplate other = await st.addTemplate('Otra', copyOf: def);
    other.logoPath = 'logos/c.png';
    st.projectById('general').templateId = other.id;
    await st.saveProjects();
    await s.logoReady();
    expect(decoded, <String>['a.png', 'b.png', 'c.png']);
    // Quitar el logo.
    other.logoPath = null;
    await st.saveProjects();
    await s.logoReady();
    expect(s.logo, isNull);
    s.dispose();
  });

  test('Al reemplazar o quitar un logo el archivo viejo se borra si nadie más lo usa (M21)', () async {
    await st.store.writeBytes('logos/a.png', <int>[1]);
    final StampTemplate def = st.templateById('default')..logoPath = 'logos/a.png';
    final StampTemplate copy = await st.addTemplate('Copia', copyOf: def);
    expect(copy.logoPath, 'logos/a.png');
    // La copia comparte el archivo: quitárselo a una no lo borra.
    def.logoPath = null;
    await st.saveProjects();
    await st.deleteLogoIfUnused('logos/a.png');
    expect(await st.store.exists('logos/a.png'), isTrue);
    // Al borrar la última plantilla que lo usa, sí.
    await st.deleteTemplate(copy.id);
    expect(await st.store.exists('logos/a.png'), isFalse);
  });

  test('El editor de proyecto trabaja sobre una copia (M21)', () async {
    final Project live = await st.addProject('Obra');
    final Project draft = live.copy();
    draft.name = 'Obra cambiada';
    draft.fields.add(const FieldDef('k', 'Lote'));
    expect(live.name, 'Obra');
    expect(live.fields, isEmpty);
    live.assignFrom(draft);
    expect(live.name, 'Obra cambiada');
    expect(live.fields.single.label, 'Lote');
  });
}
