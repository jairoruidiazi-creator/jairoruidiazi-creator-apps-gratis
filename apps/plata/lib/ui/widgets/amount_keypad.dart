import 'package:flutter/material.dart';

import '../../model/money.dart';

/// Calculadora de la entrada rápida: suma, resta, multiplica y divide al
/// anotar. Trabaja con texto de números y evalúa de izquierda a derecha.
///
/// [valueMinor] es siempre el resultado de lo que se ve, aunque no se haya
/// pulsado "=": "50.000 + 20.000" vale 70.000 y "120.000 ÷ 3", 40.000.
class Calc {
  Calc({int? initialMinor, this.spanish = true}) {
    if (initialMinor != null && initialMinor != 0) {
      _current = _fromMinor(initialMinor);
    }
  }

  /// Idioma de la expresión visible (separadores de miles y decimales). Por
  /// dentro el número siempre usa coma decimal.
  bool spanish;

  String _current = '';
  double? _acc;
  String? _op;
  bool _fresh = false;

  /// Texto que se está escribiendo ("12500,5").
  String get currentText => _current;

  /// Expresión visible: "12.500 + 3.000" (o "12,500 + 3,000" en inglés).
  String get expression {
    final String cur = _current.isEmpty ? (_fresh && _acc != null ? _fmt(_acc!) : '') : _group(_current);
    if (_acc != null && _op != null) {
      return '${_fmt(_acc!)} $_op ${_fresh ? '' : cur}'.trimRight();
    }
    return cur;
  }

  bool get hasPendingOp => _op != null;

  /// Valor en centavos de lo que se ve: con una operación a medias, su
  /// resultado ("50.000 + 20.000" = 70.000); con el operador recién puesto y
  /// sin segundo número ("50.000 +"), el primero.
  int get valueMinor {
    double v;
    final double? a = _acc;
    final String? op = _op;
    if (a != null && op != null) {
      v = _current.isEmpty ? a : _apply(a, op, _parse(_current));
    } else {
      v = _current.isEmpty ? (a ?? 0) : _parse(_current);
    }
    return (v * 100).round();
  }

  /// Resuelve la operación pendiente (como pulsar "=").
  void evaluate() {
    if (_op != null) {
      press('=');
    }
  }

  void press(String key) {
    switch (key) {
      case 'C':
        _current = '';
        _acc = null;
        _op = null;
        _fresh = false;
        return;
      case '⌫':
        if (_current.isNotEmpty) {
          _current = _current.substring(0, _current.length - 1);
        } else if (_op != null) {
          _op = null;
          _current = _acc == null ? '' : _fromMinor((_acc! * 100).round());
          _acc = null;
        }
        return;
      case '+':
      case '−':
      case '×':
      case '÷':
        _applyPending();
        _op = key;
        _fresh = true;
        return;
      case '=':
        _applyPending();
        _op = null;
        _fresh = true;
        _current = _acc == null ? '' : _fromMinor((_acc! * 100).round());
        _acc = null;
        return;
      case ',':
      case '.':
        if (_fresh) {
          _current = '';
          _fresh = false;
        }
        if (!_current.contains(',')) {
          _current = _current.isEmpty ? '0,' : '$_current,';
        }
        return;
      default:
        if (RegExp(r'^\d$').hasMatch(key)) {
          if (_fresh) {
            _current = '';
            _fresh = false;
          }
          if (_current == '0') {
            _current = key;
          } else if (_current.contains(',') && _current.split(',').last.length >= 2) {
            return;
          } else if (_current.length < 15) {
            _current = '$_current$key';
          }
        }
    }
  }

  static double _apply(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? a : a / b;
    }
    return b;
  }

  void _applyPending() {
    final double? a = _acc;
    final String? op = _op;
    if (_current.isEmpty) {
      return;
    }
    final double b = _parse(_current);
    _acc = a == null || op == null ? b : _apply(a, op, b);
    _current = '';
  }

  static double _parse(String s) => double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  static String _fromMinor(int minor) {
    final int a = minor.abs();
    final int cents = a % 100;
    return cents == 0 ? '${minor < 0 ? '-' : ''}${a ~/ 100}' : '${minor < 0 ? '-' : ''}${a ~/ 100},${cents.toString().padLeft(2, '0')}';
  }

  String _fmt(double v) => _group(_fromMinor((v * 100).round()));

  String _group(String raw) {
    final bool neg = raw.startsWith('-');
    final String s = neg ? raw.substring(1) : raw;
    final List<String> parts = s.split(',');
    final String intPart = parts.first.isEmpty ? '0' : Money.groupThousands(int.tryParse(parts.first) ?? 0, separator: spanish ? '.' : ',');
    return '${neg ? '−' : ''}$intPart${parts.length > 1 ? '${spanish ? ',' : '.'}${parts[1]}' : ''}';
  }
}

/// Teclado numérico con operaciones.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, required this.onDone, this.doneLabel = 'Listo', this.deleteLabel = 'Borrar', this.showDecimal = true, this.spanish = true});

  final ValueChanged<String> onKey;
  final VoidCallback onDone;
  final String doneLabel;

  /// Nombre de la tecla de borrar para TalkBack y VoiceOver.
  final String deleteLabel;
  final bool showDecimal;

  /// La tecla decimal muestra coma en español y punto en inglés.
  final bool spanish;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    const List<List<String>> rows = <List<String>>[
      <String>['7', '8', '9', '÷'],
      <String>['4', '5', '6', '×'],
      <String>['1', '2', '3', '−'],
      <String>[',', '0', '⌫', '+'],
    ];
    Widget key(String k) {
      final bool op = '÷×−+'.contains(k);
      final bool disabled = k == ',' && !showDecimal;
      final String label = k == ',' ? (spanish ? ',' : '.') : k;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: op ? cs.secondaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: disabled ? null : () => onKey(k),
              onLongPress: k == '⌫' ? () => onKey('C') : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: k == '⌫'
                      ? Icon(Icons.backspace_outlined, color: cs.onSurface, semanticLabel: deleteLabel)
                      : Text(label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: disabled ? cs.onSurface.withValues(alpha: 0.3) : (op ? cs.onSecondaryContainer : cs.onSurface))),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Con letra muy grande las teclas siguen cabiendo: la calculadora crece
    // hasta 1,4 veces (los números ya son grandes).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final List<String> r in rows) Row(children: r.map(key).toList()),
            Row(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: OutlinedButton(onPressed: () => onKey('='), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), child: const Text('=', style: TextStyle(fontSize: 22))),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: FilledButton(onPressed: onDone, style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), child: Text(doneLabel, style: const TextStyle(fontSize: 18))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
