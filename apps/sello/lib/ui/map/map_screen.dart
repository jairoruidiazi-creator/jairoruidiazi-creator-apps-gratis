import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/maps_links.dart';
import '../../geo/coords.dart';
import '../../geo/location_service.dart';
import '../../model/models.dart';
import '../gallery/gallery_screen.dart';
import '../gallery/photo_detail_screen.dart';

/// Mapa con las fotos (OpenStreetMap) y la posición actual.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  /// Falso en pruebas: no se descargan teselas.
  static bool tilesEnabled = true;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();
  String? _projectId;
  bool _fitted = false;
  bool _ready = false;

  @override
  void dispose() {
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
      listenable: Listenable.merge(<Listenable>[s.state, s.location]),
      builder: (BuildContext context, Widget? _) {
        final AppState st = s.state;
        final List<PhotoRecord> photos = _visible(st);
        final Fix? fix = s.location.fix;
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
                if (MapScreen.tilesEnabled)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'co.apps.sello',
                    maxNativeZoom: 19,
                  ),
                if (fix != null)
                  CircleLayer(
                    circles: <CircleMarker>[
                      CircleMarker(point: LatLng(fix.latitude, fix.longitude), radius: fix.accuracy.clamp(1.0, 500.0), useRadiusInMeter: true, color: Colors.blue.withValues(alpha: 0.12), borderColor: Colors.blue.withValues(alpha: 0.4), borderStrokeWidth: 1),
                    ],
                  ),
                MarkerLayer(
                  markers: <Marker>[
                    for (final PhotoRecord p in photos)
                      Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () => _showPhoto(context, st, p),
                          child: _Pin(color: _colorFor(st, p.projectId)),
                        ),
                      ),
                    if (fix != null)
                      Marker(
                        point: LatLng(fix.latitude, fix.longitude),
                        width: 22,
                        height: 22,
                        child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue, border: Border.all(color: Colors.white, width: 3), boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 4, color: Colors.black38)])),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _chip(context, t(context, 'Todos', 'All'), _projectId == null, () => setState(() { _projectId = null; _fitted = false; })),
                    for (final Project p in st.projects) _chip(context, p.name, _projectId == p.id, () => setState(() { _projectId = p.id; _fitted = false; }), color: _colorFor(st, p.id)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 24,
              child: Column(
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
                    onPressed: fix == null ? () => s.location.start() : () => _map.move(LatLng(fix.latitude, fix.longitude), 17),
                    child: Icon(fix == null ? Icons.location_searching : Icons.my_location),
                  ),
                ],
              ),
            ),
            if (photos.isEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(st.photos.isEmpty ? t(context, 'Las fotos con GPS aparecerán aquí. El mapa necesita internet para cargar; las fotos y sus datos no.', 'Photos with GPS will appear here. The map needs internet to load; photos and their data do not.') : t(context, 'Ninguna foto de este proyecto tiene ubicación.', 'No photo in this project has a location.'), style: Theme.of(context).textTheme.bodySmall),
                  ),
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

  static String _distanceText(double m) => m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 2 : 1)} km';

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
              leading: SizedBox(width: 64, height: 64, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: PhotoThumb(record: p, cacheWidth: 160))),
              title: Text(p.notes.isNotEmpty ? p.notes : formatDate(p.takenAt, 'dd/MM/yyyy HH:mm')),
              subtitle: Text('${st.projectById(p.projectId).name}${p.address.isNotEmpty ? '\n${p.address}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
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
                    Chip(avatar: const Icon(Icons.straighten, size: 16), label: Text(_distanceText(Coords.distanceMeters(s.location.fix!.latitude, s.location.fix!.longitude, p.latitude!, p.longitude!)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PinPainter(color));
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width * 0.32;
    final Offset c = Offset(size.width / 2, r + 2);
    final Path path = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * 0.7, c.dy + r * 0.7)
      ..lineTo(c.dx, size.height - 2)
      ..lineTo(c.dx + r * 0.7, c.dy + r * 0.7)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(c, r * 0.45, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.color != color;
}
