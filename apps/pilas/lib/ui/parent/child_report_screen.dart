import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/game_registry.dart';
import '../../games/shell/widgets.dart';
import '../../model/age_band.dart';
import '../../model/area.dart';
import '../../model/profile.dart';
import '../../model/progress.dart';
import '../../model/skill.dart';
import 'report_data.dart';
import 'report_pdf.dart';

/// Informe de un niño para el adulto, con exportación a PDF. Las habilidades
/// se cuentan sobre las del tramo de edad actual del niño.
class ChildReportScreen extends StatefulWidget {
  const ChildReportScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<ChildReportScreen> createState() => _ChildReportScreenState();
}

class _ChildReportScreenState extends State<ChildReportScreen> {
  bool _exporting = false;

  Future<void> _pdf(BuildContext buttonContext, ChildReport r) async {
    final Services s = AppScope.read(context);
    setState(() => _exporting = true);
    try {
      final Uint8List bytes = await ReportPdf.buildChild(r);
      if (!buttonContext.mounted) {
        return;
      }
      await s.sharer.shareBytes(buttonContext, s.store, bytes, baseName: 'pilas-informe-${widget.profile.nombre}', extension: 'pdf', mimeType: 'application/pdf', text: 'Informe de Pilas');
    } catch (e) {
      debugPrint('No se pudo crear el PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo crear el informe en PDF.')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final ProfileProgress prog = s.state.progressOf(widget.profile.id);
    final ChildReport r = ChildReport(profile: widget.profile, progress: prog);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.nombre),
        actions: <Widget>[
          Builder(
            builder: (BuildContext buttonContext) => IconButton(
              key: const ValueKey<String>('informe-pdf-arriba'),
              tooltip: S.informePdf,
              onPressed: _exporting ? null : () => _pdf(buttonContext, r),
              icon: _exporting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_rounded),
            ),
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
                child: Text('${widget.profile.age} años · juegos de ${r.band.label}\n${r.band.schoolLabel}', style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _Stat(label: S.hoy, value: S.minutos(r.minutosHoy)),
              _Stat(label: S.ultimos7, value: S.minutos(r.minutos7Dias)),
              _Stat(label: S.aciertosPrimerIntento, value: r.aciertosTexto),
              _Stat(label: S.habilidadesLogradas, value: '${r.skillsLogradasTramo} de ${r.skillsDelTramo.length}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(S.comoSeLogra, style: TextStyle(fontSize: 14, color: pal.tintaSuave)),
          const SizedBox(height: 16),
          Text(S.habilidadesDelTramo(r.band.label), style: Theme.of(context).textTheme.titleLarge),
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
                        Expanded(child: Text(a.area.nombre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.areaTexto(a.area)))),
                        Text(a.logradasTexto, style: TextStyle(fontWeight: FontWeight.w700, color: pal.tinta)),
                      ],
                    ),
                    if (!a.soloJuegoLibre) ...<Widget>[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: a.skillsLogradas / a.skillsPosibles,
                          minHeight: 10,
                          backgroundColor: pal.inactivo,
                          color: pal.areaTexto(a.area),
                          semanticsLabel: '${a.area.nombre}: ${a.skillsLogradas} de ${a.skillsPosibles} habilidades logradas',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (a.soloJuegoLibre)
                      Text(S.soloJuegoLibre, style: TextStyle(color: pal.tintaSuave))
                    else if (a.juegos.isEmpty)
                      Text('Sin jugar todavía', style: TextStyle(color: pal.tintaSuave))
                    else
                      for (final GameLevel g in a.juegos)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${g.game.nombre}${g.nivelTexto.isEmpty ? '' : ': ${g.nivelTexto}'} · ${g.resumen}',
                            style: TextStyle(fontSize: 14, color: pal.tinta),
                          ),
                        ),
                    const SizedBox(height: 6),
                    for (final Skill sk in SkillCatalog.forAreaAndBand(a.area, r.band))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              prog.skillsAchieved.containsKey(sk.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: prog.skillsAchieved.containsKey(sk.id) ? pal.correcto : pal.bordeFuerte,
                              semanticLabel: prog.skillsAchieved.containsKey(sk.id) ? 'Lograda' : 'Todavía no',
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(sk.nombre, style: TextStyle(fontSize: 14, color: pal.tinta))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Fichas para el adulto', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Qué trabaja cada juego, cómo seguirlo sin pantalla y qué preguntar después.', style: TextStyle(color: pal.tintaSuave)),
          const SizedBox(height: 8),
          for (final GameDef g in GameRegistry.forBand(r.band))
            ExpansionTile(
              leading: EmojiImage(g.emoji, size: 32),
              title: Text(g.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(g.roundBased ? (SkillCatalog.byId(g.skillFor(r.band) ?? '')?.nombre ?? g.area.nombre) : 'Juego libre, sin evaluación'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(g.descripcion),
                const SizedBox(height: 6),
                Text('En casa: ${g.enCasa}', style: TextStyle(color: pal.tintaSuave)),
                const SizedBox(height: 6),
                Text('Pregúntale: ${g.pregunta}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
          const SizedBox(height: 20),
          Text(S.ultimasSesiones, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (r.sesionesRecientes.isEmpty) Text(S.sinSesiones, style: TextStyle(color: pal.tintaSuave)),
          for (final SessionLog ses in r.sesionesRecientes.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(fechaHora(ses.start)),
              subtitle: Text('${S.minutos((ses.seconds / 60).round())} · ${ses.rounds} ${ses.rounds == 1 ? 'ronda' : 'rondas'} · ${ses.correct} al primer intento'),
            ),
          const SizedBox(height: 16),
          Builder(
            builder: (BuildContext buttonContext) => FilledButton.icon(
              key: const ValueKey<String>('informe-pdf'),
              onPressed: _exporting ? null : () => _pdf(buttonContext, r),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text(S.informePdf),
            ),
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
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.tinta)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: pal.tintaSuave)),
        ],
      ),
    );
  }
}
