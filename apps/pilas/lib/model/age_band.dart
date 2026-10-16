/// Tramos de edad de la app. Cada juego ajusta sus niveles a un tramo.
enum AgeBand { b3a4, b5a6, b7a8, b9a11 }

extension AgeBandX on AgeBand {
  int get minAge {
    switch (this) {
      case AgeBand.b3a4:
        return 3;
      case AgeBand.b5a6:
        return 5;
      case AgeBand.b7a8:
        return 7;
      case AgeBand.b9a11:
        return 9;
    }
  }

  int get maxAge {
    switch (this) {
      case AgeBand.b3a4:
        return 4;
      case AgeBand.b5a6:
        return 6;
      case AgeBand.b7a8:
        return 8;
      case AgeBand.b9a11:
        return 11;
    }
  }

  /// Etiqueta corta para adultos.
  String get label => '$minAge a $maxAge años';

  /// Etiqueta escolar aproximada (genérica para América Latina).
  String get schoolLabel {
    switch (this) {
      case AgeBand.b3a4:
        return 'Prejardín y jardín';
      case AgeBand.b5a6:
        return 'Transición y 1.º';
      case AgeBand.b7a8:
        return '2.º y 3.º';
      case AgeBand.b9a11:
        return '4.º y 5.º';
    }
  }

  /// Los niños de 3 a 6 años usan la interfaz sin lectura.
  bool get readsText => this == AgeBand.b7a8 || this == AgeBand.b9a11;

  /// Identificador estable para guardar en JSON.
  String get id {
    switch (this) {
      case AgeBand.b3a4:
        return '3-4';
      case AgeBand.b5a6:
        return '5-6';
      case AgeBand.b7a8:
        return '7-8';
      case AgeBand.b9a11:
        return '9-11';
    }
  }

  AgeBand? get next {
    final int i = AgeBand.values.indexOf(this);
    if (i + 1 < AgeBand.values.length) {
      return AgeBand.values[i + 1];
    }
    return null;
  }

  AgeBand? get previous {
    final int i = AgeBand.values.indexOf(this);
    if (i > 0) {
      return AgeBand.values[i - 1];
    }
    return null;
  }

  static AgeBand forAge(int age) {
    if (age <= 4) {
      return AgeBand.b3a4;
    }
    if (age <= 6) {
      return AgeBand.b5a6;
    }
    if (age <= 8) {
      return AgeBand.b7a8;
    }
    return AgeBand.b9a11;
  }

  static AgeBand? fromId(String? id) {
    for (final AgeBand b in AgeBand.values) {
      if (b.id == id) {
        return b;
      }
    }
    return null;
  }
}
