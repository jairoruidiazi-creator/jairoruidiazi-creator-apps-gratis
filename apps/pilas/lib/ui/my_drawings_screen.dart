import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_scope.dart';
import '../core/parental_gate.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../games/shell/widgets.dart';
import '../model/profile.dart';

/// Un dibujo guardado: su ruta dentro de la app y la ruta en el disco.
class _Drawing {
  const _Drawing(this.rel, this.abs);

  final String rel;
  final String abs;
}

/// Galería de los dibujos guardados por el niño. Compartir y borrar pasan
/// por la puerta parental o por una confirmación.
class MyDrawingsScreen extends StatefulWidget {
  const MyDrawingsScreen({super.key});

  @override
  State<MyDrawingsScreen> createState() => _MyDrawingsScreenState();
}

class _MyDrawingsScreenState extends State<MyDrawingsScreen> {
  List<_Drawing>? _files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Services s = AppScope.read(context);
    final Profile? p = s.state.current;
    if (p == null) {
      setState(() => _files = <_Drawing>[]);
      return;
    }
    final List<String> files = await s.store.list('drawings/${p.id}', extension: '.png');
    final List<_Drawing> out = <_Drawing>[];
    for (final String f in files.reversed) {
      out.add(_Drawing(f, await s.store.absolutePath(f)));
    }
    if (mounted) {
      setState(() => _files = out);
    }
  }

  Future<void> _compartir(BuildContext buttonContext, _Drawing d) async {
    // Compartir sale de la app: va detrás de la puerta parental.
    final Services s = AppScope.read(context);
    final bool ok = await showParentalGate(context, reason: 'Compartir el dibujo');
    if (!ok || !buttonContext.mounted) {
      return;
    }
    await s.sharer.shareFiles(buttonContext, <XFile>[XFile(d.abs, mimeType: 'image/png')], text: 'Dibujo hecho en Pilas');
  }

  Future<void> _borrar(_Drawing d) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('¿Borrar este dibujo?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(S.borrar)),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await AppScope.read(context).store.delete(d.rel);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final List<_Drawing>? files = _files;
    return Scaffold(
      appBar: AppBar(title: const Text(S.misDibujos)),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Mascot(size: 120),
                        const SizedBox(height: 16),
                        Text('Tus dibujos guardados aparecerán aquí.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.tinta)),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85),
                  itemCount: files.length,
                  itemBuilder: (BuildContext context, int i) {
                    final _Drawing d = files[i];
                    return Container(
                      decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: <Widget>[
                          Expanded(child: Semantics(label: 'Dibujo ${i + 1}', image: true, child: Image.file(File(d.abs), fit: BoxFit.contain))),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              Builder(
                                builder: (BuildContext buttonContext) => IconButton(
                                  key: ValueKey<String>('compartir-$i'),
                                  onPressed: () => _compartir(buttonContext, d),
                                  icon: const Icon(Icons.share_rounded),
                                  tooltip: 'Compartir (adulto)',
                                ),
                              ),
                              IconButton(key: ValueKey<String>('borrar-$i'), onPressed: () => _borrar(d), icon: const Icon(Icons.delete_outline_rounded), tooltip: S.borrar),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
