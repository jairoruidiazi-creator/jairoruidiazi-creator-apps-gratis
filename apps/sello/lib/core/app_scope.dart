import 'package:flutter/widgets.dart';

import '../geo/declination.dart';
import '../geo/heading.dart';
import '../geo/location_service.dart';
import 'app_state.dart';
import 'settings.dart';
import 'storage.dart';

class Services {
  const Services({required this.settings, required this.state, required this.store, required this.location, required this.heading, this.declinationLink});

  final AppSettings settings;
  final AppState state;
  final JsonStore store;
  final LocationService location;
  final HeadingService heading;

  /// Enlace GPS → declinación (nulo en pruebas).
  final DeclinationLink? declinationLink;
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
