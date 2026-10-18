// Ayudante de las capturas de tienda. La copia canónica vive en
// tools/store/dart/store_shots.dart y cada app tiene una copia idéntica en
// test/store/store_shots.dart (tools/store/check_metadata.py lo verifica).
//
// Las pruebas con la etiqueta "screenshots" dibujan pantallas reales de la app
// con datos de ejemplo y las guardan en PNG a la resolución de cada
// dispositivo. tools/store/compose_screenshots.py les pone después el titular
// y el fondo de la ficha de tienda.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un dispositivo de referencia de las tiendas.
class StoreDevice {
  const StoreDevice({required this.id, required this.physicalSize, required this.pixelRatio, required this.platform, required this.top, required this.bottom});

  /// android_phone, android_tablet, iphone o ipad.
  final String id;

  /// Tamaño en píxeles físicos de la captura cruda.
  final Size physicalSize;
  final double pixelRatio;
  final TargetPlatform platform;

  /// Barra de estado y barra de gestos o indicador de inicio, en puntos lógicos.
  final double top;
  final double bottom;

  bool get isIOS => platform == TargetPlatform.iOS;
  bool get isTablet => physicalSize.shortestSide / pixelRatio >= 600;
  Size get logicalSize => physicalSize / pixelRatio;

  /// Teléfono Android de 6,3" (1080 × 2400).
  static const StoreDevice androidPhone = StoreDevice(id: 'android_phone', physicalSize: Size(1080, 2400), pixelRatio: 2.625, platform: TargetPlatform.android, top: 24, bottom: 16);

  /// Tableta Android de 10" en vertical (1600 × 2560).
  static const StoreDevice androidTablet = StoreDevice(id: 'android_tablet', physicalSize: Size(1600, 2560), pixelRatio: 2, platform: TargetPlatform.android, top: 24, bottom: 16);

  /// iPhone de 6,9" (1320 × 2868), el tamaño que exige App Store Connect.
  static const StoreDevice iphone = StoreDevice(id: 'iphone', physicalSize: Size(1320, 2868), pixelRatio: 3, platform: TargetPlatform.iOS, top: 62, bottom: 34);

  /// iPad de 13" (2064 × 2752), obligatorio si la app corre en iPad.
  static const StoreDevice ipad = StoreDevice(id: 'ipad', physicalSize: Size(2064, 2752), pixelRatio: 2, platform: TargetPlatform.iOS, top: 24, bottom: 20);

  static const List<StoreDevice> all = <StoreDevice>[androidPhone, androidTablet, iphone, ipad];

  /// Ajusta la vista de la prueba a este dispositivo.
  void apply(WidgetTester tester) {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = pixelRatio;
    final FakeViewPadding padding = FakeViewPadding(top: top * pixelRatio, bottom: bottom * pixelRatio);
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
    // Pantalla táctil: sin anillos de foco de teclado en las capturas.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }
}

/// Idiomas de las fichas: español (principal) e inglés.
const List<String> storeLanguages = <String>['es', 'en'];

/// Carpeta de salida (variable de entorno STORE_SHOTS_DIR o build/store_shots).
String get storeShotsDir => Platform.environment['STORE_SHOTS_DIR'] ?? 'build/store_shots';

Future<void>? _fontsLoaded;

/// Carga las fuentes reales: las de la app y sus paquetes (FontManifest.json,
/// incluidos MaterialIcons y CupertinoIcons), Roboto para Android e Inter con
/// los nombres de la fuente del sistema de iOS. Sin esto las pruebas dibujan
/// cajas en lugar de letras.
Future<void> loadStoreFonts(WidgetTester tester) async {
  await tester.runAsync(() => _fontsLoaded ??= _loadFonts());
}

Future<void> _loadFonts() async {
  final String manifest = await rootBundle.loadString('FontManifest.json');
  for (final dynamic family in json.decode(manifest) as List<dynamic>) {
    final Map<String, dynamic> f = family as Map<String, dynamic>;
    final FontLoader loader = FontLoader(f['family'] as String);
    for (final dynamic font in f['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load((font as Map<String, dynamic>)['asset'] as String));
    }
    await loader.load();
  }
  final Directory dir = Directory('../../tools/store/fonts');
  Future<void> family(String name, String prefix) async {
    final List<File> files = dir.listSync().whereType<File>().where((File f) {
      final String base = f.uri.pathSegments.last;
      return base.startsWith(prefix) && base.endsWith('.ttf');
    }).toList();
    if (files.isEmpty) {
      throw StateError('No están las fuentes $prefix* en ${dir.absolute.path}');
    }
    final FontLoader loader = FontLoader(name);
    for (final File file in files) {
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Roboto', 'Roboto-');
  await family('CupertinoSystemText', 'Inter-');
  await family('CupertinoSystemDisplay', 'Inter-');
}

/// Raíz de las capturas: envuelve la app para poder dibujarla en una imagen.
final GlobalKey storeShotBoundary = GlobalKey(debugLabel: 'store_shot');

Widget storeShotRoot(Widget app) => RepaintBoundary(key: storeShotBoundary, child: app);

/// Termina de decodificar las imágenes visibles (archivos, recursos y memoria),
/// deja pasar las animaciones y vuelve a dibujar. Con [settle] en falso no
/// espera a que todo quede quieto (pantallas con animación continua, como un
/// metrónomo en marcha): solo avanza [extra].
///
/// La decodificación usa E/S real, pero sus futuros viven en la zona de tiempo
/// falso de la prueba: esperarlos dentro de `runAsync` la bloquea para
/// siempre, porque nadie vacía esa zona mientras tanto. Por eso se alternan
/// turnos cortos de tiempo real con cuadros hasta que todas terminan.
Future<void> settleForShot(WidgetTester tester, {Duration extra = const Duration(milliseconds: 400), bool settle = true}) async {
  for (int round = 0; round < 3; round++) {
    int pending = 0;
    for (final Element e in find.byType(Image).evaluate()) {
      final Image image = e.widget as Image;
      pending += 1;
      unawaited(precacheImage(image.image, e).whenComplete(() => pending -= 1));
    }
    for (int i = 0; i < 150 && pending > 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    if (pending > 0) {
      throw StateError('$pending imágenes no terminaron de cargar');
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(extra);
  }
  if (settle) {
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  } else {
    await tester.pump(extra);
  }
}

void _repaintAll(WidgetTester tester) {
  void mark(RenderObject o) {
    o.markNeedsPaint();
    o.visitChildren(mark);
  }

  for (final RenderView view in tester.binding.renderViews) {
    mark(view);
  }
}

/// Guarda la pantalla actual como `<dir>/<dispositivo>/<idioma>/<nombre>.png`.
Future<void> takeStoreShot(WidgetTester tester, StoreDevice device, String lang, String name, {bool settle = true}) async {
  await settleForShot(tester, settle: settle);
  // Las pruebas dibujan las sombras como un borde negro (debugDisableShadows);
  // para la captura se repinta todo con sombras reales, como en el teléfono,
  // y al terminar se deja el valor de prueba (el marco lo verifica al final).
  debugDisableShadows = false;
  Uint8List? png;
  try {
    _repaintAll(tester);
    await tester.pump();
    final RenderRepaintBoundary boundary = storeShotBoundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    png = await tester.runAsync<Uint8List?>(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: device.pixelRatio);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    });
  } finally {
    debugDisableShadows = true;
    _repaintAll(tester);
  }
  if (png == null) {
    throw StateError('No se pudo dibujar la captura $name');
  }
  final File file = File('$storeShotsDir/${device.id}/$lang/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png);
  debugPrint('[captura] ${file.path} (${png.length ~/ 1024} KB)');
}
