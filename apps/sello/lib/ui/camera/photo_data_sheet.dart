import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/capture_session.dart';
import '../../model/models.dart';

/// Hoja para elegir el proyecto y escribir los datos de las próximas fotos:
/// campos del proyecto, notas y etiquetas. Los valores se conservan para las
/// fotos siguientes hasta que se cambien o se cambie de proyecto.
Future<void> showPhotoDataSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: const _PhotoDataSheet(),
    ),
  );
}

class _PhotoDataSheet extends StatefulWidget {
  const _PhotoDataSheet();

  @override
  State<_PhotoDataSheet> createState() => _PhotoDataSheetState();
}

class _PhotoDataSheetState extends State<_PhotoDataSheet> {
  final Map<String, TextEditingController> _ctrls = <String, TextEditingController>{};
  TextEditingController? _notes;
  final TextEditingController _tag = TextEditingController();
  CaptureSession? _session;
  String? _projectId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      final CaptureSession session = AppScope.of(context).session;
      _session = session;
      _notes = TextEditingController(text: session.notes);
      session.addListener(_onSession);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    disposeLater(<ChangeNotifier>[..._ctrls.values, if (_notes != null) _notes!, _tag]);
    super.dispose();
  }

  /// Si el proyecto cambió (aquí o en otra pantalla), los cuadros de texto
  /// muestran los valores iniciales del nuevo.
  void _onSession() {
    final CaptureSession s = _session!;
    if (s.project.id != _projectId) {
      _projectId = s.project.id;
      disposeLater(List<ChangeNotifier>.of(_ctrls.values));
      _ctrls.clear();
    } else {
      for (final MapEntry<String, TextEditingController> e in _ctrls.entries) {
        final String v = s.fields[e.key] ?? '';
        if (e.value.text != v) {
          e.value.text = v;
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  TextEditingController _ctrl(FieldDef f) {
    final CaptureSession s = _session!;
    return _ctrls.putIfAbsent(f.key, () {
      final TextEditingController c = TextEditingController(text: s.fields[f.key] ?? f.defaultValue);
      c.addListener(() => s.setField(f.key, c.text));
      return c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Services sv = AppScope.of(context);
    final AppState state = sv.state;
    final CaptureSession session = _session!;
    final Project project = session.project;
    _projectId ??= project.id;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text(t(context, 'Proyecto', 'Project'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final Project p in state.projects)
                ChoiceChip(
                  label: Text('${p.emoji.isNotEmpty ? '${p.emoji} ' : ''}${p.name}'),
                  selected: p.id == project.id,
                  onSelected: (_) => session.selectProject(p.id),
                ),
            ],
          ),
          if (project.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(project.notes, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 14),
          if (project.fields.isNotEmpty) ...<Widget>[
            Text(t(context, 'Campos del proyecto', 'Project fields'), style: Theme.of(context).textTheme.titleMedium),
            Text(t(context, 'Se escriben en las próximas fotos y se conservan hasta que los cambies o cambies de proyecto.', 'They go on the next photos and are kept until you change them or switch projects.'), style: Theme.of(context).textTheme.bodySmall),
            for (final FieldDef f in project.fields)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _ctrl(f),
                  decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder(), isDense: true),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            const SizedBox(height: 14),
          ],
          Text(t(context, 'Notas para el sello', 'Notes for the stamp'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: t(context, 'Ej.: Fisura en muro norte, nivel 2', 'E.g.: Crack on north wall, level 2'), border: const OutlineInputBorder(), isDense: true),
            onChanged: (String v) => session.notes = v,
          ),
          const SizedBox(height: 14),
          Text(t(context, 'Etiquetas', 'Tags'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final String tag in session.tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => session.removeTag(tag),
                ),
              for (final String tag in state.allTags.where((String x) => !session.tags.contains(x)).take(12))
                ActionChip(
                  label: Text(tag),
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: () => session.addTag(tag),
                ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _tag,
                  decoration: InputDecoration(hintText: t(context, 'Nueva etiqueta', 'New tag'), isDense: true),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              IconButton(tooltip: t(context, 'Añadir etiqueta', 'Add tag'), onPressed: _addTag, icon: const Icon(Icons.add_circle_outline)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t(context, 'Listo', 'Done'))),
          ),
        ],
      ),
    );
  }

  void _addTag() {
    final String v = _tag.text.trim().replaceAll(' ', '_');
    if (v.isEmpty) {
      return;
    }
    _session!.addTag(v);
    _tag.clear();
  }
}
