import 'package:flutter/material.dart';

/// Las seis áreas del mapa de habilidades.
enum Area { logica, matematicas, lenguaje, ciencias, creatividad, socioemocional }

extension AreaX on Area {
  String get id {
    switch (this) {
      case Area.logica:
        return 'logica';
      case Area.matematicas:
        return 'matematicas';
      case Area.lenguaje:
        return 'lenguaje';
      case Area.ciencias:
        return 'ciencias';
      case Area.creatividad:
        return 'creatividad';
      case Area.socioemocional:
        return 'socioemocional';
    }
  }

  String get nombre {
    switch (this) {
      case Area.logica:
        return 'Razonamiento y lógica';
      case Area.matematicas:
        return 'Matemáticas';
      case Area.lenguaje:
        return 'Lenguaje y lectura';
      case Area.ciencias:
        return 'Ciencias y entorno';
      case Area.creatividad:
        return 'Creatividad y motricidad';
      case Area.socioemocional:
        return 'Emociones y hábitos';
    }
  }

  /// Nombre corto para los niños que ya leen.
  String get nombreCorto {
    switch (this) {
      case Area.logica:
        return 'Lógica';
      case Area.matematicas:
        return 'Números';
      case Area.lenguaje:
        return 'Letras';
      case Area.ciencias:
        return 'Ciencias';
      case Area.creatividad:
        return 'Arte';
      case Area.socioemocional:
        return 'Emociones';
    }
  }

  /// Emoji de Twemoji que identifica el área (código hexadecimal del archivo).
  String get emoji {
    switch (this) {
      case Area.logica:
        return '1f9e9'; // pieza de rompecabezas
      case Area.matematicas:
        return '1f522'; // 1234
      case Area.lenguaje:
        return '1f4d6'; // libro abierto
      case Area.ciencias:
        return '1f52c'; // microscopio
      case Area.creatividad:
        return '1f3a8'; // paleta
      case Area.socioemocional:
        return '1f49b'; // corazón amarillo
    }
  }

  Color get color {
    switch (this) {
      case Area.logica:
        return const Color(0xFF7C4DFF);
      case Area.matematicas:
        return const Color(0xFF2979FF);
      case Area.lenguaje:
        return const Color(0xFFFF7A00);
      case Area.ciencias:
        return const Color(0xFF2E9E5B);
      case Area.creatividad:
        return const Color(0xFFE91E63);
      case Area.socioemocional:
        return const Color(0xFF00897B);
    }
  }

  static Area? fromId(String? id) {
    for (final Area a in Area.values) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }
}
