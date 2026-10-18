import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../games/shell/widgets.dart';
import '../../model/age_band.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../legal/legal_document.dart';
import '../profile_edit_screen.dart';
import 'child_report_screen.dart';
import 'credits_screen.dart';
import 'family_guide_screen.dart';
import 'report_data.dart';
import 'settings_screen.dart';
import 'teacher_screen.dart';

/// Panel de adultos: avisos, niños, ajustes, guía, modo docente y créditos.
class ParentPanel extends StatelessWidget {
  const ParentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final List<Profile> profiles = s.state.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text(S.panelAdultos)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (s.state.notices.isNotEmpty) ...<Widget>[
            _Notices(notices: s.state.notices, onDismiss: s.state.dismissNotices),
            const SizedBox(height: 16),
          ],
          Text(S.ninos, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Todavía no hay perfiles. Crea el primero con el botón de abajo.', style: TextStyle(color: pal.tintaSuave)),
            ),
          for (final Profile p in profiles) _ChildTile(profile: p),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey<String>('panel-nuevo-perfil'),
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
                  key: const ValueKey<String>('panel-guia'),
                  leading: const Icon(Icons.menu_book_rounded),
                  title: const Text(S.guiaFamilias),
                  subtitle: const Text('Cómo se usa Pilas, qué mide el informe y cómo acompañar'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyGuideScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school_rounded),
                  title: const Text(S.modoDocente),
                  subtitle: const Text('Grupos, tabla del curso, exportación e importación'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeacherScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text(S.politicaPrivacidad),
                  subtitle: const Text('Qué datos maneja Pilas y dónde quedan'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen(spanish: true))),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text(S.creditos),
                  subtitle: const Text('Ayuda, pictogramas, tipografías y licencias'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreditsScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('${S.sinConexion} ${S.privacidad}', style: TextStyle(color: pal.tintaSuave)),
        ],
      ),
    );
  }
}

/// Avisos de almacenamiento (un archivo dañado que se recuperó o se apartó).
class _Notices extends StatelessWidget {
  const _Notices({required this.notices, required this.onDismiss});

  final List<StorageNotice> notices;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      key: const ValueKey<String>('panel-avisos'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: pal.pistaClaro, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.pista, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: pal.pista),
              const SizedBox(width: 8),
              Text(S.avisos, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta)),
            ],
          ),
          const SizedBox(height: 6),
          for (final StorageNotice n in notices)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${fechaHora(n.fecha)}: ${n.texto}', style: TextStyle(color: pal.tinta)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onDismiss, child: const Text(S.entendido)),
          ),
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
    final ChildReport r = ChildReport(profile: profile, progress: prog, now: clock.now());
    final String descanso = s.state.isResting(profile.id) ? ' · en su descanso' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: EmojiImage(profile.avatar, size: 44),
        title: Text(profile.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${profile.age} años · juegos de ${profile.band.label}$descanso\n'
          '${S.hoy}: ${S.minutos(r.minutosHoy)} · ${S.ultimos7}: ${S.minutos(r.minutos7Dias)}\n'
          '${S.habilidadesLogradas}: ${r.skillsLogradasTramo} de ${r.skillsDelTramo.length}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: '${S.editar} ${profile.nombre}',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileEditScreen(profile: profile))),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChildReportScreen(profile: profile))),
      ),
    );
  }
}
