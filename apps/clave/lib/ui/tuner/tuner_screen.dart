import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/tuner.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../music/instruments.dart';
import '../../music/notes.dart';
import '../widgets/adaptive.dart';
import 'tuner_settings_sheet.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with AutomaticKeepAliveClientMixin {
  Timer? _practiceTimer;
  bool _started = false;
  Services? _services;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final Services s = AppScope.of(context);
      _services = s;
      _sync();
      s.settings.addListener(_sync);
      s.tuner.addListener(_onReading);
      WidgetsBinding.instance.addPostFrameCallback((_) => s.tuner.start());
    }
  }

  void _sync() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    final AppSettings st = s.settings;
    s.tuner
      ..settings = st.pitch
      ..toleranceCents = st.toleranceCents
      ..damping = st.damping
      ..instrument = Instruments.byId(st.instrumentId);
    if (s.tuner.lockedString >= s.tuner.instrument.strings.length) {
      s.tuner.lockedString = -1;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onReading() {
    final Services? s = _services;
    if (!mounted || s == null) {
      return;
    }
    if (s.tuner.reading != null) {
      s.state.touchPractice('afinador', s.settings.instrumentId);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _practiceTimer?.cancel();
    _services?.settings.removeListener(_sync);
    _services?.tuner.removeListener(_onReading);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Services s = AppScope.of(context);
    final Tuner tuner = s.tuner;
    final TunerReading? r = tuner.reading;
    final PitchSettings ps = tuner.settings;
    final Instrument inst = tuner.instrument;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool spanish = s.settings.spanish;
    final double cents = r?.note.cents ?? 0;
    final Color noteColor = r == null ? cs.onSurface.withValues(alpha: 0.35) : colorForCents(cents, tuner.toleranceCents);

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final bool wide = c.maxWidth > c.maxHeight * 1.2;
      // Tableta en vertical: columna centrada y lectura más grande.
      final bool tablet = !wide && isWideLayout(context);
      final double k = tablet ? 1.4 : 1.0;
      final Widget gauge = AspectRatio(
        aspectRatio: 1.7,
        child: CustomPaint(painter: _GaugePainter(cents: r == null ? null : cents, tolerance: tuner.toleranceCents, color: noteColor, onSurface: cs.onSurface, locked: tuner.lockedString >= 0)),
      );
      final Widget note = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(r == null ? '—' : ps.displayName(r.note.midi), style: TextStyle(fontSize: 88 * k, fontWeight: FontWeight.w800, height: 1, color: noteColor)),
              if (r != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 4),
                  child: Text('${ps.displayOctave(r.note.midi)}', style: TextStyle(fontSize: 30 * k, fontWeight: FontWeight.w600, color: noteColor)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r == null
                ? (tuner.permissionDenied ? t(context, 'Sin permiso de micrófono', 'Microphone permission denied') : (tuner.listening ? t(context, 'Toca una nota', 'Play a note') : t(context, 'Micrófono apagado', 'Microphone off')))
                : '${cents >= 0 ? '+' : '−'}${cents.abs().toStringAsFixed(0)} cents · ${formatHz(r.note.hz, comma: spanish)} Hz',
            style: TextStyle(fontSize: 18, color: cs.onSurface.withValues(alpha: 0.75), fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
          ),
          if (r != null)
            Text(
              '${t(context, 'Meta', 'Target')}: ${formatHz(r.note.targetHz, comma: spanish)} Hz',
              style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.55)),
            ),
        ],
      );
      final Widget strings = inst.hasStrings
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(t(context, 'Auto', 'Auto')),
                    selected: tuner.lockedString < 0,
                    onSelected: (_) => setState(() => tuner.lockedString = -1),
                  ),
                  for (int i = 0; i < inst.strings.length; i++)
                    ChoiceChip(
                      label: Text('${i + 1} · ${ps.displayName(inst.strings[i])}${ps.displayOctave(inst.strings[i])}'),
                      selected: tuner.lockedString == i,
                      avatar: r != null && r.stringIndex == i && tuner.lockedString < 0 ? const Icon(Icons.hearing_rounded, size: 16) : null,
                      onSelected: (_) => setState(() => tuner.lockedString = tuner.lockedString == i ? -1 : i),
                    ),
                ],
              ),
            )
          : const SizedBox.shrink();
      final Widget history = SizedBox(
        height: 70 * k,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CustomPaint(painter: _HistoryPainter(points: tuner.history, now: tuner.now, tolerance: tuner.toleranceCents, onSurface: cs.onSurface), child: const SizedBox.expand()),
        ),
      );
      final Widget bar = Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${inst.name(spanish)} · La4 = ${formatHz(ps.a4, comma: spanish)} Hz · ${_temperamentName(ps.temperament, spanish)}${ps.transposition != 0 ? ' · ${t(context, 'transp.', 'transp.')} ${ps.transposition > 0 ? '+' : ''}${ps.transposition}' : ''}${ps.capo != 0 ? ' · capo ${ps.capo}' : ''}',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: tuner.listening ? t(context, 'Apagar micrófono', 'Stop microphone') : t(context, 'Encender micrófono', 'Start microphone'),
              icon: Icon(tuner.listening ? Icons.mic_rounded : Icons.mic_off_rounded),
              onPressed: () => tuner.listening ? tuner.stop() : tuner.start(),
            ),
            FilledButton.tonalIcon(
              onPressed: () => showTunerSettings(context),
              icon: const Icon(Icons.tune_rounded),
              label: Text(t(context, 'Ajustar', 'Adjust')),
            ),
          ],
        ),
      );
      if (wide) {
        return Row(
          children: <Widget>[
            Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[gauge, note]))),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[strings, history, bar])),
          ],
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tablet ? 680 : double.infinity),
          child: Column(
            children: <Widget>[
              SizedBox(height: 8 * k),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: gauge),
              note,
              SizedBox(height: 8 * k),
              strings,
              const Spacer(),
              history,
              bar,
            ],
          ),
        ),
      );
    });
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

/// Arco de -50 a +50 cents con aguja.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.cents, required this.tolerance, required this.color, required this.onSurface, required this.locked});

  final double? cents;
  final double tolerance;
  final Color color;
  final Color onSurface;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final double range = locked ? 200 : 50;
    final Offset center = Offset(size.width / 2, size.height * 0.95);
    final double radius = math.min(size.width / 2 - 8, size.height * 0.9);
    const double startA = math.pi * 1.12;
    const double sweep = math.pi * 0.76;
    final Rect arc = Rect.fromCircle(center: center, radius: radius);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = onSurface.withValues(alpha: 0.12);
    canvas.drawArc(arc, startA, sweep, false, track);
    // Zona afinada.
    final double tolFrac = (tolerance / range).clamp(0.0, 0.5);
    final Paint ok = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = ClaveColors.afinado.withValues(alpha: 0.35);
    canvas.drawArc(arc, startA + sweep * (0.5 - tolFrac), sweep * tolFrac * 2, false, ok);
    // Marcas.
    final Paint tick = Paint()
      ..color = onSurface.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    final int steps = locked ? 8 : 10;
    for (int i = 0; i <= steps; i++) {
      final double a = startA + sweep * i / steps;
      final bool major = i % (steps ~/ 2) == 0 || i == 0 || i == steps;
      final Offset p1 = center + Offset(math.cos(a), math.sin(a)) * (radius - 14);
      final Offset p2 = center + Offset(math.cos(a), math.sin(a)) * (radius - (major ? 30 : 22));
      canvas.drawLine(p1, p2, tick);
      if (major) {
        final double value = -range + range * 2 * i / steps;
        final TextPainter tp = TextPainter(
          text: TextSpan(text: value == 0 ? '0' : '${value > 0 ? '+' : ''}${value.toInt()}', style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6))),
          textDirection: TextDirection.ltr,
        )..layout();
        final Offset pos = center + Offset(math.cos(a), math.sin(a)) * (radius - 44);
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
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, tip, needle);
    }
    canvas.drawCircle(center, 9, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.cents != cents || old.color != color || old.locked != locked || old.tolerance != tolerance;
}

/// Historial de cents de los últimos segundos.
class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.points, required this.now, required this.tolerance, required this.onSurface});

  final List<CentsPoint> points;
  final double now;
  final double tolerance;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    const double window = 6;
    final double mid = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, mid - size.height * tolerance / 100, size.width, size.height * tolerance / 50), Paint()..color = ClaveColors.afinado.withValues(alpha: 0.18));
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
        ..color = ClaveColors.ambar,
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter old) => true;
}
