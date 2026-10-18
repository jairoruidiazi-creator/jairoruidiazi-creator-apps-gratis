import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../audio/tuner.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../music/instruments.dart';
import '../../music/notes.dart';
import '../widgets/adaptive.dart';
import 'tuner_settings_sheet.dart';

/// Nombre de nota para el lector de pantalla ("Do sostenido", "Si bemol").
String spokenNoteName(String name, {required bool spanish}) {
  return name.replaceAll('♯', spanish ? ' sostenido' : ' sharp').replaceAll('♭', spanish ? ' bemol' : ' flat');
}

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key, this.active = true});

  /// Si la pestaña está a la vista (el micrófono lo maneja HomeShell).
  final bool active;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  /// Texto de la región en vivo: cambia al cambiar de nota o al entrar o
  /// salir de "afinado", como mucho una vez por segundo.
  String _announcement = '';
  DateTime _lastAnnounce = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _announceTimer;
  String _wanted = '';

  static const Duration announceEvery = Duration(milliseconds: 1100);

  @override
  void dispose() {
    _announceTimer?.cancel();
    super.dispose();
  }

  String _statusText(BuildContext context, Tuner tuner) {
    switch (tuner.status) {
      case MicStatus.listening:
        return t(context, 'Toca una nota', 'Play a note');
      case MicStatus.off:
        // Con la pestaña a la vista y el botón encendido, "apagado" solo dura
        // lo que tarda en abrirse el micrófono: no se anuncia.
        return tuner.userEnabled && tuner.active ? t(context, 'Toca una nota', 'Play a note') : t(context, 'Micrófono apagado', 'Microphone off');
      case MicStatus.needsPermission:
        return t(context, 'Falta el permiso de micrófono', 'Microphone permission needed');
      case MicStatus.denied:
        return t(context, 'Sin permiso de micrófono', 'Microphone permission denied');
      case MicStatus.interrupted:
        return t(context, 'Micrófono en pausa por el sistema', 'Microphone paused by the system');
      case MicStatus.busy:
        return t(context, 'La grabadora está usando el micrófono', 'The recorder is using the microphone');
      case MicStatus.error:
        return t(context, 'No se pudo abrir el micrófono', 'Could not open the microphone');
    }
  }

  /// Lo que la región en vivo debería decir ahora.
  String _desiredAnnouncement(BuildContext context, Tuner tuner, PitchSettings ps, bool spanish) {
    final TunerReading? r = tuner.reading;
    if (r == null) {
      return _statusText(context, tuner);
    }
    final String name = spokenNoteName(ps.displayName(r.note.midi), spanish: spanish);
    final String state = r.inTune ? t(context, 'afinado', 'in tune') : (r.note.cents < 0 ? t(context, 'bajo', 'flat') : t(context, 'alto', 'sharp'));
    return '$name ${ps.displayOctave(r.note.midi)}, $state';
  }

  void _scheduleAnnouncement(String wanted) {
    if (wanted == _announcement) {
      _wanted = wanted;
      return;
    }
    _wanted = wanted;
    final Duration since = clock.now().difference(_lastAnnounce);
    if (since >= announceEvery) {
      _announcement = wanted;
      _lastAnnounce = clock.now();
      _announceTimer?.cancel();
      _announceTimer = null;
    } else {
      _announceTimer ??= Timer(announceEvery - since, () {
        _announceTimer = null;
        if (mounted && _wanted != _announcement) {
          setState(() {
            _announcement = _wanted;
            _lastAnnounce = clock.now();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.tuner, s.settings]),
      builder: (BuildContext context, Widget? _) => _build(context, s),
    );
  }

  Widget _build(BuildContext context, Services s) {
    final Tuner tuner = s.tuner;
    final TunerReading? r = tuner.reading;
    final PitchSettings ps = tuner.settings;
    final Instrument inst = tuner.instrument;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final bool spanish = isSpanish(context);
    final double cents = r?.note.cents ?? 0;
    final Color noteColor = r == null ? cs.onSurfaceVariant : colorForCents(pal, cents, tuner.toleranceCents);
    _scheduleAnnouncement(_desiredAnnouncement(context, tuner, ps, spanish));
    final double textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    Widget gauge(double height) => SizedBox(
          height: height,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _GaugePainter(
                cents: r == null ? null : cents,
                tolerance: tuner.toleranceCents,
                color: noteColor,
                onSurface: cs.onSurface,
                ticks: cs.onSurfaceVariant,
                ok: pal.inTune,
                locked: tuner.lockedString >= 0,
                // La escala con la tipografía del tema, no con la fuente por
                // defecto del lienzo.
                labelStyle: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );

    Widget noteBlock(double noteFont) {
      final Widget? card = _statusCard(context, s);
      if (card != null && r == null) {
        return card;
      }
      // La nota ya es grande: no se agranda más con el texto del sistema.
      final TextScaler noteScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.0);
      return Semantics(
        container: true,
        liveRegion: true,
        label: _announcement,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(r == null ? '—' : ps.displayName(r.note.midi), textScaler: noteScaler, style: TextStyle(fontSize: noteFont, fontWeight: FontWeight.w800, height: 1, color: noteColor)),
                  if (r != null)
                    Padding(
                      padding: EdgeInsets.only(top: noteFont * 0.1, left: 4),
                      child: Text('${ps.displayOctave(r.note.midi)}', textScaler: noteScaler, style: TextStyle(fontSize: noteFont * 0.34, fontWeight: FontWeight.w600, color: noteColor)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  r == null ? _statusText(context, tuner) : '${formatCents(cents)} cents · ${formatHz(r.note.hz, comma: spanish)} Hz',
                  maxLines: 1,
                  style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
                ),
              ),
              if (r != null)
                Text(
                  '${t(context, 'Meta', 'Target')}: ${formatHz(r.note.targetHz, comma: spanish)} Hz',
                  maxLines: 1,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      );
    }

    final Widget strings = inst.hasStrings
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _StringSelector(
              instrument: inst,
              settings: ps,
              locked: tuner.lockedString,
              heard: r != null && tuner.lockedString < 0 ? r.stringIndex : -1,
              onSelect: (int i) => setState(() => tuner.lockedString = tuner.lockedString == i ? -1 : i),
              spanish: spanish,
            ),
          )
        : const SizedBox.shrink();

    Widget history(double height) => SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ExcludeSemantics(
              child: CustomPaint(painter: _HistoryPainter(points: tuner.history, now: tuner.now, tolerance: tuner.toleranceCents, onSurface: cs.onSurface, line: pal.accent, ok: pal.inTune), child: const SizedBox.expand()),
            ),
          ),
        );

    final String summary =
        '${inst.name(spanish)} · ${t(context, 'La4', 'A4')} = ${formatHz(ps.a4, comma: spanish)} Hz · ${_temperamentName(ps.temperament, spanish)}${ps.transposition != 0 ? ' · ${t(context, 'transp.', 'transp.')} ${ps.transposition > 0 ? '+' : ''}${ps.transposition}' : ''}${ps.capo != 0 ? ' · capo ${ps.capo}' : ''}';
    final Widget bar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(summary, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
          IconButton(
            tooltip: tuner.userEnabled ? t(context, 'Apagar micrófono', 'Stop microphone') : t(context, 'Encender micrófono', 'Start microphone'),
            isSelected: tuner.userEnabled,
            icon: Icon(tuner.userEnabled ? Icons.mic_rounded : Icons.mic_off_rounded),
            onPressed: () => tuner.setUserEnabled(!tuner.userEnabled),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showTunerSettings(context),
            icon: const Icon(Icons.tune_rounded),
            label: Text(t(context, 'Ajustar', 'Adjust')),
          ),
        ],
      ),
    );

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final bool wide = c.maxWidth > c.maxHeight * 1.2;
      final bool tablet = !wide && isWideLayout(context);
      final double k = tablet ? 1.4 : 1.0;
      if (wide) {
        final double h = c.maxHeight;
        final double noteFont = (h * 0.16).clamp(40.0, 96.0).toDouble();
        return Row(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints lc) {
                final double noteH = noteFont + 4 + 44 * textScale;
                final double gaugeH = (lc.maxHeight - noteH - 24).clamp(60.0, lc.maxWidth / 1.7).toDouble();
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: lc.maxHeight),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: gauge(gaugeH)), noteBlock(noteFont)]),
                  ),
                );
              }),
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(children: <Widget>[const SizedBox(height: 12), strings, const SizedBox(height: 12), history(70)]),
                    ),
                  ),
                  bar,
                ],
              ),
            ),
          ],
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tablet ? 680 : double.infinity),
          child: Column(
            children: <Widget>[
              Expanded(
                child: LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
                  final double h = bc.maxHeight;
                  final double noteFont = (h * 0.14).clamp(40.0, 88.0 * k).toDouble();
                  final double historyH = (h * 0.11).clamp(36.0, 70.0 * k).toDouble();
                  final double stringsH = inst.hasStrings ? _StringSelector.heightFor(textScale) + 8 : 0;
                  final double noteH = noteFont + 4 + 44 * textScale;
                  final double gaugeH = (h - noteH - stringsH - historyH - 20).clamp(80.0, math.min(bc.maxWidth / 1.7, 300.0 * k)).toDouble();
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: h),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(height: 4 * k),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: gauge(gaugeH)),
                              noteBlock(noteFont),
                            ],
                          ),
                          strings,
                          history(historyH),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              bar,
            ],
          ),
        ),
      );
    });
  }

  /// Tarjeta en lugar de la nota cuando el micrófono no está escuchando por
  /// el permiso, la grabadora o un error.
  Widget? _statusCard(BuildContext context, Services s) {
    final Tuner tuner = s.tuner;
    final ColorScheme cs = Theme.of(context).colorScheme;
    String? text;
    Widget? action;
    switch (tuner.status) {
      case MicStatus.needsPermission:
        text = t(context, 'Para afinar, Clave escucha el micrófono. El sonido se analiza en el teléfono y no se guarda ni se envía.', 'To tune, Clave listens to the microphone. The sound is analyzed on the phone and is never stored or sent.');
        action = FilledButton.icon(onPressed: tuner.requestPermission, icon: const Icon(Icons.mic_rounded), label: Text(t(context, 'Permitir micrófono', 'Allow microphone')));
        break;
      case MicStatus.denied:
        text = t(context, 'Sin permiso de micrófono. Puedes darlo en los ajustes del teléfono; el metrónomo, el tono y la práctica funcionan sin él.', 'No microphone permission. You can grant it in the phone settings; the metronome, drone and practice log work without it.');
        action = OutlinedButton.icon(onPressed: () => s.platform.openAppSettings(), icon: const Icon(Icons.settings_outlined), label: Text(t(context, 'Abrir ajustes', 'Open settings')));
        break;
      case MicStatus.error:
        text = t(context, 'No se pudo abrir el micrófono. Puede que otra app lo esté usando.', 'Could not open the microphone. Another app may be using it.');
        action = OutlinedButton.icon(onPressed: tuner.recheck, icon: const Icon(Icons.refresh_rounded), label: Text(t(context, 'Reintentar', 'Try again')));
        break;
      case MicStatus.busy:
        text = t(context, 'La grabadora está usando el micrófono. El afinador vuelve al terminar la toma.', 'The recorder is using the microphone. The tuner comes back when the take ends.');
        break;
      case MicStatus.listening:
      case MicStatus.off:
      case MicStatus.interrupted:
        return null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface)),
              if (action != null) ...<Widget>[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ),
    );
  }

  String _temperamentName(Temperament tmp, bool spanish) {
    switch (tmp) {
      case Temperament.equal:
        return spanish ? 'igual' : 'equal';
      case Temperament.just:
        return spanish ? 'justo' : 'just';
      case Temperament.pythagorean:
        return spanish ? 'pitagórico' : 'Pythagorean';
      case Temperament.meantone:
        return spanish ? 'mesotónico' : 'meantone';
      case Temperament.custom:
        return spanish ? 'propio' : 'custom';
    }
  }
}

/// Botones de las cuerdas (órdenes): "Auto" y uno por orden, todos de al
/// menos 48 dp. Con el capo, los nombres suben con él.
class _StringSelector extends StatelessWidget {
  const _StringSelector({required this.instrument, required this.settings, required this.locked, required this.heard, required this.onSelect, required this.spanish});

  final Instrument instrument;
  final PitchSettings settings;
  final int locked;
  final int heard;
  final ValueChanged<int> onSelect;
  final bool spanish;

  static double heightFor(double textScale) => 52 * textScale.clamp(1.0, 1.4);

  String _courseLabel(int i) => settings.displayFull(instrument.courses[i].first + settings.capo);

  String? _octaveLabel(int i) {
    final List<int> c = instrument.courses[i];
    if (c.length < 2) {
      return null;
    }
    return c.skip(1).map((int m) => settings.displayFull(m + settings.capo)).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final double height = heightFor(textScale);
    final int n = instrument.courses.length;
    final List<Widget> buttons = <Widget>[
      _StringButton(
        label: 'Auto',
        selected: locked < 0,
        heard: false,
        semantics: locked < 0 ? (spanish ? 'Detección automática de la cuerda, activa' : 'Automatic string detection, on') : (spanish ? 'Detección automática de la cuerda' : 'Automatic string detection'),
        onTap: () => onSelect(locked < 0 ? -1 : locked),
      ),
      for (int i = 0; i < n; i++)
        _StringButton(
          label: _courseLabel(i),
          sublabel: _octaveLabel(i),
          selected: locked == i,
          heard: heard == i,
          semantics: _semantics(i),
          onTap: () => onSelect(i),
        ),
    ];
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      const double gap = 4;
      final double each = (c.maxWidth - gap * (buttons.length - 1)) / buttons.length;
      if (each >= 48) {
        return SizedBox(
          height: height,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < buttons.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: buttons[i]),
              ],
            ],
          ),
        );
      }
      return SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: buttons.length,
          separatorBuilder: (BuildContext context, int i) => const SizedBox(width: gap),
          itemBuilder: (BuildContext context, int i) => SizedBox(width: 56, child: buttons[i]),
        ),
      );
    });
  }

  String _semantics(int i) {
    final String number = spanish ? 'Cuerda ${instrument.courses.length - i}' : 'String ${instrument.courses.length - i}';
    final List<int> c = instrument.courses[i];
    final String notes = c.map((int m) => spokenNoteName(settings.displayFull(m + settings.capo), spanish: spanish)).join(spanish ? ' y ' : ' and ');
    final String state = locked == i ? (spanish ? ', fijada' : ', locked') : (heard == i ? (spanish ? ', es la que suena' : ', is the one sounding') : '');
    return '$number: $notes$state';
  }
}

class _StringButton extends StatelessWidget {
  const _StringButton({required this.label, required this.selected, required this.heard, required this.semantics, required this.onTap, this.sublabel});

  final String label;
  final String? sublabel;
  final bool selected;
  final bool heard;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final Color fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    // La semántica reemplaza la de los hijos: el toque va aquí también, para
    // que el lector de pantalla pueda activar el botón.
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? cs.primary : (heard ? pal.inTune : cs.outlineVariant), width: selected || heard ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                    if (sublabel != null) Text(sublabel!, maxLines: 1, style: TextStyle(fontSize: 11, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                    if (heard) Icon(Icons.hearing_rounded, size: 12, color: pal.inTune),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Arco de -50 a +50 cents (o ±200 con cuerda fijada) con aguja. Se ajusta
/// al alto disponible.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.cents, required this.tolerance, required this.color, required this.onSurface, required this.ticks, required this.ok, required this.locked, required this.labelStyle});

  final double? cents;
  final double tolerance;
  final Color color;
  final Color onSurface;
  final Color ticks;
  final Color ok;
  final bool locked;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final double range = locked ? 200 : 50;
    final double radius = math.max(20.0, math.min(size.width / 2 - 8, size.height * 0.9));
    final Offset center = Offset(size.width / 2, math.min(size.height * 0.95, radius / 0.9 * 0.95));
    final double stroke = (radius * 0.09).clamp(6.0, 14.0).toDouble();
    const double startA = math.pi * 1.12;
    const double sweep = math.pi * 0.76;
    final Rect arc = Rect.fromCircle(center: center, radius: radius);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = onSurface.withValues(alpha: 0.12);
    canvas.drawArc(arc, startA, sweep, false, track);
    // Zona afinada.
    final double tolFrac = (tolerance / range).clamp(0.0, 0.5);
    final Paint zone = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = ok.withValues(alpha: 0.45);
    canvas.drawArc(arc, startA + sweep * (0.5 - tolFrac), sweep * tolFrac * 2, false, zone);
    // Marcas.
    final Paint tick = Paint()
      ..color = ticks
      ..strokeWidth = 2;
    final int steps = locked ? 8 : 10;
    final bool labels = radius > 70;
    for (int i = 0; i <= steps; i++) {
      final double a = startA + sweep * i / steps;
      final bool major = i % (steps ~/ 2) == 0 || i == 0 || i == steps;
      final Offset p1 = center + Offset(math.cos(a), math.sin(a)) * (radius - stroke);
      final Offset p2 = center + Offset(math.cos(a), math.sin(a)) * (radius - stroke - (major ? radius * 0.14 : radius * 0.08));
      canvas.drawLine(p1, p2, tick);
      final double value = -range + range * 2 * i / steps;
      // El cero no lleva número: la aguja afinada lo taparía, y ya lo marcan
      // la franja verde y la marca larga del centro.
      if (major && labels && value != 0) {
        final TextPainter tp = TextPainter(
          text: TextSpan(text: '${value > 0 ? '+' : '−'}${value.abs().toInt()}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final Offset pos = center + Offset(math.cos(a), math.sin(a)) * (radius - stroke - radius * 0.28);
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
    // Aguja.
    final double? c = cents;
    if (c != null) {
      final double frac = ((c + range) / (2 * range)).clamp(0.0, 1.0);
      final double a = startA + sweep * frac;
      final Offset tip = center + Offset(math.cos(a), math.sin(a)) * (radius - 4);
      final Paint needle = Paint()
        ..color = color
        ..strokeWidth = math.max(3.0, stroke * 0.4)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, tip, needle);
    }
    canvas.drawCircle(center, math.max(5.0, stroke * 0.65), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.cents != cents || old.color != color || old.locked != locked || old.tolerance != tolerance || old.ticks != ticks || old.labelStyle != labelStyle;
}

/// Historial de cents de los últimos segundos.
class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.points, required this.now, required this.tolerance, required this.onSurface, required this.line, required this.ok});

  final List<CentsPoint> points;
  final double now;
  final double tolerance;
  final Color onSurface;
  final Color line;
  final Color ok;

  @override
  void paint(Canvas canvas, Size size) {
    const double window = 6;
    final double mid = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, mid - size.height * tolerance / 100, size.width, size.height * tolerance / 50), Paint()..color = ok.withValues(alpha: 0.18));
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = onSurface.withValues(alpha: 0.25));
    if (points.length < 2) {
      return;
    }
    final Path p = Path();
    bool started = false;
    double? lastT;
    for (final CentsPoint pt in points) {
      final double x = size.width * (1 - (now - pt.t) / window);
      final double y = mid - (pt.cents.clamp(-50.0, 50.0) / 50) * mid;
      if (!started || (lastT != null && pt.t - lastT > 0.5)) {
        p.moveTo(x, y);
        started = true;
      } else {
        p.lineTo(x, y);
      }
      lastT = pt.t;
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter old) => true;
}
