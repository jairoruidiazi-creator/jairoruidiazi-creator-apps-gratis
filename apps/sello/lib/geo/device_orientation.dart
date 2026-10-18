import 'dart:math' as math;

import 'package:flutter/services.dart' show DeviceOrientation;

/// Orientaciones en el orden de los cuartos de vuelta en sentido horario que
/// hay que girar el contenido para verlo derecho: vertical, girado a la
/// izquierda (borde superior a la izquierda), invertido y girado a la derecha.
const List<DeviceOrientation> kOrientationsByTurn = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.portraitDown,
  DeviceOrientation.landscapeRight,
];

/// Cuartos de vuelta (0 a 3) de una orientación respecto a la vertical.
int orientationTurns(DeviceOrientation o) {
  switch (o) {
    case DeviceOrientation.portraitUp:
      return 0;
    case DeviceOrientation.landscapeLeft:
      return 1;
    case DeviceOrientation.portraitDown:
      return 2;
    case DeviceOrientation.landscapeRight:
      return 3;
  }
}

/// Cuartos de vuelta en sentido horario que hay que girar lo que se dibuja
/// sobre una interfaz en [ui] para que se vea derecho con el teléfono en
/// [physical] (0 si coinciden).
int quarterTurnsBetween(DeviceOrientation ui, DeviceOrientation physical) => (orientationTurns(physical) - orientationTurns(ui)) % 4;

bool isLandscapeOrientation(DeviceOrientation o) => o == DeviceOrientation.landscapeLeft || o == DeviceOrientation.landscapeRight;

/// Orientación física del teléfono a partir de la gravedad que mide el
/// acelerómetro (m/s²; ejes del teléfono: x a la derecha y y hacia arriba de
/// la pantalla; en vertical y ≈ +9,8).
///
/// - Con el teléfono casi plano (la gravedad casi perpendicular a la
///   pantalla) no hay forma de saber hacia dónde está "arriba": se conserva
///   [previous].
/// - Solo cambia cuando el giro pasa de 45° más [hysteresisDegrees] respecto
///   a [previous], para que no salte de una a otra en la diagonal.
DeviceOrientation orientationFromGravity(double x, double y, double z, DeviceOrientation previous, {double hysteresisDegrees = 10}) {
  final double norm = math.sqrt(x * x + y * y + z * z);
  final double planar = math.sqrt(x * x + y * y);
  if (norm < 1e-6 || planar < norm * 0.35) {
    return previous;
  }
  // 0° en vertical, +90° con el borde superior a la izquierda.
  final double angle = math.atan2(x, y) * 180 / math.pi;
  final double center = orientationTurns(previous) * 90.0;
  final double diff = ((angle - center) % 360 + 540) % 360 - 180;
  if (diff.abs() <= 45 + hysteresisDegrees) {
    return previous;
  }
  final int turns = (angle / 90).round() % 4;
  return kOrientationsByTurn[turns];
}
