import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'core/settings.dart';
import 'core/storage.dart';
import 'geo/declination.dart';
import 'geo/geoid.dart';
import 'geo/heading.dart';
import 'geo/location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore();
  // Lo exportado ya se compartió: la copia de la app se borra al abrirla de nuevo.
  await store.clear('exports');
  final AppState state = AppState(store);
  await state.load();
  try {
    await Geoid.load();
  } catch (e) {
    debugPrint('Sin rejilla del geoide: $e');
  }
  final LocationService location = LocationService()
    ..geocodingEnabled = settings.geocoding
    ..localeIdentifier = settings.spanish ? 'es_CO' : 'en_US';
  final HeadingService heading = HeadingService();
  final DeclinationLink declinationLink = DeclinationLink(settings: settings, location: location, heading: heading);
  runApp(SelloApp(services: Services(settings: settings, state: state, store: store, location: location, heading: heading, declinationLink: declinationLink)));
  WidgetsBinding.instance.addPostFrameCallback((_) => lockPhonePortrait());
}

/// Los teléfonos van en vertical; las tabletas (lado corto de 600 dp o más)
/// giran libremente. En iPhone lo mismo lo fija el Info.plist.
void lockPhonePortrait() {
  final FlutterView? view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null || view.devicePixelRatio <= 0) {
    return;
  }
  final double shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortest > 0 && shortest < 600) {
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]));
  }
}
