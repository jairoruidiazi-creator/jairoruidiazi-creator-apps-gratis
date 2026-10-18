import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/settings.dart';

enum StartupProblem {
  /// El Keystore o el Llavero no respondió y hay datos que dependen de la llave.
  secureStore,

  /// Cualquier otro error al abrir los datos.
  unexpected,
}

/// Pantalla que se muestra si la app no puede arrancar. No borra nada por su
/// cuenta: ofrece reintentar y, si el almacén seguro no responde, empezar de
/// nuevo apartando los datos que no se pueden abrir.
class StartupErrorApp extends StatefulWidget {
  const StartupErrorApp({super.key, required this.problem, required this.onRetry, this.onStartOver});

  final StartupProblem problem;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onStartOver;

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _busy = false;
  final bool _es = AppSettings.languageFor(ui.PlatformDispatcher.instance.locales) == 'es';

  String _t(String es, String en) => _es ? es : en;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool secure = widget.problem == StartupProblem.secureStore;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: PlataColors.verde)),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: PlataColors.verde, brightness: Brightness.dark)),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(secure ? Icons.key_off_outlined : Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 12),
                      Text(secure ? _t('No se pudo abrir la llave de tus datos', 'Your data key could not be opened') : _t('Plata no pudo abrir tus datos', 'Plata could not open your data'), style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(secure
                          ? _t('El almacén seguro del teléfono (donde vive la llave que cifra tus datos) no respondió. Tus datos siguen guardados y no se tocaron. Suele ser pasajero: reintenta en un momento o reinicia el teléfono.', 'The phone\'s secure storage (where the key that encrypts your data lives) did not respond. Your data is still saved and was not touched. It is usually temporary: try again in a moment or restart the phone.')
                          : _t('Algo salió mal al abrir la app. Tus datos no se borraron. Reintenta; si sigue pasando, repórtalo desde la página de soporte.', 'Something went wrong while opening the app. Your data was not deleted. Try again; if it keeps happening, report it from the support page.')),
                      const SizedBox(height: 20),
                      FilledButton.icon(onPressed: _busy ? null : () => _run(widget.onRetry), icon: const Icon(Icons.refresh), label: Text(_t('Reintentar', 'Try again'))),
                      if (secure && widget.onStartOver != null) ...<Widget>[
                        const SizedBox(height: 24),
                        Text(_t('Si el problema no se resuelve, puedes empezar de nuevo con una llave nueva: los datos actuales quedan apartados (sin borrarse) y podrás restaurar una copia cifrada (.plata) en Más › Copias de seguridad.', 'If the problem does not go away, you can start over with a new key: the current data is set aside (not deleted) and you can restore an encrypted backup (.plata) under More › Backups.'), style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final bool? ok = await showDialog<bool>(
                                    context: context,
                                    builder: (BuildContext c) => AlertDialog(
                                      title: Text(_t('¿Empezar de nuevo?', 'Start over?')),
                                      content: Text(_t('La app abrirá vacía. Los datos que no se pueden abrir quedan apartados en la carpeta de la app.', 'The app will open empty. The data that cannot be opened is set aside in the app folder.')),
                                      actions: <Widget>[
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_t('Cancelar', 'Cancel'))),
                                        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(_t('Empezar de nuevo', 'Start over'))),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await _run(widget.onStartOver!);
                                  }
                                },
                          child: Text(_t('Empezar de nuevo con una llave nueva', 'Start over with a new key')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
