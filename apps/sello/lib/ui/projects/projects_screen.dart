import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/settings.dart';
import '../../model/models.dart';
import 'project_editor.dart';
import 'template_editor.dart';

/// Proyectos (carpetas de trabajo con sus campos) y plantillas de sello.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.state, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final AppSettings settings = s.settings;
        final Project current = st.projectById(settings.currentProjectId);
        final TextTheme tt = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(t(context, 'Proyectos', 'Projects'), style: tt.titleLarge)),
                FilledButton.tonalIcon(
                  onPressed: () => _newProject(context, st, settings),
                  icon: const Icon(Icons.add),
                  label: Text(t(context, 'Nuevo', 'New')),
                ),
              ],
            ),
            Text(t(context, 'El proyecto activo se escribe en el sello y agrupa las fotos. Toca para activarlo; el lápiz lo edita.', 'The active project is written on the stamp and groups the photos. Tap to activate; the pencil edits it.'), style: tt.bodySmall),
            const SizedBox(height: 6),
            for (final Project p in st.projects)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  leading: Icon(p.id == current.id ? Icons.radio_button_checked : Icons.radio_button_off, color: p.id == current.id ? Theme.of(context).colorScheme.primary : null),
                  title: Text('${p.emoji.isNotEmpty ? '${p.emoji} ' : ''}${p.name}'),
                  subtitle: Text(
                    '${st.photos.where((PhotoRecord x) => x.projectId == p.id).length} ${t(context, 'fotos', 'photos')} · ${t(context, 'sello', 'stamp')}: ${st.templateForProject(p).name}${p.fields.isNotEmpty ? ' · ${p.fields.map((FieldDef f) => f.label).join(', ')}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: t(context, 'Editar', 'Edit'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectEditor(projectId: p.id))),
                  ),
                  onTap: () {
                    settings.currentProjectId = p.id;
                    settings.save();
                  },
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(child: Text(t(context, 'Plantillas de sello', 'Stamp templates'), style: tt.titleLarge)),
                FilledButton.tonalIcon(
                  onPressed: () => _newTemplate(context, st),
                  icon: const Icon(Icons.add),
                  label: Text(t(context, 'Nueva', 'New')),
                ),
              ],
            ),
            Text(t(context, 'Qué datos lleva el sello, dónde va, tamaño, colores y logo. Cada proyecto elige su plantilla.', 'What the stamp shows, where it goes, size, colors and logo. Each project picks its template.'), style: tt.bodySmall),
            const SizedBox(height: 6),
            for (final StampTemplate tpl in st.templates)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  leading: const Icon(Icons.approval_outlined),
                  title: Text(tpl.name),
                  subtitle: Text(
                    '${tpl.items.length} ${t(context, 'datos', 'items')} · ${_positionName(context, tpl.position)}${tpl.logoPath != null ? ' · logo' : ''} · ${st.projects.where((Project p) => p.templateId == tpl.id).length} ${t(context, 'proyectos', 'projects')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String v) async {
                      if (v == 'dup') {
                        final StampTemplate copy = await st.addTemplate('${tpl.name} (2)', copyOf: tpl);
                        if (context.mounted) {
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TemplateEditor(templateId: copy.id)));
                        }
                      } else if (v == 'del') {
                        await st.deleteTemplate(tpl.id);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'dup', child: Text(t(context, 'Duplicar', 'Duplicate'))),
                      if (tpl.id != 'default') PopupMenuItem<String>(value: 'del', child: Text(t(context, 'Borrar', 'Delete'))),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TemplateEditor(templateId: tpl.id))),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _positionName(BuildContext context, StampPosition p) {
    switch (p) {
      case StampPosition.bottomLeft:
        return t(context, 'abajo izquierda', 'bottom left');
      case StampPosition.bottomRight:
        return t(context, 'abajo derecha', 'bottom right');
      case StampPosition.topLeft:
        return t(context, 'arriba izquierda', 'top left');
      case StampPosition.topRight:
        return t(context, 'arriba derecha', 'top right');
      case StampPosition.bottomBar:
        return t(context, 'franja inferior', 'bottom bar');
    }
  }

  Future<void> _newProject(BuildContext context, AppState st, AppSettings settings) async {
    final String? name = await askText(context, t(context, 'Nombre del proyecto', 'Project name'), hint: t(context, 'Ej.: Obra Calle 80', 'E.g.: Site 80th St'));
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final Project p = await st.addProject(name.trim());
    settings.currentProjectId = p.id;
    await settings.save();
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectEditor(projectId: p.id)));
    }
  }

  Future<void> _newTemplate(BuildContext context, AppState st) async {
    final String? name = await askText(context, t(context, 'Nombre de la plantilla', 'Template name'), hint: t(context, 'Ej.: Interventoría', 'E.g.: Inspection'));
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final StampTemplate tpl = await st.addTemplate(name.trim(), copyOf: st.templateById('default'));
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TemplateEditor(templateId: tpl.id)));
    }
  }
}

/// Diálogo sencillo de una línea de texto.
Future<String?> askText(BuildContext context, String title, {String? initial, String? hint}) async {
  final TextEditingController ctrl = TextEditingController(text: initial ?? '');
  final String? v = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint), textCapitalization: TextCapitalization.sentences, onSubmitted: (String s) => Navigator.pop(context, s)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(t(context, 'Aceptar', 'OK'))),
      ],
    ),
  );
  disposeLater(<ChangeNotifier>[ctrl]);
  return v;
}
