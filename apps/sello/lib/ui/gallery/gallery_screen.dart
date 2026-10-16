import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/exports.dart';
import '../../core/report.dart';
import '../../core/sharing.dart';
import '../../geo/coords.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import 'photo_detail_screen.dart';

/// Galería propia: cuadrícula por fecha con filtros, selección múltiple,
/// compartir, exportar (CSV, KML, KMZ, ZIP) y borrar.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  String? _projectId;
  String? _tag;
  String _query = '';
  String _sort = 'recent'; // recent | oldest | project | distance | place
  final Set<String> _selected = <String>{};
  bool _busy = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PhotoRecord> _filtered(AppState st) {
    final String q = _query.trim().toLowerCase();
    final List<PhotoRecord> out = st.photos.where((PhotoRecord p) {
      if (_projectId != null && p.projectId != _projectId) {
        return false;
      }
      if (_tag != null && !p.tags.contains(_tag)) {
        return false;
      }
      if (q.isNotEmpty) {
        final String hay = '${p.notes} ${p.address} ${p.tags.join(' ')} ${p.fields.values.join(' ')} ${p.description}'.toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    final Map<String, Project> projects = st.projectMap;
    final Fix? here = AppScope.of(context).location.fix;
    switch (_sort) {
      case 'oldest':
        out.sort((PhotoRecord a, PhotoRecord b) => a.takenAt.compareTo(b.takenAt));
        break;
      case 'project':
        out.sort((PhotoRecord a, PhotoRecord b) {
          final int c = (projects[a.projectId]?.name ?? '').compareTo(projects[b.projectId]?.name ?? '');
          return c != 0 ? c : b.takenAt.compareTo(a.takenAt);
        });
        break;
      case 'distance':
        double d(PhotoRecord p) => here == null || !p.hasLocation ? double.infinity : Coords.distanceMeters(here.latitude, here.longitude, p.latitude!, p.longitude!);
        out.sort((PhotoRecord a, PhotoRecord b) => d(a).compareTo(d(b)));
        break;
      case 'place':
        out.sort((PhotoRecord a, PhotoRecord b) {
          if (a.address.isEmpty != b.address.isEmpty) {
            return a.address.isEmpty ? 1 : -1;
          }
          final int c = a.address.compareTo(b.address);
          return c != 0 ? c : b.takenAt.compareTo(a.takenAt);
        });
        break;
      default:
        out.sort((PhotoRecord a, PhotoRecord b) => b.takenAt.compareTo(a.takenAt));
    }
    return out;
  }

  /// Cómo se agrupan las fotos en la cuadrícula según el orden elegido.
  String Function(PhotoRecord) _groupKey(BuildContext context, Map<String, Project> projects) {
    final bool spanish = AppScope.of(context).settings.spanish;
    final Fix? here = AppScope.of(context).location.fix;
    switch (_sort) {
      case 'project':
        return (PhotoRecord p) => projects[p.projectId]?.name ?? '';
      case 'place':
        return (PhotoRecord p) => p.address.isEmpty ? t(context, 'Sin dirección', 'No address') : p.address;
      case 'distance':
        return (PhotoRecord p) {
          if (here == null || !p.hasLocation) {
            return t(context, 'Sin distancia', 'No distance');
          }
          final double d = Coords.distanceMeters(here.latitude, here.longitude, p.latitude!, p.longitude!);
          if (d < 100) {
            return t(context, 'A menos de 100 m', 'Within 100 m');
          }
          if (d < 1000) {
            return t(context, 'A menos de 1 km', 'Within 1 km');
          }
          if (d < 10000) {
            return t(context, 'A menos de 10 km', 'Within 10 km');
          }
          return t(context, 'A más de 10 km', 'Farther than 10 km');
        };
      default:
        return (PhotoRecord p) => formatDate(p.takenAt, 'EEE dd/MM/yyyy', spanish: spanish);
    }
  }

  String _sortName(BuildContext context, String v) {
    switch (v) {
      case 'oldest':
        return t(context, 'Más antiguas primero', 'Oldest first');
      case 'project':
        return t(context, 'Por proyecto', 'By project');
      case 'distance':
        return t(context, 'Por distancia a mí', 'By distance from me');
      case 'place':
        return t(context, 'Por lugar (dirección)', 'By place (address)');
      default:
        return t(context, 'Más recientes primero', 'Newest first');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.state,
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final List<PhotoRecord> photos = _filtered(st);
        final bool selecting = _selected.isNotEmpty;
        final Map<String, Project> projects = st.projectMap;
        return Scaffold(
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t(context, 'Buscar en notas, dirección, etiquetas…', 'Search notes, address, tags…'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); setState(() => _query = ''); }),
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: <Widget>[
                    PopupMenuButton<String>(
                      tooltip: t(context, 'Ordenar', 'Sort'),
                      initialValue: _sort,
                      onSelected: (String v) => setState(() => _sort = v),
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        for (final String v in <String>['recent', 'oldest', 'project', 'distance', 'place']) PopupMenuItem<String>(value: v, child: Text(_sortName(context, v))),
                      ],
                      child: Chip(avatar: const Icon(Icons.sort, size: 18), label: Text(_sort == 'recent' ? t(context, 'Orden', 'Sort') : _sortName(context, _sort))),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(label: Text(t(context, 'Todos', 'All')), selected: _projectId == null, onSelected: (_) => setState(() => _projectId = null)),
                    const SizedBox(width: 6),
                    for (final Project p in st.projects) ...<Widget>[
                      ChoiceChip(label: Text(p.name), selected: _projectId == p.id, onSelected: (_) => setState(() => _projectId = _projectId == p.id ? null : p.id)),
                      const SizedBox(width: 6),
                    ],
                    if (st.allTags.isNotEmpty) const VerticalDivider(width: 12),
                    for (final String tag in st.allTags) ...<Widget>[
                      FilterChip(label: Text('#$tag'), selected: _tag == tag, onSelected: (_) => setState(() => _tag = _tag == tag ? null : tag)),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              if (selecting)
                Material(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: <Widget>[
                        IconButton(onPressed: () => setState(_selected.clear), icon: const Icon(Icons.close)),
                        Expanded(child: Text('${_selected.length} ${t(context, 'seleccionadas', 'selected')}')),
                        IconButton(tooltip: t(context, 'Seleccionar todas', 'Select all'), onPressed: () => setState(() => _selected.addAll(photos.map((PhotoRecord p) => p.id))), icon: const Icon(Icons.select_all)),
                        IconButton(tooltip: t(context, 'Editar en lote', 'Batch edit'), onPressed: _busy ? null : () => _batchEdit(st, photos), icon: const Icon(Icons.edit_outlined)),
                        IconButton(tooltip: t(context, 'Compartir', 'Share'), onPressed: _busy ? null : () => _share(st, photos), icon: const Icon(Icons.share_outlined)),
                        IconButton(tooltip: t(context, 'Borrar', 'Delete'), onPressed: _busy ? null : () => _delete(st, photos), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: photos.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            st.photos.isEmpty ? t(context, 'Aún no hay fotos. Toma la primera desde la pestaña Cámara.', 'No photos yet. Take the first one from the Camera tab.') : t(context, 'Ninguna foto coincide con el filtro.', 'No photo matches the filter.'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _Grid(
                        photos: photos,
                        projects: projects,
                        groupKey: _groupKey(context, projects),
                        selected: _selected,
                        onTap: (PhotoRecord p) {
                          if (selecting) {
                            setState(() => _selected.contains(p.id) ? _selected.remove(p.id) : _selected.add(p.id));
                          } else {
                            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoDetailScreen(photoId: p.id)));
                          }
                        },
                        onLongPress: (PhotoRecord p) => setState(() => _selected.add(p.id)),
                      ),
              ),
            ],
          ),
          floatingActionButton: photos.isEmpty
              ? null
              : FloatingActionButton.extended(
                  // Sin Hero: el botón aparece y desaparece con el filtro y no
                  // debe participar en las transiciones de página.
                  heroTag: null,
                  onPressed: _busy ? null : () => _exportMenu(st, photos),
                  icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded),
                  label: Text(t(context, 'Exportar', 'Export')),
                ),
        );
      },
    );
  }

  List<PhotoRecord> _targets(List<PhotoRecord> visible) => _selected.isEmpty ? visible : visible.where((PhotoRecord p) => _selected.contains(p.id)).toList();

  Future<void> _share(AppState st, List<PhotoRecord> visible) async {
    final List<PhotoRecord> list = _targets(visible);
    setState(() => _busy = true);
    try {
      final List<String> paths = <String>[];
      for (final PhotoRecord p in list) {
        final File f = await st.fileOf(p.stampedFile.isNotEmpty ? p.stampedFile : p.originalFile);
        if (await f.exists()) {
          paths.add(f.path);
        }
      }
      await shareFiles(paths, text: list.length == 1 ? list.first.description : null);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(AppState st, List<PhotoRecord> visible) async {
    final List<PhotoRecord> list = _targets(visible);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t(context, 'Borrar fotos', 'Delete photos')),
        content: Text(list.length == 1
            ? t(context, 'Se borrará esta foto de la app (la copia en la fototeca, si existe, se conserva).', 'This photo will be deleted from the app (the copy in the photo library, if any, is kept).')
            : '${t(context, 'Se borrarán', 'Will delete')} ${list.length} ${t(context, 'fotos de la app (las copias en la fototeca se conservan).', 'photos from the app (photo library copies are kept).')}'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Borrar', 'Delete'))),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await st.deletePhotos(list);
      _selected.clear();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Cambia el proyecto y las etiquetas de todas las fotos seleccionadas.
  Future<void> _batchEdit(AppState st, List<PhotoRecord> visible) async {
    final List<PhotoRecord> list = _targets(visible);
    String? projectId;
    final TextEditingController add = TextEditingController();
    final TextEditingController remove = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text('${t(context, 'Editar', 'Edit')} ${list.length} ${t(context, 'fotos', 'photos')}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: projectId,
                decoration: InputDecoration(labelText: t(context, 'Mover al proyecto', 'Move to project')),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: null, child: Text(t(context, '(sin cambio)', '(no change)'))),
                  for (final Project pr in st.projects) DropdownMenuItem<String>(value: pr.id, child: Text(pr.name)),
                ],
                onChanged: (String? v) => setLocal(() => projectId = v),
              ),
              TextField(controller: add, decoration: InputDecoration(labelText: t(context, 'Añadir etiquetas (separadas por espacio)', 'Add tags (space separated)'))),
              TextField(controller: remove, decoration: InputDecoration(labelText: t(context, 'Quitar etiquetas', 'Remove tags'))),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Aplicar', 'Apply'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      final List<String> plus = add.text.split(RegExp(r'[\s,]+')).map((String x) => x.replaceAll('#', '').trim()).where((String x) => x.isNotEmpty).toList();
      final List<String> minus = remove.text.split(RegExp(r'[\s,]+')).map((String x) => x.replaceAll('#', '').trim()).where((String x) => x.isNotEmpty).toList();
      for (final PhotoRecord p in list) {
        if (projectId != null) {
          p.projectId = projectId!;
        }
        for (final String tg in plus) {
          if (!p.tags.contains(tg)) {
            p.tags.add(tg);
          }
        }
        p.tags.removeWhere(minus.contains);
      }
      await st.savePhotos();
      if (mounted) {
        setState(_selected.clear);
      }
    }
    disposeLater(<ChangeNotifier>[add, remove]);
  }

  Future<void> _exportMenu(AppState st, List<PhotoRecord> visible) async {
    final List<PhotoRecord> list = _targets(visible);
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(title: Text('${t(context, 'Exportar', 'Export')} ${list.length} ${t(context, 'fotos', 'photos')}', style: Theme.of(context).textTheme.titleMedium)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t(context, 'Fotos selladas', 'Stamped photos')), subtitle: Text(t(context, 'Compartir las imágenes JPG', 'Share the JPG images')), onTap: () => Navigator.pop(context, 'photos')),
            ListTile(leading: const Icon(Icons.table_chart_outlined), title: const Text('CSV'), subtitle: Text(t(context, 'Tabla con coordenadas, UTM, MGRS, Plus Code, dirección y campos', 'Table with coordinates, UTM, MGRS, Plus Code, address and fields')), onTap: () => Navigator.pop(context, 'csv')),
            ListTile(leading: const Icon(Icons.public), title: const Text('KML'), subtitle: Text(t(context, 'Puntos para Google Earth / QGIS (sin imágenes)', 'Points for Google Earth / QGIS (no images)')), onTap: () => Navigator.pop(context, 'kml')),
            ListTile(leading: const Icon(Icons.travel_explore), title: const Text('KMZ'), subtitle: Text(t(context, 'Puntos con las fotos incrustadas', 'Points with the photos embedded')), onTap: () => Navigator.pop(context, 'kmz')),
            ListTile(leading: const Icon(Icons.folder_zip_outlined), title: const Text('ZIP'), subtitle: Text(t(context, 'Fotos selladas + CSV + KML en un archivo', 'Stamped photos + CSV + KML in one file')), onTap: () => Navigator.pop(context, 'zip')),
            ListTile(leading: const Icon(Icons.folder_zip), title: Text('ZIP ${t(context, 'con originales', 'with originals')}'), subtitle: Text(t(context, 'Fotos sin sello + CSV + KML', 'Unstamped photos + CSV + KML')), onTap: () => Navigator.pop(context, 'zip-orig')),
            ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(t(context, 'Informe PDF', 'PDF report')), subtitle: Text(t(context, 'Resumen, tabla y una ficha por foto con imagen y datos', 'Summary, table and one sheet per photo with image and data')), onTap: () => Navigator.pop(context, 'pdf')),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Services sv = AppScope.of(context);
      final Map<String, Project> projects = st.projectMap;
      final bool spanish = sv.settings.spanish;
      final String stamp = _stamp(DateTime.now());
      final String title = _projectId == null ? 'Sello' : (projects[_projectId]?.name ?? 'Sello');
      Future<File?> stamped(PhotoRecord p) async => st.fileOf(p.stampedFile.isNotEmpty ? p.stampedFile : p.originalFile);
      Future<File?> original(PhotoRecord p) async {
        final File f = await st.fileOf(p.originalFile);
        return await f.exists() ? f : st.fileOf(p.stampedFile);
      }
      switch (choice) {
        case 'photos':
          await _share(st, visible);
          break;
        case 'csv':
          // BOM para que Excel abra el UTF-8 con tildes correctas.
          await shareBytes(sv.store, 'sello_$stamp.csv', Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(Exports.csv(list, projects, spanish: spanish))]));
          break;
        case 'kml':
          await shareBytes(sv.store, 'sello_$stamp.kml', Uint8List.fromList(utf8.encode(Exports.kml(list, projects, title: title, spanish: spanish))));
          break;
        case 'kmz':
          await shareBytes(sv.store, 'sello_$stamp.kmz', await Exports.kmz(list, projects, title: title, stampedFile: stamped, spanish: spanish));
          break;
        case 'zip':
          await shareBytes(sv.store, 'sello_$stamp.zip', await Exports.zip(list, projects, title: title, file: stamped, spanish: spanish));
          break;
        case 'zip-orig':
          await shareBytes(sv.store, 'sello_${stamp}_originales.zip', await Exports.zip(list, projects, title: title, file: original, spanish: spanish));
          break;
        case 'pdf':
          final Uint8List pdf = await PdfReport.build(
            photos: list,
            projects: projects,
            title: title,
            spanish: spanish,
            imageOf: (PhotoRecord p) async {
              final File? f = await stamped(p);
              if (f == null || !await f.exists()) {
                return null;
              }
              return PdfReport.thumbnail(await f.readAsBytes());
            },
          );
          await shareBytes(sv.store, 'sello_$stamp.pdf', pdf);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo exportar', 'Export failed')}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
  }
}

class _Section {
  _Section(this.day);

  final String day;
  final List<PhotoRecord> photos = <PhotoRecord>[];
}

class _Grid extends StatelessWidget {
  const _Grid({required this.photos, required this.projects, required this.groupKey, required this.selected, required this.onTap, required this.onLongPress});

  final List<PhotoRecord> photos;
  final Map<String, Project> projects;
  final String Function(PhotoRecord) groupKey;
  final Set<String> selected;
  final ValueChanged<PhotoRecord> onTap;
  final ValueChanged<PhotoRecord> onLongPress;

  @override
  Widget build(BuildContext context) {
    // Agrupadas por día (o por proyecto, lugar o distancia según el orden).
    final List<_Section> sections = <_Section>[];
    for (final PhotoRecord p in photos) {
      final String key = groupKey(p);
      if (sections.isEmpty || sections.last.day != key) {
        sections.add(_Section(key));
      }
      sections.last.photos.add(p);
    }
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
      final int cols = (k.maxWidth / 120).floor().clamp(2, 8);
      return CustomScrollView(
        slivers: <Widget>[
          for (final _Section sec in sections) ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text(sec.day, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 4, crossAxisSpacing: 4),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) => _tile(context, sec.photos[i]),
                  childCount: sec.photos.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    });
  }

  Widget _tile(BuildContext context, PhotoRecord p) {
    final bool sel = selected.contains(p.id);
    return GestureDetector(
      onTap: () => onTap(p),
      onLongPress: () => onLongPress(p),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(borderRadius: BorderRadius.circular(8), child: PhotoThumb(record: p)),
          if (!p.hasLocation) const Positioned(left: 4, top: 4, child: Icon(Icons.location_off, size: 16, color: Colors.white)),
          if (projects.length > 1)
            Positioned(
              left: 4,
              bottom: 4,
              right: 4,
              child: Text(projects[p.projectId]?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, shadows: <Shadow>[Shadow(blurRadius: 4, color: Colors.black)])),
            ),
          if (sel)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3), color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
              child: const Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle, color: Colors.white))),
            ),
        ],
      ),
    );
  }
}

/// Miniatura de una foto guardada por la app.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.record, this.cacheWidth = 300});

  final PhotoRecord record;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final AppState st = AppScope.of(context).state;
    final String rel = record.stampedFile.isNotEmpty ? record.stampedFile : record.originalFile;
    return FutureBuilder<File>(
      future: st.fileOf(rel),
      builder: (BuildContext context, AsyncSnapshot<File> snap) {
        if (!snap.hasData) {
          return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
        }
        return Image.file(
          snap.data!,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}
