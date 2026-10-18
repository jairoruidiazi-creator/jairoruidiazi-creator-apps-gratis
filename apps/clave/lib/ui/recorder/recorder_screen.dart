import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import '../../audio/take_recorder.dart';
import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/platform_actions.dart';
import '../../core/theme.dart';
import '../../model/models.dart';
import '../../music/instruments.dart';
import '../widgets/adaptive.dart';

/// Grabadora: tomas ilimitadas con carpetas, búsqueda, notas y reproducción
/// a velocidad variable. La toma la graba [TakeRecorder] (sigue aunque se
/// cambie de pestaña); esta pantalla la muestra y la reproduce.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key, this.active = true});

  /// Si la pestaña está a la vista: solo entonces se redibuja con el nivel
  /// de entrada.
  final bool active;

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

/// Velocidades de reproducción.
const List<double> kPlaybackSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5];

/// "0,75" / "0.75" y "1" sin decimales.
String formatSpeed(double v, {required bool spanish}) {
  String s = v.toString();
  if (s.endsWith('.0')) {
    s = s.substring(0, s.length - 2);
  }
  return spanish ? s.replaceAll('.', ',') : s;
}

/// Tipo MIME de cada formato de toma.
String mimeForFormat(String format) {
  switch (format) {
    case 'wav':
      return 'audio/wav';
    case 'flac':
      return 'audio/flac';
    default:
      return 'audio/mp4';
  }
}

/// Nombre de archivo para compartir una toma: su nombre sin caracteres que
/// los sistemas de archivos no aceptan.
String shareFileName(String name, String file) {
  final String ext = file.contains('.') ? file.split('.').last : 'm4a';
  String base = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  if (base.length > 60) {
    base = base.substring(0, 60).trim();
  }
  if (base.isEmpty || base.startsWith('.')) {
    base = 'Clave';
  }
  return '$base.$ext';
}

class _RecorderScreenState extends State<RecorderScreen> with WidgetsBindingObserver {
  Services? _services;
  AudioPlayer? _playerInstance;
  final List<StreamSubscription<dynamic>> _playerSubs = <StreamSubscription<dynamic>>[];
  String _query = '';
  String? _folder;
  Recording? _playing;
  final ValueNotifier<Duration> _position = ValueNotifier<Duration>(Duration.zero);
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _isPlaying = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  /// El reproductor se crea la primera vez que se escucha una toma: abrir la
  /// pestaña no reserva recursos de audio.
  AudioPlayer get _player {
    final AudioPlayer? existing = _playerInstance;
    if (existing != null) {
      return existing;
    }
    final AudioPlayer p = AudioPlayer();
    _playerSubs.addAll(<StreamSubscription<dynamic>>[
      p.onPositionChanged.listen((Duration d) => _position.value = d),
      p.onDurationChanged.listen(_onDuration),
      p.onPlayerStateChanged.listen((PlayerState st) {
        if (mounted) {
          setState(() => _isPlaying = st == PlayerState.playing);
        }
      }),
      p.onPlayerComplete.listen((_) {
        _position.value = Duration.zero;
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      }),
    ]);
    return _playerInstance = p;
  }

  /// La duración que da el reproductor corrige la guardada (las tomas
  /// rescatadas no la traen).
  void _onDuration(Duration d) {
    final Recording? r = _playing;
    if (d <= Duration.zero || r == null) {
      return;
    }
    if (mounted) {
      setState(() => _duration = d);
    }
    if ((r.durationMs - d.inMilliseconds).abs() > 500) {
      unawaited(_services?.state.setDuration(r, d.inMilliseconds));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android no deja sonar en segundo plano sin un servicio en primer plano:
    // la toma que se escucha se pausa al salir (en iOS sigue sonando).
    if (defaultTargetPlatform == TargetPlatform.android && (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) && _isPlaying) {
      unawaited(_playerInstance?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final StreamSubscription<dynamic> sub in _playerSubs) {
      unawaited(sub.cancel());
    }
    final AudioPlayer? player = _playerInstance;
    if (player != null) {
      unawaited(player.dispose());
    }
    _position.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ grabar

  Future<void> _toggleRecord() async {
    final Services s = _services!;
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      if (s.recorder.recording) {
        await _stopRecording(s);
      } else {
        await _startRecording(s);
      }
    } finally {
      _busy = false;
      if (mounted) {
        // Los botones de reproducir dependen de si se graba.
        setState(() {});
      }
    }
  }

  /// Pide el permiso con una explicación antes del diálogo del sistema; si
  /// está negado, ofrece abrir los ajustes.
  Future<bool> _ensurePermission(Services s) async {
    if (await s.recorder.hasPermission(request: false)) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    if (!s.settings.micAsked) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          icon: const Icon(Icons.mic_rounded),
          title: Text(t(context, 'Micrófono', 'Microphone')),
          content: Text(t(
            context,
            'Para grabar tus tomas, Clave usa el micrófono. Las tomas se guardan solo en este teléfono y solo salen de él si tú las compartes.',
            'To record your takes, Clave uses the microphone. Takes are stored only on this phone and leave it only if you share them.',
          )),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Ahora no', 'Not now'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Continuar', 'Continue'))),
          ],
        ),
      );
      if (go != true) {
        return false;
      }
    }
    s.settings.micAsked = true;
    unawaited(s.settings.save());
    s.tuner.permissionAsked = true;
    if (await s.recorder.hasPermission()) {
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'Clave no tiene permiso para usar el micrófono.', 'Clave has no permission to use the microphone.')),
        action: SnackBarAction(label: t(context, 'Abrir ajustes', 'Open settings'), onPressed: () => unawaited(s.platform.openAppSettings())),
      ));
    }
    return false;
  }

  Future<void> _startRecording(Services s) async {
    if (!await _ensurePermission(s) || !mounted) {
      return;
    }
    final String cannotRecord = t(context, 'No se pudo empezar a grabar. Puede que otra app esté usando el micrófono.', 'Could not start recording. Another app may be using the microphone.');
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await _stopPlayback();
    try {
      await s.recorder.start(
        format: s.settings.recordingFormat,
        folder: _folder ?? '',
        instrumentId: s.settings.instrumentId,
        bpm: s.metronome.running ? s.metronome.currentBpm : null,
      );
    } catch (e) {
      debugPrint('No se pudo grabar: $e');
      messenger.showSnackBar(SnackBar(content: Text(cannotRecord)));
    }
  }

  Future<void> _stopRecording(Services s) async {
    final String takeWord = t(context, 'Toma', 'Take');
    final String notSaved = t(context, 'La toma no se pudo guardar.', 'The take could not be saved.');
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TakeResult? result = await s.recorder.stop();
    if (result == null) {
      messenger.showSnackBar(SnackBar(content: Text(notSaved)));
      return;
    }
    final Recording r = await s.state.addTake(result, takeWord: takeWord);
    if (mounted) {
      await _edit(r, isNew: true);
    }
  }

  // ------------------------------------------------------------ reproducir

  Future<void> _play(Recording r) async {
    final Services s = _services!;
    if (s.recorder.recording) {
      return;
    }
    if (_playing?.id == r.id && _isPlaying) {
      await _player.pause();
      return;
    }
    if (_playing?.id == r.id && !_isPlaying && _position.value > Duration.zero) {
      await _player.resume();
      return;
    }
    final String failed = t(context, 'No se pudo reproducir la toma.', 'Could not play the take.');
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String path = await s.store.absolutePath(r.file);
    if (!await File(path).exists()) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    setState(() {
      _playing = r;
      _duration = Duration(milliseconds: r.durationMs);
    });
    _position.value = Duration.zero;
    try {
      await _player.stop();
      await _player.setPlaybackRate(_speed);
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('No se pudo reproducir: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _stopPlayback() async {
    final AudioPlayer? p = _playerInstance;
    if (p != null) {
      try {
        await p.stop();
      } catch (e) {
        debugPrint('Reproductor: $e');
      }
    }
    if (mounted && _playing != null) {
      setState(() {
        _playing = null;
        _isPlaying = false;
      });
    }
    _position.value = Duration.zero;
  }

  Future<void> _setSpeed(double v) async {
    setState(() => _speed = v);
    try {
      await _playerInstance?.setPlaybackRate(v);
    } catch (e) {
      debugPrint('Velocidad: $e');
    }
  }

  // ------------------------------------------------------------ editar

  Future<void> _edit(Recording r, {bool isNew = false}) async {
    final Services s = _services!;
    final TextEditingController name = TextEditingController(text: r.name);
    final TextEditingController notes = TextEditingController(text: r.notes);
    String folderText = r.folder;
    String instrument = Instruments.maybeById(r.instrumentId)?.id ?? s.settings.instrumentId;
    final bool spanish = s.settings.spanish;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setDialog) => AlertDialog(
          title: Text(isNew ? t(context, 'Toma guardada', 'Take saved') : t(context, 'Editar toma', 'Edit take')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name')),
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(Preset.maxName)],
                ),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: r.folder),
                  optionsBuilder: (TextEditingValue v) => s.state.folders.where((String f) => f.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (String v) => folderText = v,
                  fieldViewBuilder: (BuildContext context, TextEditingController c, FocusNode f, VoidCallback onSubmit) {
                    return TextField(
                      controller: c,
                      focusNode: f,
                      onChanged: (String v) => folderText = v,
                      inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(60)],
                      decoration: InputDecoration(labelText: t(context, 'Carpeta', 'Folder')),
                    );
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: instrument,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t(context, 'Instrumento', 'Instrument')),
                  items: <DropdownMenuItem<String>>[for (final Instrument i in Instruments.all) DropdownMenuItem<String>(value: i.id, child: Text(i.name(spanish)))],
                  onChanged: (String? v) => setDialog(() => instrument = v ?? instrument),
                ),
                TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes')),
                  maxLines: 3,
                  inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(Preset.maxNotes)],
                ),
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
      r.folder = folderText.trim();
      r.notes = notes.text.trim();
      r.instrumentId = instrument;
      await s.state.saveRecordings();
    }
    disposeLater(<ChangeNotifier>[name, notes]);
  }

  /// Comparte la toma con su nombre como nombre de archivo (copia en
  /// export/, que se vacía al abrir la app).
  Future<void> _share(Recording r, Rect? origin) async {
    final Services s = _services!;
    final String failed = t(context, 'No se pudo compartir la toma.', 'Could not share the take.');
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final String src = await s.store.absolutePath(r.file);
      final String dst = await s.store.absolutePath('export/${shareFileName(r.name, r.file)}');
      await File(dst).parent.create(recursive: true);
      await File(src).copy(dst);
      await s.platform.share(ShareParams(
        files: <XFile>[XFile(dst, mimeType: mimeForFormat(r.format))],
        subject: r.name,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      debugPrint('Compartir toma: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _delete(Recording r) async {
    final Services s = _services!;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, '¿Borrar la toma?', 'Delete the take?')),
        content: Text(r.name),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Borrar', 'Delete'))),
        ],
      ),
    );
    if (ok == true) {
      if (_playing?.id == r.id) {
        await _stopPlayback();
      }
      await s.state.deleteRecording(r);
    }
  }

  // ------------------------------------------------------------ pantalla

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    final bool spanish = isSpanish(context);
    return ListenableBuilder(
      listenable: st,
      builder: (BuildContext context, Widget? _) {
        final String q = _query.trim().toLowerCase();
        final List<String> folders = st.folders;
        if (_folder != null && !folders.contains(_folder)) {
          _folder = null;
        }
        final List<Recording> shown = st.recordings.where((Recording r) {
          if (_folder != null && r.folder != _folder) {
            return false;
          }
          if (q.isEmpty) {
            return true;
          }
          final String instrument = Instruments.maybeById(r.instrumentId)?.name(spanish).toLowerCase() ?? '';
          return r.name.toLowerCase().contains(q) || r.notes.toLowerCase().contains(q) || r.folder.toLowerCase().contains(q) || instrument.contains(q);
        }).toList();
        return ReadableWidth(
          child: Column(
            children: <Widget>[
              _RecordPanel(active: widget.active, folder: _folder, onToggle: _toggleRecord),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t(context, 'Buscar por nombre, notas o instrumento', 'Search by name, notes or instrument'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
              if (folders.isNotEmpty)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    children: <Widget>[
                      ChoiceChip(label: Text(t(context, 'Todas', 'All')), selected: _folder == null, onSelected: (_) => setState(() => _folder = null)),
                      for (final String f in folders) ...<Widget>[
                        const SizedBox(width: 6),
                        ChoiceChip(label: Text(f), selected: _folder == f, onSelected: (_) => setState(() => _folder = _folder == f ? null : f)),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            st.recordings.isEmpty
                                ? t(context, 'Sin grabaciones todavía. Toca el botón rojo para grabar una toma.', 'No recordings yet. Tap the red button to record a take.')
                                : t(context, 'Ninguna toma coincide con la búsqueda.', 'No take matches the search.'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: shown.length,
                        itemBuilder: (BuildContext context, int i) => _tile(context, s, shown[i], spanish),
                      ),
              ),
              if (_playing != null) _playerBar(context, spanish),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Services s, Recording r, bool spanish) {
    final bool current = _playing?.id == r.id;
    final bool playingThis = current && _isPlaying;
    final String? instrument = Instruments.maybeById(r.instrumentId)?.name(spanish);
    final String duration = r.durationMs > 0 ? formatClock(r.durationMs) : t(context, 'duración por conocer', 'duration unknown');
    final List<String> parts = <String>[
      duration,
      formatDateTime(context, r.createdAt),
      if (instrument != null) instrument,
      if (r.folder.isNotEmpty) r.folder,
      if (r.bpm != null) '${r.bpm!.toStringAsFixed(0)}\u00a0BPM',
      if (r.recovered) t(context, 'rescatada', 'recovered'),
    ];
    return ListTile(
      leading: IconButton.filledTonal(
        tooltip: playingThis ? '${t(context, 'Pausar', 'Pause')} ${r.name}' : '${t(context, 'Reproducir', 'Play')} ${r.name}',
        onPressed: s.recorder.recording ? null : () => _play(r),
        icon: Icon(playingThis ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
      title: Text(r.name, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text(
        // El punto va pegado a lo anterior: una línea nunca empieza con "·".
        '${parts.join('\u00a0· ')}${r.notes.isNotEmpty ? '\n${r.notes}' : ''}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: r.notes.isNotEmpty,
      trailing: Builder(
        builder: (BuildContext menuContext) => PopupMenuButton<String>(
          tooltip: '${t(context, 'Opciones de', 'Options for')} ${r.name}',
          onSelected: (String v) {
            if (v == 'edit') {
              unawaited(_edit(r));
            } else if (v == 'share') {
              unawaited(_share(r, shareOriginOf(menuContext)));
            } else if (v == 'delete') {
              unawaited(_delete(r));
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'edit', child: Text(t(context, 'Editar', 'Edit'))),
            PopupMenuItem<String>(value: 'share', child: Text(t(context, 'Compartir', 'Share'))),
            PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
          ],
        ),
      ),
    );
  }

  Widget _playerBar(BuildContext context, bool spanish) {
    final Recording r = _playing!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int knownMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : r.durationMs;
    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: ValueListenableBuilder<Duration>(
            valueListenable: _position,
            builder: (BuildContext context, Duration pos, Widget? _) {
              final double total = (knownMs > 0 ? knownMs : pos.inMilliseconds).toDouble();
              final double max = total <= 0 ? 1 : total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton.filled(
                        tooltip: _isPlaying ? t(context, 'Pausar', 'Pause') : t(context, 'Reproducir', 'Play'),
                        onPressed: () => _play(r),
                        icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(
                        '${formatClock(pos.inMilliseconds)} / ${knownMs > 0 ? formatClock(knownMs) : '--:--'}',
                        style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
                      ),
                      IconButton(tooltip: t(context, 'Cerrar el reproductor', 'Close the player'), onPressed: _stopPlayback, icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  Slider(
                    min: 0,
                    max: max,
                    value: pos.inMilliseconds.toDouble().clamp(0.0, max),
                    semanticFormatterCallback: (double v) => '${formatClock(v.toInt())} ${t(context, 'de', 'of')} ${knownMs > 0 ? formatClock(knownMs) : '--:--'}',
                    onChanged: (double v) {
                      _position.value = Duration(milliseconds: v.toInt());
                    },
                    onChangeEnd: (double v) => unawaited(_playerInstance?.seek(Duration(milliseconds: v.toInt()))),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(t(context, 'Velocidad', 'Speed')),
                      for (final double v in kPlaybackSpeeds)
                        ChoiceChip(
                          label: Text('${formatSpeed(v, spanish: spanish)}×', semanticsLabel: '${t(context, 'Velocidad', 'Speed')} ${formatSpeed(v, spanish: spanish)}'),
                          selected: _speed == v,
                          onSelected: (_) => _setSpeed(v),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Panel de grabación: botón, tiempo, nivel y formato. Con la pestaña oculta
/// no escucha a la grabadora (no se redibuja con cada nivel).
class _RecordPanel extends StatelessWidget {
  const _RecordPanel({required this.active, required this.folder, required this.onToggle});

  final bool active;
  final String? folder;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    if (!active) {
      return _build(context, s);
    }
    return ListenableBuilder(listenable: s.recorder, builder: (BuildContext context, Widget? _) => _build(context, s));
  }

  Widget _build(BuildContext context, Services s) {
    final TakeRecorder rec = s.recorder;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final bool spanish = isSpanish(context);
    final bool recording = rec.recording;
    final double level = recording ? rec.level : 0;
    final Color onPanel = recording ? cs.onErrorContainer : cs.onSurface;
    final Color secondary = recording ? cs.onErrorContainer : cs.onSurfaceVariant;
    final String format = (recording ? rec.format : s.settings.recordingFormat).toUpperCase();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: recording ? cs.errorContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: <Widget>[
          IconButton.filled(
            tooltip: recording ? t(context, 'Detener y guardar la toma', 'Stop and save the take') : t(context, 'Grabar una toma', 'Record a take'),
            onPressed: onToggle,
            iconSize: 30,
            style: IconButton.styleFrom(minimumSize: const Size(64, 64), backgroundColor: pal.record, foregroundColor: pal.onRecord),
            icon: Icon(recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  recording ? '${t(context, 'Grabando', 'Recording')} · ${formatClock(rec.elapsed.inMilliseconds)}' : t(context, 'Lista para grabar', 'Ready to record'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: onPanel),
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: level, minHeight: 8, backgroundColor: cs.surface, color: level > 0.9 ? pal.far : pal.inTune),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$format · ${formatDecimal(44.1, spanish: spanish)} kHz · ${t(context, 'mono', 'mono')}${folder != null ? ' · ${t(context, 'carpeta', 'folder')}: $folder' : ''}',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
