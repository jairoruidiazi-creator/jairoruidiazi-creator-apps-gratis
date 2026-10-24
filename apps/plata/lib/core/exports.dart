import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/models.dart';
import 'ledger.dart';

/// CSV, XLSX y respaldos, generados en el teléfono.
class Exports {
  Exports._();

  static String _cell(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') || s.contains(';')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Columnas de texto libre del CSV (cuentas, categorías, descripción,
  /// beneficiario, etiquetas y notas). Pueden venir de avisos de otras apps.
  static const Set<int> _textColumns = <int>{2, 3, 4, 5, 6, 7, 11, 12};

  /// Una celda que empieza por = + - @, tabulador o retorno se abre en Excel
  /// o en Hojas de cálculo como fórmula: se le antepone un apóstrofo para que
  /// quede como texto (recomendación de OWASP contra la inyección en CSV).
  static String _safeText(String s) {
    if (s.isEmpty) {
      return s;
    }
    final String first = s[0];
    if (first == '=' || first == '+' || first == '-' || first == '@' || first == '\t' || first == '\r') {
      return "'$s";
    }
    return s;
  }

  static List<String> headers({bool spanish = true}) => spanish
      ? <String>['fecha', 'tipo', 'cuenta', 'cuenta_destino', 'categoria', 'subcategoria', 'descripcion', 'beneficiario', 'monto', 'moneda', 'monto_base', 'etiquetas', 'notas', 'cuotas', 'conciliado', 'origen', 'id']
      : <String>['date', 'type', 'account', 'to_account', 'category', 'subcategory', 'description', 'payee', 'amount', 'currency', 'amount_base', 'tags', 'notes', 'installments', 'reconciled', 'source', 'id'];

  /// Filas (sin encabezado) de los movimientos. Las divididas van en una fila por parte.
  static List<List<String>> rows(Ledger l, List<Tx> txs, {bool spanish = true}) {
    final List<List<String>> out = <List<String>>[];
    String kindName(TxKind k) {
      switch (k) {
        case TxKind.expense:
          return spanish ? 'gasto' : 'expense';
        case TxKind.income:
          return spanish ? 'ingreso' : 'income';
        case TxKind.transfer:
          return spanish ? 'transferencia' : 'transfer';
      }
    }

    for (final Tx t in txs) {
      final List<List<String>> parts = <List<String>>[];
      if (t.splits.isNotEmpty) {
        for (final TxSplit s in t.splits) {
          parts.add(<String>[s.categoryId, s.amountMinor.toString(), s.note]);
        }
      } else {
        parts.add(<String>[t.categoryId ?? '', t.amountMinor.toString(), '']);
      }
      for (final List<String> p in parts) {
        final Category? c = l.category(p[0]);
        final Category? parent = c == null ? null : l.category(c.parentId);
        final int amount = int.parse(p[1]);
        final int signed = t.kind == TxKind.expense ? -amount : amount;
        out.add(<String>[
          formatDate(t.date, 'yyyy-MM-dd HH:mm'),
          kindName(t.kind),
          l.account(t.accountId)?.name ?? '',
          l.account(t.toAccountId)?.name ?? '',
          parent?.name ?? c?.name ?? '',
          parent == null ? '' : (c?.name ?? ''),
          Ledger.shownDescription(t, spanish: spanish),
          t.payee,
          _decimal(signed),
          t.currency,
          _decimal(t.kind == TxKind.expense ? -l.toBase(amount, t.currency, rate: t.rateToBase) : l.toBase(amount, t.currency, rate: t.rateToBase)),
          t.tags.join(' '),
          p[2].isNotEmpty ? '${t.notes} ${p[2]}'.trim() : t.notes,
          t.installments.toString(),
          t.reconciled ? (spanish ? 'sí' : 'yes') : (spanish ? 'no' : 'no'),
          t.source,
          t.id,
        ]);
      }
    }
    return out;
  }

  /// Centavos → "1234.50" (punto decimal, para hojas de cálculo).
  static String _decimal(int minor) {
    final bool neg = minor < 0;
    final int a = minor.abs();
    return '${neg ? '-' : ''}${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }

  static String csv(Ledger l, List<Tx> txs, {bool spanish = true}) {
    final StringBuffer b = StringBuffer();
    b.writeln(headers(spanish: spanish).join(','));
    for (final List<String> r in rows(l, txs, spanish: spanish)) {
      final List<String> cells = <String>[];
      for (int i = 0; i < r.length; i++) {
        cells.add(_cell(_textColumns.contains(i) ? _safeText(r[i]) : r[i]));
      }
      b.writeln(cells.join(','));
    }
    return b.toString();
  }

  /// CSV en UTF-8 con BOM (Excel lo abre con tildes correctas).
  static Uint8List csvBytes(Ledger l, List<Tx> txs, {bool spanish = true}) => Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv(l, txs, spanish: spanish))]);

  /// Libro de Excel con dos hojas: movimientos y saldos de cuentas.
  static Uint8List xlsx(Ledger l, List<Tx> txs, {bool spanish = true}) {
    final List<List<Object?>> sheet1 = <List<Object?>>[headers(spanish: spanish)];
    for (final List<String> r in rows(l, txs, spanish: spanish)) {
      sheet1.add(<Object?>[r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], double.parse(r[8]), r[9], double.parse(r[10]), r[11], r[12], int.parse(r[13]), r[14], r[15], r[16]]);
    }
    final List<List<Object?>> sheet2 = <List<Object?>>[
      spanish ? <String>['cuenta', 'tipo', 'moneda', 'saldo', 'saldo_base'] : <String>['account', 'type', 'currency', 'balance', 'balance_base'],
      for (final Account a in l.activeAccounts) <Object?>[a.name, a.type.name, a.currency, l.balanceMinor(a.id) / 100, l.toBase(l.balanceMinor(a.id), a.currency) / 100],
    ];
    return XlsxWriter.build(<XlsxSheet>[XlsxSheet(spanish ? 'Movimientos' : 'Transactions', sheet1), XlsxSheet(spanish ? 'Cuentas' : 'Accounts', sheet2)]);
  }

  /// Respaldo en JSON (sin cifrar) del libro completo.
  static String backupJson(Ledger l) => const JsonEncoder.withIndent(' ').convert(l.toJson());
}

class XlsxSheet {
  const XlsxSheet(this.name, this.rows);

  final String name;
  final List<List<Object?>> rows;
}

/// Escritor mínimo de XLSX (Office Open XML) sin dependencias: cadenas en
/// línea, números como números y la primera fila en negrita.
class XlsxWriter {
  XlsxWriter._();

  static Uint8List build(List<XlsxSheet> sheets) {
    final Archive a = Archive();
    void add(String name, String content) {
      final List<int> bytes = utf8.encode(content);
      a.addFile(ArchiveFile.bytes(name, bytes));
    }

    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${List<String>.generate(sheets.length, (int i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}'
        '</Types>');
    add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>${List<String>.generate(sheets.length, (int i) => '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}</sheets>'
        '</workbook>');
    add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${List<String>.generate(sheets.length, (int i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    add('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
        '</styleSheet>');
    for (int i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  static String _sheetXml(XlsxSheet sheet) {
    final StringBuffer b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    b.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (int r = 0; r < sheet.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final List<Object?> row = sheet.rows[r];
      for (int c = 0; c < row.length; c++) {
        final String ref = '${columnName(c)}${r + 1}';
        final Object? v = row[c];
        if (v == null) {
          continue;
        }
        if (v is num) {
          b.write('<c r="$ref" s="${v is double ? 2 : 0}"><v>$v</v></c>');
        } else if (v is bool) {
          b.write('<c r="$ref" t="b"><v>${v ? 1 : 0}</v></c>');
        } else {
          b.write('<c r="$ref" t="inlineStr"${r == 0 ? ' s="1"' : ''}><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  /// 0 → A, 25 → Z, 26 → AA.
  static String columnName(int index) {
    String s = '';
    int i = index;
    while (true) {
      s = String.fromCharCode(65 + i % 26) + s;
      i = i ~/ 26 - 1;
      if (i < 0) {
        break;
      }
    }
    return s;
  }

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
}
