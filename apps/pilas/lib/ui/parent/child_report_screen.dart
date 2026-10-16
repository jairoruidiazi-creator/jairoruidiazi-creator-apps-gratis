import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/game_registry.dart';
import '../../games/shell/widgets.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../../model/skill.dart';
import 'report_data.dart';
import 'report_pdf.dart';

/// Informe de un niño para el adulto, con exportación a PDF.
class ChildReportScreen extends StatefulWidget {
  const ChildReportScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<ChildReportScreen> createState() => _ChildReportScreenState();
}

class _ChildReportScreenState extends State<ChildReportScreen> {
  bool _exporting = false;

  Future<void> _pdf(ChildReport r) async {
    setState(() => _exporting = true);
    try {
      final Uint8List bytes = await ReportPdf.buildChild(r);
      await ReportPdf.share(bytes, 'pilas-informe-${widget.profile.nombre.toLowerCase().replaceAll(' ', '-')}.pdf');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final ProfileProgress prog = s.state.progressOf(widget.profile.id);
    final ChildReport r = ChildReport(profile: widget.profile, progress: prog);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.nombre),
        actions: <Widget>[
          IconButton(
            tooltip: S.informePdf,
            onPressed: _exporting ? null : () => _pdf(r),
            icon: _exporting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              EmojiImage(widget.profile.avatar, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${widget.profile.age} años · ${r.band.label}\n${r.band.schoolLabel}', style: const TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _Stat(label: S.hoy, value: S.minutos(r.minutosHoy))),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: S.estaSemana, value: S.minutos(r.minutosSemana))),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'Aciertos', value: r.rondasTotal == 0 ? '-' : '${(r.aciertosTotal * 100 / r.rondasTotal).round()} %')),
            ],
          ),
          const SizedBox(height: 20),
          Text(S.habilidadesLogradas, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final AreaSummary a in r.areas)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        EmojiImage(a.area.emoji, size: 28),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a.area.nombre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: a.area.color))),
                        Text('${a.skillsLogradas} de ${a.skillsPosibles}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: a.skillsPosibles == 0 ? 0 : a.skillsLogradas / a.skillsPosibles,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFEFE9DA),
                        color: a.area.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (a.juegos.isEmpty)
                      const Text('Sin jugar todavía', style: TextStyle(color: PilasColors.tintaSuave))
                    else
                      for (final GameLevel g in a.juegos)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('${g.game.nombre}: nivel ${g.level} de ${g.maxLevel} · ${g.rondas} rondas · ${g.rondas == 0 ? '-' : '${(g.aciertos * 100 / g.rondas).round()} %'} aciertos', style: const TextStyle(fontSize: 14)),
                        ),
                    const SizedBox(height: 6),
                    for (final Skill sk in SkillCatalog.forAreaAndBand(a.area, r.band))
                      Row(
                        children: <Widget>[
                          Icon(prog.skillsAchieved.containsKey(sk.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: prog.skillsAchieved.containsKey(sk.id) ? PilasColors.verde : PilasColors.borde),
                          const SizedBox(width: 6),
                          Expanded(child: Text(sk.nombre, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Fichas para el adulto', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Qué trabaja cada juego, cómo seguirlo sin pantalla y qué preguntar después.', style: TextStyle(color: PilasColors.tintaSuave)),
          const SizedBox(height: 8),
          for (final GameDef g in GameRegistry.forBand(r.band))
            ExpansionTile(
              leading: EmojiImage(g.emoji, size: 32),
              title: Text(g.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(SkillCatalog.byId(g.skillFor(r.band) ?? '')?.nombre ?? g.area.nombre),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(g.descripcion),
                const SizedBox(height: 6),
                Text('En casa: ${g.enCasa}', style: const TextStyle(color: PilasColors.tintaSuave)),
                const SizedBox(height: 6),
                Text('Pregúntale: ${g.pregunta}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
          const SizedBox(height: 20),
          Text(S.ultimasSesiones, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (r.sesionesRecientes.isEmpty) const Text(S.sinSesiones, style: TextStyle(color: PilasColors.tintaSuave)),
          for (final SessionLog ses in r.sesionesRecientes.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(fechaHora(ses.start)),
              subtitle: Text('${(ses.seconds / 60).round()} min · ${ses.rounds} rondas · ${ses.correct} aciertos'),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _exporting ? null : () => _pdf(r),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text(S.informePdf),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: PilasColors.borde, width: 2)),
      child: Column(
        children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 13, color: PilasColors.tintaSuave)),
        ],
      ),
    );
  }
}
