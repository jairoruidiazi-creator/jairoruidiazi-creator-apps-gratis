import 'package:flutter/widgets.dart';

/// Dice a una pestaña si se está mostrando. Las pantallas que no están dentro
/// de una pestaña (las que se abren encima) cuentan como visibles.
class TabVisibility extends InheritedWidget {
  const TabVisibility({super.key, required this.visible, required super.child});

  final bool visible;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabVisibility>()?.visible ?? true;

  @override
  bool updateShouldNotify(TabVisibility oldWidget) => oldWidget.visible != visible;
}

/// Como ListenableBuilder, pero una pestaña oculta no se reconstruye con cada
/// cambio: se pone al día cuando vuelve a verse (TabVisibility avisa y build
/// corre de nuevo).
class LiveBuilder extends StatefulWidget {
  const LiveBuilder({super.key, required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends State<LiveBuilder> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(LiveBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Al volver a ser visible, build() corre después de esto con los datos al día.
    _visible = TabVisibility.of(context);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    if (_visible) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
