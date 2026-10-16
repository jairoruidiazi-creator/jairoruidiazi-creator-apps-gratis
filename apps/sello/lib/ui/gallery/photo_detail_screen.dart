import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/maps_links.dart';
import '../../core/sharing.dart';
import '../../geo/coords.dart';
import '../../model/models.dart';
import '../../stamp/capture_pipeline.dart';
import '../../stamp/composer.dart';
import '../../stamp/stamp_data.dart';
import '../../stamp/stamp_painter.dart';

/// Detalle de una foto: imagen (sellada u original), todos los datos,
/// edición de notas/etiquetas/campos/proyecto, compartir, volver a sellar,
/// abrir en mapas y borrar.
class PhotoDetailScreen extends StatefulWidget {
  const PhotoDetailScreen({super.key, required this.photoId});

  final String photoId;

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  bool _showOriginal = false;
  bool _busy = false;
  int _imageVersion = 0;

  PhotoRecord? _record(AppState st) {
    for (final PhotoRecord p in st.photos) {
      if (p.id == widget.photoId) {
        return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.state,
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final PhotoRecord? p = _record(st);
        if (p == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(t(context, 'La foto ya no existe.', 'The photo no longer exists.'))));
        }
        final Project project = st.projectById(p.projectId);
        final bool spanish = s.settings.spanish;
        final String rel = _showOriginal || p.stampedFile.isEmpty ? p.originalFile : p.stampedFile;
        return Scaffold(
          appBar: AppBar(
            title: Text(formatDate(p.takenAt, 'dd/MM/yyyy HH:mm', spanish: spanish)),
            actions: <Widget>[
              IconButton(tooltip: t(context, 'Compartir', 'Share'), onPressed: _busy ? null : () => _share(st, p), icon: const Icon(Icons.share_outlined)),
              PopupMenuButton<String>(
                onSelected: (String v) => _menu(v, st, p),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t(context, 'Editar datos', 'Edit data')))),
                  PopupMenuItem<String>(value: 'restamp', child: ListTile(leading: const Icon(Icons.approval_outlined), title: Text(t(context, 'Volver a sellar', 'Re-stamp')), subtitle: Text(t(context, 'Con la plantilla actual del proyecto', 'With the project\'s current template')))),
                  PopupMenuItem<String>(value: 'share-clean', child: ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t(context, 'Compartir sin EXIF', 'Share without EXIF')), subtitle: Text(t(context, 'Sin ubicación ni fecha en los metadatos', 'No location or date in the metadata')))),
                  PopupMenuItem<String>(value: 'copy', child: ListTile(leading: const Icon(Icons.copy_rounded), title: Text(t(context, 'Copiar datos', 'Copy data')))),
                  if (p.hasLocation) PopupMenuItem<String>(value: 'maps', child: ListTile(leading: const Icon(Icons.map_outlined), title: Text(t(context, 'Abrir en mapas', 'Open in maps')))),
                  if (p.hasLocation) PopupMenuItem<String>(value: 'navigate', child: ListTile(leading: const Icon(Icons.directions_outlined), title: Text(t(context, 'Cómo llegar', 'Directions')))),
                  PopupMenuItem<String>(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(t(context, 'Borrar', 'Delete')))),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              AspectRatio(
                aspectRatio: p.width > 0 && p.height > 0 ? p.width / p.height : 4 / 3,
                child: ColoredBox(
                  color: Colors.black,
                  child: _Photo(key: ValueKey<String>('$rel-$_imageVersion'), relative: rel, busy: _busy),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (p.stampedFile.isNotEmpty)
                      SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(value: false, label: Text(t(context, 'Sellada', 'Stamped'))),
                          ButtonSegment<bool>(value: true, label: Text(t(context, 'Original', 'Original'))),
                        ],
                        selected: <bool>{_showOriginal},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<bool> v) => setState(() => _showOriginal = v.first),
                      ),
                    Chip(avatar: const Icon(Icons.folder_outlined, size: 18), label: Text(project.name)),
                    for (final String tag in p.tags) Chip(label: Text('#$tag')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (p.description.isNotEmpty) _Row(t(context, 'Sello', 'Stamp'), p.description),
              if (p.notes.isNotEmpty) _Row(t(context, 'Notas', 'Notes'), p.notes),
              if (p.hasLocation) ...<Widget>[
                for (final CoordFormat cf in Coords.formatsFor(p.latitude!, p.longitude!)) _Row(Coords.formatName(cf), Coords.format(cf, p.latitude!, p.longitude!), copyable: true),
                if (p.accuracy != null) _Row(t(context, 'Precisión', 'Accuracy'), '± ${p.accuracy!.toStringAsFixed(1)} m'),
                if (p.altitude != null) _Row(t(context, 'Altitud', 'Altitude'), '${p.altitude!.toStringAsFixed(1)} m ${p.altitudeReference == 'ellipsoid' ? t(context, 'sobre el elipsoide', 'above the ellipsoid') : t(context, 'sobre el nivel del mar', 'above sea level')}'),
              ] else
                _Row(t(context, 'Ubicación', 'Location'), t(context, 'Sin señal GPS al momento de la foto', 'No GPS fix when the photo was taken')),
              if (p.heading != null) _Row(t(context, 'Rumbo', 'Heading'), '${p.heading!.toStringAsFixed(0)}° ${Coords.cardinal(p.heading!, spanish: spanish)} · ${t(context, 'fachada', 'facade')} ${Coords.facade(p.heading!, spanish: spanish)}${p.pitch != null ? ' · ${t(context, 'incl.', 'tilt')} ${p.pitch!.toStringAsFixed(0)}°' : ''}'),
              if (p.speed != null && p.speed! > 0.5) _Row(t(context, 'Velocidad', 'Speed'), '${(p.speed! * 3.6).toStringAsFixed(0)} km/h'),
              if (p.address.isNotEmpty) _Row(t(context, 'Dirección', 'Address'), p.address),
              _Row('UTC', '${formatDate(p.takenAt.toUtc(), 'yyyy-MM-dd HH:mm:ss')}Z'),
              for (final MapEntry<String, String> e in p.fields.entries)
                if (e.value.isNotEmpty) _Row(_fieldLabel(project, e.key), e.value),
              _Row(t(context, 'Archivo', 'File'), p.stampedFile.split('/').last),
              if (p.width > 0) _Row(t(context, 'Tamaño', 'Size'), '${p.width} × ${p.height} px'),
            ],
          ),
        );
      },
    );
  }

  String _fieldLabel(Project project, String key) {
    for (final FieldDef f in project.fields) {
      if (f.key == key) {
        return f.label;
      }
    }
    return key;
  }

  Future<void> _menu(String v, AppState st, PhotoRecord p) async {
    switch (v) {
      case 'edit':
        await _edit(st, p);
        break;
      case 'restamp':
        await _restamp(st, p);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _plainText(st, p)));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Datos copiados', 'Data copied'))));
        }
        break;
      case 'share-clean':
        await _share(st, p, withoutMetadata: true);
        break;
      case 'maps':
        if (p.hasLocation) {
          await openInMaps(p.latitude!, p.longitude!, label: p.notes.isNotEmpty ? p.notes : 'Sello');
        }
        break;
      case 'navigate':
        if (p.hasLocation) {
          await navigateTo(p.latitude!, p.longitude!);
        }
        break;
      case 'delete':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(t(context, 'Borrar foto', 'Delete photo')),
            content: Text(t(context, 'Se borra de la app; la copia de la fototeca, si existe, se conserva.', 'Deleted from the app; the photo library copy, if any, is kept.')),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Borrar', 'Delete'))),
            ],
          ),
        );
        if (ok == true) {
          await st.deletePhotos(<PhotoRecord>[p]);
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
        break;
    }
  }

  String _plainText(AppState st, PhotoRecord p) {
    final List<String> lines = <String>[
      formatDate(p.takenAt, 'dd/MM/yyyy HH:mm:ss'),
      if (p.hasLocation) ...<String>[Coords.dd(p.latitude!, p.longitude!), Coords.utm(p.latitude!, p.longitude!), Coords.mgrs(p.latitude!, p.longitude!), Coords.plusCode(p.latitude!, p.longitude!, length: 11)],
      if (p.accuracy != null) '± ${p.accuracy!.toStringAsFixed(1)} m',
      if (p.altitude != null) 'Alt. ${p.altitude!.toStringAsFixed(1)} m',
      if (p.heading != null) '${p.heading!.toStringAsFixed(0)}°',
      if (p.address.isNotEmpty) p.address,
      st.projectById(p.projectId).name,
      for (final MapEntry<String, String> e in p.fields.entries) '${e.key}: ${e.value}',
      if (p.notes.isNotEmpty) p.notes,
      if (p.tags.isNotEmpty) p.tags.map((String x) => '#$x').join(' '),
    ];
    return lines.join('\n');
  }

  Future<void> _share(AppState st, PhotoRecord p, {bool withoutMetadata = false}) async {
    final Services s = AppScope.of(context);
    final File f = await st.fileOf(_showOriginal || p.stampedFile.isEmpty ? p.originalFile : p.stampedFile);
    if (!await f.exists()) {
      return;
    }
    final String link = p.hasLocation ? 'https://www.openstreetmap.org/?mlat=${p.latitude}&mlon=${p.longitude}#map=18/${p.latitude}/${p.longitude}' : '';
    if (withoutMetadata) {
      // Copia sin EXIF (sin ubicación ni fecha en los metadatos); el sello
      // dibujado se conserva.
      final Uint8List clean = stripMetadata(await f.readAsBytes());
      final String name = f.uri.pathSegments.last.replaceAll('.jpg', '_sin_exif.jpg');
      await shareBytes(s.store, name, clean);
      return;
    }
    await shareFiles(<String>[f.path], text: <String>[if (p.description.isNotEmpty) p.description, if (link.isNotEmpty) link].join('\n'));
  }

  Future<void> _edit(AppState st, PhotoRecord p) async {
    final Project project = st.projectById(p.projectId);
    final TextEditingController notes = TextEditingController(text: p.notes);
    final TextEditingController tags = TextEditingController(text: p.tags.join(' '));
    final Map<String, TextEditingController> fieldCtrls = <String, TextEditingController>{
      for (final FieldDef f in project.fields) f.key: TextEditingController(text: p.fields[f.key] ?? ''),
    };
    String projectId = p.projectId;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text(t(context, 'Editar datos', 'Edit data')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: InputDecoration(labelText: t(context, 'Proyecto', 'Project')),
                  items: <DropdownMenuItem<String>>[for (final Project pr in st.projects) DropdownMenuItem<String>(value: pr.id, child: Text(pr.name))],
                  onChanged: (String? v) => setLocal(() => projectId = v ?? projectId),
                ),
                for (final FieldDef f in project.fields) TextField(controller: fieldCtrls[f.key], decoration: InputDecoration(labelText: f.label)),
                TextField(controller: notes, decoration: InputDecoration(labelText: t(context, 'Notas', 'Notes')), maxLines: 3, minLines: 1),
                TextField(controller: tags, decoration: InputDecoration(labelText: t(context, 'Etiquetas (separadas por espacio)', 'Tags (space separated)'))),
                const SizedBox(height: 8),
                Text(t(context, 'Los cambios quedan en los datos y en las exportaciones; para verlos en la imagen usa "Volver a sellar".', 'Changes apply to the data and exports; use "Re-stamp" to see them in the image.'), style: Theme.of(context).textTheme.bodySmall),
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
      p.notes = notes.text.trim();
      p.tags
        ..clear()
        ..addAll(tags.text.split(RegExp(r'[\s,]+')).map((String x) => x.trim().replaceAll('#', '')).where((String x) => x.isNotEmpty));
      p.projectId = projectId;
      fieldCtrls.forEach((String k, TextEditingController c) => p.fields[k] = c.text.trim());
      await st.savePhotos();
    }
    disposeLater(<ChangeNotifier>[notes, tags, ...fieldCtrls.values]);
  }

  /// Vuelve a componer la copia sellada a partir del original con la
  /// plantilla actual del proyecto y los datos (editados) del registro.
  Future<void> _restamp(AppState st, PhotoRecord p) async {
    final Services s = AppScope.of(context);
    final File original = await st.fileOf(p.originalFile);
    if (!await original.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se conservó el original de esta foto; no se puede volver a sellar.', 'The original of this photo was not kept; it cannot be re-stamped.'))));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final Project project = st.projectById(p.projectId);
      final StampTemplate tpl = st.templateForProject(project);
      final StampData data = StampData(
        time: p.takenAt,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        altitudeIsMsl: p.altitudeReference != 'ellipsoid',
        heading: p.heading,
        pitch: p.pitch,
        speed: p.speed,
        address: p.address,
        projectName: project.name,
        fields: p.fields,
        fieldLabels: <String, String>{for (final FieldDef f in project.fields) f.key: f.label},
        notes: p.notes,
        spanish: s.settings.spanish,
      );
      final Uint8List bytes = await original.readAsBytes();
      final JpegDims? dims = jpegSize(bytes);
      int w = dims?.width ?? (p.width > 0 ? p.width : 2000);
      int h = dims?.height ?? (p.height > 0 ? p.height : 1500);
      if (CapturePipeline.exifOrientation(bytes) >= 5) {
        final int tmp = w;
        w = h;
        h = tmp;
      }
      const int layerW = 2000;
      final int layerH = (layerW * h / w).round().clamp(200, 6000);
      ui.Image? logo;
      final File? logoF = await st.logoFile(tpl);
      if (logoF != null) {
        logo = await decodeLogo(await logoF.readAsBytes());
      }
      final Uint8List overlay = await renderStampPng(tpl, data, width: layerW, height: layerH, logo: logo);
      final String stampedRel = p.stampedFile.isNotEmpty ? p.stampedFile : p.originalFile.replaceAll('-orig.jpg', '.jpg');
      final String outPath = await s.store.absolutePath(stampedRel);
      final ComposeResult r = await composeStamped(ComposeJob(
        originalPath: original.path,
        outputPath: outPath,
        overlayPng: overlay,
        overlayWidth: layerW,
        overlayHeight: layerH,
        quality: s.settings.jpegQuality,
        latitude: p.latitude,
        longitude: p.longitude,
        altitude: p.altitude,
        heading: p.heading,
        takenAt: p.takenAt,
        description: data.summary(tpl),
      ));
      p.stampedFile = stampedRel;
      p.description = data.summary(tpl);
      p.width = r.width;
      p.height = r.height;
      await FileImage(File(outPath)).evict();
      await st.savePhotos();
      if (mounted) {
        setState(() => _imageVersion += 1);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Foto sellada de nuevo.', 'Photo re-stamped.'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo sellar', 'Could not stamp')}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _Photo extends StatelessWidget {
  const _Photo({super.key, required this.relative, required this.busy});

  final String relative;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppState st = AppScope.of(context).state;
    return FutureBuilder<File>(
      future: st.fileOf(relative),
      builder: (BuildContext context, AsyncSnapshot<File> snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            InteractiveViewer(
              maxScale: 8,
              child: Image.file(
                snap.data!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(child: Text(AppScope.of(context).settings.spanish ? 'No se encontró el archivo' : 'File not found', style: const TextStyle(color: Colors.white70))),
              ),
            ),
            if (busy) const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Copiado', 'Copied')}: $value'), duration: const Duration(seconds: 1)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
            if (copyable) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy_rounded, size: 16)),
          ],
        ),
      ),
    );
  }
}
