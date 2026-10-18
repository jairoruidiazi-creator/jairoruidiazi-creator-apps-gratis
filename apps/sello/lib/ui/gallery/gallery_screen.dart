import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/exports.dart';
import '../../core/report.dart';
import '../../core/sharing.dart';
import '../../core/storage.dart';
import '../../geo/coords.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import 'photo_detail_screen.dart';

/// Anchos de las miniaturas en la caché de imágenes (para refrescarlas
/// todas cuando una foto se vuelve a sellar).
const int kCameraThumbWidth = 128;
const int kMapThumbWidth = 160;
const int kGalleryThumbWidth = 300;
const List<int> kThumbWidths = <int>[kCameraThumbWidth, kMapThumbWidth, kGalleryThumbWidth];

/// Olvida las copias en caché de una imagen (tamaño completo y miniaturas).
Future<void> evictPhotoImages(File file) async {
  await FileImage(file).evict();
  for (final int w in kThumbWidths) {
    await ResizeImage(FileImage(file), width: w).evict();
  }
}

/// Galería propia: cuadrícula por fecha con filtros, selección múltiple,
/// compartir, exportar (CSV, KML, KMZ, ZIP, PDF) y borrar.
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
    final Map<String, Project> projects = st.projectMap;
    final List<PhotoRecord> out = st.photos.where((PhotoRecord p) {
      if (_projectId != null && p.projectId != _projectId) {
        return false;
      }
      if (_tag != null && !p.tags.contains(_tag)) {
        return false;
      }
      if (q.isNotEmpty) {
        final String fields = p.labeledFields(projects[p.projectId]).map((MapEntry<String, String> e) => '${e.key} ${e.value}').join(' ');
        final String hay = '${p.notes} ${p.address} ${p.tags.join(' ')} $fields ${p.description}'.toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
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
        return (PhotoRecord p) => formatDate(p.wallTime, 'EEE dd/MM/yyyy', spanish: spanish);
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
      listenable: Listenable.merge(<Listenable>[s.state, s.queue]),
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
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: t(context, 'Borrar búsqueda', 'Clear search'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
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
                        IconButton(tooltip: t(context, 'Cancelar selección', 'Cancel selection'), onPressed: () => setState(_selected.clear), icon: const Icon(Icons.close)),
                        Expanded(child: Text('${_selected.length} ${t(context, 'seleccionadas', 'selected')}')),
                        IconButton(tooltip: t(context, 'Seleccionar todas', 'Select all'), onPressed: () => setState(() => _selected.addAll(photos.map((PhotoRecord p) => p.id))), icon: const Icon(Icons.select_all)),
                        IconButton(tooltip: t(context, 'Editar en lote', 'Batch edit'), onPressed: _busy ? null : () => _batchEdit(st, photos), icon: const Icon(Icons.edit_outlined)),
                        Builder(
                          builder: (BuildContext buttonContext) => IconButton(tooltip: t(context, 'Compartir', 'Share'), onPressed: _busy ? null : () => _share(st, photos, shareOriginOf(buttonContext)), icon: const Icon(Icons.share_outlined)),
                        ),
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
                        spanish: s.settings.spanish,
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
              : Builder(
                  builder: (BuildContext fabContext) => FloatingActionButton.extended(
                    // Sin Hero: el botón aparece y desaparece con el filtro y no
                    // debe participar en las transiciones de página.
                    heroTag: null,
                    onPressed: _busy ? null : () => _exportMenu(st, photos, shareOriginOf(fabContext)),
                    icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded),
                    label: Text(t(context, 'Exportar', 'Export')),
                  ),
                ),
        );
      },
    );
  }

  List<PhotoRecord> _targets(List<PhotoRecord> visible) => _selected.isEmpty ? visible : visible.where((PhotoRecord p) => _selected.contains(p.id)).toList();

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Comparte las fotos (selladas; si una no está sellada, su original).
  Future<void> _share(AppState st, List<PhotoRecord> visible, Rect origin) async {
    final List<PhotoRecord> list = _targets(visible);
    setState(() => _busy = true);
    try {
      final List<String> paths = <String>[];
      for (final PhotoRecord p in list) {
        final File? f = await st.displayFile(p);
        if (f != null) {
          paths.add(f.path);
        }
      }
      await shareFiles(paths, origin: origin, text: list.length == 1 ? list.first.description : null);
    } catch (e) {
      _toast('${t(context, 'No se pudo compartir', 'Could not share')}: $e');
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
    } catch (e) {
      _toast('${t(context, 'No se pudo borrar', 'Could not delete')}: $e');
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
          content: SingleChildScrollView(
            child: Column(
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

  Future<void> _exportMenu(AppState st, List<PhotoRecord> visible, Rect origin) async {
    final List<PhotoRecord> list = _targets(visible);
    // Siete formatos con descripción no caben en la altura por defecto de la
    // hoja (9/16 de la pantalla): se deja crecer y se desplaza si hace falta,
    // para que el informe PDF quede siempre al alcance.
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(title: Text('${t(context, 'Exportar', 'Export')} ${list.length} ${t(context, 'fotos', 'photos')}', style: Theme.of(context).textTheme.titleMedium)),
                ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t(context, 'Fotos selladas', 'Stamped photos')), subtitle: Text(t(context, 'Compartir las imágenes JPG', 'Share the JPG images')), onTap: () => Navigator.pop(context, 'photos')),
                ListTile(leading: const Icon(Icons.table_chart_outlined), title: const Text('CSV'), subtitle: Text(t(context, 'Tabla para Excel con coordenadas, UTM, MGRS, Plus Code, dirección y campos', 'Spreadsheet table with coordinates, UTM, MGRS, Plus Code, address and fields')), onTap: () => Navigator.pop(context, 'csv')),
                ListTile(leading: const Icon(Icons.public), title: const Text('KML'), subtitle: Text(t(context, 'Puntos para Google Earth / QGIS (sin imágenes)', 'Points for Google Earth / QGIS (no images)')), onTap: () => Navigator.pop(context, 'kml')),
                ListTile(leading: const Icon(Icons.travel_explore), title: const Text('KMZ'), subtitle: Text(t(context, 'Puntos con las fotos incrustadas', 'Points with the photos embedded')), onTap: () => Navigator.pop(context, 'kmz')),
                ListTile(leading: const Icon(Icons.folder_zip_outlined), title: const Text('ZIP'), subtitle: Text(t(context, 'Fotos selladas + CSV + KML en un archivo', 'Stamped photos + CSV + KML in one file')), onTap: () => Navigator.pop(context, 'zip')),
                ListTile(leading: const Icon(Icons.folder_zip), title: Text('ZIP ${t(context, 'con originales', 'with originals')}'), subtitle: Text(t(context, 'Fotos sin sello + CSV + KML', 'Unstamped photos + CSV + KML')), onTap: () => Navigator.pop(context, 'zip-orig')),
                ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(t(context, 'Informe PDF', 'PDF report')), subtitle: Text(t(context, 'Resumen, tabla y una ficha por foto con imagen y datos', 'Summary, table and a card per photo with image and data')), onTap: () => Navigator.pop(context, 'pdf')),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    if (choice == 'photos') {
      await _share(st, visible, origin);
      return;
    }
    final Services sv = AppScope.of(context);
    final ExportProgress progress = ExportProgress();
    setState(() => _busy = true);
    unawaited(showExportProgress(context, progress));
    try {
      final String path = await runExport(choice, list, st, sv.store, spanish: sv.settings.spanish, title: _projectId == null ? 'Sello' : (st.projectMap[_projectId]?.name ?? 'Sello'), progress: progress);
      progress.close();
      await shareFiles(<String>[path], origin: origin);
    } on ExportCancelled {
      progress.close();
    } catch (e) {
      progress.close();
      _toast('${t(context, 'No se pudo exportar', 'Export failed')}: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// Avance de una exportación, para el diálogo de progreso.
class ExportProgress extends ChangeNotifier {
  final ExportCancel cancel = ExportCancel();
  int done = 0;
  int total = 0;
  String stage = '';
  bool _closed = false;
  VoidCallback? _close;

  bool get closed => _closed;

  void update(int d, int tot, [String? s]) {
    done = d;
    total = tot;
    if (s != null) {
      stage = s;
    }
    notifyListeners();
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _close?.call();
    }
  }
}

/// Diálogo con el avance y un botón para cancelar.
Future<void> showExportProgress(BuildContext context, ExportProgress progress, {String? title}) {
  final NavigatorState nav = Navigator.of(context, rootNavigator: true);
  progress._close = () {
    if (nav.mounted && nav.canPop()) {
      nav.pop();
    }
  };
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (BuildContext context) => PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: progress,
        builder: (BuildContext context, Widget? _) => AlertDialog(
          title: Text(title ?? t(context, 'Exportando', 'Exporting')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinearProgressIndicator(value: progress.total > 0 ? progress.done / progress.total : null),
              const SizedBox(height: 12),
              Text(progress.stage.isEmpty ? t(context, 'Preparando…', 'Preparing…') : progress.stage),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: progress.cancel.cancel, child: Text(t(context, 'Cancelar', 'Cancel'))),
          ],
        ),
      ),
    ),
  );
}

String _fileStamp(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}

/// Arma una exportación en un archivo de la carpeta exports/ y devuelve su
/// ruta. Lo pesado (ZIP, KMZ, miniaturas y PDF) corre fuera del hilo de la
/// interfaz.
Future<String> runExport(String kind, List<PhotoRecord> list, AppState st, JsonStore store, {required bool spanish, required String title, required ExportProgress progress}) async {
  String k(String es, String en) => spanish ? es : en;
  final Map<String, Project> projects = st.projectMap;
  final String stamp = _fileStamp(clock.now());
  Future<String> out(String name) => store.absolutePath('exports/$name');
  Future<Map<String, String>> files({required bool originals}) async {
    final Map<String, String> m = <String, String>{};
    for (final PhotoRecord p in list) {
      File? f;
      if (originals) {
        final File o = await st.fileOf(p.originalFile);
        f = await o.exists() ? o : await st.displayFile(p);
      } else {
        f = await st.displayFile(p);
      }
      if (f != null) {
        m[p.id] = f.path;
      }
    }
    return m;
  }

  void onProgress(int d, int tot) => progress.update(d, tot, '${k('Guardando', 'Saving')} $d ${k('de', 'of')} $tot');
  switch (kind) {
    case 'csv':
      {
        await store.writeBytes('exports/sello_$stamp.csv', Exports.csvBytes(list, projects, spanish: spanish));
        return out('sello_$stamp.csv');
      }
    case 'kml':
      {
        await store.writeBytes('exports/sello_$stamp.kml', utf8.encode(Exports.kml(list, projects, title: title, spanish: spanish)));
        return out('sello_$stamp.kml');
      }
    case 'kmz':
      {
        final String path = await out('sello_$stamp.kmz');
        await writeZipFile(path, Exports.kmzEntries(list, projects, title: title, files: await files(originals: false), spanish: spanish), onProgress: onProgress, cancel: progress.cancel);
        return path;
      }
    case 'zip':
    case 'zip-orig':
      {
        final bool originals = kind == 'zip-orig';
        final String name = originals ? 'sello_${stamp}_${k('originales', 'originals')}.zip' : 'sello_$stamp.zip';
        final String path = await out(name);
        await writeZipFile(path, Exports.zipEntries(list, projects, title: title, files: await files(originals: originals), spanish: spanish), onProgress: onProgress, cancel: progress.cancel);
        return path;
      }
    case 'pdf':
      {
        final Map<String, Uint8List> images = <String, Uint8List>{};
        for (int i = 0; i < list.length; i++) {
          if (progress.cancel.cancelled) {
            throw const ExportCancelled();
          }
          progress.update(i, list.length, '${k('Preparando imagen', 'Preparing image')} ${i + 1} ${k('de', 'of')} ${list.length}');
          final File? f = await st.displayFile(list[i]);
          if (f != null) {
            try {
              images[list[i].id] = await PdfReport.thumbnail(await f.readAsBytes());
            } catch (_) {}
          }
        }
        progress.update(list.length, list.length, k('Armando el PDF…', 'Building the PDF…'));
        final Uint8List pdf = await PdfReport.build(photos: list, projects: projects, title: title, images: images, spanish: spanish);
        if (progress.cancel.cancelled) {
          throw const ExportCancelled();
        }
        await store.writeBytes('exports/sello_$stamp.pdf', pdf);
        return out('sello_$stamp.pdf');
      }
  }
  throw ArgumentError.value(kind, 'kind');
}

class _Section {
  _Section(this.day);

  final String day;
  final List<PhotoRecord> photos = <PhotoRecord>[];
}

class _Grid extends StatelessWidget {
  const _Grid({required this.photos, required this.projects, required this.groupKey, required this.selected, required this.onTap, required this.onLongPress, required this.spanish});

  final List<PhotoRecord> photos;
  final Map<String, Project> projects;
  final String Function(PhotoRecord) groupKey;
  final Set<String> selected;
  final ValueChanged<PhotoRecord> onTap;
  final ValueChanged<PhotoRecord> onLongPress;
  final bool spanish;

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
                child: Semantics(header: true, child: Text(sec.day, style: Theme.of(context).textTheme.labelLarge)),
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
    final String project = projects[p.projectId]?.name ?? '';
    final String state = p.isPending ? (spanish ? ', sellando' : ', stamping') : (p.isFailed ? (spanish ? ', sin sellar' : ', not stamped') : '');
    final String label = '${spanish ? 'Foto del' : 'Photo of'} ${formatDate(p.wallTime, 'dd/MM/yyyy HH:mm')}${project.isEmpty ? '' : ', $project'}${p.notes.isEmpty ? '' : ', ${p.notes}'}${p.hasLocation ? '' : (spanish ? ', sin GPS' : ', no GPS')}$state';
    return Semantics(
      button: true,
      selected: sel,
      label: label,
      onLongPressHint: spanish ? 'seleccionar' : 'select',
      excludeSemantics: true,
      // Las acciones del GestureDetector quedan excluidas: se declaran aquí.
      onTap: () => onTap(p),
      onLongPress: () => onLongPress(p),
      child: GestureDetector(
        onTap: () => onTap(p),
        onLongPress: () => onLongPress(p),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(borderRadius: BorderRadius.circular(8), child: PhotoThumb(key: ValueKey<String>('${p.id}-${p.version}-${p.status.name}'), record: p)),
            if (!p.hasLocation) const Positioned(left: 4, top: 4, child: Icon(Icons.location_off, size: 16, color: Colors.white)),
            if (p.isPending)
              const Positioned(right: 6, top: 6, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
            else if (p.isFailed)
              const Positioned(right: 4, top: 4, child: Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber)),
            if (projects.length > 1)
              Positioned(
                left: 4,
                bottom: 4,
                right: 4,
                child: Text(project, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, shadows: <Shadow>[Shadow(blurRadius: 4, color: Colors.black)])),
              ),
            if (sel)
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3), color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
                child: const Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle, color: Colors.white))),
              ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de una foto guardada por la app: la copia sellada o, mientras
/// se sella (o si falló), el original.
class PhotoThumb extends StatefulWidget {
  const PhotoThumb({super.key, required this.record, this.cacheWidth = kGalleryThumbWidth});

  final PhotoRecord record;
  final int cacheWidth;

  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  Future<File?>? _file;
  String _key = '';

  String _keyOf(PhotoRecord p) => '${p.id}|${p.version}|${p.status.name}|${p.stampedFile}|${p.originalFile}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant PhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final String key = _keyOf(widget.record);
    if (_file == null || key != _key) {
      _key = key;
      _file = AppScope.of(context).state.displayFile(widget.record);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FutureBuilder<File?>(
      future: _file,
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        final File? f = snap.data;
        if (f == null) {
          return ColoredBox(color: placeholder, child: snap.connectionState == ConnectionState.done ? const Icon(Icons.broken_image_outlined) : null);
        }
        return Image.file(
          f,
          fit: BoxFit.cover,
          cacheWidth: widget.cacheWidth,
          errorBuilder: (_, __, ___) => ColoredBox(color: placeholder, child: const Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}
