import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../games/shell/widgets.dart';
import '../../model/area.dart';
import '../../model/group.dart';
import '../../model/profile.dart';
import 'report_data.dart';
import 'report_pdf.dart';

/// Modo docente: grupos de aula, tabla del curso, exportación e importación.
class TeacherScreen extends StatefulWidget {
  const TeacherScreen({super.key});

  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  bool _busy = false;

  Future<void> _nuevoGrupo() async {
    final TextEditingController ctrl = TextEditingController();
    final String? nombre = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(S.nuevoGrupo),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: S.nombreGrupo), textCapitalization: TextCapitalization.sentences),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(ctrl.text.trim()), child: const Text(S.guardar)),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty || !mounted) {
      return;
    }
    await AppScope.read(context).state.addGroup(nombre);
  }

  Future<void> _exportarTodo() async {
    setState(() => _busy = true);
    try {
      final Services s = AppScope.read(context);
      final Map<String, dynamic> data = await s.state.exportAll();
      final File f = File(await s.store.absolutePath('export/pilas-datos-${DateTime.now().millisecondsSinceEpoch}.json'));
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(f.path, mimeType: 'application/json')], text: 'Datos de Pilas'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importar() async {
    final TextEditingController ctrl = TextEditingController();
    final String? texto = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(S.importarDatos),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Pega aquí el contenido del archivo JSON exportado desde otra tableta.', style: TextStyle(color: PilasColors.tintaSuave)),
              const SizedBox(height: 8),
              TextField(controller: ctrl, maxLines: 6, decoration: const InputDecoration(hintText: '{"app":"pilas", ...}')),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text(S.importarDatos)),
        ],
      ),
    );
    ctrl.dispose();
    if (texto == null || texto.trim().isEmpty || !mounted) {
      return;
    }
    try {
      final dynamic decoded = jsonDecode(texto);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('No es un objeto JSON');
      }
      final int n = await AppScope.read(context).state.importAll(decoded);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se importaron $n perfiles.')));
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo importar: ${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState state = s.state;
    return Scaffold(
      appBar: AppBar(title: const Text(S.modoDocente)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Crea un grupo por curso y agrega los perfiles de los niños que usan esta tableta. Para varias tabletas, exporta los datos de cada una e impórtalos aquí.',
            style: TextStyle(color: PilasColors.tintaSuave),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(child: FilledButton.icon(onPressed: _nuevoGrupo, icon: const Icon(Icons.group_add_rounded), label: const Text(S.nuevoGrupo))),
              const SizedBox(width: 10),
              IconButton.outlined(onPressed: _busy ? null : _exportarTodo, icon: const Icon(Icons.upload_rounded), tooltip: S.exportarDatos),
              const SizedBox(width: 6),
              IconButton.outlined(onPressed: _importar, icon: const Icon(Icons.download_rounded), tooltip: S.importarDatos),
            ],
          ),
          const SizedBox(height: 16),
          if (state.groups.isEmpty) const Text('Todavía no hay grupos.', style: TextStyle(color: PilasColors.tintaSuave)),
          for (final ClassGroup g in state.groups) _GroupCard(group: g),
        ],
      ),
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({required this.group});

  final ClassGroup group;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _busy = false;

  Future<void> _miembros() async {
    final AppState state = AppScope.read(context).state;
    final Set<String> sel = Set<String>.from(widget.group.profileIds);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setDialog) => AlertDialog(
          title: const Text(S.agregarNinos),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final Profile p in state.profiles)
                  CheckboxListTile(
                    value: sel.contains(p.id),
                    onChanged: (bool? v) => setDialog(() {
                      if (v == true) {
                        sel.add(p.id);
                      } else {
                        sel.remove(p.id);
                      }
                    }),
                    secondary: EmojiImage(p.avatar, size: 32),
                    title: Text(p.nombre),
                    subtitle: Text('${p.age} años'),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(S.guardar)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    widget.group.profileIds
      ..clear()
      ..addAll(sel);
    await state.updateGroup(widget.group);
  }

  List<ChildReport> _reports(AppState state) {
    final List<ChildReport> out = <ChildReport>[];
    for (final String id in widget.group.profileIds) {
      final Profile? p = state.profileById(id);
      if (p != null) {
        out.add(ChildReport(profile: p, progress: state.progressOf(p.id)));
      }
    }
    return out;
  }

  Future<void> _csv() async {
    final AppState state = AppScope.read(context).state;
    final List<ChildReport> rs = _reports(state);
    final StringBuffer b = StringBuffer();
    b.writeln('Niño;Edad;Nivel;Minutos semana;Minutos total;Rondas;Aciertos;${Area.values.map((Area a) => a.nombre).join(';')};Habilidades logradas');
    for (final ChildReport r in rs) {
      final List<AreaSummary> areas = r.areas;
      b.writeln(<String>[
        r.profile.nombre,
        '${r.profile.age}',
        r.band.label,
        '${r.minutosSemana}',
        '${r.minutosTotal}',
        '${r.rondasTotal}',
        '${r.aciertosTotal}',
        ...areas.map((AreaSummary a) => '${a.skillsLogradas}/${a.skillsPosibles}'),
        '${r.progress.skillsAchieved.length}',
      ].join(';'));
    }
    final Services s = AppScope.read(context);
    final File f = File(await s.store.absolutePath('export/pilas-grupo-${widget.group.nombre.replaceAll(' ', '-')}.csv'));
    await f.parent.create(recursive: true);
    await f.writeAsString(b.toString());
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(f.path, mimeType: 'text/csv')], text: 'Grupo ${widget.group.nombre}'));
  }

  Future<void> _pdf() async {
    setState(() => _busy = true);
    try {
      final AppState state = AppScope.read(context).state;
      final Uint8List bytes = await ReportPdf.buildGroup(widget.group.nombre, _reports(state));
      await ReportPdf.share(bytes, 'pilas-grupo-${widget.group.nombre.replaceAll(' ', '-')}.pdf');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _borrar() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('¿Borrar el grupo ${widget.group.nombre}?'),
        content: const Text('Los perfiles de los niños no se borran.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(S.borrar)),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.read(context).state.deleteGroup(widget.group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context).state;
    final List<ChildReport> rs = _reports(state);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(widget.group.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(onPressed: _miembros, icon: const Icon(Icons.group_rounded), tooltip: S.agregarNinos),
                IconButton(onPressed: rs.isEmpty ? null : _csv, icon: const Icon(Icons.table_chart_rounded), tooltip: S.exportarCsv),
                IconButton(onPressed: rs.isEmpty || _busy ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: S.informeGrupo),
                IconButton(onPressed: _borrar, icon: const Icon(Icons.delete_outline_rounded), tooltip: S.borrar),
              ],
            ),
            if (rs.isEmpty)
              const Text('Sin niños todavía. Toca el ícono de grupo para agregarlos.', style: TextStyle(color: PilasColors.tintaSuave))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 44,
                  columns: <DataColumn>[
                    const DataColumn(label: Text('Niño')),
                    const DataColumn(label: Text('Min. sem.')),
                    const DataColumn(label: Text('Aciertos')),
                    for (final Area a in Area.values) DataColumn(label: Text(a.nombreCorto)),
                  ],
                  rows: <DataRow>[
                    for (final ChildReport r in rs)
                      DataRow(cells: <DataCell>[
                        DataCell(Text(r.profile.nombre)),
                        DataCell(Text('${r.minutosSemana}')),
                        DataCell(Text(r.rondasTotal == 0 ? '-' : '${(r.aciertosTotal * 100 / r.rondasTotal).round()} %')),
                        for (final AreaSummary a in r.areas) DataCell(Text('${a.skillsLogradas}/${a.skillsPosibles}')),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
