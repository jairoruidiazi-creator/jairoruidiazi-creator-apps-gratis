import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre un punto en la app de mapas del sistema (Google Maps, Apple Maps,
/// OsmAnd, Waze…) y, si ninguna responde, en OpenStreetMap en el navegador.
Future<bool> openInMaps(double lat, double lon, {String label = ''}) async {
  final String q = '$lat,$lon';
  final List<Uri> candidates = <Uri>[
    if (!kIsWeb && Platform.isIOS) Uri.parse('maps://?ll=$q&q=${Uri.encodeComponent(label.isEmpty ? q : label)}'),
    Uri.parse('geo:$q?q=$q${label.isEmpty ? '' : '(${Uri.encodeComponent(label)})'}'),
    Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=18/$lat/$lon'),
  ];
  return _firstThatOpens(candidates);
}

/// Pide indicaciones hasta el punto en la app de navegación del sistema.
Future<bool> navigateTo(double lat, double lon) async {
  final String q = '$lat,$lon';
  final List<Uri> candidates = <Uri>[
    if (!kIsWeb && Platform.isIOS) Uri.parse('maps://?daddr=$q&dirflg=d'),
    if (!kIsWeb && Platform.isAndroid) Uri.parse('google.navigation:q=$q'),
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q'),
  ];
  return _firstThatOpens(candidates);
}

Future<bool> _firstThatOpens(List<Uri> candidates) async {
  for (final Uri u in candidates) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}
