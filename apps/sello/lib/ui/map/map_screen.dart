import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/maps_links.dart';
import '../../geo/coords.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import '../gallery/gallery_screen.dart';
import '../gallery/photo_detail_screen.dart';

/// Mapa con las fotos (OpenStreetMap) y la posición actual. Se crea solo
/// cuando se abre su pestaña (ver HomeShell): antes no pide teselas.
class MapScreen extends StatefulWidget {
  /// Distancia a una foto. Si alguno de los dos puntos es aproximado, en
  /// kilómetros enteros y con «≈»: más detalle sería falso.
  /// Radio en metros del círculo de una foto aproximada: su precisión, entre
  /// 1 km (el redondeo a 0,01° ya suma casi eso) y 10 km.
  static double approximateRadius(double? accuracy) => accuracy == null || !accuracy.isFinite ? 1000.0 : accuracy.clamp(1000.0, 10000.0);

  static String distanceText(double m, {bool approximate = false}) {
    if (approximate) {
      return '≈ ${math.max(1, (m / 1000).round())} km';
    }
    return m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 2 : 1)} km';
  }

  const MapScreen({super.key, this.active = true});

  /// El mapa está a la vista: mientras tanto usa la ubicación (tu posición y
  /// la distancia a cada foto); fuera de vista la suelta.
  final bool active;

  /// Falso en pruebas: no se descargan teselas.
  static bool tilesEnabled = true;

  /// Proveedor de teselas para pruebas (por ejemplo, teselas guardadas en
  /// disco para las capturas de tienda). En la app es nulo.
  @visibleForTesting
  static TileProvider? tileProviderOverride;

  static const String userAgent = '$kAppName/$kAppVersion (co.appsgratis.sello; +$kRepoUrl)';

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();

  /// La política de teselas de OpenStreetMap pide un User-Agent propio que
  /// nombre la app y una forma de contacto. TileLayer lo libera al quitarse
  /// (al apagar el mapa en línea): si se vuelve a encender, se crea otro.
  NetworkTileProvider? _tiles;
  String? _projectId;
  bool _fitted = false;
  bool _ready = false;
  LocationService? _location;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_location == null) {
      _location = AppScope.of(context).location;
      if (widget.active) {
        _location!.acquire(this);
      }
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        _location?.acquire(this);
      } else {
        _location?.release(this);
      }
    }
  }

  @override
  void dispose() {
    _location?.release(this);
    _map.dispose();
    super.dispose();
  }

  List<PhotoRecord> _visible(AppState st) => st.photos.where((PhotoRecord p) => p.hasLocation && (_projectId == null || p.projectId == _projectId)).toList();

  void _fitAll(List<PhotoRecord> photos, Fix? fix) {
    if (!_ready) {
      return;
    }
    final List<LatLng> pts = <LatLng>[for (final PhotoRecord p in photos) LatLng(p.latitude!, p.longitude!)];
    if (fix != null) {
      pts.add(LatLng(fix.latitude, fix.longitude));
    }
    if (pts.isEmpty) {
      return;
    }
    if (pts.length == 1) {
      _map.move(pts.first, 16);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 17));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.state, s.location, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final List<PhotoRecord> photos = _visible(st);
        final Fix? fix = s.location.fix;
        final bool tiles = MapScreen.tilesEnabled && s.settings.mapTiles;
        if (!tiles) {
          _tiles = null;
        }
        final bool spanish = s.settings.spanish;
        // Al tener datos por primera vez se encuadra todo.
        if (!_fitted && _ready && (photos.isNotEmpty || fix != null)) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll(photos, fix));
        }
        final LatLng initial = fix != null ? LatLng(fix.latitude, fix.longitude) : (photos.isNotEmpty ? LatLng(photos.first.latitude!, photos.first.longitude!) : const LatLng(4.6097, -74.0817));
        return Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: fix != null || photos.isNotEmpty ? 15 : 5,
                maxZoom: 19,
                onMapReady: () {
                  _ready = true;
                  if (!_fitted) {
                    setState(() {});
                  }
                },
              ),
              children: <Widget>[
                if (tiles)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'co.appsgratis.sello',
                    tileProvider: MapScreen.tileProviderOverride ?? (_tiles ??= NetworkTileProvider(headers: <String, String>{'User-Agent': MapScreen.userAgent})),
                    maxNativeZoom: 19,
                  ),
                // Las fotos con ubicación aproximada llevan un círculo con su
                // precisión (la misma del EXIF), de 1 km como mínimo: la
                // chincheta no es un punto exacto.
                if (photos.any((PhotoRecord p) => p.approximateLocation))
                  CircleLayer(
                    circles: <CircleMarker>[
                      for (final PhotoRecord p in photos)
                        if (p.approximateLocation) CircleMarker(point: LatLng(p.latitude!, p.longitude!), radius: MapScreen.approximateRadius(p.accuracy), useRadiusInMeter: true, color: Colors.orange.withValues(alpha: 0.10), borderColor: Colors.orange.withValues(alpha: 0.5), borderStrokeWidth: 1),
                    ],
                  ),
                // El círculo de la posición en vivo es su precisión real; con la
                // aproximada puede pasar de 2 km (el tope de 500 m la achicaba).
                if (fix != null && fix.accuracy != null)
                  CircleLayer(
                    circles: <CircleMarker>[
                      CircleMarker(point: LatLng(fix.latitude, fix.longitude), radius: fix.accuracy!.clamp(1.0, fix.approximate ? 10000.0 : 500.0), useRadiusInMeter: true, color: Colors.blue.withValues(alpha: 0.12), borderColor: Colors.blue.withValues(alpha: 0.4), borderStrokeWidth: 1),
                    ],
                  ),
                MarkerLayer(
                  markers: <Marker>[
                    for (final PhotoRecord p in photos)
                      Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: Semantics(
                          button: true,
                          label: '${spanish ? 'Foto del' : 'Photo of'} ${formatDate(p.wallTime, 'dd/MM/yyyy HH:mm')}${p.notes.isEmpty ? '' : ', ${p.notes}'}${p.approximateLocation ? (spanish ? ', ubicación aproximada' : ', approximate location') : ''}',
                          excludeSemantics: true,
                          onTap: () => _showPhoto(context, st, p),
                          child: GestureDetector(
                            onTap: () => _showPhoto(context, st, p),
                            child: _Pin(color: _colorFor(st, p.projectId), approximate: p.approximateLocation),
                          ),
                        ),
                      ),
                    if (fix != null)
                      Marker(
                        point: LatLng(fix.latitude, fix.longitude),
                        width: 22,
                        height: 22,
                        child: Semantics(
                          label: spanish ? 'Tu posición' : 'Your position',
                          child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue, border: Border.all(color: Colors.white, width: 3), boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 4, color: Colors.black38)])),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _chip(context, t(context, 'Todos', 'All'), _projectId == null, () => setState(() {
                          _projectId = null;
                          _fitted = false;
                        })),
                    for (final Project p in st.projects)
                      _chip(context, p.name, _projectId == p.id, () => setState(() {
                            _projectId = p.id;
                            _fitted = false;
                          }), color: _colorFor(st, p.id)),
                  ],
                ),
              ),
            ),
            // Abajo: el aviso (si no hay fotos) y los botones, y debajo de
            // todo la atribución, que nada tapa aunque el texto sea grande.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: photos.isEmpty
                              ? Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(st.photos.isEmpty ? t(context, 'Las fotos con GPS aparecerán aquí. El mapa necesita internet para cargar; las fotos y sus datos no.', 'Photos with GPS will appear here. The map needs internet to load; photos and their data do not.') : t(context, 'Ninguna foto de este proyecto tiene ubicación.', 'No photo in this project has a location.'), style: Theme.of(context).textTheme.bodySmall),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            FloatingActionButton.small(
                              heroTag: null,
                              tooltip: t(context, 'Ver todas las fotos', 'Show all photos'),
                              onPressed: () => _fitAll(photos, fix),
                              child: const Icon(Icons.zoom_out_map),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: null,
                              tooltip: t(context, 'Mi posición', 'My position'),
                              onPressed: fix == null ? () => s.location.retry() : () => _map.move(LatLng(fix.latitude, fix.longitude), 17),
                              child: Icon(fix == null ? Icons.location_searching : Icons.my_location),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (tiles) const Align(alignment: Alignment.centerLeft, child: _OsmAttribution()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 6),
        onSelected: (_) => onTap(),
      ),
    );
  }

  static const List<Color> _palette = <Color>[Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00897B), Color(0xFF6D4C41), Color(0xFF3949AB)];

  Color _colorFor(AppState st, String projectId) {
    int i = 0;
    for (final Project p in st.projects) {
      if (p.id == projectId) {
        return _palette[i % _palette.length];
      }
      i++;
    }
    return _palette.first;
  }

  Future<void> _showPhoto(BuildContext context, AppState st, PhotoRecord p) {
    final Services s = AppScope.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: SizedBox(width: 64, height: 64, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: PhotoThumb(record: p, cacheWidth: kMapThumbWidth))),
              title: Text(p.notes.isNotEmpty ? p.notes : formatDate(p.wallTime, 'dd/MM/yyyy HH:mm')),
              subtitle: Text('${st.projectById(p.projectId).name}${p.approximateLocation ? ' · ${t(context, 'ubicación aproximada', 'approximate location')}' : ''}${p.address.isNotEmpty ? '\n${p.address}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoDetailScreen(photoId: p.id)));
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(onPressed: () => navigateTo(p.latitude!, p.longitude!), icon: const Icon(Icons.directions_outlined), label: Text(t(context, 'Cómo llegar', 'Directions'))),
                  OutlinedButton.icon(onPressed: () => openInMaps(p.latitude!, p.longitude!, label: p.notes), icon: const Icon(Icons.map_outlined), label: Text(t(context, 'Abrir en mapas', 'Open in maps'))),
                  if (s.location.fix != null)
                    Chip(avatar: const Icon(Icons.straighten, size: 16), label: Text(MapScreen.distanceText(Coords.distanceMeters(s.location.fix!.latitude, s.location.fix!.longitude, p.latitude!, p.longitude!), approximate: p.approximateLocation || s.location.fix!.approximate))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Atribución de OpenStreetMap siempre visible (la política de teselas no
/// admite esconderla tras un botón). Al tocarla abre la página de derechos.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    final String text = t(context, '© colaboradores de OpenStreetMap', '© OpenStreetMap contributors');
    void open() => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication);
    // El recuadro se ve pequeño, pero se puede tocar en 48 dp de alto.
    return Semantics(
      link: true,
      label: '$text, ${t(context, 'licencia ODbL', 'ODbL license')}',
      excludeSemantics: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.bottomLeft,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: const BorderRadius.only(topRight: Radius.circular(6))),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _AttributionText(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttributionText extends StatelessWidget {
  const _AttributionText();

  @override
  Widget build(BuildContext context) {
    return Text(t(context, '© colaboradores de OpenStreetMap', '© OpenStreetMap contributors'), style: const TextStyle(fontSize: 12, color: Colors.black87, decoration: TextDecoration.underline));
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, this.approximate = false});

  final Color color;

  /// Foto con ubicación aproximada: chincheta hueca.
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PinPainter(color, approximate: approximate));
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color, {this.approximate = false});

  final Color color;
  final bool approximate;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width * 0.3;
    final Offset c = Offset(size.width / 2, r + 2);
    final Path path = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * 0.7, c.dy + r * 0.7)
      ..lineTo(c.dx, size.height - 2)
      ..lineTo(c.dx + r * 0.7, c.dy + r * 0.7)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    if (approximate) {
      // Hueca: relleno blanco y borde del color del proyecto.
      canvas.drawPath(path, Paint()..color = Colors.white);
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.35,
      );
      return;
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(c, r * 0.45, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.color != color || old.approximate != approximate;
}
