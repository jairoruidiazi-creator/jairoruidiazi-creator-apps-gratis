import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../model/workout.dart';
import '../widgets/common.dart';
import 'runner_screen.dart';

/// Cuenta atrás simple con preajustes guardados (té, horno, siesta).
class CountdownView extends StatefulWidget {
  const CountdownView({super.key});

  @override
  State<CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<CountdownView> {
  int? _seconds;

  Future<void> _start(Services s, {required String name, required int seconds, String? presetId}) async {
    final bool ok = await RunnerScreen.confirmReplace(context);
    if (!ok || !mounted) {
      return;
    }
    s.timer.startCountdown(name: name, seconds: seconds, presetId: presetId);
    unawaited(s.notices.askNotifications());
    if (mounted) {
      await RunnerScreen.open(context);
    }
  }

  Future<void> _savePreset(Services s, int seconds) async {
    final String? value = await askText(
      context,
      title: t(context, 'Guardar cuenta atrás', 'Save countdown'),
      label: t(context, 'Nombre', 'Name'),
      hint: t(context, 'Té, pasta, siesta…', 'Tea, pasta, nap…'),
      okLabel: t(context, 'Guardar', 'Save'),
    );
    if (value == null) {
      return;
    }
    final String n = value.trim().isEmpty ? formatDurationShort(seconds, spanish: s.settings.spanish) : value.trim();
    s.timers.addPreset(CountdownPreset(id: newId(), name: n, seconds: seconds));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.timers, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final bool es = s.settings.spanish;
        final ThemeData theme = Theme.of(context);
        final int seconds = _seconds ?? s.timers.lastCountdownSeconds;
        final List<CountdownPreset> presets = s.timers.presets;
        return ReadableWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      Semantics(
                        label: es ? 'Duración: ${formatDurationShort(seconds, spanish: true)}' : 'Duration: ${formatDurationShort(seconds, spanish: false)}',
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(formatClock(seconds), style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DurationChoice(seconds: seconds, maxSeconds: 10 * 3600, onChanged: (int v) => setState(() => _seconds = v)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          for (final int m in const <int>[1, 3, 5, 10, 15, 25, 45])
                            ChoiceChip(
                              label: Text('$m min'),
                              selected: seconds == m * 60,
                              onSelected: (_) => setState(() => _seconds = m * 60),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          OutlinedButton.icon(onPressed: () => _savePreset(s, seconds), icon: const Icon(Icons.bookmark_add_outlined), label: Text(t(context, 'Guardar', 'Save'))),
                          FilledButton.icon(
                            onPressed: () => _start(s, name: es ? 'Cuenta atrás de ${formatDurationShort(seconds, spanish: true)}' : '${formatDurationShort(seconds, spanish: false)} countdown', seconds: seconds),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(t(context, 'Iniciar', 'Start')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SectionHeader(t(context, 'Guardadas', 'Saved')),
              if (presets.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(t(context, 'Guarda las que uses seguido para empezarlas con un toque.', 'Save the ones you use often to start them with one tap.'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              for (final CountdownPreset p in presets)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(p.name),
                  subtitle: Text(formatClock(p.seconds)),
                  onTap: () => _start(s, name: p.name, seconds: p.seconds, presetId: p.id),
                  trailing: IconButton(
                    tooltip: es ? 'Borrar ${p.name}' : 'Delete ${p.name}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final bool ok = await confirm(context, title: t(context, '¿Borrar esta cuenta atrás?', 'Delete this countdown?'), message: p.name, yes: t(context, 'Borrar', 'Delete'), destructive: true);
                      if (ok) {
                        s.timers.removePreset(p.id);
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
