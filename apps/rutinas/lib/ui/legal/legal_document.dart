// Política de privacidad dentro de la app. El original está en
// tools/shared/dart/legal_document.dart y cada app tiene una copia idéntica en
// lib/ui/legal/legal_document.dart (tools/store/check_metadata.py lo verifica).
// El texto sale de assets/legal/privacy_<es|en>.md, el mismo archivo que se
// publica en el repositorio y que enlazan las fichas de las tiendas.
import 'package:flutter/material.dart';

/// Tipos de bloque del Markdown reducido de los textos legales.
enum LegalBlockKind { title, heading, paragraph, bullet }

/// Un bloque del documento: título (`# `), sección (`## `), viñeta (`- `) o
/// párrafo. El texto puede llevar `**negrita**`.
class LegalBlock {
  const LegalBlock(this.kind, this.text);

  final LegalBlockKind kind;
  final String text;
}

/// Convierte el Markdown reducido en bloques. Las líneas seguidas forman un
/// solo párrafo (o continúan la viñeta anterior) y una línea en blanco cierra
/// el bloque.
List<LegalBlock> parseLegalMarkdown(String source) {
  final List<LegalBlock> out = <LegalBlock>[];
  final StringBuffer buffer = StringBuffer();
  LegalBlockKind? open;

  void flush() {
    if (open != null && buffer.isNotEmpty) {
      out.add(LegalBlock(open!, buffer.toString()));
    }
    buffer.clear();
    open = null;
  }

  for (final String raw in source.replaceAll('\r\n', '\n').split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('# ')) {
      flush();
      out.add(LegalBlock(LegalBlockKind.title, line.substring(2).trim()));
    } else if (line.startsWith('## ')) {
      flush();
      out.add(LegalBlock(LegalBlockKind.heading, line.substring(3).trim()));
    } else if (line.startsWith('- ')) {
      flush();
      open = LegalBlockKind.bullet;
      buffer.write(line.substring(2).trim());
    } else {
      if (open == null) {
        open = LegalBlockKind.paragraph;
      } else {
        buffer.write(' ');
      }
      buffer.write(line);
    }
  }
  flush();
  return out;
}

/// Trozos de texto con la negrita aplicada a lo que va entre `**`.
List<TextSpan> legalSpans(String text, TextStyle bold) {
  final List<TextSpan> spans = <TextSpan>[];
  final List<String> parts = text.split('**');
  for (int i = 0; i < parts.length; i++) {
    if (parts[i].isNotEmpty) {
      spans.add(TextSpan(text: parts[i], style: i.isOdd ? bold : null));
    }
  }
  return spans;
}

/// Ruta del asset de la política en el idioma pedido.
String privacyAsset({required bool spanish}) => spanish ? 'assets/legal/privacy_es.md' : 'assets/legal/privacy_en.md';

/// Pantalla con la política de privacidad, legible y seleccionable para
/// copiar direcciones. No necesita internet.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key, required this.spanish});

  final bool spanish;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  Future<String>? _text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text ??= DefaultAssetBundle.of(context).loadString(privacyAsset(spanish: widget.spanish));
  }

  @override
  Widget build(BuildContext context) {
    final bool es = widget.spanish;
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Política de privacidad' : 'Privacy policy')),
      body: FutureBuilder<String>(
        future: _text,
        builder: (BuildContext context, AsyncSnapshot<String> snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  es
                      ? 'No se pudo abrir la política. También está en github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis.'
                      : 'The policy could not be opened. It is also at github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _LegalBody(blocks: parseLegalMarkdown(snap.data!));
        },
      ),
    );
  }
}

class _LegalBody extends StatelessWidget {
  const _LegalBody({required this.blocks});

  final List<LegalBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme tt = theme.textTheme;
    final TextStyle body = (tt.bodyLarge ?? const TextStyle(fontSize: 16)).copyWith(height: 1.45);
    final TextStyle bold = body.copyWith(fontWeight: FontWeight.w700);
    final List<Widget> children = <Widget>[];
    for (final LegalBlock b in blocks) {
      if (b.kind == LegalBlockKind.title) {
        children.add(Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(b.text, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ));
      } else if (b.kind == LegalBlockKind.heading) {
        children.add(Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(b.text, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
          ),
        ));
      } else if (b.kind == LegalBlockKind.bullet) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(child: Text('•  ', style: bold)),
              Expanded(child: Text.rich(TextSpan(style: body, children: legalSpans(b.text, bold)))),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(TextSpan(style: body, children: legalSpans(b.text, bold))),
        ));
      }
    }
    return SelectionArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: children,
          ),
        ),
      ),
    );
  }
}
