import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Ancho desde el que la app usa el diseño de tableta con menú lateral
/// (clase de ventana "mediana" de Material 3).
const double kWideLayout = 600;

/// Ancho máximo del contenido para que las líneas sigan siendo legibles en
/// tabletas y en pantallas horizontales.
const double kReadableWidth = 760;

/// Solo para las capturas de la ficha: esconde los botones flotantes en las
/// escenas donde taparían contenido (en la app siempre se ven).
@visibleForTesting
final ValueNotifier<bool> hideFloatingButtons = ValueNotifier<bool>(false);

/// El botón flotante, salvo en las capturas que lo esconden.
Widget? floatingButton(Widget? button) => button == null
    ? null
    : ValueListenableBuilder<bool>(
        valueListenable: hideFloatingButtons,
        builder: (BuildContext context, bool hide, Widget? child) => hide ? const SizedBox.shrink() : child!,
        child: button,
      );

bool isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideLayout;

/// Centra el contenido y lo limita a un ancho cómodo de leer.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = kReadableWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Scaffold cuyo cuerpo no se estira más allá de [kReadableWidth]: en el
/// teléfono es idéntico a un Scaffold; en la tableta el contenido queda
/// centrado con la barra superior de lado a lado.
class ReadableScaffold extends StatelessWidget {
  const ReadableScaffold({super.key, this.appBar, this.body, this.floatingActionButton, this.maxWidth = kReadableWidth, this.safeBottom = true});

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final double maxWidth;

  /// Deja libre la franja de abajo del sistema (la barra de inicio del iPhone
  /// o la de gestos de Android) para que no tache el final de la lista. El
  /// editor de movimientos la maneja por su cuenta.
  final bool safeBottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: body == null ? null : SafeArea(top: false, bottom: safeBottom, child: ReadableWidth(maxWidth: maxWidth, child: body!)),
      floatingActionButton: floatingButton(floatingActionButton),
    );
  }
}
