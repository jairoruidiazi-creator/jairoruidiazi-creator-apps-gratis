import 'package:flutter/widgets.dart';

import '../geo/declination.dart';
import '../geo/heading.dart';
import '../geo/location_service.dart';
import '../stamp/capture_pipeline.dart';
import '../stamp/stamp_queue.dart';
import 'app_state.dart';
import 'capture_session.dart';
import 'device_files.dart';
import 'keep_awake.dart';
import 'settings.dart';
import 'storage.dart';

class Services {
  Services({
    required this.settings,
    required this.state,
    required this.store,
    required this.location,
    required this.heading,
    this.declinationLink,
    CaptureSession? session,
    CapturePipeline? pipeline,
    StampQueue? queue,
    KeepAwake? keepAwake,
    DeviceFiles? files,
  })  : session = session ?? CaptureSession(state: state, settings: settings),
        pipeline = pipeline ?? CapturePipeline(store: store, state: state, settings: settings),
        keepAwake = keepAwake ?? const KeepAwake(),
        files = files ?? const DeviceFiles() {
    this.queue = queue ?? StampQueue(pipeline: this.pipeline);
  }

  /// Pantalla encendida con la cámara a la vista.
  final KeepAwake keepAwake;

  /// Espacio libre y documentos del sistema (copia completa en Android).
  final DeviceFiles files;

  /// Avisa a la pestaña activa cuando otra pantalla completa la tapa (la
  /// cámara se libera mientras tanto).
  final RouteObserver<PageRoute<dynamic>> routes = RouteObserver<PageRoute<dynamic>>();

  final AppSettings settings;
  final AppState state;
  final JsonStore store;
  final LocationService location;
  final HeadingService heading;

  /// Enlace GPS → declinación (nulo en pruebas).
  final DeclinationLink? declinationLink;

  /// Proyecto, campos, notas, etiquetas y logo de la próxima foto.
  final CaptureSession session;
  final CapturePipeline pipeline;

  /// Cola de sellado (una foto a la vez, con reanudación).
  late final StampQueue queue;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

/// Texto en el idioma de la app.
String t(BuildContext context, String es, String en) => AppScope.of(context).settings.spanish ? es : en;

/// Libera controladores después de que cierre el diálogo que los usaba.
void disposeLater(List<ChangeNotifier> controllers) {
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final ChangeNotifier c in controllers) {
      c.dispose();
    }
  });
}
