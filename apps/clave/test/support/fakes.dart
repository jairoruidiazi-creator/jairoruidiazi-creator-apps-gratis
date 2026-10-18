// Dobles de prueba compartidos: micrófono, captura de tomas, acciones del
// sistema y un juego de servicios con el motor de audio mudo.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clave/audio/audio_engine.dart';
import 'package:clave/audio/click_synth.dart';
import 'package:clave/audio/drone.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/audio/haptics.dart';
import 'package:clave/audio/metronome.dart';
import 'package:clave/audio/mic_capture.dart';
import 'package:clave/audio/take_recorder.dart';
import 'package:clave/audio/tuner.dart';
import 'package:clave/core/app_scope.dart';
import 'package:clave/core/app_state.dart';
import 'package:clave/core/platform_actions.dart';
import 'package:clave/core/practice_log.dart';
import 'package:clave/core/service_links.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/core/storage.dart';
import 'package:clave/model/models.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show RecordState;
import 'package:share_plus/share_plus.dart' show ShareParams;

/// Micrófono de prueba: cuenta aperturas y cierres y deja inyectar muestras.
class FakeMic implements MicCapture {
  FakeMic({this.granted = true, this.grantOnRequest = true});

  bool granted;

  /// Lo que responde la persona al diálogo del sistema.
  bool grantOnRequest;
  int requests = 0;
  int starts = 0;
  int stops = 0;
  bool open = false;
  StreamController<Uint8List>? _data;
  final StreamController<bool> _paused = StreamController<bool>.broadcast();

  @override
  Future<bool> hasPermission({bool request = true}) async {
    if (request && !granted) {
      requests++;
      granted = grantOnRequest;
    }
    return granted;
  }

  @override
  Future<Stream<Uint8List>> start(int sampleRate) async {
    starts++;
    open = true;
    final StreamController<Uint8List> c = StreamController<Uint8List>();
    _data = c;
    return c.stream;
  }

  /// Entrega muestras como si llegaran del micrófono.
  void push(Float32List samples) {
    _data?.add(floatToPcm16(samples));
  }

  /// El sistema pausa o reanuda la captura (llamada, Siri).
  void systemPause(bool value) => _paused.add(value);

  @override
  Future<void> stop() async {
    if (!open) {
      return;
    }
    open = false;
    stops++;
    final StreamController<Uint8List>? c = _data;
    _data = null;
    unawaited(c?.close());
  }

  @override
  Stream<bool> get paused => _paused.stream;

  @override
  Future<void> dispose() async {
    await stop();
    unawaited(_paused.close());
  }
}

/// Captura de tomas de prueba: escribe un archivo pequeño y deja simular
/// las pausas del sistema.
class FakeFileCapture implements AudioFileCapture {
  FakeFileCapture({this.granted = true, this.grantOnRequest = true});

  bool granted;
  bool grantOnRequest;
  int requests = 0;
  int starts = 0;
  String? path;
  final StreamController<RecordState> _state = StreamController<RecordState>.broadcast();
  final StreamController<double> _level = StreamController<double>.broadcast();

  @override
  Future<bool> hasPermission({bool request = true}) async {
    if (request && !granted) {
      requests++;
      granted = grantOnRequest;
    }
    return granted;
  }

  @override
  Future<void> start(String path, {required String format}) async {
    starts++;
    this.path = path;
    File(path).writeAsBytesSync(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
    _state.add(RecordState.record);
  }

  @override
  Future<String?> stop() async {
    final String? p = path;
    path = null;
    _state.add(RecordState.stop);
    return p;
  }

  void systemPause() => _state.add(RecordState.pause);

  void emitLevel(double db) => _level.add(db);

  @override
  Stream<RecordState> get state => _state.stream;

  @override
  Stream<double> level(Duration interval) => _level.stream;

  @override
  Future<void> dispose() async {
    unawaited(_state.close());
    unawaited(_level.close());
  }
}

/// Acciones del sistema de prueba: guarda lo compartido y lo pedido.
class FakePlatformActions implements PlatformActions {
  final List<ShareParams> shared = <ShareParams>[];
  XFile? nextPick;
  Object? shareError;
  Object? pickError;
  int picks = 0;
  int settingsOpened = 0;

  @override
  Future<void> share(ShareParams params) async {
    shared.add(params);
    final Object? e = shareError;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<XFile?> pickJsonFile() async {
    picks++;
    final Object? e = pickError;
    if (e != null) {
      throw e;
    }
    return nextPick;
  }

  @override
  Future<void> openAppSettings() async {
    settingsOpened++;
  }
}

/// Vibración de prueba: anota cada pulso.
class FakeHaptics implements Haptics {
  final List<bool> pulses = <bool>[];

  @override
  void pulse({required bool accent}) => pulses.add(accent);
}

/// Servicios de la app con dobles de prueba, cableados con [ServiceLinks]
/// como en main.dart.
class TestServices {
  TestServices._(this.services, this.mic, this.capture, this.platform, this.haptics, this.engine, this.dir, this.links);

  factory TestServices({bool micGranted = true, AppSettings? settings}) {
    final Directory dir = Directory.systemTemp.createTempSync('clave_test');
    final AppSettings st = settings ?? AppSettings();
    final JsonStore store = JsonStore(root: dir);
    final AppState state = AppState(store);
    final PracticeLog practice = PracticeLog(store);
    final SilentEngine engine = SilentEngine();
    final FakeHaptics haptics = FakeHaptics();
    final FakeMic mic = FakeMic(granted: micGranted);
    final FakeFileCapture capture = FakeFileCapture(granted: micGranted);
    final FakePlatformActions platform = FakePlatformActions();
    final Services s = Services(
      settings: st,
      state: state,
      practice: practice,
      store: store,
      engine: engine,
      metronome: Metronome(engine, haptics: haptics),
      tuner: Tuner(mic: mic),
      drone: DroneController(engine),
      recorder: TakeRecorder(store: store, capture: capture),
      platform: platform,
    );
    return TestServices._(s, mic, capture, platform, haptics, engine, dir, ServiceLinks(s));
  }

  final Services services;
  final FakeMic mic;
  final FakeFileCapture capture;
  final FakePlatformActions platform;
  final FakeHaptics haptics;
  final SilentEngine engine;
  final Directory dir;
  final ServiceLinks links;

  /// Para todo lo que suena o escucha y suelta los temporizadores (sin
  /// esperar las escrituras en disco, que en las pruebas de widgets no
  /// avanzan con el tiempo simulado).
  Future<void> stopAll() async {
    await services.metronome.stop();
    await services.drone.stopAll();
    services.tuner.setActive(false);
    await services.tuner.settle();
    unawaited(services.practice.closeAll());
  }

  void dispose() {
    links.dispose();
    services.metronome.dispose();
    services.practice.dispose();
  }

  /// Desmonta la app, para todo y suelta los temporizadores dentro de la
  /// prueba (si queda uno pendiente, la prueba falla).
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await stopAll();
    await tester.pump(const Duration(seconds: 1));
    dispose();
  }
}

/// Datos de muestra en memoria (sin escribir en disco) para probar las
/// pantallas llenas: preajustes, una setlist, tomas con nombres largos y una
/// semana de práctica.
void seedSample(TestServices t, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final Services s = t.services;
  s.state.presets.addAll(<Preset>[
    Preset(id: 'p1', name: 'Bambuco', rhythm: const RhythmConfig(bpm: 96, beatsPerBar: 3, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal], subdivision: 2), notes: 'Tiple rasgueado, acento en el tercer tiempo'),
    Preset(id: 'p2', name: 'Pasillo para practicar con el metrónomo muy despacio', rhythm: const RhythmConfig(bpm: 126, beatsPerBar: 3, beats: <BeatMode>[BeatMode.accent, BeatMode.normal, BeatMode.normal], trainer: TrainerConfig(targetBpm: 140))),
    Preset(id: 'p3', name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2, denominator: 2, beats: <BeatMode>[BeatMode.accent, BeatMode.normal])),
  ]);
  s.state.setlists.add(Setlist(id: 's1', name: 'Ensayo del sábado', presetIds: <String>['p1', 'p2', 'p3']));
  s.state.recordings.addAll(<Recording>[
    Recording(id: 'r1', name: 'Bambuco · primera parte, toma 3 con el tiple nuevo', file: 'recordings/r1.m4a', format: 'aac', durationMs: 94000, createdAt: n.subtract(const Duration(minutes: 25)), folder: 'Repertorio', instrumentId: 'tiple', bpm: 96, notes: 'Cuidar el rasgueo en el compás 12, que se adelanta'),
    Recording(id: 'r2', name: 'Escala de Sol', file: 'recordings/r2.wav', format: 'wav', durationMs: 0, createdAt: n.subtract(const Duration(hours: 5)), recovered: true),
    Recording(id: 'r3', name: 'Arpegios', file: 'recordings/r3.flac', format: 'flac', durationMs: 61000, createdAt: n.subtract(const Duration(days: 2)), folder: 'Técnica', instrumentId: 'requinto_guitarra'),
  ]);
  s.state.nextTake = 4;
  int id = 0;
  for (int back = 6; back >= 0; back--) {
    final DateTime day = DateTime(n.year, n.month, n.day - back, 8);
    for (final String tool in PracticeSession.tools) {
      final DateTime start = day.add(Duration(minutes: 20 * PracticeSession.tools.indexOf(tool)));
      s.practice.sessions.add(PracticeSession(id: 'x${id++}', start: start, end: start.add(Duration(minutes: 4 + back)), tool: tool, instrumentId: back.isEven ? 'guitarra' : 'requinto_guitarra'));
    }
  }
}
