import 'package:flutter/material.dart';

import '../../audio/click_synth.dart';
import '../../audio/sequencer.dart';
import '../../core/app_scope.dart';

Future<void> _sheet(BuildContext context, Widget Function(BuildContext context, void Function(void Function()) setState) builder) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, void Function(void Function()) setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: builder(context, setState),
      ),
    ),
  );
}

Future<void> showTimeSignatureSheet(BuildContext context, RhythmConfig initial, ValueChanged<RhythmConfig> onChange) {
  RhythmConfig c = initial;
  return _sheet(context, (BuildContext context, void Function(void Function()) setState) {
    void applyConfig(RhythmConfig n) {
      c = n;
      onChange(n);
      setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t(context, 'Compás', 'Time signature'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(t(context, 'Pulsos por compás', 'Beats per bar')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (int n = 1; n <= 16; n++) ChoiceChip(label: Text('$n'), selected: c.beatsPerBar == n, onSelected: (_) => applyConfig(c.copyWith(beatsPerBar: n))),
          ],
        ),
        const SizedBox(height: 12),
        Text(t(context, 'Figura del pulso', 'Beat value')),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final int d in <int>[2, 4, 8, 16]) ChoiceChip(label: Text('$d'), selected: c.denominator == d, onSelected: (_) => applyConfig(c.copyWith(denominator: d))),
          ],
        ),
        const SizedBox(height: 12),
        Text(t(context, 'Compases frecuentes', 'Common signatures')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final List<int> ts in <List<int>>[<int>[2, 4], <int>[3, 4], <int>[4, 4], <int>[5, 4], <int>[6, 8], <int>[7, 8], <int>[9, 8], <int>[12, 8], <int>[3, 8]])
              ActionChip(
                label: Text('${ts[0]}/${ts[1]}'),
                onPressed: () {
                  // Los compases compuestos acentúan cada tres pulsos.
                  final List<BeatMode> beats = List<BeatMode>.generate(ts[0], (int i) => i == 0 ? BeatMode.accent : (ts[1] == 8 && ts[0] % 3 == 0 && i % 3 == 0 ? BeatMode.accent : BeatMode.normal));
                  applyConfig(c.copyWith(beatsPerBar: ts[0], denominator: ts[1], beats: beats));
                },
              ),
          ],
        ),
      ],
    );
  });
}

Future<void> showSubdivisionSheet(BuildContext context, RhythmConfig initial, ValueChanged<RhythmConfig> onChange) {
  RhythmConfig c = initial;
  return _sheet(context, (BuildContext context, void Function(void Function()) setState) {
    void applyConfig(RhythmConfig n) {
      c = n;
      onChange(n);
      setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t(context, 'Subdivisión', 'Subdivision'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final List<dynamic> o in <List<dynamic>>[
              <dynamic>[1, t(context, 'Ninguna', 'None')],
              <dynamic>[2, t(context, 'Corcheas', 'Eighths')],
              <dynamic>[3, t(context, 'Tresillos', 'Triplets')],
              <dynamic>[4, t(context, 'Semicorcheas', 'Sixteenths')],
              <dynamic>[6, t(context, 'Seisillos', 'Sextuplets')],
            ])
              ChoiceChip(label: Text(o[1] as String), selected: c.subdivision == o[0], onSelected: (_) => applyConfig(c.copyWith(subdivision: o[0] as int))),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Las subdivisiones suenan', 'Subdivisions are audible')),
          subtitle: Text(t(context, 'Si no, solo se usan para el swing y la animación.', 'Otherwise they only drive swing and the animation.')),
          value: c.subdivisionAudible,
          onChanged: (bool v) => applyConfig(c.copyWith(subdivisionAudible: v)),
        ),
        if (c.subdivision == 2) ...<Widget>[
          Text('Swing: ${(c.swing * 100).round()} %'),
          Slider(min: 0, max: 1, divisions: 10, value: c.swing, label: '${(c.swing * 100).round()} %', onChanged: (double v) => applyConfig(c.copyWith(swing: v))),
          Text(t(context, '0 % = corcheas rectas · 100 % = corchea de tresillo', '0% = straight eighths · 100% = triplet feel'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  });
}

Future<void> showSoundSheet(BuildContext context, RhythmConfig initial, ValueChanged<RhythmConfig> onChange) {
  RhythmConfig c = initial;
  final bool spanish = AppScope.of(context).settings.spanish;
  return _sheet(context, (BuildContext context, void Function(void Function()) setState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t(context, 'Sonido del clic', 'Click sound'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(t(context, 'Cada sonido tiene tres variantes: acento, pulso y subdivisión. Todos están sintetizados en la app.', 'Each sound has accent, beat and subdivision variants. All are synthesized in the app.'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ClickSound s in ClickSound.values)
              ChoiceChip(
                label: Text(spanish ? s.nameEs : s.nameEn),
                selected: c.sound == s,
                onSelected: (_) {
                  c = c.copyWith(sound: s);
                  onChange(c);
                  setState(() {});
                },
              ),
          ],
        ),
      ],
    );
  });
}

Future<void> showTrainerSheet(BuildContext context, RhythmConfig initial, ValueChanged<RhythmConfig> onChange) {
  RhythmConfig c = initial;
  TrainerConfig tr = initial.trainer ?? TrainerConfig(targetBpm: (initial.bpm + 20).clamp(20, 400).toDouble());
  bool on = initial.trainer != null;
  return _sheet(context, (BuildContext context, void Function(void Function()) setState) {
    void apply() {
      c = on ? c.copyWith(trainer: tr) : c.copyWith(clearTrainer: true);
      onChange(c);
      setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t(context, 'Entrenador de tempo', 'Tempo trainer'), style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Activar', 'Enable')),
          subtitle: Text(t(context, 'Sube (o baja) el tempo por pasos hasta la meta.', 'Steps the tempo up (or down) until the target.')),
          value: on,
          onChanged: (bool v) {
            on = v;
            apply();
          },
        ),
        Text('${t(context, 'Tempo meta', 'Target tempo')}: ${tr.targetBpm.toStringAsFixed(0)} BPM'),
        Slider(min: 20, max: 400, value: tr.targetBpm.clamp(20.0, 400.0), onChanged: (double v) { tr = TrainerConfig(targetBpm: v.roundToDouble(), stepBpm: tr.stepBpm, everyBars: tr.everyBars); apply(); }),
        Text('${t(context, 'Paso', 'Step')}: ${tr.stepBpm.toStringAsFixed(0)} BPM'),
        Slider(min: 1, max: 20, divisions: 19, value: tr.stepBpm.clamp(1.0, 20.0), onChanged: (double v) { tr = TrainerConfig(targetBpm: tr.targetBpm, stepBpm: v.roundToDouble(), everyBars: tr.everyBars); apply(); }),
        Text('${t(context, 'Cada', 'Every')}: ${tr.everyBars} ${t(context, 'compases', 'bars')}'),
        Slider(min: 1, max: 16, divisions: 15, value: tr.everyBars.toDouble(), onChanged: (double v) { tr = TrainerConfig(targetBpm: tr.targetBpm, stepBpm: tr.stepBpm, everyBars: v.round()); apply(); }),
      ],
    );
  });
}

Future<void> showMuteSheet(BuildContext context, RhythmConfig initial, ValueChanged<RhythmConfig> onChange) {
  RhythmConfig c = initial;
  MuteConfig m = initial.muteBars ?? const MuteConfig();
  bool on = initial.muteBars != null;
  return _sheet(context, (BuildContext context, void Function(void Function()) setState) {
    void apply() {
      c = on ? c.copyWith(muteBars: m) : c.copyWith(clearMute: true);
      onChange(c);
      setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(t(context, 'Compases mudos', 'Mute bars'), style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Activar', 'Enable')),
          subtitle: Text(t(context, 'El clic se calla algunos compases para entrenar el pulso interno; la animación sigue.', 'The click goes silent for some bars to train your inner pulse; the animation continues.')),
          value: on,
          onChanged: (bool v) {
            on = v;
            apply();
          },
        ),
        Text('${t(context, 'Compases que suenan', 'Bars with click')}: ${m.soundBars}'),
        Slider(min: 1, max: 8, divisions: 7, value: m.soundBars.toDouble(), onChanged: (double v) { m = MuteConfig(soundBars: v.round(), muteBarsCount: m.muteBarsCount); apply(); }),
        Text('${t(context, 'Compases mudos', 'Silent bars')}: ${m.muteBarsCount}'),
        Slider(min: 1, max: 8, divisions: 7, value: m.muteBarsCount.toDouble(), onChanged: (double v) { m = MuteConfig(soundBars: m.soundBars, muteBarsCount: v.round()); apply(); }),
      ],
    );
  });
}
