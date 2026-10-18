import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/backup.dart';
import '../../core/dates.dart';
import '../../core/notifications.dart';
import '../../core/settings.dart';
import '../../model/workout.dart';
import '../catalog.dart';
import '../legal/legal_document.dart';
import '../timer/timer_texts.dart';
import '../widgets/common.dart';

/// Ajustes: idioma, tema, sonidos y voz, permisos, copia de seguridad y
/// "acerca de".
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  void _save(AppSettings st) {
    unawaited(st.save());
  }

  Future<void> _export(Services s) async {
    setState(() => _busy = true);
    try {
      s.flushAll();
      final DateTime now = clock.now();
      final Map<String, dynamic> data = Backups.build(habits: s.habits, reminders: s.reminders, timers: s.timers, settings: s.settings, now: now);
      final String rel = 'exports/${Backups.fileName(now)}';
      await s.store.writeBytes(rel, utf8.encode(Backups.encode(data)));
      final String path = await s.store.absolutePath(rel);
      await s.io.shareFile(path, subject: s.settings.spanish ? 'Copia de Rutinas' : 'Rutinas backup', text: s.settings.spanish ? 'Copia de seguridad de Rutinas (${formatLongDate(now, spanish: true)}).' : 'Rutinas backup (${formatLongDate(now, spanish: false)}).');
      s.settings.lastExportAt = now;
      await s.settings.save();
    } catch (e) {
      if (mounted) {
        showSnack(context, t(context, 'No se pudo exportar la copia: $e', 'The backup could not be exported: $e'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import(Services s) async {
    String? text;
    try {
      text = await s.io.pickText();
    } catch (e) {
      if (mounted) {
        showSnack(context, t(context, 'No se pudo abrir el archivo: $e', 'The file could not be opened: $e'));
      }
      return;
    }
    if (text == null || !mounted) {
      return;
    }
    BackupContents contents;
    try {
      contents = Backups.decode(text);
    } on FormatException catch (e) {
      String why;
      switch (e.message) {
        case 'not-rutinas':
          why = t(context, 'Ese archivo no es una copia de Rutinas.', 'That file is not a Rutinas backup.');
          break;
        case 'newer-version':
          why = t(context, 'La copia es de una versión más nueva de Rutinas: actualiza la app primero.', 'The backup comes from a newer version of Rutinas: update the app first.');
          break;
        case 'damaged':
          why = t(context, 'La copia está dañada y no se puede leer.', 'The backup is damaged and cannot be read.');
          break;
        default:
          why = t(context, 'El archivo no se puede leer.', 'The file cannot be read.');
      }
      showSnack(context, why);
      return;
    }
    final bool es = s.settings.spanish;
    final String when = contents.exportedAt == null ? '' : (es ? ' del ${formatLongDate(contents.exportedAt!, spanish: true)}' : ' from ${formatLongDate(contents.exportedAt!, spanish: false)}');
    final bool ok = await confirm(
      context,
      title: t(context, '¿Reemplazar todos los datos?', 'Replace all data?'),
      message: es
          ? 'La copia$when trae ${contents.habits} hábitos (${contents.days} días con registros), ${contents.reminders} recordatorios y ${contents.workouts} entrenamientos. Lo que hay ahora en la app se reemplaza.'
          : 'The backup$when has ${contents.habits} habits (${contents.days} days with records), ${contents.reminders} reminders and ${contents.workouts} workouts. What is in the app now will be replaced.',
      yes: t(context, 'Restaurar', 'Restore'),
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      await Backups.restore(contents, habits: s.habits, reminders: s.reminders, timers: s.timers, settings: s.settings);
    } catch (e) {
      // La copia ya se leyó entera antes de confirmar: esto solo pasa si falla
      // el disco. Lo que había sigue en memoria y se vuelve a guardar.
      if (mounted) {
        showSnack(context, t(context, 'No se pudo restaurar la copia: $e', 'The backup could not be restored: $e'));
      }
      return;
    }
    // Las alarmas de antes no sirven: todo se vuelve a programar desde cero.
    await s.notices.afterRestore();
    if (mounted) {
      showSnack(context, t(context, 'Copia restaurada.', 'Backup restored.'));
    }
  }

  /// Abre el ajuste de alarmas exactas del sistema; al volver, si se
  /// concedió, todo se reprograma como alarmas exactas.
  void _exact(Services s) => unawaited(s.notices.askExactAlarms());

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Ajustes', 'Settings'))),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[s.settings, s.notices]),
        builder: (BuildContext context, Widget? _) => _content(context, s),
      ),
    );
  }

  Widget _content(BuildContext context, Services s) {
    final AppSettings st = s.settings;
    final bool es = st.spanish;
    final ThemeData theme = Theme.of(context);
    final NoticePermissions p = s.notices.permissions;
    final String? damaged = s.habits.damagedCopy ?? s.reminders.damagedCopy ?? s.timers.damagedCopy;
    Widget chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onPick) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final T v in values) ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => onPick(v)),
            ],
          ),
        );
    Widget label(String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(text, style: theme.textTheme.bodyLarge));
    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: <Widget>[
          if (damaged != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      es ? 'Un archivo de datos estaba dañado y no se pudo leer. Se guardó aparte en la carpeta de la app; si tienes una copia de seguridad, restáurala abajo.' : 'A data file was damaged and could not be read. It was set aside in the app folder; if you have a backup, restore it below.',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onErrorContainer),
                        onPressed: () {
                          s.habits.clearDamaged();
                          s.reminders.clearDamaged();
                          s.timers.clearDamaged();
                        },
                        child: Text(t(context, 'Ocultar', 'Dismiss')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SectionHeader(t(context, 'General', 'General')),
          label(t(context, 'Idioma', 'Language')),
          chips<String>(const <String>['es', 'en'], st.language, (String v) => v == 'es' ? 'Español' : 'English', (String v) {
            st.language = v;
            _save(st);
            // Canales, botones y textos de los avisos en el idioma nuevo.
            unawaited(s.notices.languageChanged());
          }),
          label(t(context, 'Tema', 'Theme')),
          chips<String>(const <String>['system', 'light', 'dark'], st.themeMode, (String v) => v == 'system' ? t(context, 'Sistema', 'System') : (v == 'light' ? t(context, 'Claro', 'Light') : t(context, 'Oscuro', 'Dark')), (String v) {
            st.themeMode = v;
            _save(st);
          }),
          label(t(context, 'Color de acento', 'Accent color')),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ColorChoice(
              colors: kAccents,
              selected: kAccents[st.accent.clamp(0, kAccents.length - 1)].value,
              onChanged: (int v) {
                st.accent = kAccents.indexWhere((NamedColor c) => c.value == v);
                _save(st);
              },
            ),
          ),
          label(t(context, 'La semana empieza el', 'Week starts on')),
          chips<int>(const <int>[DateTime.monday, DateTime.sunday], st.weekStart, (int v) => weekdayName(v, spanish: es), (int v) {
            st.weekStart = v;
            _save(st);
            s.notices.requestSync();
          }),
          SectionHeader(t(context, 'Temporizador', 'Timer')),
          SwitchListTile(
            title: Text(t(context, 'Sonidos', 'Sounds')),
            subtitle: Text(t(context, 'Pitidos, campana, bocina y gong al cambiar de intervalo.', 'Beeps, bell, horn and gong when intervals change.')),
            value: st.sounds,
            onChanged: (bool v) {
              st.sounds = v;
              _save(st);
            },
          ),
          if (st.sounds) ...<Widget>[
            ListTile(
              title: Text(t(context, 'Volumen', 'Volume')),
              subtitle: Slider(
                value: st.volume,
                label: '${(st.volume * 100).round()} %',
                divisions: 10,
                onChanged: (double v) {
                  st.volume = v;
                  _save(st);
                },
                onChangeEnd: (_) => unawaited(s.cues.sound(CueSound.beep)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final CueSound snd in const <CueSound>[CueSound.beep, CueSound.bell, CueSound.horn, CueSound.gong])
                    ActionChip(avatar: const Icon(Icons.volume_up, size: 18), label: Text(TimerTexts.sound(snd, es)), tooltip: es ? 'Escuchar ${TimerTexts.sound(snd, true).toLowerCase()}' : 'Play ${TimerTexts.sound(snd, false).toLowerCase()}', onPressed: () => unawaited(s.cues.sound(snd))),
                ],
              ),
            ),
          ],
          SwitchListTile(
            title: Text(t(context, 'Voz', 'Voice')),
            subtitle: Text(s.cues.voiceAvailable == false ? t(context, 'No hay voz del sistema en este idioma: instálala en los ajustes de texto a voz del teléfono.', 'There is no system voice in this language: install one in the phone\'s text-to-speech settings.') : t(context, 'Anuncia cada intervalo con la voz del sistema, en el idioma de la app.', 'Announces each interval with the system voice, in the app language.')),
            value: st.voice,
            onChanged: (bool v) {
              st.voice = v;
              _save(st);
            },
          ),
          if (st.voice) ...<Widget>[
            SwitchListTile(
              title: Text(t(context, 'Cuenta regresiva hablada', 'Spoken countdown')),
              subtitle: Text(t(context, 'Dice "3, 2, 1" antes de cada cambio; si la apagas, suenan pitidos.', 'Says "3, 2, 1" before each change; if off, beeps play instead.')),
              value: st.voiceCountdown,
              onChanged: (bool v) {
                st.voiceCountdown = v;
                _save(st);
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                child: TextButton.icon(
                  onPressed: () => unawaited(s.cues.speak(es ? 'Trabajo. Tres, dos, uno.' : 'Work. Three, two, one.')),
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(t(context, 'Probar la voz', 'Test the voice')),
                ),
              ),
            ),
          ],
          SwitchListTile(
            title: Text(t(context, 'Vibración', 'Vibration')),
            subtitle: Text(t(context, 'Al cambiar de intervalo y al terminar.', 'When intervals change and at the end.')),
            value: st.vibration,
            onChanged: (bool v) {
              st.vibration = v;
              _save(st);
            },
          ),
          SwitchListTile(
            title: Text(t(context, 'Mantener la pantalla encendida', 'Keep the screen on')),
            subtitle: Text(t(context, 'Mientras corre un temporizador con la app abierta.', 'While a timer runs with the app open.')),
            value: st.keepAwake,
            onChanged: (bool v) {
              st.keepAwake = v;
              _save(st);
            },
          ),
          LabeledControl(
            label: t(context, 'Insistencia de "Avísame en…"', '"Remind me in…" repeats'),
            help: t(context, 'Cada cuántos minutos vuelve a sonar una cuenta regresiva hasta que la apagues.', 'How often a countdown rings again until you turn it off.'),
            child: NumberStepper(value: st.countdownNag, min: 1, max: 60, label: t(context, 'Minutos', 'Minutes'), format: (int v) => '$v min', onChanged: (int v) {
              st.countdownNag = v;
              _save(st);
            }),
          ),
          SectionHeader(t(context, 'Permisos', 'Permissions')),
          ListTile(
            leading: Icon(p.notifications == false ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
            title: Text(t(context, 'Notificaciones', 'Notifications')),
            subtitle: Text(p.notifications == null
                ? t(context, 'Se piden la primera vez que creas un aviso o empiezas un temporizador.', 'Requested the first time you create a reminder or start a timer.')
                : (p.notifications! ? t(context, 'Permitidas: los avisos suenan aunque la app esté cerrada.', 'Allowed: alerts ring even when the app is closed.') : t(context, 'Apagadas: sin ellas no suenan los recordatorios ni el temporizador con la pantalla apagada.', 'Off: without them, reminders and the timer cannot ring with the screen off.'))),
            trailing: p.notifications == true
                ? null
                : TextButton(
                    onPressed: () async {
                      final bool ok = await s.notices.askNotifications(force: true);
                      if (!ok) {
                        await s.notices.openSystemSettings();
                      }
                    },
                    child: Text(t(context, 'Permitir', 'Allow')),
                  ),
          ),
          if (p.exactAlarmsApply)
            ListTile(
              leading: Icon(p.exactAlarms ? Icons.alarm_on : Icons.alarm_off),
              title: Text(t(context, 'Alarmas exactas', 'Exact alarms')),
              subtitle: Text(p.exactAlarms
                  ? t(context, 'Permitidas: los cambios de intervalo y los recordatorios llegan a su hora con la pantalla apagada.', 'Allowed: interval changes and reminders arrive on time with the screen off.')
                  : t(context, 'No permitidas: con la pantalla apagada, Android puede entregar los avisos hasta una hora tarde. Toca para permitirlas en Configuración › Alarmas y recordatorios.', 'Not allowed: with the screen off, Android can deliver alerts up to an hour late. Tap to allow them in Settings › Alarms & reminders.')),
              trailing: p.exactAlarms ? null : TextButton(onPressed: () => _exact(s), child: Text(t(context, 'Permitir', 'Allow'))),
              onTap: p.exactAlarms ? null : () => _exact(s),
            ),
          if (s.notices.coveredUntil != null)
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(t(context, 'Avisos programados', 'Scheduled alerts')),
              subtitle: Text(es
                  ? 'Hasta el ${formatShortDate(s.notices.coveredUntil!, spanish: true)}, ${formatTime(s.notices.coveredUntil!, spanish: true)}. El teléfono guarda ${s.notices.limits.budget} avisos a la vez y no caben todos: abre Rutinas antes de esa hora y se programan los siguientes.'
                  : 'Until ${formatShortDate(s.notices.coveredUntil!, spanish: false)}, ${formatTime(s.notices.coveredUntil!, spanish: false)}. The phone keeps ${s.notices.limits.budget} alerts at a time and they do not all fit: open Rutinas before then and the next ones get scheduled.'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              s.notices.gateway.isIOS
                  ? t(context, 'Con la pantalla apagada o en otra app, el temporizador sigue: Rutinas programa un aviso con sonido para cada cambio de intervalo y, al volver, lo muestra exacto. Con el iPhone en silencio, los avisos llegan sin sonido.', 'With the screen off or in another app, the timer keeps going: Rutinas schedules an alert with sound for each interval change and shows the exact time when you come back. With the iPhone on silent, alerts arrive without sound.')
                  : t(context, 'Con la pantalla apagada o en otra app, el temporizador sigue: Rutinas programa un aviso con sonido para cada cambio de intervalo y, al volver, lo muestra exacto. Sin alarmas exactas, esos avisos pueden llegar hasta una hora tarde.', 'With the screen off or in another app, the timer keeps going: Rutinas schedules an alert with sound for each interval change and shows the exact time when you come back. Without exact alarms, those alerts can arrive up to an hour late.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SectionHeader(t(context, 'Copia de seguridad', 'Backup')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              t(context, 'Rutinas no tiene cuenta ni nube: para cambiar de teléfono, exporta una copia (un archivo JSON) y ábrela en el nuevo con "Restaurar".', 'Rutinas has no account or cloud: to change phones, export a backup (a JSON file) and open it on the new one with "Restore".'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(t(context, 'Exportar copia', 'Export backup')),
            subtitle: Text(st.lastExportAt == null ? t(context, 'Todavía no has exportado ninguna.', 'You have not exported one yet.') : (es ? 'Última: ${formatLongDate(st.lastExportAt!, spanish: true)}' : 'Last: ${formatLongDate(st.lastExportAt!, spanish: false)}')),
            trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)) : null,
            onTap: _busy ? null : () => _export(s),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(t(context, 'Restaurar desde archivo', 'Restore from file')),
            subtitle: Text(t(context, 'Reemplaza los datos actuales por los de la copia.', 'Replaces the current data with the backup.')),
            onTap: _busy ? null : () => _import(s),
          ),
          SectionHeader(t(context, 'Acerca de', 'About')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('$kAppName $kAppVersion'),
            subtitle: Text(t(context, 'Gratis, sin anuncios, sin cuenta y sin internet. Tus datos se quedan en tu teléfono. Código abierto (Apache-2.0); sonidos sintetizados por la app.', 'Free, no ads, no account and no internet. Your data stays on your phone. Open source (Apache-2.0); sounds synthesized by the app.')),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(t(context, 'Política de privacidad', 'Privacy policy')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PrivacyPolicyScreen(spanish: es))),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(t(context, 'Licencias de código abierto', 'Open-source licenses')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context, applicationName: kAppName, applicationVersion: kAppVersion),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(t(context, 'Ayuda y código fuente', 'Help and source code')),
            subtitle: SelectableText(kSupportUrl, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
