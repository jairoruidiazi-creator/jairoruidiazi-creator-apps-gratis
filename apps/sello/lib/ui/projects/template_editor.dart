import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../geo/coords.dart';
import '../../model/models.dart';
import '../../stamp/stamp_data.dart';
import '../../stamp/stamp_painter.dart';

/// Edición de una plantilla de sello con vista previa en vivo.
class TemplateEditor extends StatefulWidget {
  const TemplateEditor({super.key, required this.templateId});

  final String templateId;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  StampTemplate? _tpl;
  late final TextEditingController _name;
  late final TextEditingController _dateFormat;
  ui.Image? _logo;
  String? _logoLoadedFor;
  bool _dirty = false;

  static const List<String> _dateFormats = <String>['dd/MM/yyyy HH:mm:ss', 'dd/MM/yyyy HH:mm', 'yyyy-MM-dd HH:mm:ss', 'EEE dd/MM/yyyy HH:mm', 'dd-MM-yyyy HH:mm'];
  static const List<int> _textColors = <int>[0xFFFFFFFF, 0xFFFFEB3B, 0xFF000000, 0xFFB9F6CA, 0xFF80DEEA, 0xFFFFAB91];
  static const List<int> _bgColors = <int>[0xFF000000, 0xFFFFFFFF, 0xFF1B4332, 0xFF0D47A1, 0xFF4E342E, 0xFFB71C1C];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tpl == null) {
      final StampTemplate tpl = AppScope.of(context).state.templateById(widget.templateId);
      _tpl = tpl;
      _name = TextEditingController(text: tpl.displayName(spanish: AppScope.of(context).settings.spanish));
      _dateFormat = TextEditingController(text: tpl.dateFormat);
      _name.addListener(() {
        tpl.name = _name.text.trim().isEmpty ? tpl.name : _name.text.trim();
        _dirty = true;
      });
      _dateFormat.addListener(() {
        if (_dateFormat.text.trim().isNotEmpty) {
          _edit(() => tpl.dateFormat = _dateFormat.text.trim());
        }
      });
    }
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    final StampTemplate tpl = _tpl!;
    if (_logoLoadedFor == tpl.logoPath) {
      return;
    }
    _logoLoadedFor = tpl.logoPath;
    final File? f = await AppScope.of(context).state.logoFile(tpl);
    ui.Image? img;
    if (f != null) {
      try {
        img = await decodeLogo(await f.readAsBytes());
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _logo = img);
    }
  }

  @override
  void dispose() {
    disposeLater(<ChangeNotifier>[_name, _dateFormat]);
    super.dispose();
  }

  void _edit(VoidCallback fn) {
    setState(() {
      fn();
      _dirty = true;
    });
  }

  Future<void> _save(AppState st) async {
    await st.saveProjects();
    if (mounted) {
      setState(() => _dirty = false);
    }
  }

  Future<void> _pickLogo(AppState st) async {
    final XTypeGroup images = XTypeGroup(label: t(context, 'Imágenes', 'Images'), extensions: <String>['png', 'jpg', 'jpeg', 'webp'], mimeTypes: <String>['image/*'], uniformTypeIdentifiers: <String>['public.image']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo abrir el selector', 'Could not open the picker')}: $e')));
      }
      return;
    }
    if (file == null) {
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    final String ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'png';
    final String rel = 'logos/${_tpl!.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await st.store.writeBytes(rel, bytes);
    _edit(() => _tpl!.logoPath = rel);
    await _save(st);
    await _loadLogo();
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    final StampTemplate tpl = _tpl!;
    final bool spanish = s.settings.spanish;
    final StampData sample = StampData(
      time: clock.now(),
      latitude: 4.711000,
      longitude: -74.072100,
      accuracy: 4.2,
      altitude: 2601,
      heading: 135,
      pitch: 3,
      speed: 0,
      address: spanish ? 'Cra 7 # 72-41, Chapinero, Bogotá, Colombia' : '7th Ave # 72-41, Chapinero, Bogotá, Colombia',
      projectName: spanish ? 'Obra Calle 80' : 'Site 80th St',
      fields: <String, String>{'lote': '12', 'inspector': 'J. Díaz'},
      fieldLabels: <String, String>{'lote': spanish ? 'Lote' : 'Lot', 'inspector': 'Inspector'},
      notes: spanish ? 'Columna C-3, nivel 2' : 'Column C-3, level 2',
      spanish: spanish,
    );
    final TextTheme tt = Theme.of(context).textTheme;
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop && _dirty) {
          st.saveProjects();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t(context, 'Plantilla de sello', 'Stamp template')),
          actions: <Widget>[TextButton(onPressed: () => _save(st), child: Text(t(context, 'Guardar', 'Save')))],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: <Widget>[
            // Vista previa
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CustomPaint(
                  painter: const _SamplePhotoPainter(),
                  foregroundPainter: StampPainter(template: tpl, data: sample, logo: _logo),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(t(context, 'Vista previa con datos de ejemplo. El tamaño del texto es proporcional al ancho de la foto.', 'Preview with sample data. Text size is proportional to the photo width.'), style: tt.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'), border: const OutlineInputBorder())),
            const SizedBox(height: 16),
            Text(t(context, 'Datos del sello', 'Stamp data'), style: tt.titleMedium),
            for (final StampItem item in StampItem.values)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_itemName(context, item)),
                subtitle: _itemHint(context, item) == null ? null : Text(_itemHint(context, item)!),
                value: tpl.items.contains(item),
                onChanged: (bool? v) => _edit(() => v == true ? tpl.items.add(item) : tpl.items.remove(item)),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'Mostrar rótulos', 'Show labels')),
              subtitle: Text(t(context, '"GPS: 4.711000, -74.072100" en vez de solo los números', '"GPS: 4.711000, -74.072100" instead of just the numbers')),
              value: tpl.showLabels,
              onChanged: (bool v) => _edit(() => tpl.showLabels = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<CoordFormat>(
                    initialValue: tpl.coordFormat,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t(context, 'Coordenadas', 'Coordinates'), border: const OutlineInputBorder()),
                    items: <DropdownMenuItem<CoordFormat>>[for (final CoordFormat f in CoordFormat.values) DropdownMenuItem<CoordFormat>(value: f, child: Text(_formatName(context, f), overflow: TextOverflow.ellipsis))],
                    onChanged: (CoordFormat? v) => _edit(() => tpl.coordFormat = v ?? tpl.coordFormat),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<CoordFormat>(
                    initialValue: tpl.coordFormat2,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t(context, '2.º formato', '2nd format'), border: const OutlineInputBorder()),
                    items: <DropdownMenuItem<CoordFormat>>[for (final CoordFormat f in CoordFormat.values) DropdownMenuItem<CoordFormat>(value: f, child: Text(_formatName(context, f), overflow: TextOverflow.ellipsis))],
                    onChanged: (CoordFormat? v) => _edit(() {
                      tpl.coordFormat2 = v ?? tpl.coordFormat2;
                      tpl.items.add(StampItem.coords2);
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(t(context, 'Formato de fecha', 'Date format'), style: tt.titleMedium),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (final String f in _dateFormats)
                  ChoiceChip(
                    label: Text(formatDate(clock.now(), f, spanish: spanish)),
                    selected: tpl.dateFormat == f,
                    onSelected: (_) {
                      _dateFormat.text = f;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(controller: _dateFormat, decoration: InputDecoration(labelText: t(context, 'Patrón (dd MM yyyy HH mm ss EEE)', 'Pattern (dd MM yyyy HH mm ss EEE)'), border: const OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 16),
            Text(t(context, 'Posición', 'Position'), style: tt.titleMedium),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (final StampPosition p in StampPosition.values)
                  ChoiceChip(label: Text(_positionName(context, p)), selected: tpl.position == p, onSelected: (_) => _edit(() => tpl.position = p)),
              ],
            ),
            const SizedBox(height: 12),
            Text('${t(context, 'Tamaño del texto', 'Text size')}: ${(tpl.textScale * 100).round()} %', style: tt.titleMedium),
            Slider(min: 0.6, max: 2.2, divisions: 16, value: tpl.textScale.clamp(0.6, 2.2), label: '${(tpl.textScale * 100).round()} %', onChanged: (double v) => _edit(() => tpl.textScale = v)),
            Text(t(context, 'Color del texto', 'Text color'), style: tt.titleMedium),
            _Swatches(colors: _textColors, selected: tpl.textColor, onPick: (int c) => _edit(() => tpl.textColor = c)),
            const SizedBox(height: 8),
            Text(t(context, 'Fondo', 'Background'), style: tt.titleMedium),
            _Swatches(colors: _bgColors, selected: tpl.backgroundColor, onPick: (int c) => _edit(() => tpl.backgroundColor = c)),
            Row(
              children: <Widget>[
                Text(t(context, 'Opacidad', 'Opacity')),
                Expanded(child: Slider(min: 0, max: 1, divisions: 20, value: tpl.backgroundOpacity.clamp(0.0, 1.0), label: '${(tpl.backgroundOpacity * 100).round()} %', onChanged: (double v) => _edit(() => tpl.backgroundOpacity = v))),
                SizedBox(width: 44, child: Text('${(tpl.backgroundOpacity * 100).round()} %', textAlign: TextAlign.end)),
              ],
            ),
            const SizedBox(height: 12),
            Text(t(context, 'Logo', 'Logo'), style: tt.titleMedium),
            Text(t(context, 'Imagen PNG o JPG (ideal PNG con fondo transparente). Se guarda dentro de la app.', 'PNG or JPG image (PNG with transparent background works best). Stored inside the app.'), style: tt.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.tonalIcon(onPressed: () => _pickLogo(st), icon: const Icon(Icons.image_outlined), label: Text(tpl.logoPath == null ? t(context, 'Elegir logo', 'Choose logo') : t(context, 'Cambiar logo', 'Change logo'))),
                if (tpl.logoPath != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final String old = tpl.logoPath!;
                      _edit(() => tpl.logoPath = null);
                      _logo = null;
                      _logoLoadedFor = null;
                      if (!old.startsWith('/')) {
                        await st.store.delete(old);
                      }
                      await _save(st);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(t(context, 'Quitar', 'Remove')),
                  ),
              ],
            ),
            if (tpl.logoPath != null) ...<Widget>[
              const SizedBox(height: 6),
              Text('${t(context, 'Tamaño del logo', 'Logo size')}: ${(tpl.logoScale * 100).round()} %'),
              Slider(min: 0.4, max: 3, divisions: 26, value: tpl.logoScale.clamp(0.4, 3.0), label: '${(tpl.logoScale * 100).round()} %', onChanged: (double v) => _edit(() => tpl.logoScale = v)),
              Text('${t(context, 'Opacidad del logo', 'Logo opacity')}: ${(tpl.logoOpacity * 100).round()} %'),
              Slider(min: 0.1, max: 1, divisions: 18, value: tpl.logoOpacity.clamp(0.1, 1.0), label: '${(tpl.logoOpacity * 100).round()} %', onChanged: (double v) => _edit(() => tpl.logoOpacity = v)),
              Text(t(context, 'Posición del logo', 'Logo position')),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final StampPosition p in StampPosition.values)
                    if (p != StampPosition.bottomBar) ChoiceChip(label: Text(_positionName(context, p)), selected: tpl.logoPosition == p, onSelected: (_) => _edit(() => tpl.logoPosition = p)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: () => _save(st), child: Text(_dirty ? t(context, 'Guardar cambios', 'Save changes') : t(context, 'Guardado', 'Saved'))),
          ],
        ),
      ),
    );
  }

  static String _itemName(BuildContext context, StampItem i) {
    switch (i) {
      case StampItem.dateTime:
        return t(context, 'Fecha y hora local', 'Local date and time');
      case StampItem.utc:
        return t(context, 'Hora UTC', 'UTC time');
      case StampItem.coords:
        return t(context, 'Coordenadas', 'Coordinates');
      case StampItem.coords2:
        return t(context, 'Coordenadas en un segundo formato', 'Coordinates in a second format');
      case StampItem.altitude:
        return t(context, 'Altitud', 'Altitude');
      case StampItem.accuracy:
        return t(context, 'Precisión del GPS', 'GPS accuracy');
      case StampItem.heading:
        return t(context, 'Rumbo e inclinación', 'Heading and tilt');
      case StampItem.facade:
        return t(context, 'Fachada fotografiada', 'Facade photographed');
      case StampItem.speed:
        return t(context, 'Velocidad (si se mueve)', 'Speed (when moving)');
      case StampItem.address:
        return t(context, 'Dirección aproximada', 'Approximate address');
      case StampItem.project:
        return t(context, 'Nombre del proyecto', 'Project name');
      case StampItem.fields:
        return t(context, 'Campos del proyecto', 'Project fields');
      case StampItem.notes:
        return t(context, 'Notas de la foto', 'Photo notes');
      case StampItem.compass:
        return t(context, 'Rosa de los vientos', 'Compass rose');
    }
  }

  static String? _itemHint(BuildContext context, StampItem i) {
    switch (i) {
      case StampItem.address:
        return t(context, 'Necesita internet al momento de la foto', 'Needs internet when the photo is taken');
      case StampItem.facade:
        return t(context, 'Lado del edificio que mira a la cámara (rumbo + 180°)', 'Side of the building facing the camera (heading + 180°)');
      case StampItem.compass:
        return t(context, 'Dibujo con el norte y el rumbo de la cámara', 'Drawing with north and the camera heading');
      default:
        return null;
    }
  }

  static String _formatName(BuildContext context, CoordFormat f) => Coords.formatName(f, spanish: AppScope.of(context).settings.spanish, withCountry: true);

  static String _positionName(BuildContext context, StampPosition p) {
    switch (p) {
      case StampPosition.bottomLeft:
        return t(context, 'Abajo izq.', 'Bottom left');
      case StampPosition.bottomRight:
        return t(context, 'Abajo der.', 'Bottom right');
      case StampPosition.topLeft:
        return t(context, 'Arriba izq.', 'Top left');
      case StampPosition.topRight:
        return t(context, 'Arriba der.', 'Top right');
      case StampPosition.bottomBar:
        return t(context, 'Franja inferior', 'Bottom bar');
    }
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.selected, required this.onPick});

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        for (final int c in colors)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: selected == c ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant, width: selected == c ? 3 : 1),
              ),
              child: selected == c ? Icon(Icons.check, size: 18, color: Color(c).computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
            ),
          ),
      ],
    );
  }
}

/// Fondo de ejemplo para la vista previa: cielo, suelo y una obra.
class _SamplePhotoPainter extends CustomPainter {
  const _SamplePhotoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF8EC5FC), Color(0xFFE0F2FE)]).createShader(r));
    final Rect ground = Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38);
    canvas.drawRect(ground, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF9E8B6E), Color(0xFF6D5A42)]).createShader(ground));
    final Paint wall = Paint()..color = const Color(0xFFBDBDBD);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.15, size.height * 0.25, size.width * 0.42, size.height * 0.4), wall);
    final Paint win = Paint()..color = const Color(0xFF546E7A);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 2; j++) {
        canvas.drawRect(Rect.fromLTWH(size.width * (0.19 + i * 0.12), size.height * (0.3 + j * 0.15), size.width * 0.07, size.height * 0.09), win);
      }
    }
    canvas.drawRect(Rect.fromLTWH(size.width * 0.62, size.height * 0.2, size.width * 0.03, size.height * 0.45), Paint()..color = const Color(0xFFF9A825));
    canvas.drawRect(Rect.fromLTWH(size.width * 0.5, size.height * 0.2, size.width * 0.35, size.height * 0.025), Paint()..color = const Color(0xFFF9A825));
  }

  @override
  bool shouldRepaint(covariant _SamplePhotoPainter old) => false;
}
