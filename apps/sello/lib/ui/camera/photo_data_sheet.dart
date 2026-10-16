import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/settings.dart';
import '../../model/models.dart';

/// Hoja para elegir el proyecto y escribir los datos de la próxima foto:
/// campos del proyecto, notas y etiquetas. Modifica [fields] y [tags] en
/// sitio y avisa las notas con [onChanged].
Future<void> showPhotoDataSheet(BuildContext context, {required Map<String, String> fields, required String notes, required List<String> tags, required ValueChanged<String> onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _PhotoDataSheet(fields: fields, notes: notes, tags: tags, onChanged: onChanged),
    ),
  );
}

class _PhotoDataSheet extends StatefulWidget {
  const _PhotoDataSheet({required this.fields, required this.notes, required this.tags, required this.onChanged});

  final Map<String, String> fields;
  final String notes;
  final List<String> tags;
  final ValueChanged<String> onChanged;

  @override
  State<_PhotoDataSheet> createState() => _PhotoDataSheetState();
}

class _PhotoDataSheetState extends State<_PhotoDataSheet> {
  final Map<String, TextEditingController> _ctrls = <String, TextEditingController>{};
  late final TextEditingController _notes = TextEditingController(text: widget.notes);
  final TextEditingController _tag = TextEditingController();

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[..._ctrls.values, _notes, _tag]);
    super.dispose();
  }

  TextEditingController _ctrl(FieldDef f) {
    return _ctrls.putIfAbsent(f.key, () {
      final TextEditingController c = TextEditingController(text: widget.fields[f.key] ?? f.defaultValue);
      widget.fields[f.key] = c.text;
      c.addListener(() {
        widget.fields[f.key] = c.text;
        widget.onChanged(_notes.text);
      });
      return c;
    });
  }

  void _switchProject(AppSettings st, Project p) {
    st.currentProjectId = p.id;
    st.save();
    // Al cambiar de proyecto se olvidan los campos del anterior.
    widget.fields.clear();
    disposeLater(List<ChangeNotifier>.of(_ctrls.values));
    _ctrls.clear();
    setState(() {});
    widget.onChanged(_notes.text);
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState state = s.state;
    final AppSettings st = s.settings;
    final Project project = state.projectById(st.currentProjectId);
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
                  onSelected: (_) => _switchProject(st, p),
                ),
            ],
          ),
          if (project.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(project.notes, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 14),
          if (project.fields.isNotEmpty) ...<Widget>[
            Text(t(context, 'Campos del proyecto', 'Project fields'), style: Theme.of(context).textTheme.titleMedium),
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
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 14),
          Text(t(context, 'Etiquetas', 'Tags'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final String tag in widget.tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() => widget.tags.remove(tag)),
                ),
              for (final String tag in state.allTags.where((String x) => !widget.tags.contains(x)).take(12))
                ActionChip(
                  label: Text(tag),
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: () => setState(() => widget.tags.add(tag)),
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
              IconButton(onPressed: _addTag, icon: const Icon(Icons.add_circle_outline)),
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
    setState(() {
      if (!widget.tags.contains(v)) {
        widget.tags.add(v);
      }
      _tag.clear();
    });
  }
}
