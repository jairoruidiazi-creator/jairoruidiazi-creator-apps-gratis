import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Agrega a la página de licencias del sistema las de los recursos que la app
/// trae incluidos (tipografías y pictogramas); las de los paquetes de Dart y
/// Flutter ya las agrega el propio Flutter.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(_bundled);
}

Stream<LicenseEntry> _bundled() async* {
  yield LicenseEntryWithLineBreaks(<String>['Lexend'], await rootBundle.loadString('assets/legal/OFL-lexend.txt'));
  yield LicenseEntryWithLineBreaks(<String>['Andika'], await rootBundle.loadString('assets/legal/OFL-andika.txt'));
  yield LicenseEntryWithLineBreaks(<String>['DejaVu Sans (Simbolos)'], await rootBundle.loadString('assets/legal/LICENSE-DejaVu.txt'));
  yield const LicenseEntryWithLineBreaks(
    <String>['Twemoji'],
    'Copyright 2020 Twitter, Inc and other contributors (github.com/jdecked/twemoji).\n\n'
    'Graphics licensed under CC-BY 4.0: https://creativecommons.org/licenses/by/4.0/\n\n'
    'Pilas incluye los pictogramas en SVG sin modificar.',
  );
}
