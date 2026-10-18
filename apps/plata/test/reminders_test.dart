// G16 del informe de auditoría: los recordatorios se reprograman solos cada
// vez que cambia algo del libro o de los ajustes, no solo al abrir la app.

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

void main() {
  test('G16: un programado nuevo, uno editado o el idioma reprograman los avisos', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('plata_rem');
    await withClock(Clock.fixed(DateTime(2026, 10, 16, 8)), () async {
      final Ledger l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => DateTime(2026, 10, 16, 8));
      await l.load();
      final AppSettings settings = AppSettings()..billReminders = true;
      final NoopNotifier n = NoopNotifier();
      final ReminderScheduler r = ReminderScheduler(ledger: l, settings: settings, notifier: n, delay: const Duration(milliseconds: 20));
      Future<void> later() => Future<void>.delayed(const Duration(milliseconds: 150));
      r.start();
      final Scheduled s = await l.addScheduled(Scheduled(id: 's', name: 'Arriendo', kind: TxKind.expense, amountMinor: 150000000, accountId: 'a_cash', nextDate: DateTime(2026, 10, 20)));
      await later();
      expect(r.syncs, 1);
      expect(n.log.any((String x) => x.startsWith('at:100:2026-10-19T09:00') && x.contains('Arriendo')), isTrue);
      // Varios cambios seguidos se agrupan en una sola sincronización.
      n.log.clear();
      s.name = 'Arriendo apartamento';
      s.nextDate = DateTime(2026, 10, 25);
      l.save();
      l.save();
      await later();
      expect(r.syncs, 2);
      expect(n.log.any((String x) => x.startsWith('at:100:2026-10-24T09:00') && x.contains('Arriendo apartamento')), isTrue);
      // Otro idioma: el canal y los textos cambian.
      settings.language = 'en';
      settings.refresh();
      await later();
      expect(r.syncs, 3);
      expect(n.spanish, isFalse);
      expect(n.log.any((String x) => x.contains('Coming up: Arriendo apartamento')), isTrue);
      // Desactivar los recordatorios de pagos los quita.
      n.log.clear();
      settings.billReminders = false;
      settings.refresh();
      await later();
      expect(n.log, <String>['cancelAll']);
      r.stop();
      l.save();
      await later();
      expect(r.syncs, 4);
      l.dispose();
    });
    await tmp.delete(recursive: true);
  });
}
