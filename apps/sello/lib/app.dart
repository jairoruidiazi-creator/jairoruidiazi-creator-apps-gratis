import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'model/models.dart';
import 'stamp/stamp_queue.dart';
import 'ui/camera/camera_screen.dart';
import 'ui/gallery/gallery_screen.dart';
import 'ui/gallery/photo_detail_screen.dart';
import 'ui/map/map_screen.dart';
import 'ui/projects/projects_screen.dart';
import 'ui/settings/settings_screen.dart';

class SelloColors {
  SelloColors._();

  static const Color selva = Color(0xFF1B4332);
  static const Color musgo = Color(0xFF40916C);
  static const Color arena = Color(0xFFF4E7C3);
  static const Color naranja = Color(0xFFFF7043);
}

class SelloApp extends StatelessWidget {
  const SelloApp({super.key, required this.services, this.cameraEnabled = true});

  final Services services;

  /// Falso en pruebas: no se abre la cámara ni se piden permisos.
  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final String mode = services.settings.themeMode;
          ThemeData theme(Brightness b) => ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: SelloColors.selva, brightness: b, secondary: SelloColors.naranja),
                // Flechas y marcas que Roboto no trae (subconjunto de DejaVu Sans).
                fontFamilyFallback: const <String>['Simbolos'],
                cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(56, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
              );
          return MaterialApp(
            title: 'Sello',
            debugShowCheckedModeBanner: false,
            // Para saber cuándo una pantalla completa tapa la pestaña activa.
            navigatorObservers: <NavigatorObserver>[services.routes],
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: mode == 'light' ? ThemeMode.light : (mode == 'dark' ? ThemeMode.dark : ThemeMode.system),
            locale: Locale(services.settings.language),
            supportedLocales: const <Locale>[Locale('es'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HomeShell(cameraEnabled: cameraEnabled),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0, this.cameraEnabled = true});

  final int initialIndex;

  /// Falso en pruebas: la pestaña de cámara muestra un marcador en vez de abrir la cámara.
  final bool cameraEnabled;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver, RouteAware {
  late int _index = widget.initialIndex;

  /// El mapa se crea la primera vez que se abre su pestaña: antes no hay
  /// por qué pedir teselas a OpenStreetMap.
  late bool _mapBuilt = widget.initialIndex == 2;
  StreamSubscription<StampEvent>? _events;
  bool _galleryNoticeShown = false;
  bool _noticesShown = false;
  Services? _services;
  PageRoute<dynamic>? _route;

  /// Otra pantalla completa (Ajustes, el detalle de una foto, un editor…)
  /// tapa las pestañas: la cámara y el mapa se tratan como fuera de vista.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Services s = AppScope.of(context);
    if (_events == null) {
      _services = s;
      _events = s.queue.events.listen(_onStampEvent);
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLoadNotices());
    }
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _route)) {
      s.routes.unsubscribe(this);
      s.routes.subscribe(this, route);
      _route = route;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services?.routes.unsubscribe(this);
    unawaited(_events?.cancel());
    super.dispose();
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() => setState(() => _covered = false);

  /// En segundo plano se detiene la ubicación (Sello no la usa en segundo
  /// plano) y al volver se retoma si la cámara o el mapa están a la vista.
  /// El usuario cambió el idioma del teléfono con la app abierta (en
  /// Android la actividad no se reinicia): si la app sigue al teléfono,
  /// cambia ya, y la dirección aproximada también.
  @override
  void didChangeLocales(List<Locale>? locales) {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    s.settings.deviceLocaleChanged(WidgetsBinding.instance.platformDispatcher.locale);
    s.location.localeIdentifier = s.settings.geocoderLocale;
  }

  /// "inactive" no cuenta: lo provocan los diálogos de permiso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      s.location.foreground = true;
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      s.location.foreground = false;
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action: action,
      duration: Duration(seconds: action == null ? 6 : 8),
      // Desde Flutter 3.38 un SnackBar con acción no se cierra solo; aquí sí se
      // cierra, salvo con lector de pantalla, donde se queda hasta que se atienda.
      persist: MediaQuery.accessibleNavigationOf(context),
    ));
  }

  /// Avisos visibles de la cola de sellado: si una foto no se pudo sellar
  /// (queda el original y se puede reintentar) o si no se copió a la fototeca
  /// (este último, una vez por sesión).
  void _onStampEvent(StampEvent e) {
    if (!mounted) {
      return;
    }
    final Services s = AppScope.of(context);
    switch (e.kind) {
      case StampEventKind.stamped:
        break;
      case StampEventKind.failed:
        if (e.record.status == PhotoStatus.ok) {
          // Falló volver a sellar una foto que ya tenía su copia: lo avisa el detalle.
          break;
        }
        _snack(
          t(context, 'Una foto no se pudo sellar. Quedó guardada con sus datos; ábrela en la galería para reintentar.', 'A photo could not be stamped. It was saved with its data; open it in the gallery to retry.'),
          action: SnackBarAction(label: t(context, 'Ver', 'View'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoDetailScreen(photoId: e.record.id)))),
        );
        break;
      case StampEventKind.galleryDenied:
        if (!_galleryNoticeShown) {
          _galleryNoticeShown = true;
          _snack(
            t(context, 'Guardada en la app. Para copiarla también a la fototeca, da el permiso en los ajustes del teléfono o apaga la copia en Ajustes.', 'Saved in the app. To also copy it to the photo library, allow it in the phone settings or turn the copy off in Settings.'),
            action: SnackBarAction(label: t(context, 'Ajustes', 'Settings'), onPressed: () => s.location.backend.openAppSettings()),
          );
        }
        break;
      case StampEventKind.galleryError:
        if (!_galleryNoticeShown) {
          _galleryNoticeShown = true;
          _snack(t(context, 'Guardada en la app; no se pudo copiar a la fototeca.', 'Saved in the app; could not copy to the photo library.'));
        }
        break;
    }
  }

  /// Si al abrir hubo que recuperar datos, se dice qué pasó.
  void _showLoadNotices() {
    if (_noticesShown || !mounted) {
      return;
    }
    _noticesShown = true;
    final AppState st = AppScope.of(context).state;
    for (final LoadNotice n in st.notices) {
      switch (n.kind) {
        case LoadNoticeKind.photosFromBackup:
          _snack(t(context, 'El índice de fotos estaba dañado y se recuperó de la copia anterior.', 'The photo index was damaged and was restored from the previous copy.'));
          break;
        case LoadNoticeKind.photosLost:
          _snack(t(context, 'El índice de fotos estaba dañado. Las fotos se recuperaron de la carpeta de la app con los datos de su EXIF.', 'The photo index was damaged. Photos were recovered from the app folder with their EXIF data.'));
          break;
        case LoadNoticeKind.projectsFromBackup:
          _snack(t(context, 'Los proyectos estaban dañados y se recuperaron de la copia anterior.', 'Projects were damaged and were restored from the previous copy.'));
          break;
        case LoadNoticeKind.projectsLost:
          _snack(t(context, 'No se pudieron leer los proyectos y plantillas; se empezó con los de fábrica.', 'Projects and templates could not be read; the defaults were used.'));
          break;
        case LoadNoticeKind.photosRecovered:
          _snack('${t(context, 'Se recuperaron fotos que no estaban en el índice', 'Recovered photos that were missing from the index')}: ${n.count}');
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      CameraScreen(enabled: widget.cameraEnabled, active: _index == 0 && !_covered),
      const GalleryScreen(),
      if (_mapBuilt) MapScreen(active: _index == 2 && !_covered) else const SizedBox.shrink(),
      const ProjectsScreen(),
    ];
    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              title: Text(<String>['', t(context, 'Galería', 'Gallery'), t(context, 'Mapa', 'Map'), t(context, 'Proyectos y sellos', 'Projects & stamps')][_index]),
              actions: <Widget>[
                IconButton(
                  tooltip: t(context, 'Ajustes', 'Settings'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() {
          _index = i;
          if (i == 2) {
            _mapBuilt = true;
          }
        }),
        destinations: <NavigationDestination>[
          NavigationDestination(icon: const Icon(Icons.photo_camera_outlined), selectedIcon: const Icon(Icons.photo_camera), label: t(context, 'Cámara', 'Camera')),
          NavigationDestination(icon: const Icon(Icons.photo_library_outlined), selectedIcon: const Icon(Icons.photo_library), label: t(context, 'Galería', 'Gallery')),
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map), label: t(context, 'Mapa', 'Map')),
          NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: t(context, 'Proyectos', 'Projects')),
        ],
      ),
    );
  }
}
