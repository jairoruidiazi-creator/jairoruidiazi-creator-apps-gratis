import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../core/storage.dart';

/// Datos de la app en un archivo JSON propio, con guardado diferido (300 ms)
/// y síncrono: lo que se cambia queda en disco aunque la app se cierre justo
/// después, y un archivo dañado se aparta en vez de sobrescribirse.
abstract class PersistentStore extends ChangeNotifier {
  PersistentStore(this.store, this.file);

  final JsonStore store;
  final String file;
  Timer? _debounce;
  bool _dirty = false;

  /// Si el archivo no se pudo leer, dónde quedó apartado (se avisa en Ajustes).
  String? damagedCopy;

  /// Se llama después de cada cambio (por ejemplo, para reprogramar avisos).
  VoidCallback? onChanged;

  Map<String, dynamic> toJson();

  void fromJson(Map<String, dynamic> json);

  /// Deja el almacén vacío.
  void reset();

  bool get dirty => _dirty || _debounce != null;

  void load() {
    reset();
    final bool exists = store.existsSync(file);
    final Map<String, dynamic>? json = exists ? store.readJsonSync(file) : null;
    if (exists && json == null) {
      damagedCopy = store.setAsideSync(file, 'danado-${clock.now().millisecondsSinceEpoch}');
    } else if (json != null) {
      try {
        fromJson(json);
      } catch (e) {
        debugPrint('No se pudo leer $file: $e');
        reset();
        damagedCopy = store.setAsideSync(file, 'danado-${clock.now().millisecondsSinceEpoch}');
      }
    }
    notifyListeners();
  }

  /// Marca un cambio: avisa a la interfaz y programa el guardado.
  void changed() {
    _dirty = true;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), flush);
    onChanged?.call();
  }

  /// Escribe ya lo pendiente (al pasar a segundo plano o antes de exportar).
  void flush() {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) {
      return;
    }
    _dirty = false;
    try {
      store.writeJsonSync(file, toJson());
    } catch (e) {
      // Se reintenta en el siguiente cambio; los datos siguen en memoria.
      _dirty = true;
      debugPrint('No se pudo guardar $file: $e');
    }
  }

  @override
  void dispose() {
    flush();
    super.dispose();
  }
}
