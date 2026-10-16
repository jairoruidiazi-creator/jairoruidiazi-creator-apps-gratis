import 'package:flutter/material.dart';

import '../../model/money.dart';

/// Calculadora de la entrada rápida: suma, resta, multiplica y divide al
/// anotar. Trabaja con texto de números y evalúa de izquierda a derecha.
class Calc {
  Calc({int? initialMinor}) {
    if (initialMinor != null && initialMinor != 0) {
      _current = _fromMinor(initialMinor);
    }
  }

  String _current = '';
  double? _acc;
  String? _op;
  bool _fresh = false;

  /// Texto que se está escribiendo ("12.500,5").
  String get currentText => _current;

  /// Expresión visible: "12.500 + 3.000".
  String get expression {
    final String cur = _current.isEmpty ? (_fresh && _acc != null ? _fmt(_acc!) : '') : _group(_current);
    if (_acc != null && _op != null) {
      return '${_fmt(_acc!)} $_op ${_fresh ? '' : cur}'.trimRight();
    }
    return cur;
  }

  bool get hasPendingOp => _op != null;

  /// Valor actual en centavos (lo escrito, o el acumulado si no hay nada escrito).
  int get valueMinor {
    final double v = _current.isEmpty ? (_acc ?? 0) : _parse(_current);
    return (v * 100).round();
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

  void _applyPending() {
    final double? a = _acc;
    final String? op = _op;
    if (_current.isEmpty) {
      return;
    }
    final double b = _parse(_current);
    if (a == null || op == null) {
      _acc = b;
    } else {
      switch (op) {
        case '+':
          _acc = a + b;
          break;
        case '−':
          _acc = a - b;
          break;
        case '×':
          _acc = a * b;
          break;
        case '÷':
          _acc = b == 0 ? a : a / b;
          break;
      }
    }
    _current = '';
  }

  static double _parse(String s) => double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  static String _fromMinor(int minor) {
    final int a = minor.abs();
    final int cents = a % 100;
    return cents == 0 ? '${minor < 0 ? '-' : ''}${a ~/ 100}' : '${minor < 0 ? '-' : ''}${a ~/ 100},${cents.toString().padLeft(2, '0')}';
  }

  static String _fmt(double v) => _group(_fromMinor((v * 100).round()));

  static String _group(String raw) {
    final bool neg = raw.startsWith('-');
    final String s = neg ? raw.substring(1) : raw;
    final List<String> parts = s.split(',');
    final String intPart = parts.first.isEmpty ? '0' : Money.groupThousands(int.tryParse(parts.first) ?? 0);
    return '${neg ? '−' : ''}$intPart${parts.length > 1 ? ',${parts[1]}' : ''}';
  }
}

/// Teclado numérico con operaciones.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, required this.onDone, this.doneLabel = 'Listo', this.showDecimal = true});

  final ValueChanged<String> onKey;
  final VoidCallback onDone;
  final String doneLabel;
  final bool showDecimal;

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
              child: SizedBox(
                height: 48,
                child: Center(
                  child: k == '⌫'
                      ? Icon(Icons.backspace_outlined, color: cs.onSurface)
                      : Text(k, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: disabled ? cs.onSurface.withValues(alpha: 0.3) : (op ? cs.onSecondaryContainer : cs.onSurface))),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
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
    );
  }
}
