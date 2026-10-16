import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import '../../audio/sequencer.dart';
import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../model/models.dart';

/// Preajustes (canciones) y setlists del metrónomo.
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
        final Setlist? setlist = _setlistId == null ? null : st.setlists.where((Setlist x) => x.id == _setlistId).firstOrNull;
        final List<Preset> shown = setlist == null ? st.presets : setlist.presetIds.map(st.presetById).whereType<Preset>().toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(t(context, 'Preajustes', 'Presets')),
            actions: <Widget>[
              IconButton(tooltip: t(context, 'Importar', 'Import'), icon: const Icon(Icons.file_open_outlined), onPressed: () => _import(context)),
              IconButton(tooltip: t(context, 'Exportar', 'Export'), icon: const Icon(Icons.ios_share_rounded), onPressed: st.presets.isEmpty ? null : () => _export(context)),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _savePreset(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(t(context, 'Guardar el actual', 'Save current')),
          ),
          body: Column(
            children: <Widget>[
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: <Widget>[
                    ChoiceChip(label: Text(t(context, 'Todos', 'All')), selected: _setlistId == null, onSelected: (_) => setState(() => _setlistId = null)),
                    const SizedBox(width: 8),
                    for (final Setlist sl in st.setlists) ...<Widget>[
                      ChoiceChip(
                        label: Text('${sl.name} (${sl.presetIds.length})'),
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
                      Expanded(child: Text(t(context, 'Mantén presionado un preajuste para añadirlo o quitarlo de la setlist.', 'Long-press a preset to add it to or remove it from the setlist.'), style: Theme.of(context).textTheme.bodySmall)),
                      IconButton(tooltip: t(context, 'Borrar setlist', 'Delete setlist'), icon: const Icon(Icons.delete_outline), onPressed: () async {
                        await st.deleteSetlist(setlist.id);
                        if (mounted) {
                          setState(() => _setlistId = null);
                        }
                      }),
                    ],
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t(context, 'Aún no hay preajustes. Ajusta el metrónomo y toca "Guardar el actual".', 'No presets yet. Set up the metronome and tap "Save current".'), textAlign: TextAlign.center)))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: shown.length,
                        buildDefaultDragHandles: setlist != null,
                        // onReorderItem existe desde Flutter 3.41; se mantiene onReorder por compatibilidad.
                        // ignore: deprecated_member_use
                        onReorder: (int a, int b) async {
                          if (setlist == null) {
                            return;
                          }
                          if (b > a) {
                            b -= 1;
                          }
                          final String id = setlist.presetIds.removeAt(a);
                          setlist.presetIds.insert(b, id);
                          await st.savePresets();
                        },
                        itemBuilder: (BuildContext context, int i) {
                          final Preset p = shown[i];
                          final RhythmConfig r = p.rhythm;
                          return ListTile(
                            key: ValueKey<String>('${setlist?.id ?? 'all'}-${p.id}'),
                            leading: CircleAvatar(child: Text(r.bpm.toStringAsFixed(0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                            title: Text(p.name.isEmpty ? t(context, 'Sin nombre', 'Untitled') : p.name),
                            subtitle: Text('${r.timeSignature} · ${_subName(context, r.subdivision)}${r.trainer != null ? ' · ${t(context, 'entrenador', 'trainer')}' : ''}${p.notes.isNotEmpty ? '\n${p.notes}' : ''}'),
                            isThreeLine: p.notes.isNotEmpty,
                            trailing: PopupMenuButton<String>(
                              onSelected: (String v) async {
                                if (v == 'load') {
                                  s.metronome.setConfig(r);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                } else if (v == 'rename') {
                                  await _rename(context, p);
                                } else if (v == 'delete') {
                                  await st.deletePreset(p.id);
                                } else if (v.startsWith('sl:')) {
                                  final Setlist? target = st.setlists.where((Setlist x) => x.id == v.substring(3)).firstOrNull;
                                  if (target != null) {
                                    if (target.presetIds.contains(p.id)) {
                                      target.presetIds.remove(p.id);
                                    } else {
                                      target.presetIds.add(p.id);
                                    }
                                    await st.savePresets();
                                  }
                                }
                              },
                              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(value: 'load', child: Text(t(context, 'Cargar', 'Load'))),
                                PopupMenuItem<String>(value: 'rename', child: Text(t(context, 'Renombrar / notas', 'Rename / notes'))),
                                for (final Setlist sl in st.setlists)
                                  PopupMenuItem<String>(value: 'sl:${sl.id}', child: Text('${sl.presetIds.contains(p.id) ? '✓ ' : ''}${sl.name}')),
                                PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
                              ],
                            ),
                            onTap: () {
                              s.metronome.setConfig(r);
                              Navigator.of(context).pop();
                            },
                            onLongPress: setlist == null
                                ? null
                                : () async {
                                    if (setlist.presetIds.contains(p.id)) {
                                      setlist.presetIds.remove(p.id);
                                    } else {
                                      setlist.presetIds.add(p.id);
                                    }
                                    await st.savePresets();
                                  },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
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
    final Setlist? sl = _setlistId == null ? null : s.state.setlists.where((Setlist x) => x.id == _setlistId).firstOrNull;
    if (sl != null) {
      sl.presetIds.add(p.id);
      await s.state.savePresets();
    }
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
            TextField(controller: name, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'))),
            TextField(controller: notes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes')), maxLines: 3),
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
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences),
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

  Future<void> _export(BuildContext context) async {
    final Services s = AppScope.of(context);
    final String json = const JsonEncoder.withIndent('  ').convert(s.state.exportPresets());
    final String path = await s.store.absolutePath('export/clave-preajustes.json');
    final File f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(json);
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(path, mimeType: 'application/json')], subject: 'Clave: preajustes'));
  }

  Future<void> _import(BuildContext context) async {
    final Services s = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String okMsg = t(context, 'preajustes importados', 'presets imported');
    final String errMsg = t(context, 'No se pudo leer el archivo.', 'Could not read the file.');
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[const XTypeGroup(label: 'JSON', extensions: <String>['json'])]);
    if (file == null) {
      return;
    }
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('No es un objeto JSON');
      }
      final int n = await s.state.importPresets(decoded);
      messenger.showSnackBar(SnackBar(content: Text('$n $okMsg')));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errMsg)));
    }
  }
}
