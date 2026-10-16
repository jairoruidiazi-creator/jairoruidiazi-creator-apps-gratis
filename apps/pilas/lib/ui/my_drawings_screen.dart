import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_scope.dart';
import '../core/parental_gate.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../games/shell/widgets.dart';
import '../model/profile.dart';

/// Galería de los dibujos guardados por el niño.
class MyDrawingsScreen extends StatefulWidget {
  const MyDrawingsScreen({super.key});

  @override
  State<MyDrawingsScreen> createState() => _MyDrawingsScreenState();
}

class _MyDrawingsScreenState extends State<MyDrawingsScreen> {
  List<String>? _files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Services s = AppScope.read(context);
    final Profile? p = s.state.current;
    if (p == null) {
      setState(() => _files = <String>[]);
      return;
    }
    final List<String> files = await s.store.list('drawings/${p.id}', extension: '.png');
    final List<String> abs = <String>[];
    for (final String f in files.reversed) {
      abs.add(await s.store.absolutePath(f));
    }
    if (mounted) {
      setState(() => _files = abs);
    }
  }

  Future<void> _compartir(String path) async {
    // Compartir sale de la app: va detrás de la puerta parental.
    final bool ok = await showParentalGate(context, reason: 'Compartir el dibujo');
    if (!ok) {
      return;
    }
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(path)], text: 'Dibujo hecho en Pilas'));
  }

  Future<void> _borrar(String path) async {
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
    if (ok != true) {
      return;
    }
    final File f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<String>? files = _files;
    return Scaffold(
      appBar: AppBar(title: const Text(S.misDibujos)),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Mascot(size: 120),
                        SizedBox(height: 16),
                        Text('Tus dibujos guardados aparecerán aquí.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final int cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85),
                      itemCount: files.length,
                      itemBuilder: (BuildContext context, int i) {
                        final String path = files[i];
                        return Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: PilasColors.borde, width: 2)),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: <Widget>[
                              Expanded(child: Image.file(File(path), fit: BoxFit.contain)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: <Widget>[
                                  IconButton(onPressed: () => _compartir(path), icon: const Icon(Icons.share_rounded), tooltip: 'Compartir'),
                                  IconButton(onPressed: () => _borrar(path), icon: const Icon(Icons.delete_outline_rounded), tooltip: S.borrar),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
