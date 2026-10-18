import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/model/progress.dart';

/// Reloj que se adelanta a mano.
class RelojFalso {
  RelojFalso(this.ahora);

  DateTime ahora;

  Clock get clock => Clock(() => ahora);

  void avanza(Duration d) => ahora = ahora.add(d);
}

void main() {
  late Directory tmp;
  late JsonStore store;
  final GameDef patrones = GameRegistry.byId('patrones')!;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pilas_state');
    store = JsonStore(root: tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<AppState> nueva({int limite = 20}) async {
    final AppState s = AppState(store)..sessionLimitMinutes = () => limite;
    await s.load();
    return s;
  }

  group('B1: el avance nunca se pisa con uno vacío', () {
    test('Abrir el panel (leer el avance de todos) y luego jugar conserva el nivel', () async {
      final AppState a = await nueva();
      final Profile ana = await a.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
      await a.selectProfile(ana);
      for (int i = 0; i < 6; i++) {
        await a.recordRound(patrones, AgeBand.b5a6, true);
      }
      expect(a.progressOf(ana.id).masteryIfAny('patrones', AgeBand.b5a6)!.level, 2);
      await a.selectProfile(null);
      a.dispose();

      // La app se abre otra vez: el adulto entra al panel (que lee el avance
      // de todos los niños) y después el niño juega una ronda.
      final AppState b = await nueva();
      final Profile ana2 = b.profileById(ana.id)!;
      expect(b.progressOf(ana2.id).masteryIfAny('patrones', AgeBand.b5a6)?.level, 2);
      await b.selectProfile(ana2);
      await b.recordRound(patrones, AgeBand.b5a6, false);
      expect(b.progressOf(ana2.id).masteryIfAny('patrones', AgeBand.b5a6)!.level, 2);
      expect(b.progressOf(ana2.id).stickers.length, 1);
      await b.selectProfile(null);
      b.dispose();

      // Y en el disco quedó el avance completo.
      final AppState c = await nueva();
      expect(c.progressOf(ana.id).masteryIfAny('patrones', AgeBand.b5a6)!.roundsPlayed, 7);
      expect(c.progressOf(ana.id).stickers.length, 1);
      c.dispose();
    });

    test('Pedir el avance de un perfil desconocido no crea nada que se guarde', () async {
      final AppState a = await nueva();
      final ProfileProgress p = a.progressOf('no-existe');
      p.masteryFor('patrones', AgeBand.b3a4).level = 3;
      await a.saveProgress('no-existe');
      expect(File(await store.absolutePath('progress/no-existe.json')).existsSync(), isFalse);
      a.dispose();
    });

    test('Importar junta el avance sin borrarlo ni inflarlo', () async {
      final AppState a = await nueva();
      final Profile ana = await a.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
      await a.selectProfile(ana);
      for (int i = 0; i < 6; i++) {
        await a.recordRound(patrones, AgeBand.b5a6, true);
      }
      final Map<String, dynamic> datos = await a.exportAll();
      await a.recordRound(patrones, AgeBand.b5a6, true);
      final int n = await a.importAll(datos);
      expect(n, 1);
      final ProfileProgress p = a.progressOf(ana.id);
      expect(p.masteryIfAny('patrones', AgeBand.b5a6)!.level, 2);
      // Lo jugado después de exportar no se pierde, y lo que ya estaba no se
      // cuenta dos veces aunque se importe otra vez el mismo archivo.
      expect(p.masteryIfAny('patrones', AgeBand.b5a6)!.roundsPlayed, 7);
      await a.importAll(datos);
      expect(a.progressOf(ana.id).masteryIfAny('patrones', AgeBand.b5a6)!.roundsPlayed, 7);
      expect(a.profiles.length, 1);
      expect(p.stickers.length, 1);
      await expectLater(a.importAll(<String, dynamic>{'app': 'otra'}), throwsFormatException);
      await expectLater(a.importAll(<String, dynamic>{'app': 'pilas', 'profiles': 'basura'}), throwsFormatException);
      a.dispose();
    });
  });

  group('G1: tiempo por sesión, solo en primer plano, con descanso que persiste', () {
    test('Solo cuenta el tiempo en primer plano y la sesión termina tras 10 minutos sin jugar', () async {
      final RelojFalso r = RelojFalso(DateTime(2026, 3, 2, 9));
      await withClock(r.clock, () async {
        final AppState s = await nueva();
        final Profile ana = await s.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        await s.selectProfile(ana);
        r.avanza(const Duration(minutes: 5));
        await s.tick();
        expect(s.sessionSeconds, 300);
        // Segundo plano 3 minutos: no cuenta y la sesión sigue.
        await s.pauseClock();
        r.avanza(const Duration(minutes: 3));
        await s.resumeClock();
        expect(s.sessionSeconds, 300);
        r.avanza(const Duration(minutes: 2));
        await s.tick();
        expect(s.sessionSeconds, 420);
        // Segundo plano 30 minutos: la sesión se cerró y empieza otra.
        await s.pauseClock();
        r.avanza(const Duration(minutes: 30));
        await s.resumeClock();
        expect(s.sessionSeconds, 0);
        final ProfileProgress p = s.progressOf(ana.id);
        expect(p.sessions.length, 1);
        expect(p.sessions.first.seconds, 420);
        // La sesión cerrada no se cuenta dos veces.
        expect(p.secondsOn(r.ahora), 420);
        s.dispose();
      });
    });

    test('Al cumplirse el límite empieza un descanso que no se salta cerrando la app', () async {
      final RelojFalso r = RelojFalso(DateTime(2026, 3, 2, 9));
      await withClock(r.clock, () async {
        final AppState s = await nueva();
        final Profile ana = await s.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        final Profile beto = await s.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1);
        int descansos = 0;
        s.onRestStarted = () => descansos += 1;
        await s.selectProfile(ana);
        for (int i = 0; i < 19; i++) {
          r.avanza(const Duration(minutes: 1));
          await s.tick();
        }
        expect(s.isResting(ana.id), isFalse);
        r.avanza(const Duration(minutes: 1));
        await s.tick();
        expect(descansos, 1);
        expect(s.isResting(ana.id), isTrue);
        expect(s.restRemaining(ana.id), const Duration(minutes: 10));
        // Cada niño tiene su tiempo: Beto no descansa, pero cambiar de jugador
        // mientras Ana descansa pide la puerta (la pantalla de perfiles lo usa).
        expect(s.isResting(beto.id), isFalse);
        expect(s.restingProfileOtherThan(beto.id)?.id, ana.id);
        s.dispose();

        // Se cierra y se abre la app dos minutos después: el descanso sigue.
        r.avanza(const Duration(minutes: 2));
        final AppState s2 = await nueva();
        expect(s2.isResting(ana.id), isTrue);
        expect(s2.restRemaining(ana.id), const Duration(minutes: 8));
        await s2.selectProfile(s2.profileById(ana.id));
        expect(s2.counting, isFalse);
        // Termina el descanso: la sesión nueva empieza de cero.
        r.avanza(const Duration(minutes: 8));
        expect(s2.isResting(ana.id), isFalse);
        await s2.finishRest();
        expect(s2.sessionSeconds, 0);
        expect(s2.counting, isTrue);
        s2.dispose();
      });
    });

    test('Un adulto da 10 minutos más', () async {
      final RelojFalso r = RelojFalso(DateTime(2026, 3, 2, 9));
      await withClock(r.clock, () async {
        final AppState s = await nueva(limite: 10);
        final Profile ana = await s.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        await s.selectProfile(ana);
        r.avanza(const Duration(minutes: 10));
        await s.tick();
        expect(s.isResting(ana.id), isTrue);
        r.avanza(const Duration(minutes: 1));
        await s.grantExtraTime();
        expect(s.isResting(ana.id), isFalse);
        r.avanza(const Duration(minutes: 9));
        await s.tick();
        expect(s.isResting(ana.id), isFalse);
        r.avanza(const Duration(minutes: 1));
        await s.tick();
        expect(s.isResting(ana.id), isTrue);
        s.dispose();
      });
    });

    test('Si el reloj del teléfono se atrasa, el descanso no se alarga', () async {
      final RelojFalso r = RelojFalso(DateTime(2026, 3, 2, 9));
      await withClock(r.clock, () async {
        final AppState s = await nueva(limite: 5);
        final Profile ana = await s.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        await s.selectProfile(ana);
        r.avanza(const Duration(minutes: 5));
        await s.tick();
        expect(s.isResting(ana.id), isTrue);
        s.dispose();
        r.avanza(const Duration(hours: -3));
        final AppState s2 = await nueva(limite: 5);
        expect(s2.restRemaining(ana.id), lessThanOrEqualTo(AppState.restLength));
        s2.dispose();
      });
    });
  });
}
