import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'ui/profiles_screen.dart';

/// Raíz de la app: servicios, tema y pantalla inicial.
class PilasApp extends StatelessWidget {
  const PilasApp({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      state: services.state,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (BuildContext context, Widget? _) {
          final ThemeData theme = PilasTheme.light(highContrast: services.settings.highContrast, dyslexiaFont: services.settings.dyslexiaFont);
          return MaterialApp(
            title: S.appName,
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('es', 'CO'),
            supportedLocales: const <Locale>[Locale('es', 'CO'), Locale('es')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData mq = MediaQuery.of(context);
              final double factor = services.settings.largeText ? 1.2 : 1.0;
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(factor)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const ProfilesScreen(),
          );
        },
      ),
    );
  }
}
