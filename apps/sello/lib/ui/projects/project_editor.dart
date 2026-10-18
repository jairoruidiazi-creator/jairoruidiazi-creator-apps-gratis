import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../model/models.dart';
import '../../stamp/stamp_data.dart';
import 'projects_screen.dart';

/// Edición de un proyecto: nombre, emoji, notas, plantilla, patrón del
/// nombre de archivo y campos personalizados.
class ProjectEditor extends StatefulWidget {
  const ProjectEditor({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<ProjectEditor> {
  late final TextEditingController _name;
  late final TextEditingController _emoji;
  late final TextEditingController _notes;
  late final TextEditingController _pattern;

  /// Copia que se edita; el proyecto vivo solo cambia al guardar.
  Project? _draft;
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draft == null) {
      final Project p = AppScope.of(context).state.projectById(widget.projectId);
      _draft = p.copy();
      _name = TextEditingController(text: p.name);
      _emoji = TextEditingController(text: p.emoji);
      _notes = TextEditingController(text: p.notes);
      _pattern = TextEditingController(text: p.fileNamePattern);
      for (final TextEditingController c in <TextEditingController>[_name, _emoji, _notes, _pattern]) {
        c.addListener(_markDirty);
      }
    }
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _emoji, _notes, _pattern]);
    super.dispose();
  }

  Future<void> _save(AppState st) async {
    final Project d = _draft!;
    final Project live = st.projectById(widget.projectId);
    d.name = _name.text.trim().isEmpty ? live.name : _name.text.trim();
    d.emoji = _emoji.text.trim();
    d.notes = _notes.text.trim();
    d.fileNamePattern = _pattern.text.trim().isEmpty ? '{proyecto}_{fecha}_{hora}' : _pattern.text.trim();
    if (live.id == d.id) {
      live.assignFrom(d);
      await st.saveProjects();
    }
    if (mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  /// Al salir sin guardar se pregunta si se descartan los cambios.
  Future<void> _confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, '¿Descartar los cambios?', 'Discard changes?')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Seguir editando', 'Keep editing'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Descartar', 'Discard'))),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    final Project p = _draft!;
    final String sample = buildFileName(_pattern.text.trim().isEmpty ? '{proyecto}_{fecha}_{hora}' : _pattern.text, project: _name.text, time: clock.now(), lat: 4.711, lon: -74.0721, n: 7);
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'Proyecto', 'Project')),
        actions: <Widget>[
          if (st.projects.length > 1)
            IconButton(
              tooltip: t(context, 'Borrar proyecto', 'Delete project'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(t(context, 'Borrar proyecto', 'Delete project')),
                    content: Text(t(context, 'Las fotos no se borran: pasan al primer proyecto de la lista.', 'Photos are not deleted: they move to the first project in the list.')),
                    actions: <Widget>[
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Borrar', 'Delete'))),
                    ],
                  ),
                );
                if (ok == true) {
                  await st.deleteProject(p.id);
                  if (s.settings.currentProjectId == p.id) {
                    // La sesión de captura reinicia los campos al notar el cambio.
                    await s.session.selectProject(st.projects.first.id);
                  }
                  if (context.mounted) {
                    setState(() => _dirty = false);
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          TextButton(onPressed: () => _save(st), child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: 72, child: TextField(controller: _emoji, textAlign: TextAlign.center, maxLength: 2, decoration: const InputDecoration(labelText: 'Emoji', counterText: '', border: OutlineInputBorder(), hintText: '🏗️'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.sentences)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: t(context, 'Descripción (no sale en el sello)', 'Description (not on the stamp)'), border: const OutlineInputBorder())),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: st.templates.any((StampTemplate x) => x.id == p.templateId) ? p.templateId : 'default',
            decoration: InputDecoration(labelText: t(context, 'Plantilla de sello', 'Stamp template'), border: const OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[for (final StampTemplate tpl in st.templates) DropdownMenuItem<String>(value: tpl.id, child: Text(tpl.displayName(spanish: AppScope.of(context).settings.spanish)))],
            onChanged: (String? v) {
              if (v != null) {
                setState(() {
                  p.templateId = v;
                  _dirty = true;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pattern,
            decoration: InputDecoration(
              labelText: t(context, 'Nombre de los archivos', 'File names'),
              border: const OutlineInputBorder(),
              helperText: '${t(context, 'Variables', 'Tokens')}: {proyecto} {fecha} {hora} {lat} {lon} {n}\n${t(context, 'Ejemplo', 'Example')}: $sample.jpg',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(child: Text(t(context, 'Campos personalizados', 'Custom fields'), style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () async {
                  final String? label = await askText(context, t(context, 'Nombre del campo', 'Field name'), hint: t(context, 'Ej.: Lote, Inspector, Nivel', 'E.g.: Lot, Inspector, Level'));
                  if (label != null && label.trim().isNotEmpty) {
                    setState(() {
                      p.fields.add(FieldDef(newId(), label.trim()));
                      _dirty = true;
                    });
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(t(context, 'Añadir', 'Add')),
              ),
            ],
          ),
          Text(
            t(
              context,
              'Sus valores se llenan en la cámara, tocando el nombre del proyecto, y se conservan en las fotos siguientes hasta que los cambies o cambies de proyecto. Salen con su nombre en el sello, el CSV, el KML y el PDF (por ejemplo: Lote, Inspector, Elemento).',
              'Their values are filled in on the camera, by tapping the project name, and stay for the next photos until you change them or switch projects. They appear with their name on the stamp, the CSV, the KML and the PDF (e.g.: Lot, Inspector, Element).',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          if (p.fields.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(t(context, 'Sin campos.', 'No fields.'), style: Theme.of(context).textTheme.bodySmall)),
          for (int i = 0; i < p.fields.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.short_text),
              title: Text(p.fields[i].label),
              subtitle: p.fields[i].defaultValue.isEmpty ? null : Text('${t(context, 'Valor inicial', 'Default')}: ${p.fields[i].defaultValue}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: t(context, 'Valor inicial', 'Default value'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final String? v = await askText(context, '${t(context, 'Valor inicial de', 'Default value for')} ${p.fields[i].label}', initial: p.fields[i].defaultValue);
                      if (v != null) {
                        setState(() {
                          p.fields[i] = FieldDef(p.fields[i].key, p.fields[i].label, defaultValue: v.trim());
                          _dirty = true;
                        });
                      }
                    },
                  ),
                  IconButton(
                    tooltip: t(context, 'Quitar', 'Remove'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      p.fields.removeAt(i);
                      _dirty = true;
                    }),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => _save(st), child: Text(_dirty ? t(context, 'Guardar cambios', 'Save changes') : t(context, 'Listo', 'Done'))),
        ],
      ),
      ),
    );
  }
}
