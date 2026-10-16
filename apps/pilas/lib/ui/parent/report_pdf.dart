import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../model/age_band.dart';
import '../../model/area.dart';
import '../../model/progress.dart';
import '../../model/skill.dart';
import 'report_data.dart';

/// Informe PDF de un niño: tiempo, habilidades por área, juegos y sugerencias.
class ReportPdf {
  ReportPdf._();

  static Future<pw.ThemeData> _theme() async {
    final ByteData regular = await rootBundle.load('assets/fonts/Lexend-Regular.ttf');
    final ByteData bold = await rootBundle.load('assets/fonts/Lexend-Bold.ttf');
    return pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }

  static Future<Uint8List> buildChild(ChildReport r) async {
    final pw.ThemeData theme = await _theme();
    final pw.Document doc = pw.Document(theme: theme, title: 'Informe de ${r.profile.nombre}', author: 'Pilas');
    final PdfColor tinta = PdfColor.fromHex('#1F2954');
    final PdfColor suave = PdfColor.fromHex('#5B6386');
    final PdfColor borde = PdfColor.fromHex('#E8DFC8');

    pw.Widget h2(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 6), child: pw.Text(t, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: tinta)));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) => <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text('Pilas · Informe de ${r.profile.nombre}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: tinta)),
              pw.Text(fechaCorta(r.now), style: pw.TextStyle(color: suave)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('${r.profile.age} años · nivel ${r.band.label} (${r.band.schoolLabel})', style: pw.TextStyle(color: suave)),
          h2('Tiempo de juego'),
          pw.Table(
            border: pw.TableBorder.all(color: borde),
            children: <pw.TableRow>[
              _row(<String>['Hoy', 'Esta semana', 'Total', 'Sesiones', 'Rondas', 'Aciertos'], bold: true),
              _row(<String>['${r.minutosHoy} min', '${r.minutosSemana} min', '${r.minutosTotal} min', '${r.sesiones}', '${r.rondasTotal}', r.rondasTotal == 0 ? '-' : '${(r.aciertosTotal * 100 / r.rondasTotal).round()} %']),
            ],
          ),
          h2('Habilidades por área'),
          pw.Table(
            border: pw.TableBorder.all(color: borde),
            columnWidths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.5), 4: const pw.FlexColumnWidth(4)},
            children: <pw.TableRow>[
              _row(<String>['Área', 'Habilidades logradas', 'Rondas', 'Aciertos', 'Juegos y nivel'], bold: true),
              for (final AreaSummary a in r.areas)
                _row(<String>[
                  a.area.nombre,
                  '${a.skillsLogradas} de ${a.skillsPosibles}',
                  '${a.rondas}',
                  a.rondas == 0 ? '-' : '${(a.precision * 100).round()} %',
                  a.juegos.isEmpty ? 'Sin jugar todavía' : a.juegos.map((GameLevel g) => '${g.game.nombre}: nivel ${g.level} de ${g.maxLevel}').join('; '),
                ]),
            ],
          ),
          h2('Habilidades logradas'),
          if (r.habilidades.isEmpty) pw.Text('Todavía ninguna. Una habilidad se logra al dominar el último nivel de un juego en su tramo.', style: pw.TextStyle(color: suave)),
          for (final MapEntry<Skill, DateTime> e in r.habilidades)
            pw.Bullet(text: '${e.key.nombre} (${e.key.area.nombre}, ${fechaCorta(e.value)}): ${e.key.descripcion}'),
          h2('Pegatinas'),
          pw.Text('${r.progress.stickers.length} pegatinas ganadas.'),
          h2('Sugerencias para la casa'),
          for (final String s in r.sugerencias) pw.Bullet(text: s),
          h2('Últimas sesiones'),
          if (r.sesionesRecientes.isEmpty) pw.Text('Sin sesiones en los últimos 14 días.', style: pw.TextStyle(color: suave)),
          if (r.sesionesRecientes.isNotEmpty)
            pw.Table(
              border: pw.TableBorder.all(color: borde),
              children: <pw.TableRow>[
                _row(<String>['Fecha', 'Minutos', 'Rondas', 'Aciertos'], bold: true),
                for (final SessionLog s in r.sesionesRecientes.take(20))
                  _row(<String>[fechaHora(s.start), '${(s.seconds / 60).round()}', '${s.rounds}', '${s.correct}']),
              ],
            ),
          pw.SizedBox(height: 18),
          pw.Text('Pilas es gratuita, sin anuncios y sin cuenta. Los datos del niño viven solo en el dispositivo; este informe se generó allí mismo.', style: pw.TextStyle(fontSize: 9, color: suave)),
        ],
      ),
    );
    return doc.save();
  }

  static pw.TableRow _row(List<String> cells, {bool bold = false}) {
    return pw.TableRow(
      children: <pw.Widget>[
        for (final String c in cells)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.Text(c, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
      ],
    );
  }

  /// Informe de un grupo: una fila por niño.
  static Future<Uint8List> buildGroup(String nombreGrupo, List<ChildReport> reports) async {
    final pw.ThemeData theme = await _theme();
    final pw.Document doc = pw.Document(theme: theme, title: 'Informe del grupo $nombreGrupo', author: 'Pilas');
    final PdfColor tinta = PdfColor.fromHex('#1F2954');
    final PdfColor borde = PdfColor.fromHex('#E8DFC8');
    final DateTime now = DateTime.now();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context ctx) => <pw.Widget>[
          pw.Text('Pilas · Grupo $nombreGrupo · ${fechaCorta(now)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: tinta)),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: borde),
            children: <pw.TableRow>[
              _row(<String>['Niño', 'Edad', 'Min. semana', 'Rondas', 'Aciertos', 'Lógica', 'Números', 'Letras', 'Ciencias', 'Arte', 'Emociones', 'Habilidades'], bold: true),
              for (final ChildReport r in reports)
                _row(<String>[
                  r.profile.nombre,
                  '${r.profile.age}',
                  '${r.minutosSemana}',
                  '${r.rondasTotal}',
                  r.rondasTotal == 0 ? '-' : '${(r.aciertosTotal * 100 / r.rondasTotal).round()} %',
                  for (final AreaSummary a in r.areas) '${a.skillsLogradas}/${a.skillsPosibles}',
                  '${r.progress.skillsAchieved.length}',
                ]),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('Las columnas por área muestran habilidades logradas sobre las posibles en el nivel de cada niño.', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> share(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
