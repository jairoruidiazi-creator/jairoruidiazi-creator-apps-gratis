import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'settings.dart';
import 'sfx.dart';
import 'share.dart';
import 'speech.dart';
import 'storage.dart';

/// Servicios compartidos por toda la app.
class Services {
  Services({
    required this.settings,
    required this.voice,
    required this.sfx,
    required this.store,
    required this.state,
    Sharer? sharer,
  }) : sharer = sharer ?? Sharer();

  final AppSettings settings;
  final Voice voice;
  final Sfx sfx;
  final JsonStore store;
  final AppState state;

  /// Hoja de compartir del sistema.
  final Sharer sharer;
}

/// Pone los servicios al alcance del árbol y reconstruye cuando cambia el estado.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required this.services,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  final Services services;

  static Services of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  /// Igual que [of], pero sin suscribirse a los cambios.
  static Services read(BuildContext context) {
    final AppScope? scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  static AppState stateOf(BuildContext context) => of(context).state;
}
