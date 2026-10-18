import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import '../../audio/sequencer.dart';
import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/platform_actions.dart';
import '../../model/models.dart';
import '../widgets/adaptive.dart';

/// Preajustes (canciones) y setlists del metrónomo.
/// Nombre del archivo exportado, en el idioma de la app.
String presetsFileName({required bool spanish}) => spanish ? 'clave-preajustes.json' : 'clave-presets.json';

class PresetsScreen extends StatefulWidget {
  const PresetsScreen({super.key});

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen> {
  String? _setlistId; // null = todos los preajustes

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    return ListenableBuilder(
      listenable: st,
      builder: (BuildContext context, Widget? _) {
        final Setlist? setlist = _setlistId == null ? null : st.setlistById(_setlistId!);
        final List<Preset> shown = setlist == null ? st.presets : st.presetsOf(setlist);
        return Scaffold(
          appBar: AppBar(
            title: Text(t(context, 'Preajustes', 'Presets')),
            actions: <Widget>[
              IconButton(tooltip: t(context, 'Importar preajustes', 'Import presets'), icon: const Icon(Icons.file_open_outlined), onPressed: () => _import(context)),
              Builder(
                builder: (BuildContext buttonContext) => IconButton(
                  tooltip: t(context, 'Exportar preajustes', 'Export presets'),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: st.presets.isEmpty ? null : () => _export(context, shareOriginOf(buttonContext)),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _savePreset(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(t(context, 'Guardar el actual', 'Save current')),
          ),
          body: ReadableWidth(
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: <Widget>[
                      ChoiceChip(label: Text(t(context, 'Todos', 'All')), selected: _setlistId == null, onSelected: (_) => setState(() => _setlistId = null)),
                      const SizedBox(width: 8),
                      for (final Setlist sl in st.setlists) ...<Widget>[
                        ChoiceChip(
                          label: Text('${sl.name} (${st.presetsOf(sl).length})'),
                          selected: _setlistId == sl.id,
                          onSelected: (_) => setState(() => _setlistId = sl.id),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ActionChip(avatar: const Icon(Icons.playlist_add_rounded, size: 18), label: Text(t(context, 'Nueva setlist', 'New setlist')), onPressed: () => _newSetlist(context)),
                    ],
                  ),
                ),
                if (setlist != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          // El asa se dibuja con el mismo ícono de la lista (un
                          // signo de texto podría no estar en la fuente).
                          child: Text.rich(
                            TextSpan(children: <InlineSpan>[
                              TextSpan(text: t(context, 'Arrastra ', 'Drag ')),
                              WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.drag_handle_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              TextSpan(text: t(context, ' para cambiar el orden. Añade o quita canciones con el menú de cada preajuste en "Todos".', ' to reorder. Add or remove songs from each preset\'s menu under "All".')),
                            ]),
                            semanticsLabel: t(context, 'Arrastra el asa de cada canción para cambiar el orden. Añade o quita canciones con el menú de cada preajuste en "Todos".', 'Drag a song\'s handle to reorder. Add or remove songs from each preset\'s menu under "All".'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: t(context, 'Borrar setlist', 'Delete setlist'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteSetlist(context, setlist),
                        ),
                      ],
                    ),
                  ),
                if (setlist != null && shown.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _load(context, shown.first, setlist: setlist, index: 0),
                        icon: const Icon(Icons.playlist_play_rounded),
                        label: Text(t(context, 'Usar esta setlist en el metrónomo', 'Use this setlist in the metronome')),
                      ),
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              setlist == null
                                  ? t(context, 'Aún no hay preajustes. Ajusta el metrónomo y toca "Guardar el actual".', 'No presets yet. Set up the metronome and tap "Save current".')
                                  : t(context, 'Esta setlist está vacía. Añade canciones con el menú de cada preajuste en "Todos".', 'This setlist is empty. Add songs from each preset\'s menu under "All".'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: shown.length,
                          buildDefaultDragHandles: false,
                          // onReorderItem existe desde Flutter 3.41; se mantiene onReorder por compatibilidad.
                          // ignore: deprecated_member_use
                          onReorder: (int a, int b) async {
                            if (setlist == null) {
                              return;
                            }
                            if (b > a) {
                              b -= 1;
                            }
                            _move(setlist, shown, a, b);
                            await st.savePresets();
                          },
                          itemBuilder: (BuildContext context, int i) => _tile(context, s, shown, i, setlist),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Mueve la canción [from] a [to] dentro de la setlist (posiciones de la
  /// lista visible, que no incluye preajustes borrados).
  void _move(Setlist setlist, List<Preset> shown, int from, int to) {
    final List<String> ids = shown.map((Preset p) => p.id).toList();
    final String id = ids.removeAt(from);
    ids.insert(to.clamp(0, ids.length), id);
    setlist.presetIds
      ..clear()
      ..addAll(ids);
  }

  Widget _tile(BuildContext context, Services s, List<Preset> shown, int i, Setlist? setlist) {
    final AppState st = s.state;
    final Preset p = shown[i];
    final RhythmConfig r = p.rhythm;
    return ListTile(
      key: ValueKey<String>('${setlist?.id ?? 'all'}-${p.id}'),
      leading: CircleAvatar(child: Text(r.bpm.toStringAsFixed(0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
      title: Text(p.name.isEmpty ? t(context, 'Sin nombre', 'Untitled') : p.name),
      subtitle: Text('${r.timeSignature} · ${_subName(context, r.subdivision)}${r.trainer != null ? ' · ${t(context, 'entrenador', 'trainer')}' : ''}${p.notes.isNotEmpty ? '\n${p.notes}' : ''}'),
      isThreeLine: p.notes.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PopupMenuButton<String>(
            tooltip: t(context, 'Opciones de ${p.name}', 'Options for ${p.name}'),
            onSelected: (String v) async {
              if (v == 'load') {
                await _load(context, p, setlist: setlist, index: i);
              } else if (v == 'rename') {
                await _rename(context, p);
              } else if (v == 'delete') {
                await _deletePreset(context, p);
              } else if (v == 'up' && setlist != null && i > 0) {
                _move(setlist, shown, i, i - 1);
                await st.savePresets();
              } else if (v == 'down' && setlist != null && i < shown.length - 1) {
                _move(setlist, shown, i, i + 1);
                await st.savePresets();
              } else if (v.startsWith('sl:')) {
                final Setlist? target = st.setlistById(v.substring(3));
                if (target != null) {
                  if (target.presetIds.contains(p.id)) {
                    target.presetIds.remove(p.id);
                  } else if (target.presetIds.length < Setlist.maxItems) {
                    target.presetIds.add(p.id);
                  }
                  await st.savePresets();
                }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'load', child: Text(t(context, 'Cargar', 'Load'))),
              PopupMenuItem<String>(value: 'rename', child: Text(t(context, 'Renombrar / notas', 'Rename / notes'))),
              if (setlist != null && i > 0) PopupMenuItem<String>(value: 'up', child: Text(t(context, 'Subir en la setlist', 'Move up in the setlist'))),
              if (setlist != null && i < shown.length - 1) PopupMenuItem<String>(value: 'down', child: Text(t(context, 'Bajar en la setlist', 'Move down in the setlist'))),
              for (final Setlist sl in st.setlists)
                PopupMenuItem<String>(value: 'sl:${sl.id}', child: Text(sl.presetIds.contains(p.id) ? t(context, '✓ En «${sl.name}» (quitar)', '✓ In "${sl.name}" (remove)') : t(context, 'Añadir a «${sl.name}»', 'Add to "${sl.name}"'))),
              PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
            ],
          ),
          if (setlist != null)
            ReorderableDragStartListener(
              index: i,
              child: Semantics(
                label: t(context, 'Arrastrar para ordenar', 'Drag to reorder'),
                child: const SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle_rounded)),
              ),
            ),
        ],
      ),
      onTap: () => _load(context, p, setlist: setlist, index: i),
    );
  }

  /// Carga el preajuste en el metrónomo. Desde una setlist, la deja activa
  /// (con anterior y siguiente en el metrónomo).
  Future<void> _load(BuildContext context, Preset p, {Setlist? setlist, int index = 0}) async {
    final Services s = AppScope.of(context);
    final NavigatorState nav = Navigator.of(context);
    s.metronome.setConfig(p.rhythm);
    s.settings.activeSetlistId = setlist?.id ?? '';
    s.settings.activeSetlistIndex = setlist == null ? 0 : index;
    await s.settings.save();
    if (mounted) {
      nav.pop();
    }
  }

  String _subName(BuildContext context, int n) {
    switch (n) {
      case 2:
        return t(context, 'corcheas', 'eighths');
      case 3:
        return t(context, 'tresillos', 'triplets');
      case 4:
        return t(context, 'semicorcheas', 'sixteenths');
      case 6:
        return t(context, 'seisillos', 'sextuplets');
      default:
        return t(context, 'sin subdivisión', 'no subdivision');
    }
  }

  Future<void> _savePreset(BuildContext context) async {
    final Services s = AppScope.of(context);
    final String? name = await _askText(context, t(context, 'Nombre de la canción o ejercicio', 'Song or exercise name'));
    if (name == null || !context.mounted) {
      return;
    }
    final Preset p = await s.state.addPreset(Preset(id: newId(), name: name, rhythm: s.metronome.config));
    final Setlist? sl = _setlistId == null ? null : s.state.setlistById(_setlistId!);
    if (sl != null) {
      sl.presetIds.add(p.id);
      await s.state.savePresets();
    }
  }

  /// Borra el preajuste y ofrece deshacerlo (vuelve a su lugar y a sus
  /// setlists).
  Future<void> _deletePreset(BuildContext context, Preset p) async {
    final Services s = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String name = p.name.isEmpty ? t(context, 'Sin nombre', 'Untitled') : p.name;
    final String done = t(context, 'Se borró «$name»', 'Deleted "$name"');
    final String undo = t(context, 'Deshacer', 'Undo');
    final PresetRemoval? removal = await s.state.deletePreset(p.id);
    if (removal == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(done), action: SnackBarAction(label: undo, onPressed: () => s.state.restorePreset(removal))));
  }

  /// Borra la setlist (los preajustes se quedan) y ofrece deshacerlo.
  Future<void> _deleteSetlist(BuildContext context, Setlist setlist) async {
    final Services s = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String done = t(context, 'Se borró la setlist «${setlist.name}»', 'Deleted the "${setlist.name}" setlist');
    final String undo = t(context, 'Deshacer', 'Undo');
    final bool wasActive = s.settings.activeSetlistId == setlist.id;
    final int activeIndex = s.settings.activeSetlistIndex;
    final int index = await s.state.deleteSetlist(setlist.id);
    if (wasActive) {
      s.settings.activeSetlistId = '';
      await s.settings.save();
    }
    if (mounted) {
      setState(() => _setlistId = null);
    }
    if (index < 0) {
      return;
    }
    Future<void> restore() async {
      await s.state.restoreSetlist(setlist, index);
      if (s.state.setlistById(setlist.id) == null) {
        return;
      }
      if (wasActive && s.settings.activeSetlistId.isEmpty) {
        s.settings
          ..activeSetlistId = setlist.id
          ..activeSetlistIndex = activeIndex;
        await s.settings.save();
      }
      if (mounted) {
        setState(() => _setlistId = setlist.id);
      }
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(done), action: SnackBarAction(label: undo, onPressed: restore)));
  }

  Future<void> _rename(BuildContext context, Preset p) async {
    final Services s = AppScope.of(context);
    final TextEditingController name = TextEditingController(text: p.name);
    final TextEditingController notes = TextEditingController(text: p.notes);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, 'Editar preajuste', 'Edit preset')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(controller: name, maxLength: Preset.maxName, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'))),
            TextField(controller: notes, maxLength: Preset.maxNotes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes')), maxLines: 3),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
    );
    if (ok == true) {
      p.name = name.text.trim();
      p.notes = notes.text.trim();
      await s.state.savePresets();
    }
    disposeLater(<ChangeNotifier>[name, notes]);
  }

  Future<void> _newSetlist(BuildContext context) async {
    final Services s = AppScope.of(context);
    final String? name = await _askText(context, t(context, 'Nombre de la setlist', 'Setlist name'));
    if (name == null) {
      return;
    }
    final Setlist sl = await s.state.addSetlist(name);
    if (mounted) {
      setState(() => _setlistId = sl.id);
    }
  }

  Future<String?> _askText(BuildContext context, String title) async {
    final TextEditingController ctrl = TextEditingController();
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, maxLength: Preset.maxName, textCapitalization: TextCapitalization.sentences),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(t(context, 'Aceptar', 'OK'))),
        ],
      ),
    );
    disposeLater(<ChangeNotifier>[ctrl]);
    if (v == null || v.isEmpty) {
      return null;
    }
    return v;
  }

  /// Exporta a un JSON y abre la hoja de compartir anclada al botón tocado.
  Future<void> _export(BuildContext context, Rect? origin) async {
    final Services s = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = t(context, 'No se pudo compartir el archivo.', 'Could not share the file.');
    final String subject = t(context, 'Clave: preajustes', 'Clave: presets');
    final String fileName = presetsFileName(spanish: isSpanish(context));
    try {
      final String json = const JsonEncoder.withIndent('  ').convert(s.state.exportPresets());
      final String path = await s.store.absolutePath('export/$fileName');
      final File f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(json, flush: true);
      await s.platform.share(ShareParams(files: <XFile>[XFile(path, mimeType: 'application/json')], subject: subject, sharePositionOrigin: origin));
    } catch (e) {
      debugPrint('Exportar: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _import(BuildContext context) async {
    final Services s = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool spanish = isSpanish(context);
    final String errMsg = t(context, 'No se pudo leer el archivo: no es un archivo de preajustes de Clave.', 'Could not read the file: it is not a Clave presets file.');
    try {
      final XFile? file = await s.platform.pickJsonFile();
      if (file == null) {
        return;
      }
      final int size = await file.length();
      if (size > 5 * 1024 * 1024) {
        throw const FormatException('Archivo demasiado grande');
      }
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('No es un objeto JSON');
      }
      final ImportResult r = await s.state.importPresets(decoded);
      final String msg = spanish
          ? '${r.presets} ${r.presets == 1 ? 'preajuste importado' : 'preajustes importados'}${r.setlists > 0 ? ' y ${r.setlists} ${r.setlists == 1 ? 'setlist' : 'setlists'}' : ''}.'
          : '${r.presets} ${r.presets == 1 ? 'preset' : 'presets'}${r.setlists > 0 ? ' and ${r.setlists} ${r.setlists == 1 ? 'setlist' : 'setlists'}' : ''} imported.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint('Importar: $e');
      messenger.showSnackBar(SnackBar(content: Text(errMsg)));
    }
  }
}
