import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/parental_gate.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../games/shell/widgets.dart';
import '../model/age_band.dart';
import '../model/profile.dart';

/// Crear o editar un perfil. Lo usa el adulto.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.profile});

  final Profile? profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nombre;
  late String _avatar;
  late int _edad;
  late int _mes;
  AgeBand? _override;
  late bool _zurdo;

  static const List<String> meses = <String>['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

  @override
  void initState() {
    super.initState();
    final Profile? p = widget.profile;
    _nombre = TextEditingController(text: p?.nombre ?? '');
    _avatar = p?.avatar ?? Profile.avatares.first;
    _edad = p?.age ?? 5;
    _mes = p?.birthMonth ?? clock.now().month;
    _override = p?.bandOverride;
    _zurdo = p?.leftHanded ?? false;
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final String nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe un nombre o apodo.')));
      return;
    }
    final Services s = AppScope.read(context);
    final DateTime now = clock.now();
    int birthYear = now.year - _edad;
    if (_mes > now.month) {
      birthYear -= 1;
    }
    final Profile? p = widget.profile;
    if (p == null) {
      await s.state.addProfile(nombre: nombre, avatar: _avatar, birthYear: birthYear, birthMonth: _mes, bandOverride: _override, leftHanded: _zurdo);
    } else {
      p.nombre = nombre;
      p.avatar = _avatar;
      p.birthYear = birthYear;
      p.birthMonth = _mes;
      p.bandOverride = _override;
      p.leftHanded = _zurdo;
      await s.state.updateProfile(p);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _borrar() async {
    final Profile? p = widget.profile;
    if (p == null) {
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(S.borrarPerfil),
        content: Text(S.confirmarBorrar(p.nombre)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(S.cancelar)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(S.borrar)),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    final bool gate = await showParentalGate(context, reason: S.borrarPerfil);
    if (!gate || !mounted) {
      return;
    }
    await AppScope.read(context).state.deleteProfile(p.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool editing = widget.profile != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? S.editar : S.nuevoPerfil),
        actions: <Widget>[
          if (editing) IconButton(onPressed: _borrar, icon: const Icon(Icons.delete_outline_rounded), tooltip: S.borrar),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('perfil-nombre'),
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            maxLength: 20,
            style: const TextStyle(fontSize: 22),
            // Sin menú de copiar, pegar, buscar o traducir: ningún campo de
            // texto lleva fuera de la app.
            contextMenuBuilder: null,
            enableInteractiveSelection: false,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: S.nombre),
          ),
          const SizedBox(height: 16),
          Text(S.elegirAvatar, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final String a in Profile.avatares)
                Semantics(
                  button: true,
                  selected: _avatar == a,
                  label: Profile.nombresAvatar[a],
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: ValueKey<String>('avatar-$a'),
                    onTap: () => setState(() => _avatar = a),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _avatar == a ? pal.acentoClaro : pal.tarjeta,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _avatar == a ? pal.acento : pal.bordeFuerte, width: _avatar == a ? 3 : 1.5),
                      ),
                      child: EmojiImage(a, size: 48),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(S.edad, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int e = 3; e <= 11; e++)
                ChoiceChip(
                  label: Text('$e ${S.anios}'),
                  selected: _edad == e,
                  onSelected: (_) => setState(() => _edad = e),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _mes,
            decoration: const InputDecoration(labelText: S.mesNacimiento),
            items: <DropdownMenuItem<int>>[
              for (int m = 1; m <= 12; m++) DropdownMenuItem<int>(value: m, child: Text(meses[m - 1])),
            ],
            onChanged: (int? v) => setState(() => _mes = v ?? _mes),
          ),
          const SizedBox(height: 20),
          Text('Edad de los juegos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Según su edad, verá los juegos de ${AgeBandX.forAge(_edad).label} (${AgeBandX.forAge(_edad).schoolLabel.toLowerCase()}). Cámbialo solo si el niño va más adelante o necesita algo más sencillo.',
            style: TextStyle(color: pal.tintaSuave),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(label: const Text(S.tramoAuto), selected: _override == null, onSelected: (_) => setState(() => _override = null)),
              for (final AgeBand b in AgeBand.values)
                ChoiceChip(label: Text(b.label), selected: _override == b, onSelected: (_) => setState(() => _override = b)),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const ValueKey<String>('perfil-zurdo'),
            value: _zurdo,
            onChanged: (bool v) => setState(() => _zurdo = v),
            title: const Text(S.zurdo),
            subtitle: const Text(S.zurdoDetalle),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 24),
          FilledButton(key: const ValueKey<String>('perfil-guardar'), onPressed: _guardar, child: const Text(S.guardar)),
        ],
      ),
    );
  }
}
