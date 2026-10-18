import 'package:flutter/foundation.dart';

import 'app_scope.dart';
import 'crypto_store.dart';

/// Borra todo lo que Plata guarda en el teléfono (cuentas, movimientos,
/// presupuestos, fotos de recibos, copias automáticas, avisos pendientes, la
/// clave de acceso y la llave de cifrado) y deja la app como recién instalada,
/// con el mismo idioma. Es la salida cuando se olvida la clave: sin ella los
/// datos no se pueden abrir, pero la app vuelve a servir y se puede restaurar
/// una copia cifrada con contraseña.
Future<void> wipeAllData(Services s) async {
  try {
    await s.notices.disable();
  } catch (e) {
    debugPrint('Borrar todo (avisos): $e');
  }
  await s.ledger.discardPendingWrites();
  await s.store.wipe();
  await s.keys.deleteAll();
  // Llave nueva: lo que se escriba de aquí en adelante no depende de la vieja.
  s.ledger.store.box = await CryptoBox.fromKeyStore(s.keys);
  await s.lock.reset();
  await s.settings.resetAll();
  try {
    await s.notifier.cancelAll();
  } catch (e) {
    debugPrint('Borrar todo (recordatorios): $e');
  }
  await s.ledger.startFresh();
}
