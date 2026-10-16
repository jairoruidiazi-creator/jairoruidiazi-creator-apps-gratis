import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../model/models.dart';
import '../../music/instruments.dart';

/// Grabadora: tomas ilimitadas con carpetas, búsqueda, notas y reproducción
/// a velocidad variable.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> with AutomaticKeepAliveClientMixin {
  Services? _services;
  AudioRecorder? _recorderInstance;
  final AudioPlayer _player = AudioPlayer();

  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;
  double _level = 0;
  StreamSubscription<Amplitude>? _ampSub;
  String? _recordingPath;
  String? _recordingFile;
  String _recordingFormat = 'aac';
  String _query = '';
  String? _folder;
  Recording? _playing;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double _speed = 1.0;
  bool _isPlaying = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= AppScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    _posSub = _player.onPositionChanged.listen((Duration d) => setState(() => _pos = d));
    _durSub = _player.onDurationChanged.listen((Duration d) => setState(() => _dur = d));
    _stateSub = _player.onPlayerStateChanged.listen((PlayerState st) => setState(() => _isPlaying = st == PlayerState.playing));
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    unawaited(_ampSub?.cancel());
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_stateSub?.cancel());
    final AudioRecorder? rec = _recorderInstance;
    if (rec != null) {
      unawaited(rec.dispose());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  // ------------------------------------------------------------ grabar

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final Services s = _services!;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String noPerm = t(context, 'Sin permiso de micrófono.', 'Microphone permission denied.');
    final String cannotRecord = t(context, 'No se pudo grabar', 'Could not record');
    if (!await _recorder.hasPermission()) {
      messenger.showSnackBar(SnackBar(content: Text(noPerm)));
      return;
    }
    // El afinador suelta el micrófono mientras se graba.
    await s.tuner.stop();
    await _player.stop();
    _recordingFormat = s.settings.recordingFormat;
    final AudioEncoder enc = _recordingFormat == 'wav' ? AudioEncoder.wav : (_recordingFormat == 'flac' ? AudioEncoder.flac : AudioEncoder.aacLc);
    final String ext = _recordingFormat == 'wav' ? 'wav' : (_recordingFormat == 'flac' ? 'flac' : 'm4a');
    final String rel = 'recordings/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final String path = await s.store.absolutePath(rel);
    await File(path).parent.create(recursive: true);
    try {
      await _recorder.start(RecordConfig(encoder: enc, sampleRate: 44100, numChannels: 1, bitRate: 160000), path: path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$cannotRecord: $e')));
      return;
    }
    _recordingPath = path;
    _recordingFile = rel;
    _recStart = DateTime.now();
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((Amplitude a) {
      // dBFS de -60 a 0 → 0 a 1
      final double v = ((a.current + 60) / 60).clamp(0.0, 1.0);
      if (mounted) {
        setState(() => _level = v);
      }
    });
    _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) {
        setState(() {});
      }
      s.state.touchPractice('grabadora', s.settings.instrumentId);
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    final Services s = _services!;
    final String takeWord = t(context, 'Toma', 'Take');
    _recTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final int ms = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inMilliseconds;
    setState(() {
      _recording = false;
      _level = 0;
    });
    final String? rel = _recordingFile;
    if ((path ?? _recordingPath) == null || rel == null) {
      return;
    }
    final int n = s.state.recordings.length + 1;
    final Recording r = Recording(
      id: newId(),
      name: '$takeWord $n',
      file: rel,
      format: _recordingFormat,
      durationMs: ms,
      createdAt: DateTime.now(),
      folder: _folder ?? '',
      instrumentId: s.settings.instrumentId,
      bpm: s.metronome.running ? s.metronome.currentBpm : null,
    );
    await s.state.addRecording(r);
    if (mounted) {
      await _edit(r, isNew: true);
    }
  }

  // ------------------------------------------------------------ reproducir

  Future<void> _play(Recording r) async {
    final Services s = _services!;
    if (_playing?.id == r.id && _isPlaying) {
      await _player.pause();
      return;
    }
    if (_playing?.id == r.id && !_isPlaying && _pos > Duration.zero) {
      await _player.resume();
      return;
    }
    await s.tuner.stop();
    final String path = await s.store.absolutePath(r.file);
    setState(() {
      _playing = r;
      _pos = Duration.zero;
      _dur = Duration(milliseconds: r.durationMs);
    });
    try {
      await _player.setPlaybackRate(_speed);
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo reproducir', 'Could not play')}: $e')));
      }
    }
  }

  Future<void> _setSpeed(double v) async {
    _speed = v;
    try {
      await _player.setPlaybackRate(v);
    } catch (_) {}
    setState(() {});
  }

  // ------------------------------------------------------------ editar

  Future<void> _edit(Recording r, {bool isNew = false}) async {
    final Services s = _services!;
    final TextEditingController name = TextEditingController(text: r.name);
    final TextEditingController folder = TextEditingController(text: r.folder);
    final TextEditingController notes = TextEditingController(text: r.notes);
    String instrument = r.instrumentId.isEmpty ? s.settings.instrumentId : r.instrumentId;
    final bool spanish = s.settings.spanish;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setDialog) => AlertDialog(
          title: Text(isNew ? t(context, 'Grabación guardada', 'Recording saved') : t(context, 'Editar grabación', 'Edit recording')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: name, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name')), textCapitalization: TextCapitalization.sentences),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: r.folder),
                  optionsBuilder: (TextEditingValue v) => s.state.folders.where((String f) => f.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (String v) => folder.text = v,
                  fieldViewBuilder: (BuildContext context, TextEditingController c, FocusNode f, VoidCallback onSubmit) {
                    c.addListener(() => folder.text = c.text);
                    return TextField(controller: c, focusNode: f, decoration: InputDecoration(labelText: t(context, 'Carpeta', 'Folder')));
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: instrument,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t(context, 'Instrumento', 'Instrument')),
                  items: <DropdownMenuItem<String>>[for (final Instrument i in Instruments.all) DropdownMenuItem<String>(value: i.id, child: Text(i.name(spanish)))],
                  onChanged: (String? v) => setDialog(() => instrument = v ?? instrument),
                ),
                TextField(controller: notes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes')), maxLines: 3),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Guardar', 'Save'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      r.name = name.text.trim().isEmpty ? r.name : name.text.trim();
      r.folder = folder.text.trim();
      r.notes = notes.text.trim();
      r.instrumentId = instrument;
      await s.state.saveRecordings();
    }
    disposeLater(<ChangeNotifier>[name, folder, notes]);
  }

  Future<void> _share(Recording r) async {
    final String path = await _services!.store.absolutePath(r.file);
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(path)], subject: r.name));
  }

  Future<void> _delete(Recording r) async {
    final Services s = _services!;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, '¿Borrar la grabación?', 'Delete recording?')),
        content: Text(r.name),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Borrar', 'Delete'))),
        ],
      ),
    );
    if (ok == true) {
      if (_playing?.id == r.id) {
        await _player.stop();
        _playing = null;
      }
      await s.state.deleteRecording(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool spanish = s.settings.spanish;
    return ListenableBuilder(
      listenable: st,
      builder: (BuildContext context, Widget? _) {
        final String q = _query.trim().toLowerCase();
        final List<Recording> shown = st.recordings.where((Recording r) {
          if (_folder != null && r.folder != _folder) {
            return false;
          }
          if (q.isEmpty) {
            return true;
          }
          return r.name.toLowerCase().contains(q) || r.notes.toLowerCase().contains(q) || r.folder.toLowerCase().contains(q) || Instruments.byId(r.instrumentId).name(spanish).toLowerCase().contains(q);
        }).toList();
        final int elapsed = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inMilliseconds;
        return Column(
          children: <Widget>[
            // Panel de grabación
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _recording ? cs.errorContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: <Widget>[
                  FilledButton(
                    onPressed: _toggleRecord,
                    style: FilledButton.styleFrom(shape: const CircleBorder(), minimumSize: const Size(64, 64), backgroundColor: _recording ? cs.error : ClaveColors.lejos),
                    child: Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 30, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(_recording ? '${t(context, 'Grabando', 'Recording')} · ${formatClock(elapsed)}' : t(context, 'Lista para grabar', 'Ready to record'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: _recording ? _level : 0, minHeight: 8, backgroundColor: cs.surface, color: _level > 0.9 ? ClaveColors.lejos : ClaveColors.afinado),
                        ),
                        const SizedBox(height: 4),
                        Text('${s.settings.recordingFormat.toUpperCase()} · 44,1 kHz · ${t(context, 'mono', 'mono')}${_folder != null ? ' · ${t(context, 'carpeta', 'folder')}: $_folder' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Búsqueda y carpetas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t(context, 'Buscar por nombre, notas o instrumento', 'Search by name, notes or instrument'), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
            if (st.folders.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: <Widget>[
                    ChoiceChip(label: Text(t(context, 'Todas', 'All')), selected: _folder == null, onSelected: (_) => setState(() => _folder = null)),
                    for (final String f in st.folders) ...<Widget>[
                      const SizedBox(width: 6),
                      ChoiceChip(label: Text(f), selected: _folder == f, onSelected: (_) => setState(() => _folder = _folder == f ? null : f)),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Sin grabaciones todavía. Toca el botón rojo para grabar una toma.', 'No recordings yet. Tap the red button to record a take.'), textAlign: TextAlign.center)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: shown.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Recording r = shown[i];
                        final bool current = _playing?.id == r.id;
                        return ListTile(
                          leading: IconButton.filledTonal(
                            onPressed: () => _play(r),
                            icon: Icon(current && _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          ),
                          title: Text(r.name, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w500)),
                          subtitle: Text(
                            '${formatClock(r.durationMs)} · ${_date(r.createdAt)} · ${Instruments.byId(r.instrumentId).name(spanish)}${r.folder.isNotEmpty ? ' · ${r.folder}' : ''}${r.bpm != null ? ' · ${r.bpm!.toStringAsFixed(0)} BPM' : ''}${r.notes.isNotEmpty ? '\n${r.notes}' : ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: r.notes.isNotEmpty,
                          trailing: PopupMenuButton<String>(
                            onSelected: (String v) {
                              if (v == 'edit') {
                                _edit(r);
                              } else if (v == 'share') {
                                _share(r);
                              } else if (v == 'delete') {
                                _delete(r);
                              }
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(value: 'edit', child: Text(t(context, 'Editar', 'Edit'))),
                              PopupMenuItem<String>(value: 'share', child: Text(t(context, 'Compartir', 'Share'))),
                              PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
                            ],
                          ),
                          onTap: () => _play(r),
                        );
                      },
                    ),
            ),
            if (_playing != null) _playerBar(context, cs),
          ],
        );
      },
    );
  }

  Widget _playerBar(BuildContext context, ColorScheme cs) {
    final Recording r = _playing!;
    final double total = _dur.inMilliseconds <= 0 ? r.durationMs.toDouble() : _dur.inMilliseconds.toDouble();
    return Material(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton.filled(onPressed: () => _play(r), icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                const SizedBox(width: 8),
                Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${formatClock(_pos.inMilliseconds)} / ${formatClock(total.toInt())}', style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                IconButton(onPressed: () async { await _player.stop(); setState(() => _playing = null); }, icon: const Icon(Icons.close_rounded)),
              ],
            ),
            Slider(
              min: 0,
              max: total <= 0 ? 1 : total,
              value: _pos.inMilliseconds.toDouble().clamp(0, total <= 0 ? 1 : total),
              onChanged: (double v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(t(context, 'Velocidad', 'Speed')),
                for (final double v in <double>[0.5, 0.75, 1.0, 1.25, 1.5])
                  ChoiceChip(label: Text('${v}x'), selected: _speed == v, onSelected: (_) => _setSpeed(v), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
