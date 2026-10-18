import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'ui/camera/camera_screen.dart';
import 'ui/gallery/gallery_screen.dart';
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

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      CameraScreen(enabled: widget.cameraEnabled, active: _index == 0),
      const GalleryScreen(),
      const MapScreen(),
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
        onDestinationSelected: (int i) => setState(() => _index = i),
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
