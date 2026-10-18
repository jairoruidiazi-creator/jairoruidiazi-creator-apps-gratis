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
  Future<bool> isEnabled();
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
  final List<RawNotice> pending = <RawNotice>[];
  final StreamController<RawNotice> controller = StreamController<RawNotice>.broadcast();

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> openSettings() async {
    enabled = true;
    return true;
  }

  @override
  Future<List<RawNotice>> readPending() async => List<RawNotice>.from(pending);

  @override
  Future<void> clearPending() async => pending.clear();

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

  /// Arranca la escucha en vivo y procesa lo pendiente.
  Future<void> start() async {
    if (!settings.noticesEnabled) {
      return;
    }
    await pull();
    _sub ??= bridge.live.listen((RawNotice n) => unawaited(handle(n)));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Procesa los avisos guardados mientras la app estaba cerrada.
  Future<int> pull() async {
    if (!settings.noticesEnabled) {
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
  Future<bool> handle(RawNotice n) async {
    final BankSuggestion? s = BankRules.parse(packageName: n.package, title: n.title, text: n.text);
    if (s == null) {
      return false;
    }
    final InboxItem item = InboxItem(id: newId(), bank: s.bank, kind: s.kind, amountMinor: s.amountMinor, currency: s.currency, merchant: s.merchant, last4: s.last4, receivedAt: n.time, rawTitle: n.title, rawText: n.text);
    final InboxItem stored = await ledger.addInbox(item);
    if (!identical(stored, item)) {
      return false; // duplicado
    }
    if (settings.noticesAutoPost && stored.accountId != null) {
      await ledger.acceptInbox(stored);
    }
    return true;
  }
}
