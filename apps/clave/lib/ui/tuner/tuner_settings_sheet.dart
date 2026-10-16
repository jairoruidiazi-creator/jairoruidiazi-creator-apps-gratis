import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../music/instruments.dart';
import '../../music/notes.dart';

Future<void> showTunerSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const FractionallySizedBox(heightFactor: 0.9, child: TunerSettingsSheet()),
  );
}

class TunerSettingsSheet extends StatefulWidget {
  const TunerSettingsSheet({super.key});

  @override
  State<TunerSettingsSheet> createState() => _TunerSettingsSheetState();
}

class _TunerSettingsSheetState extends State<TunerSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    final bool spanish = st.spanish;
    void save() {
      st.save();
      setState(() {});
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        Text(t(context, 'Instrumento', 'Instrument'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: st.instrumentId,
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final Instrument i in Instruments.all) DropdownMenuItem<String>(value: i.id, child: Text(i.name(spanish))),
          ],
          onChanged: (String? v) {
            if (v == null) {
              return;
            }
            final Instrument i = Instruments.byId(v);
            st.instrumentId = v;
            // Los instrumentos transpositores traen su transposición.
            st.transposition = i.transposition;
            save();
          },
        ),
        const SizedBox(height: 16),
        _Section(title: t(context, 'Referencia La4', 'A4 reference'), trailing: '${st.a4.toStringAsFixed(1).replaceAll('.', spanish ? ',' : '.')} Hz'),
        Row(
          children: <Widget>[
            IconButton(onPressed: () { st.a4 = (st.a4 - 0.1).clamp(400.0, 480.0); save(); }, icon: const Icon(Icons.remove_circle_outline)),
            Expanded(
              child: Slider(
                min: 400,
                max: 480,
                divisions: 800,
                value: st.a4.clamp(400.0, 480.0),
                label: st.a4.toStringAsFixed(1),
                onChanged: (double v) { st.a4 = (v * 10).round() / 10; save(); },
              ),
            ),
            IconButton(onPressed: () { st.a4 = (st.a4 + 0.1).clamp(400.0, 480.0); save(); }, icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final double a in <double>[415, 432, 440, 442, 443, 444])
              ActionChip(label: Text(a.toStringAsFixed(0)), onPressed: () { st.a4 = a; save(); }),
          ],
        ),
        const SizedBox(height: 16),
        _Section(title: t(context, 'Temperamento', 'Temperament')),
        SegmentedButton<Temperament>(
          segments: <ButtonSegment<Temperament>>[
            ButtonSegment<Temperament>(value: Temperament.equal, label: Text(t(context, 'Igual', 'Equal'))),
            ButtonSegment<Temperament>(value: Temperament.just, label: Text(t(context, 'Justo', 'Just'))),
            ButtonSegment<Temperament>(value: Temperament.pythagorean, label: Text(t(context, 'Pitag.', 'Pyth.'))),
            ButtonSegment<Temperament>(value: Temperament.meantone, label: Text(t(context, 'Mesot.', 'Mean.'))),
            ButtonSegment<Temperament>(value: Temperament.custom, label: Text(t(context, 'Propio', 'Custom'))),
          ],
          selected: <Temperament>{st.temperament},
          showSelectedIcon: false,
          onSelectionChanged: (Set<Temperament> v) { st.temperament = v.first; save(); },
        ),
        if (st.temperament != Temperament.equal) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(t(context, 'Tónica', 'Root')),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  value: st.temperamentRoot,
                  isExpanded: true,
                  items: <DropdownMenuItem<int>>[
                    for (int pc = 0; pc < 12; pc++) DropdownMenuItem<int>(value: pc, child: Text(Notes.name(pc, st.notation, flats: st.flats))),
                  ],
                  onChanged: (int? v) { if (v != null) { st.temperamentRoot = v; save(); } },
                ),
              ),
            ],
          ),
        ],
        if (st.temperament == Temperament.custom) ...<Widget>[
          const SizedBox(height: 8),
          Text(t(context, 'Desviación de cada grado respecto al temperamento igual (cents)', 'Offset of each degree from equal temperament (cents)'), style: Theme.of(context).textTheme.bodySmall),
          for (int i = 0; i < 12; i++)
            Row(
              children: <Widget>[
                SizedBox(width: 44, child: Text(Notes.name((st.temperamentRoot + i) % 12, st.notation, flats: st.flats))),
                Expanded(
                  child: Slider(
                    min: -50,
                    max: 50,
                    divisions: 100,
                    value: st.customTemperament[i].clamp(-50.0, 50.0),
                    label: st.customTemperament[i].toStringAsFixed(0),
                    onChanged: (double v) { st.customTemperament[i] = v.roundToDouble(); save(); },
                  ),
                ),
                SizedBox(width: 36, child: Text('${st.customTemperament[i] >= 0 ? '+' : ''}${st.customTemperament[i].toStringAsFixed(0)}', textAlign: TextAlign.end)),
              ],
            ),
          TextButton(onPressed: () { st.customTemperament = List<double>.filled(12, 0); save(); }, child: Text(t(context, 'Poner todo en 0', 'Reset to 0'))),
        ],
        const SizedBox(height: 16),
        _Section(title: t(context, 'Notación', 'Notation')),
        SegmentedButton<Notation>(
          segments: <ButtonSegment<Notation>>[
            ButtonSegment<Notation>(value: Notation.solfeo, label: Text(t(context, 'Do Re Mi', 'Do Re Mi'))),
            const ButtonSegment<Notation>(value: Notation.english, label: Text('C D E')),
            const ButtonSegment<Notation>(value: Notation.german, label: Text('C D E (H)')),
            const ButtonSegment<Notation>(value: Notation.indian, label: Text('Sa Re Ga')),
          ],
          selected: <Notation>{st.notation},
          showSelectedIcon: false,
          onSelectionChanged: (Set<Notation> v) { st.notation = v.first; save(); },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Mostrar bemoles en vez de sostenidos', 'Show flats instead of sharps')),
          value: st.flats,
          onChanged: (bool v) { st.flats = v; save(); },
        ),
        const SizedBox(height: 8),
        _Section(title: t(context, 'Transposición', 'Transposition'), trailing: '${st.transposition > 0 ? '+' : ''}${st.transposition}'),
        Wrap(
          spacing: 8,
          children: <Widget>[
            _chip(context, 'Do / C', 0, st, save),
            _chip(context, 'Si♭ / B♭', 2, st, save),
            _chip(context, 'Mi♭ / E♭', 9, st, save),
            _chip(context, 'Fa / F', 7, st, save),
            _chip(context, 'La / A', 3, st, save),
          ],
        ),
        Slider(min: -12, max: 14, divisions: 26, value: st.transposition.toDouble(), label: '${st.transposition}', onChanged: (double v) { st.transposition = v.round(); save(); }),
        _Section(title: t(context, 'Capo (traste)', 'Capo (fret)'), trailing: '${st.capo}'),
        Slider(min: 0, max: 12, divisions: 12, value: st.capo.toDouble(), label: '${st.capo}', onChanged: (double v) { st.capo = v.round(); save(); }),
        const SizedBox(height: 8),
        _Section(title: t(context, 'Tolerancia de afinado', 'In-tune tolerance'), trailing: '± ${st.toleranceCents.toStringAsFixed(0)} cents'),
        Slider(min: 1, max: 15, divisions: 14, value: st.toleranceCents, label: st.toleranceCents.toStringAsFixed(0), onChanged: (double v) { st.toleranceCents = v.roundToDouble(); save(); }),
        _Section(title: t(context, 'Amortiguación de la aguja', 'Needle damping'), trailing: '${(st.damping * 100).round()} %'),
        Slider(min: 0, max: 0.95, divisions: 19, value: st.damping, label: '${(st.damping * 100).round()} %', onChanged: (double v) { st.damping = v; save(); }),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, int semis, AppSettings st, VoidCallback save) {
    return ChoiceChip(label: Text(label), selected: st.transposition == semis, onSelected: (_) { st.transposition = semis; save(); });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
