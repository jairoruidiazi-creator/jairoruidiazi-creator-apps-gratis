import 'dart:async';
import 'dart:convert';

import '../audio/click_synth.dart';
import '../music/instruments.dart';
import 'app_scope.dart';
import 'settings.dart';

/// Une los servicios entre sí. La usan main y las pruebas, así que lo que se
/// prueba es el cableado real:
///
/// - Práctica: el metrónomo cuenta mientras corre; el bordón, el teclado y
///   los acordes mientras suenan; la grabadora mientras graba; el afinador
///   mientras oye un tono estable (que no sea un sonido de la propia app).
/// - Micrófono: mientras la grabadora graba, el afinador no lo abre.
/// - Ajustes: llegan al afinador, al metrónomo y al bordón.
/// - El ritmo del metrónomo se guarda para abrir la app como se dejó.
class ServiceLinks {
  ServiceLinks(this.s) {
    _instrumentId = s.settings.instrumentId;
    s.metronome.addListener(_onMetronome);
    s.drone.addListener(_onDrone);
    s.recorder.addListener(_onRecorder);
    s.settings.addListener(_onSettings);
    s.tuner
      ..permissionAsked = s.settings.micAsked
      ..onPermissionAsked = _onPermissionAsked
      ..onStableTone = _onStableTone
      ..ownFrequencies = ownFrequencies;
    _lastConfig = jsonEncode(s.metronome.config.toJson());
    _onSettings();
  }

  final Services s;
  bool _metronomeRunning = false;
  bool _droneSounding = false;
  bool _recording = false;
  late String _instrumentId;
  Timer? _configSave;
  String _lastConfig = '';

  void _onPermissionAsked() {
    s.settings.micAsked = true;
    unawaited(s.settings.save());
  }

  void _onStableTone() => s.practice.ping('afinador', s.settings.instrumentId);

  /// Frecuencias que suenan desde la propia app ahora mismo.
  List<double> ownFrequencies() => <double>[
        if (s.metronome.running) ...ClickSynth.pitchedFrequencies(s.metronome.sound),
        ...s.drone.soundingFrequencies,
      ];

  void _onMetronome() {
    final bool running = s.metronome.running;
    if (running != _metronomeRunning) {
      _metronomeRunning = running;
      if (running) {
        s.practice.start('metronomo', s.settings.instrumentId);
      } else {
        s.practice.stop('metronomo');
      }
    }
    final String json = jsonEncode(s.metronome.config.toJson());
    if (json != _lastConfig) {
      _lastConfig = json;
      _configSave?.cancel();
      _configSave = Timer(const Duration(milliseconds: 600), () {
        s.settings.metronomeConfig = json;
        unawaited(s.settings.save());
      });
    }
  }

  void _onDrone() {
    final bool sounding = s.drone.sounding;
    if (sounding != _droneSounding) {
      _droneSounding = sounding;
      if (sounding) {
        s.practice.start('tono', s.settings.instrumentId);
      } else {
        s.practice.stop('tono');
      }
    }
  }

  void _onRecorder() {
    final bool recording = s.recorder.recording;
    if (recording != _recording) {
      _recording = recording;
      if (recording) {
        s.practice.start('grabadora', s.settings.instrumentId);
      } else {
        s.practice.stop('grabadora');
      }
    }
    s.tuner.setMicBusy(recording);
  }

  void _onSettings() {
    final AppSettings st = s.settings;
    s.tuner
      ..settings = st.pitch
      ..toleranceCents = st.toleranceCents
      ..damping = st.damping
      ..instrument = Instruments.byId(st.instrumentId);
    if (s.tuner.lockedString >= s.tuner.instrument.courses.length) {
      s.tuner.lockedString = -1;
    }
    s.metronome
      ..hapticsEnabled = st.haptics
      ..flashEnabled = st.flash
      ..audioDelayMs = st.audioDelayMs
      ..volume = st.metronomeVolume;
    s.drone
      ..setPitch(st.pitch)
      ..setVolume(st.droneVolume);
    if (st.instrumentId != _instrumentId) {
      _instrumentId = st.instrumentId;
      s.practice.changeInstrument(st.instrumentId);
    }
  }

  void dispose() {
    _configSave?.cancel();
    s.metronome.removeListener(_onMetronome);
    s.drone.removeListener(_onDrone);
    s.recorder.removeListener(_onRecorder);
    s.settings.removeListener(_onSettings);
    s.tuner
      ..onStableTone = null
      ..onPermissionAsked = null
      ..ownFrequencies = null;
  }
}
