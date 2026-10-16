import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../games/shell/widgets.dart';
import '../../model/age_band.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../profile_edit_screen.dart';
import 'child_report_screen.dart';
import 'credits_screen.dart';
import 'settings_screen.dart';
import 'teacher_screen.dart';

/// Panel de adultos: niños, ajustes, informes, modo docente y créditos.
class ParentPanel extends StatelessWidget {
  const ParentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final List<Profile> profiles = s.state.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text(S.panelAdultos)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(S.ninos, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Todavía no hay perfiles. Crea uno desde la pantalla de inicio.', style: TextStyle(color: PilasColors.tintaSuave)),
            ),
          for (final Profile p in profiles) _ChildTile(profile: p),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen())),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text(S.nuevoPerfil),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text(S.ajustes),
                  subtitle: const Text('Voz, sonidos, tiempo por sesión y accesibilidad'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school_rounded),
                  title: const Text(S.modoDocente),
                  subtitle: const Text('Grupos, tabla del curso y exportación'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeacherScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text(S.creditos),
                  subtitle: const Text('Pictogramas, tipografías y licencias'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreditsScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('${S.sinConexion} ${S.privacidad}', style: TextStyle(color: PilasColors.tintaSuave)),
        ],
      ),
    );
  }
}

class _ChildTile extends StatelessWidget {
  const _ChildTile({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final ProfileProgress prog = s.state.progressOf(profile.id);
    final int hoy = prog.secondsOn(DateTime.now()) ~/ 60;
    final int semana = prog.secondsSince(DateTime.now().subtract(const Duration(days: 7))) ~/ 60;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: EmojiImage(profile.avatar, size: 44),
        title: Text(profile.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${profile.age} años · ${profile.band.label} · ${S.hoy}: ${S.minutos(hoy)} · ${S.estaSemana}: ${S.minutos(semana)} · ${prog.skillsAchieved.length} habilidades'),
        trailing: IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: S.editar,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileEditScreen(profile: profile))),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChildReportScreen(profile: profile))),
      ),
    );
  }
}
