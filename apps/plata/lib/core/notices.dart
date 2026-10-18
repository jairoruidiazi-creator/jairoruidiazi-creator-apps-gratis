import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import 'bank_rules.dart';
import 'ledger.dart';
import 'settings.dart';

/// Aviso crudo recibido del sistema.
class RawNotice {
  const RawNotice({required this.package, required this.title, required this.text, required this.time});

  final String package;
  final String title;
  final String text;
  final DateTime time;

  static RawNotice? fromMap(Object? o) {
    if (o is! Map) {
      return null;
    }
    final Map<Object?, Object?> m = o;
    final int ms = (m['time'] as num?)?.toInt() ?? clock.now().millisecondsSinceEpoch;
    return RawNotice(package: (m['package'] ?? '').toString(), title: (m['title'] ?? '').toString(), text: (m['text'] ?? '').toString(), time: DateTime.fromMillisecondsSinceEpoch(ms));
  }
}

/// Puente con el servicio nativo de Android (ver native/android).
abstract class NoticeBridge {
  Future<bool> isSupported();

  /// Si el usuario concedió el "Acceso a notificaciones" en Android.
  Future<bool> isEnabled();

  /// Enciende o apaga la lectura en el servicio nativo. Apagada, el servicio
  /// ignora todo aviso aunque el permiso del sistema siga concedido, y borra
  /// los que tenía guardados.
  Future<void> setEnabled(bool on);
  Future<bool> openSettings();
  Future<List<RawNotice>> readPending();
  Future<void> clearPending();
  Stream<RawNotice> get live;
}

class PlatformNoticeBridge implements NoticeBridge {
  static const MethodChannel _m = MethodChannel('co.appsgratis.plata/notices');
  static const EventChannel _e = EventChannel('co.appsgratis.plata/notices/stream');

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isSupported() async {
    if (!_android) {
      return false;
    }
    try {
      return await _m.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnabled() async {
    if (!_android) {
      return false;
    }
    try {
      return await _m.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool on) async {
    if (!_android) {
      return;
    }
    try {
      await _m.invokeMethod<bool>('setEnabled', on);
    } catch (e) {
      debugPrint('Avisos (setEnabled): $e');
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await _m.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<RawNotice>> readPending() async {
    if (!_android) {
      return <RawNotice>[];
    }
    try {
      final List<Object?>? list = await _m.invokeListMethod<Object?>('readPending');
      return (list ?? <Object?>[]).map(RawNotice.fromMap).whereType<RawNotice>().toList();
    } catch (_) {
      return <RawNotice>[];
    }
  }

  @override
  Future<void> clearPending() async {
    if (!_android) {
      return;
    }
    try {
      await _m.invokeMethod<void>('clearPending');
    } catch (_) {}
  }

  @override
  Stream<RawNotice> get live => _android ? _e.receiveBroadcastStream().map(RawNotice.fromMap).where((RawNotice? n) => n != null).cast<RawNotice>() : const Stream<RawNotice>.empty();
}

class FakeNoticeBridge implements NoticeBridge {
  FakeNoticeBridge({this.supported = true, this.enabled = true});

  bool supported;
  bool enabled;

  /// Estado de la bandera del servicio nativo (null = nunca se fijó).
  bool? capturing;
  int cleared = 0;
  final List<RawNotice> pending = <RawNotice>[];
  final StreamController<RawNotice> controller = StreamController<RawNotice>.broadcast();

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool on) async {
    capturing = on;
    if (!on) {
      pending.clear();
    }
  }

  @override
  Future<bool> openSettings() async {
    enabled = true;
    return true;
  }

  @override
  Future<List<RawNotice>> readPending() async => List<RawNotice>.from(pending);

  @override
  Future<void> clearPending() async {
    cleared += 1;
    pending.clear();
  }

  @override
  Stream<RawNotice> get live => controller.stream;
}

/// Convierte los avisos en sugerencias de la bandeja (o en movimientos, si
/// el usuario pidió anotarlos solos).
class NoticeService {
  NoticeService({required this.bridge, required this.ledger, required this.settings});

  final NoticeBridge bridge;
  final Ledger ledger;
  final AppSettings settings;
  StreamSubscription<RawNotice>? _sub;

  /// Sincroniza la bandera nativa con el ajuste, escucha en vivo y procesa lo
  /// pendiente. Con la lectura apagada, borra lo que hubiera quedado guardado.
  /// Mientras el libro no se pueda abrir (modo de recuperación) no procesa ni
  /// borra nada: los avisos esperan a que se restaure una copia.
  Future<void> start() async {
    await bridge.setEnabled(settings.noticesEnabled);
    if (!settings.noticesEnabled) {
      await stop();
      await bridge.clearPending();
      return;
    }
    if (ledger.readOnly) {
      return;
    }
    await pull();
    _sub ??= bridge.live.listen((RawNotice n) => unawaited(handle(n)));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Apaga la lectura: deja de escuchar, apaga el servicio nativo y borra los
  /// avisos que estaban esperando.
  Future<void> disable() async {
    await stop();
    await bridge.setEnabled(false);
    await bridge.clearPending();
  }

  /// Procesa los avisos guardados mientras la app estaba cerrada.
  Future<int> pull() async {
    if (!settings.noticesEnabled || ledger.readOnly) {
      return 0;
    }
    final List<RawNotice> list = await bridge.readPending();
    int added = 0;
    for (final RawNotice n in list) {
      if (await handle(n)) {
        added += 1;
      }
    }
    await bridge.clearPending();
    return added;
  }

  /// Interpreta un aviso y lo deja en la bandeja; devuelve si produjo algo.
  ///
  /// Con "Anotar sin preguntar" solo se anota directo un gasto o un ingreso
  /// cuya cuenta se identificó sin dudas ([NoticeMatch.certain]), en la misma
  /// moneda de la cuenta y que no parece repetir un movimiento ya anotado
  /// ([InboxItem.duplicateOf]). Pagos de tarjeta, retiros, movimientos entre
  /// cuentas propias y reversos siempre quedan para revisar.
  Future<bool> handle(RawNotice n) async {
    if (!settings.noticesEnabled || ledger.readOnly) {
      return false;
    }
    final BankSuggestion? s = BankRules.parse(packageName: n.package, title: n.title, text: n.text);
    if (s == null) {
      return false;
    }
    final InboxItem item = InboxItem(id: newId(), bank: s.bank, kind: s.kind, amountMinor: s.amountMinor, currency: s.currency, merchant: s.merchant, last4: s.last4, toLast4: s.toLast4, flow: s.flow, receivedAt: n.time, rawTitle: n.title, rawText: n.text);
    final InboxItem stored = await ledger.addInbox(item);
    if (!identical(stored, item)) {
      return false; // duplicado
    }
    // Un reverso o devolución, o un aviso que parece repetir un movimiento ya
    // anotado (un programado, algo anotado a mano), siempre se revisa.
    if (settings.noticesAutoPost && stored.kind != TxKind.transfer && stored.flow != NoticeFlow.refund && stored.duplicateOf == null) {
      final NoticeMatch m = ledger.matchNotice(stored);
      if (m.certain && m.account != null && m.account!.currency == stored.currency) {
        await ledger.acceptInbox(stored, accountId: m.account!.id);
      }
    }
    return true;
  }
}
