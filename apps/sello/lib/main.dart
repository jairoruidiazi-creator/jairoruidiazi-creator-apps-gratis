import 'package:flutter/material.dart';

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
}
