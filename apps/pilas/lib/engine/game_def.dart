import 'package:flutter/widgets.dart';

import '../model/age_band.dart';
import '../model/area.dart';
import '../model/profile.dart';

/// Datos con los que arranca un juego: el juego, el tramo y el perfil.
class GameLaunch {
  const GameLaunch({required this.game, required this.band, required this.profile});

  final GameDef game;
  final AgeBand band;
  final Profile profile;
}

typedef GameBuilder = Widget Function(BuildContext context, GameLaunch launch);

/// Definición de un juego: a qué área y tramos pertenece, qué habilidad
/// trabaja en cada tramo y cómo seguirla sin pantalla.
class GameDef {
  const GameDef({
    required this.id,
    required this.nombre,
    required this.area,
    required this.emoji,
    required this.minBand,
    required this.maxBand,
    required this.skills,
    required this.descripcion,
    required this.enCasa,
    required this.pregunta,
    required this.build,
    this.levels = 4,
    this.roundBased = true,
  });

  final String id;
  final String nombre;
  final Area area;

  /// Código Twemoji del ícono del juego.
  final String emoji;
  final AgeBand minBand;
  final AgeBand maxBand;

  /// Habilidad del mapa que trabaja en cada tramo.
  final Map<AgeBand, String> skills;

  /// Qué trabaja, para la ficha del adulto.
  final String descripcion;

  /// Cómo seguir la habilidad sin pantalla.
  final String enCasa;

  /// Qué preguntarle al niño después de jugar.
  final String pregunta;
  final GameBuilder build;

  /// Niveles por tramo.
  final int levels;

  /// Los juegos libres (colorear, dibujar) no tienen rondas ni niveles.
  final bool roundBased;

  bool supports(AgeBand band) => band.index >= minBand.index && band.index <= maxBand.index;

  int levelsFor(AgeBand band) => levels;

  String? skillFor(AgeBand band) => skills[band];
}
