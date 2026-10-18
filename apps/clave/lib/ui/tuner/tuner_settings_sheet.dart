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
    final bool spanish = isSpanish(context);
    final PitchSettings ps = st.pitch;
    void save() {
      st.save();
      setState(() {});
    }

    String hz(double v) => '${formatDecimal(v, spanish: spanish)} Hz';
    String signed(int v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        Text(t(context, 'Instrumento', 'Instrument'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: st.instrumentId,
          isExpanded: true,
          decoration: InputDecoration(labelText: t(context, 'Perfil del afinador', 'Tuner profile')),
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
        _Section(title: t(context, 'Referencia La4', 'A4 reference'), trailing: hz(st.a4)),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: t(context, 'Bajar 0,1 Hz', 'Down 0.1 Hz'),
              onPressed: () {
                st.a4 = ((st.a4 - 0.1).clamp(400.0, 480.0) * 10).round() / 10;
                save();
              },
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: Slider(
                min: 400,
                max: 480,
                divisions: 800,
                value: st.a4.clamp(400.0, 480.0),
                label: hz(st.a4),
                semanticFormatterCallback: hz,
                onChanged: (double v) {
                  st.a4 = (v * 10).round() / 10;
                  save();
                },
              ),
            ),
            IconButton(
              tooltip: t(context, 'Subir 0,1 Hz', 'Up 0.1 Hz'),
              onPressed: () {
                st.a4 = ((st.a4 + 0.1).clamp(400.0, 480.0) * 10).round() / 10;
                save();
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final double a in <double>[415, 432, 440, 442, 443, 444])
              ChoiceChip(
                label: Text(a.toStringAsFixed(0)),
                tooltip: '${a.toStringAsFixed(0)} Hz',
                selected: st.a4 == a,
                onSelected: (_) {
                  st.a4 = a;
                  save();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(title: t(context, 'Temperamento', 'Temperament')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final MapEntry<Temperament, String> o in <Temperament, String>{
              Temperament.equal: t(context, 'Igual', 'Equal'),
              Temperament.just: t(context, 'Justo', 'Just'),
              Temperament.pythagorean: t(context, 'Pitagórico', 'Pythagorean'),
              Temperament.meantone: t(context, 'Mesotónico', 'Meantone'),
              Temperament.custom: t(context, 'Propio', 'Custom'),
            }.entries)
              ChoiceChip(
                label: Text(o.value),
                selected: st.temperament == o.key,
                onSelected: (_) {
                  st.temperament = o.key;
                  save();
                },
              ),
          ],
        ),
        if (st.temperament != Temperament.equal) ...<Widget>[
          const SizedBox(height: 8),
          // La tónica se elige con los nombres que muestra el afinador (con la
          // transposición del instrumento); se guarda como altura real.
          DropdownButtonFormField<int>(
            initialValue: st.temperamentRoot,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context, 'Tónica del temperamento', 'Temperament root')),
            items: <DropdownMenuItem<int>>[
              for (int pc = 0; pc < 12; pc++) DropdownMenuItem<int>(value: pc, child: Text(ps.displayName(pc))),
            ],
            onChanged: (int? v) {
              if (v != null) {
                st.temperamentRoot = v;
                save();
              }
            },
          ),
        ],
        if (st.temperament == Temperament.custom) ...<Widget>[
          const SizedBox(height: 8),
          Text(t(context, 'Desviación de cada grado respecto al temperamento igual (cents)', 'Offset of each degree from equal temperament (cents)'), style: Theme.of(context).textTheme.bodySmall),
          for (int i = 0; i < 12; i++)
            Row(
              children: <Widget>[
                SizedBox(width: 52, child: Text(ps.displayName((st.temperamentRoot + i) % 12))),
                Expanded(
                  child: Slider(
                    min: -50,
                    max: 50,
                    divisions: 100,
                    value: st.customTemperament[i].clamp(-50.0, 50.0),
                    label: '${signed(st.customTemperament[i].round())} cents',
                    semanticFormatterCallback: (double v) => '${ps.displayName((st.temperamentRoot + i) % 12)}: ${signed(v.round())} cents',
                    onChanged: (double v) {
                      st.customTemperament[i] = v.roundToDouble();
                      save();
                    },
                  ),
                ),
                SizedBox(width: 40, child: Text(signed(st.customTemperament[i].round()), textAlign: TextAlign.end)),
              ],
            ),
          TextButton(
            onPressed: () {
              st.customTemperament = List<double>.filled(12, 0);
              save();
            },
            child: Text(t(context, 'Poner todo en 0', 'Reset to 0')),
          ),
        ],
        const SizedBox(height: 16),
        _Section(title: t(context, 'Notación', 'Notation')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final MapEntry<Notation, String> o in const <Notation, String>{
              Notation.solfeo: 'Do Re Mi',
              Notation.english: 'C D E',
              Notation.german: 'C D E (H)',
              Notation.indian: 'Sa Re Ga',
            }.entries)
              ChoiceChip(
                label: Text(o.value),
                selected: st.notation == o.key,
                onSelected: (_) {
                  st.notation = o.key;
                  save();
                },
              ),
          ],
        ),
        if (st.notation == Notation.indian) ...<Widget>[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: st.indianTonic,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context, 'Nota de Sa', 'Sa note')),
            items: <DropdownMenuItem<int>>[
              for (int pc = 0; pc < 12; pc++) DropdownMenuItem<int>(value: pc, child: Text(Notes.name(pc, spanish ? Notation.solfeo : Notation.english, flats: st.flats))),
            ],
            onChanged: (int? v) {
              if (v != null) {
                st.indianTonic = v;
                save();
              }
            },
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Mostrar bemoles en vez de sostenidos', 'Show flats instead of sharps')),
          value: st.flats,
          onChanged: (bool v) {
            st.flats = v;
            save();
          },
        ),
        const SizedBox(height: 8),
        _Section(title: t(context, 'Transposición', 'Transposition'), trailing: signed(st.transposition)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            _chip('Do / C', 0, st, save),
            _chip('Si♭ / B♭', 2, st, save),
            _chip('Mi♭ / E♭', 9, st, save),
            _chip('Fa / F', 7, st, save),
            _chip('La / A', 3, st, save),
          ],
        ),
        Slider(
          min: -12,
          max: 14,
          divisions: 26,
          value: st.transposition.toDouble(),
          label: signed(st.transposition),
          semanticFormatterCallback: (double v) => '${signed(v.round())} ${t(context, 'semitonos', 'semitones')}',
          onChanged: (double v) {
            st.transposition = v.round();
            save();
          },
        ),
        _Section(title: t(context, 'Capo (traste)', 'Capo (fret)'), trailing: '${st.capo}'),
        Text(t(context, 'Con capo, las cuerdas suben esos semitonos y el afinador las nombra y las mide así.', 'With a capo the open strings rise by that many semitones; the tuner names and measures them that way.'), style: Theme.of(context).textTheme.bodySmall),
        Slider(
          min: 0,
          max: 12,
          divisions: 12,
          value: st.capo.toDouble(),
          label: '${st.capo}',
          semanticFormatterCallback: (double v) => '${t(context, 'traste', 'fret')} ${v.round()}',
          onChanged: (double v) {
            st.capo = v.round();
            save();
          },
        ),
        const SizedBox(height: 8),
        _Section(title: t(context, 'Tolerancia de afinado', 'In-tune tolerance'), trailing: '± ${st.toleranceCents.toStringAsFixed(0)} cents'),
        Slider(
          min: 1,
          max: 15,
          divisions: 14,
          value: st.toleranceCents,
          label: '± ${st.toleranceCents.toStringAsFixed(0)} cents',
          semanticFormatterCallback: (double v) => '± ${v.round()} cents',
          onChanged: (double v) {
            st.toleranceCents = v.roundToDouble();
            save();
          },
        ),
        _Section(title: t(context, 'Amortiguación de la aguja', 'Needle damping'), trailing: formatPercent(st.damping, spanish: spanish)),
        Slider(
          min: 0,
          max: 0.95,
          divisions: 19,
          value: st.damping,
          label: formatPercent(st.damping, spanish: spanish),
          semanticFormatterCallback: (double v) => formatPercent(v, spanish: spanish),
          onChanged: (double v) {
            st.damping = v;
            save();
          },
        ),
      ],
    );
  }

  Widget _chip(String label, int semis, AppSettings st, VoidCallback save) {
    return ChoiceChip(
      label: Text(label),
      selected: st.transposition == semis,
      onSelected: (_) {
        st.transposition = semis;
        save();
      },
    );
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
