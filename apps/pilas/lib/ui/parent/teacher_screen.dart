import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../games/shell/widgets.dart';
import '../../model/age_band.dart';
import '../../model/area.dart';
import '../../model/group.dart';
import '../../model/profile.dart';
import 'report_data.dart';
import 'report_pdf.dart';

/// Tabla CSV de un grupo, lista para Excel o Google Sheets en español: con
/// BOM (para que Excel lea bien las tildes), separada por punto y coma y con
/// los campos entre comillas cuando hace falta.
String groupCsv(List<ChildReport> reports) {
  String campo(String v) => v.contains(';') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v;
  final StringBuffer b = StringBuffer('\uFEFF');
  b.write(<String>[
    'Niño',
    'Edad',
    'Tramo',
    'Minutos últimos 7 días',
    'Minutos en total',
    'Rondas jugadas',
    // Es un conteo, no el porcentaje que muestran el informe y el PDF.
    'Rondas acertadas al primer intento',
    ...Area.values.map((Area a) => a.nombre),
    'Habilidades logradas del tramo',
  ].map(campo).join(';'));
  b.write('\r\n');
  for (final ChildReport r in reports) {
    final List<AreaSummary> areas = r.areas;
    b.write(<String>[
      r.profile.nombre,
      '${r.profile.age}',
      r.band.label,
      '${r.minutos7Dias}',
      '${r.minutosTotal}',
      '${r.rondasTotal}',
      '${r.aciertosTotal}',
      ...areas.map((AreaSummary a) => a.soloJuegoLibre ? 'libre' : '${a.skillsLogradas} de ${a.skillsPosibles}'),
      '${r.skillsLogradasTramo} de ${r.skillsDelTramo.length}',
    ].map(campo).join(';'));
    b.write('\r\n');
  }
  return b.toString();
}

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
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: S.nombreGrupo), textCapitalization: TextCapitalization.sentences, maxLength: 40),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(ctrl.text.trim()), child: const Text(S.guardar)),
        ],
      ),
    );
    // Se libera después de la animación de cierre del diálogo.
    Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
    if (nombre == null || nombre.isEmpty || !mounted) {
      return;
    }
    await AppScope.read(context).state.addGroup(nombre);
  }

  Future<void> _exportarTodo(BuildContext buttonContext) async {
    final Services s = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> data = await s.state.exportAll();
      if (!buttonContext.mounted) {
        return;
      }
      final DateTime now = clock.now();
      final String fecha = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await s.sharer.shareBytes(buttonContext, s.store, utf8.encode(jsonEncode(data)), baseName: 'pilas-datos-$fecha', extension: 'json', mimeType: 'application/json', text: 'Datos de Pilas');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importar() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final AppState state = s.state;
    return Scaffold(
      appBar: AppBar(title: const Text(S.modoDocente)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Crea un grupo por curso y agrega los perfiles de los niños que usan esta tableta. Para juntar varias tabletas, exporta los datos de cada una e impórtalos aquí: se juntan con lo que ya hay, sin borrar nada. Las sesiones, pegatinas y habilidades de las dos tabletas quedan todas, y de cada juego queda el nivel más avanzado.',
            style: TextStyle(color: pal.tintaSuave),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(key: const ValueKey<String>('nuevo-grupo'), onPressed: _nuevoGrupo, icon: const Icon(Icons.group_add_rounded), label: const Text(S.nuevoGrupo)),
              Builder(
                builder: (BuildContext buttonContext) => OutlinedButton.icon(
                  key: const ValueKey<String>('exportar-datos'),
                  onPressed: _busy ? null : () => _exportarTodo(buttonContext),
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text(S.exportarDatos),
                ),
              ),
              OutlinedButton.icon(key: const ValueKey<String>('importar-datos'), onPressed: _importar, icon: const Icon(Icons.download_rounded), label: const Text(S.importarDatos)),
            ],
          ),
          const SizedBox(height: 16),
          if (state.groups.isEmpty) Text('Todavía no hay grupos.', style: TextStyle(color: pal.tintaSuave)),
          for (final ClassGroup g in state.groups) _GroupCard(group: g),
        ],
      ),
    );
  }
}

/// Importar los datos exportados desde otra tableta: se elige el archivo (o
/// se pega su contenido) y se junta con el avance de esta tableta.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _elegirArchivo() async {
    const XTypeGroup json = XTypeGroup(label: 'Datos de Pilas', extensions: <String>['json'], mimeTypes: <String>['application/json'], uniformTypeIdentifiers: <String>['public.json']);
    try {
      final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[json]);
      if (file == null || !mounted) {
        return;
      }
      final String texto = await file.readAsString();
      if (!mounted) {
        return;
      }
      setState(() {
        _ctrl.text = texto;
        _error = null;
      });
      await _importar();
    } catch (e) {
      debugPrint('No se pudo abrir el archivo: $e');
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el archivo. Prueba copiando su contenido y tocando Pegar.');
      }
    }
  }

  Future<void> _pegar() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    setState(() {
      _ctrl.text = data?.text ?? '';
      _error = (data?.text ?? '').trim().isEmpty ? 'El portapapeles está vacío. Abre el archivo exportado, copia todo su contenido y vuelve a intentarlo.' : null;
    });
  }

  Future<void> _importar() async {
    final String texto = _ctrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Pega primero el contenido del archivo exportado.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Services s = AppScope.read(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState nav = Navigator.of(context);
    try {
      final dynamic decoded = jsonDecode(texto);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('El contenido no es un archivo de Pilas.');
      }
      final int n = await s.state.importAll(decoded);
      messenger.showSnackBar(SnackBar(content: Text(n == 1 ? 'Se importó 1 perfil.' : 'Se importaron $n perfiles.')));
      nav.pop();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo importar: ${e.message.isEmpty ? 'el contenido no es válido.' : e.message}');
      }
    } catch (e) {
      // Cualquier otro problema (un dato con un tipo inesperado, un archivo a
      // medias): se avisa y no se toca nada.
      debugPrint('Importación fallida: $e');
      if (mounted) {
        setState(() => _error = 'No se pudo importar: el contenido está incompleto o dañado. No se cambió nada.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.importarDatos)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '1. En la otra tableta, entra a Modo docente y toca Exportar datos; guarda el archivo o envíalo a esta tableta.\n2. Aquí, toca Elegir archivo y busca ese archivo (o copia su contenido y toca Pegar e Importar).\n3. Los perfiles nuevos se agregan. En los que ya existen se juntan las sesiones, las pegatinas y las habilidades de las dos tabletas, y de cada juego queda el nivel más avanzado.',
                style: TextStyle(color: pal.tinta, height: 1.4),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('importar-texto'),
                  controller: _ctrl,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: const InputDecoration(hintText: '{"app":"pilas", ...}', alignLabelWithHint: true),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: pal.error, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  FilledButton.icon(key: const ValueKey<String>('importar-archivo'), onPressed: _busy ? null : _elegirArchivo, icon: const Icon(Icons.folder_open_rounded), label: const Text('Elegir archivo')),
                  OutlinedButton.icon(key: const ValueKey<String>('importar-pegar'), onPressed: _busy ? null : _pegar, icon: const Icon(Icons.content_paste_rounded), label: const Text('Pegar')),
                  OutlinedButton.icon(key: const ValueKey<String>('importar-ok'), onPressed: _busy ? null : _importar, icon: const Icon(Icons.download_done_rounded), label: const Text('Importar')),
                ],
              ),
            ],
          ),
        ),
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

  Future<void> _csv(BuildContext buttonContext) async {
    final Services s = AppScope.read(context);
    final String csv = groupCsv(_reports(s.state));
    await s.sharer.shareBytes(buttonContext, s.store, utf8.encode(csv), baseName: 'pilas-grupo-${widget.group.nombre}', extension: 'csv', mimeType: 'text/csv', text: 'Grupo ${widget.group.nombre}');
  }

  Future<void> _pdf(BuildContext buttonContext) async {
    final Services s = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final Uint8List bytes = await ReportPdf.buildGroup(widget.group.nombre, _reports(s.state));
      if (!buttonContext.mounted) {
        return;
      }
      await s.sharer.shareBytes(buttonContext, s.store, bytes, baseName: 'pilas-grupo-${widget.group.nombre}', extension: 'pdf', mimeType: 'application/pdf', text: 'Informe del grupo ${widget.group.nombre}');
    } catch (e) {
      debugPrint('No se pudo crear el PDF del grupo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo crear el informe del grupo.')));
      }
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
    final PilasPalette pal = PilasPalette.of(context);
    final List<ChildReport> rs = _reports(state);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.group.nombre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta)),
            Wrap(
              children: <Widget>[
                IconButton(onPressed: _miembros, icon: const Icon(Icons.group_rounded), tooltip: S.agregarNinos),
                Builder(builder: (BuildContext b) => IconButton(onPressed: rs.isEmpty ? null : () => _csv(b), icon: const Icon(Icons.table_chart_rounded), tooltip: S.exportarCsv)),
                Builder(builder: (BuildContext b) => IconButton(onPressed: rs.isEmpty || _busy ? null : () => _pdf(b), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: S.informeGrupo)),
                IconButton(onPressed: _borrar, icon: const Icon(Icons.delete_outline_rounded), tooltip: S.borrar),
              ],
            ),
            if (rs.isEmpty)
              Text('Sin niños todavía. Toca el ícono de grupo para agregarlos.', style: TextStyle(color: pal.tintaSuave))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 48,
                  columns: <DataColumn>[
                    const DataColumn(label: Text('Niño')),
                    const DataColumn(label: Text('Min. 7 días')),
                    const DataColumn(label: Text('Aciertos')),
                    for (final Area a in Area.values) DataColumn(label: Text(a.nombreCorto)),
                  ],
                  rows: <DataRow>[
                    for (final ChildReport r in rs)
                      DataRow(cells: <DataCell>[
                        DataCell(Text(r.profile.nombre)),
                        DataCell(Text('${r.minutos7Dias}')),
                        DataCell(Text(r.aciertosTexto)),
                        for (final AreaSummary a in r.areas) DataCell(Text(a.soloJuegoLibre ? 'libre' : '${a.skillsLogradas}/${a.skillsPosibles}')),
                      ]),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text('Habilidades logradas sobre las posibles en el tramo de cada niño. Aciertos: respuestas al primer intento.', style: TextStyle(fontSize: 12, color: pal.tintaSuave)),
          ],
        ),
      ),
    );
  }
}
