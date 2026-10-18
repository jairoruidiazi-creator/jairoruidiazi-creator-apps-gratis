import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/app_info.dart';
import 'package:rutinas/ui/legal/legal_document.dart';

const List<String> _mesesEs = <String>['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const List<String> _monthsEn = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

List<LegalBlock> _blocks(bool spanish) => parseLegalMarkdown(File(privacyAsset(spanish: spanish)).readAsStringSync());

DateTime _effective(bool spanish) {
  final String line = _blocks(spanish)[1].text;
  if (spanish) {
    final RegExpMatch m = RegExp(r'^Vigente desde el (\d{1,2}) de ([a-z]+) de (\d{4})\.$').firstMatch(line)!;
    return DateTime(int.parse(m.group(3)!), _mesesEs.indexOf(m.group(2)!) + 1, int.parse(m.group(1)!));
  }
  final RegExpMatch m = RegExp(r'^Effective ([A-Z][a-z]+) (\d{1,2}), (\d{4})\.$').firstMatch(line)!;
  return DateTime(int.parse(m.group(3)!), _monthsEn.indexOf(m.group(1)!) + 1, int.parse(m.group(2)!));
}

void main() {
  test('el Markdown reducido se convierte en bloques', () {
    final List<LegalBlock> b = parseLegalMarkdown('# Título\n\nUno\ndos.\n\n## Sección\n\n- **Hábitos.** Se guardan\n  en el teléfono.\n- Otra\n\nFin.\n');
    expect(b.map((LegalBlock x) => x.kind).toList(), <LegalBlockKind>[LegalBlockKind.title, LegalBlockKind.paragraph, LegalBlockKind.heading, LegalBlockKind.bullet, LegalBlockKind.bullet, LegalBlockKind.paragraph]);
    expect(b[1].text, 'Uno dos.');
    expect(b[3].text, '**Hábitos.** Se guardan en el teléfono.');
    final List<TextSpan> spans = legalSpans(b[3].text, const TextStyle(fontWeight: FontWeight.w700));
    expect(spans.map((TextSpan s) => s.text).toList(), <String>['Hábitos.', ' Se guardan en el teléfono.']);
    expect(spans.first.style?.fontWeight, FontWeight.w700);
    expect(spans.last.style, isNull);
  });

  for (final bool spanish in <bool>[true, false]) {
    final String lang = spanish ? 'es' : 'en';
    test('la política ($lang) está completa y solo usa la sintaxis que la app dibuja', () {
      final String src = File(privacyAsset(spanish: spanish)).readAsStringSync();
      final List<LegalBlock> blocks = _blocks(spanish);
      expect(blocks.first.kind, LegalBlockKind.title);
      expect(blocks.first.text, contains(kAppName));
      expect(blocks.where((LegalBlock b) => b.kind == LegalBlockKind.title), hasLength(1));
      expect(_effective(spanish).year, greaterThanOrEqualTo(2026));
      final List<String> headings = blocks.where((LegalBlock b) => b.kind == LegalBlockKind.heading).map((LegalBlock b) => b.text).toList();
      expect(headings.length, greaterThanOrEqualTo(8));
      expect(headings.last, spanish ? 'Contacto' : 'Contact');
      for (final LegalBlock b in blocks) {
        expect('**'.allMatches(b.text).length.isEven, isTrue, reason: b.text);
        expect(RegExp(r'[\[\]`|<>]|(^|\s)#|\*\*\s*\*\*').hasMatch(b.text), isFalse, reason: b.text);
        expect(b.text.replaceAll('**', '').contains('*'), isFalse, reason: b.text);
      }
      expect(RegExp(r'\bTODO\b|\bTBD\b|XXX').hasMatch(src), isFalse);
      expect(RegExp(r'lorem ipsum|ejemplo\.com|example\.com', caseSensitive: false).hasMatch(src), isFalse);
      // El contacto, también el privado, va por la página de soporte; sin correos.
      expect(blocks.last.text, contains('github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md'));
      expect(src.contains('@'), isFalse);
      // La app no se conecta a internet ni tiene permiso para hacerlo.
      expect(src, contains(spanish ? 'no se conecta a internet' : 'does not connect to the internet'));
    });
  }

  test('las dos versiones tienen la misma fecha y la misma estructura', () {
    expect(_effective(true), _effective(false));
    final List<LegalBlock> es = _blocks(true);
    final List<LegalBlock> en = _blocks(false);
    expect(en.map((LegalBlock b) => b.kind).toList(), es.map((LegalBlock b) => b.kind).toList());
  });

  testWidgets('la pantalla muestra la política de principio a fin', (WidgetTester tester) async {
    for (final bool spanish in <bool>[true, false]) {
      await tester.pumpWidget(MaterialApp(key: ValueKey<bool>(spanish), home: PrivacyPolicyScreen(spanish: spanish)));
      await tester.pump();
      await tester.pump();
      final List<LegalBlock> blocks = _blocks(spanish);
      expect(find.text(spanish ? 'Política de privacidad' : 'Privacy policy'), findsOneWidget);
      expect(find.text(blocks.first.text), findsOneWidget);
      final String last = blocks.where((LegalBlock b) => b.kind == LegalBlockKind.heading).last.text;
      await tester.scrollUntilVisible(find.text(last), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text(last), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
