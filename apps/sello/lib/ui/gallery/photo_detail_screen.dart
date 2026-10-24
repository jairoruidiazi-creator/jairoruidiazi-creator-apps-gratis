import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/maps_links.dart';
import '../../core/sharing.dart';
import '../../core/user_errors.dart';
import '../../geo/coords.dart';
import '../../model/models.dart';
import '../../stamp/capture_pipeline.dart';
import '../../stamp/composer.dart';
import 'gallery_screen.dart';

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

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.state, s.queue, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final PhotoRecord? p = st.photoById(widget.photoId);
        if (p == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(t(context, 'La foto ya no existe.', 'The photo no longer exists.'))));
        }
        final Project project = st.projectById(p.projectId);
        final bool spanish = s.settings.spanish;
        final bool stamping = s.queue.contains(p.id) || _busy;
        final bool canShowStamped = p.status == PhotoStatus.ok && p.stampedFile.isNotEmpty;
        final bool showOriginal = _showOriginal || !canShowStamped;
        return Scaffold(
          appBar: AppBar(
            title: Text(formatDate(p.wallTime, 'dd/MM/yyyy HH:mm', spanish: spanish)),
            actions: <Widget>[
              Builder(
                builder: (BuildContext buttonContext) => IconButton(tooltip: t(context, 'Compartir', 'Share'), onPressed: stamping ? null : () => _share(st, p, shareOriginOf(buttonContext)), icon: const Icon(Icons.share_outlined)),
              ),
              Builder(
                builder: (BuildContext menuContext) => PopupMenuButton<String>(
                  tooltip: t(context, 'Más opciones', 'More options'),
                  onSelected: (String v) => _menu(v, st, p, shareOriginOf(menuContext)),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t(context, 'Editar datos', 'Edit data')))),
                    PopupMenuItem<String>(
                      value: 'restamp',
                      enabled: !stamping,
                      child: ListTile(
                        leading: const Icon(Icons.approval_outlined),
                        title: Text(p.status == PhotoStatus.ok ? t(context, 'Volver a sellar', 'Re-stamp') : t(context, 'Reintentar sellado', 'Retry stamping')),
                        subtitle: Text(t(context, 'Con la plantilla actual del proyecto', 'With the project\'s current template')),
                      ),
                    ),
                    PopupMenuItem<String>(value: 'share-clean', enabled: !stamping, child: ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t(context, 'Compartir sin EXIF', 'Share without EXIF')), subtitle: Text(t(context, 'Sin ubicación ni fecha en los metadatos', 'No location or date in the metadata')))),
                    PopupMenuItem<String>(value: 'copy', child: ListTile(leading: const Icon(Icons.copy_rounded), title: Text(t(context, 'Copiar datos', 'Copy data')))),
                    if (p.hasLocation) PopupMenuItem<String>(value: 'maps', child: ListTile(leading: const Icon(Icons.map_outlined), title: Text(t(context, 'Abrir en mapas', 'Open in maps')))),
                    if (p.hasLocation) PopupMenuItem<String>(value: 'navigate', child: ListTile(leading: const Icon(Icons.directions_outlined), title: Text(t(context, 'Cómo llegar', 'Directions')))),
                    PopupMenuItem<String>(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(t(context, 'Borrar', 'Delete')))),
                  ],
                ),
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
                  child: _Photo(key: ValueKey<String>('${p.id}-${p.version}-${p.status.name}-$showOriginal'), record: p, original: showOriginal, busy: stamping),
                ),
              ),
              if (p.status != PhotoStatus.ok) _StatusBanner(record: p, stamping: stamping, onRetry: stamping ? null : () => _restamp(st, p)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (canShowStamped)
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
              _Row(t(context, 'Fecha y hora', 'Date and time'), '${formatDate(p.wallTime, 'dd/MM/yyyy HH:mm:ss', spanish: spanish)} ${p.offsetLabel}'),
              _Row('UTC', '${formatDate(p.takenAt, 'yyyy-MM-dd HH:mm:ss')}Z'),
              if (p.hasLocation) ...<Widget>[
                for (final CoordFormat cf in Coords.formatsFor(p.latitude!, p.longitude!, coarse: p.approximateLocation)) _Row(Coords.formatName(cf, spanish: spanish, coarse: p.approximateLocation), Coords.format(cf, p.latitude!, p.longitude!, coarse: p.approximateLocation), copyable: true),
                _Row(t(context, 'Posición', 'Position'), _sourceText(context, p)),
                if (p.accuracy != null) _Row(t(context, 'Precisión', 'Accuracy'), '± ${p.accuracy!.toStringAsFixed(1)} m'),
                if (p.altitude != null) _Row(t(context, 'Altitud', 'Altitude'), '${p.altitude!.toStringAsFixed(1)} m ${p.altitudeReference == 'ellipsoid' ? t(context, 'sobre el elipsoide', 'above the ellipsoid') : t(context, 'sobre el nivel del mar', 'above sea level')}'),
              ] else
                _Row(t(context, 'Ubicación', 'Location'), t(context, 'Sin señal GPS al momento de la foto', 'No GPS fix when the photo was taken')),
              if (p.heading != null)
                _Row(
                  t(context, 'Rumbo', 'Heading'),
                  '${p.heading!.toStringAsFixed(0)}° ${Coords.cardinal(p.heading!, spanish: spanish)}${p.headingTrue ? '' : t(context, ' (magnético)', ' (magnetic)')} · ${t(context, 'fachada', 'facade')} ${Coords.facade(p.heading!, spanish: spanish)}${p.pitch != null ? ' · ${t(context, 'incl.', 'tilt')} ${p.pitch!.toStringAsFixed(0)}°' : ''}${p.frontCamera ? t(context, ' · cámara frontal', ' · front camera') : ''}',
                ),
              if (p.speed != null && p.speed! > 0.5 && p.positionSource == PositionSource.gps) _Row(t(context, 'Velocidad', 'Speed'), '${(p.speed! * 3.6).toStringAsFixed(0)} km/h'),
              if (p.address.isNotEmpty) _Row(t(context, 'Dirección', 'Address'), p.address),
              for (final MapEntry<String, String> e in p.labeledFields(project)) _Row(e.key, e.value),
              _Row(t(context, 'Archivo', 'File'), (showOriginal ? p.originalFile : p.stampedFile).split('/').last),
              if (p.width > 0) _Row(t(context, 'Tamaño', 'Size'), '${p.width} × ${p.height} px'),
            ],
          ),
        );
      },
    );
  }

  String _sourceText(BuildContext context, PhotoRecord p) {
    final String source = _sourceKind(context, p);
    return p.approximateLocation ? '$source · ${t(context, 'ubicación aproximada: el teléfono solo dio permiso de ubicación aproximada y puede estar a kilómetros', 'approximate location: the phone only allowed approximate location and it may be kilometres off')}' : source;
  }

  String _sourceKind(BuildContext context, PhotoRecord p) {
    switch (p.positionSource) {
      case PositionSource.gps:
        return p.fixAgeSeconds > 30 ? '${t(context, 'GPS (lectura de hace', 'GPS (reading from')} ${p.fixAgeSeconds} s${t(context, ')', ' ago)')}' : 'GPS';
      case PositionSource.locked:
        return t(context, 'Fijada a mano desde una lectura del GPS', 'Locked from a GPS reading');
      case PositionSource.averaged:
        return '${t(context, 'Promedio de', 'Average of')} ${p.averagedSamples} ${t(context, 'lecturas', 'readings')}';
      case PositionSource.manual:
        return t(context, 'Escrita a mano (sin precisión ni altitud)', 'Entered by hand (no accuracy or altitude)');
    }
  }

  Future<void> _menu(String v, AppState st, PhotoRecord p, Rect origin) async {
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
          _toast(t(context, 'Datos copiados', 'Data copied'));
        }
        break;
      case 'share-clean':
        await _share(st, p, origin, withoutMetadata: true);
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

  /// Datos de la foto en texto, con los rótulos de los campos.
  String _plainText(AppState st, PhotoRecord p) {
    final Project project = st.projectById(p.projectId);
    final List<String> lines = <String>[
      '${formatDate(p.wallTime, 'dd/MM/yyyy HH:mm:ss')} ${p.offsetLabel}',
      if (p.hasLocation) ...<String>[
        for (final CoordFormat cf in <CoordFormat>[CoordFormat.dd, CoordFormat.utm, CoordFormat.mgrs]) Coords.format(cf, p.latitude!, p.longitude!, coarse: p.approximateLocation),
        if (p.approximateLocation) Coords.plusCode(p.latitude!, p.longitude!, length: 6) else Coords.plusCode(p.latitude!, p.longitude!, length: 11),
        if (p.approximateLocation) t(context, '(ubicación aproximada)', '(approximate location)'),
      ],
      if (p.hasLocation && Coords.inColombia(p.latitude!, p.longitude!)) ...<String>['CTM12 ${Coords.format(CoordFormat.ctm12, p.latitude!, p.longitude!, coarse: p.approximateLocation)}', 'MAGNA ${Coords.format(CoordFormat.magna, p.latitude!, p.longitude!, coarse: p.approximateLocation)}'],
      if (p.accuracy != null) '± ${p.accuracy!.toStringAsFixed(1)} m',
      if (p.altitude != null) 'Alt. ${p.altitude!.toStringAsFixed(1)} m ${p.altitudeReference == 'ellipsoid' ? t(context, 'elip.', 'ellips.') : t(context, 's. n. m.', 'MSL')}',
      if (p.heading != null) '${p.heading!.toStringAsFixed(0)}°${p.headingTrue ? '' : t(context, ' (magnético)', ' (magnetic)')}',
      if (p.address.isNotEmpty) p.address,
      project.name,
      for (final MapEntry<String, String> e in p.labeledFields(project)) '${e.key}: ${e.value}',
      if (p.notes.isNotEmpty) p.notes,
      if (p.tags.isNotEmpty) p.tags.map((String x) => '#$x').join(' '),
    ];
    return lines.join('\n');
  }

  Future<void> _share(AppState st, PhotoRecord p, Rect origin, {bool withoutMetadata = false}) async {
    final Services s = AppScope.of(context);
    try {
      final bool original = _showOriginal || p.status != PhotoStatus.ok;
      final File f = await st.fileOf(original ? p.originalFile : p.stampedFile);
      if (!await f.exists()) {
        if (mounted) {
          _toast(t(context, 'No se encontró el archivo de la foto.', 'The photo file was not found.'));
        }
        return;
      }
      if (withoutMetadata) {
        // Copia sin EXIF (sin ubicación ni fecha en los metadatos); el sello
        // dibujado se conserva y la original no queda de lado.
        final Uint8List clean = stripMetadata(await f.readAsBytes());
        final String name = f.uri.pathSegments.last.replaceAll('.jpg', s.settings.spanish ? '_sin_exif.jpg' : '_no_exif.jpg');
        await shareBytes(s.store, name, clean, origin: origin);
        return;
      }
      final String link = p.hasLocation ? 'https://www.openstreetmap.org/?mlat=${p.latitude}&mlon=${p.longitude}#map=18/${p.latitude}/${p.longitude}' : '';
      await shareFiles(<String>[f.path], origin: origin, text: <String>[if (p.description.isNotEmpty) p.description, if (link.isNotEmpty) link].join('\n'));
    } catch (e) {
      if (mounted) {
        _toast('${t(context, 'No se pudo compartir', 'Could not share')}: ${errorReason(e, spanish: AppScope.of(context).settings.spanish)}.');
      }
    }
  }

  Future<void> _edit(AppState st, PhotoRecord p) async {
    final TextEditingController notes = TextEditingController(text: p.notes);
    final TextEditingController tags = TextEditingController(text: p.tags.join(' '));
    // Cuadros de los campos del proyecto elegido: si se cambia de proyecto
    // aparecen los del nuevo (con lo que la foto ya tuviera o el valor
    // inicial), y al guardar se graban esos.
    final Map<String, TextEditingController> fieldCtrls = <String, TextEditingController>{};
    void ensureFields(Project pr) {
      for (final FieldDef f in pr.fields) {
        fieldCtrls.putIfAbsent(f.key, () => TextEditingController(text: p.fields[f.key] ?? (pr.id == p.projectId ? '' : f.defaultValue)));
      }
    }

    String projectId = p.projectId;
    ensureFields(st.projectById(projectId));
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
                  onChanged: (String? v) => setLocal(() {
                    projectId = v ?? projectId;
                    ensureFields(st.projectById(projectId));
                  }),
                ),
                for (final FieldDef f in st.projectById(projectId).fields) TextField(key: ValueKey<String>('campo-${f.key}'), controller: fieldCtrls[f.key], decoration: InputDecoration(labelText: f.label)),
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
      // Los campos del proyecto elegido; los de otro proyecto que la foto ya
      // tuviera se conservan con su rótulo (son datos de la foto).
      for (final FieldDef f in st.projectById(projectId).fields) {
        p.fields[f.key] = fieldCtrls[f.key]!.text.trim();
        p.fieldLabels[f.key] = f.label;
      }
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
        _toast(t(context, 'No se conservó el original de esta foto; no se puede volver a sellar.', 'The original of this photo was not kept; it cannot be re-stamped.'));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bool ok = await s.queue.restamp(p.id);
      if (p.stampedFile.isNotEmpty) {
        await evictPhotoImages(await st.fileOf(p.stampedFile));
      }
      if (mounted) {
        setState(() => _showOriginal = false);
        _toast(ok ? t(context, 'Foto sellada de nuevo.', 'Photo re-stamped.') : '${t(context, 'No se pudo sellar', 'Could not stamp')}: ${_errorText(context, p.error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// Motivo de un fallo de sellado, en palabras.
String _errorText(BuildContext context, String error) {
  switch (error) {
    case StampException.missingOriginal:
      return t(context, 'falta el archivo original', 'the original file is missing');
    case StampException.unreadable:
      return t(context, 'el archivo no se puede leer', 'the file cannot be read');
    case AppState.kErrorRecoveredOriginal:
      return t(context, 'se recuperó de la carpeta sin sus datos de sellado', 'it was recovered from the folder without its stamp data');
  }
  // Otro error (memoria, disco…): su texto técnico no se muestra.
  return t(context, 'ocurrió un error inesperado al sellarla', 'an unexpected error occurred while stamping it');
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.record, required this.stamping, required this.onRetry});

  final PhotoRecord record;
  final bool stamping;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool failed = record.isFailed && !stamping;
    return Material(
      color: failed ? cs.errorContainer : cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            if (failed) Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer) else const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                failed
                    ? '${t(context, 'Esta foto no se pudo sellar: se muestra el original.', 'This photo could not be stamped: the original is shown.')} ${record.error.isEmpty ? '' : '(${_errorText(context, record.error)})'}'
                    : t(context, 'Sellando la foto… la imagen sellada aparece en un momento.', 'Stamping the photo… the stamped image appears in a moment.'),
                style: TextStyle(color: failed ? cs.onErrorContainer : cs.onSecondaryContainer),
              ),
            ),
            if (failed) TextButton(onPressed: onRetry, child: Text(t(context, 'Reintentar', 'Retry'))),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatefulWidget {
  const _Photo({super.key, required this.record, required this.original, required this.busy});

  final PhotoRecord record;
  final bool original;
  final bool busy;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  Future<File?>? _file;

  /// Al acercar más de 2,5× se decodifica con más detalle (hasta
  /// [kDetailZoomBox]); antes, al doble de lo que ocupa en pantalla.
  final TransformationController _zoom = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  void _onZoom() {
    if (!_zoomed && _zoom.value.getMaxScaleOnAxis() > 2.5) {
      setState(() => _zoomed = true);
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _file ??= _resolve();
  }

  Future<File?> _resolve() async {
    final AppState st = AppScope.of(context).state;
    if (widget.original) {
      final File o = await st.fileOf(widget.record.originalFile);
      if (await o.exists()) {
        return o;
      }
    }
    return st.displayFile(widget.record);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        final File? f = snap.data;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (f != null)
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final double dpr = MediaQuery.devicePixelRatioOf(context);
                  final double side = math.max(box.maxWidth.isFinite ? box.maxWidth : 0, box.maxHeight.isFinite ? box.maxHeight : 0) * dpr * 2;
                  return InteractiveViewer(
                    maxScale: 8,
                    transformationController: _zoom,
                    child: Semantics(
                      image: true,
                      label: AppScope.of(context).settings.spanish ? 'Foto' : 'Photo',
                      child: Image(
                        image: detailImage(f, _zoomed ? kDetailZoomBox : detailBoxFor(side)),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Center(child: Text(AppScope.of(context).settings.spanish ? 'No se encontró el archivo' : 'File not found', style: const TextStyle(color: Colors.white70))),
                      ),
                    ),
                  );
                },
              )
            else if (snap.connectionState == ConnectionState.done)
              Center(child: Text(AppScope.of(context).settings.spanish ? 'No se encontró el archivo' : 'File not found', style: const TextStyle(color: Colors.white70))),
            if (widget.busy) const Center(child: CircularProgressIndicator()),
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
    void copy() {
      Clipboard.setData(ClipboardData(text: value));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Copiado', 'Copied')}: $value'), duration: const Duration(seconds: 1)));
    }

    // Toda la fila copia: mide al menos 48 dp (guías de Android y Apple) y el
    // lector de pantalla anuncia la acción («copiar»), no solo «botón».
    return Semantics(
      button: true,
      label: '$label: $value',
      onTapHint: t(context, 'copiar', 'copy'),
      onTap: copy,
      excludeSemantics: true,
      child: InkWell(
        onTap: copy,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Separación fija: una etiqueta larga ("Degrees and decimal minutes")
            // no debe quedar pegada al valor.
            SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 10),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
            if (copyable) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy_rounded, size: 16)),
          ],
        ),
            ),
          ),
        ),
      ),
    );
  }
}
