import 'dart:ui';

/// Convierte la cadena `d` de un path SVG en un [Path] de Flutter.
/// Soporta M, L, H, V, C, S, Q, T y Z, absolutos y relativos (sin arcos).
Path parseSvgPath(String d) {
  final Path path = Path();
  final _Tokens t = _Tokens(d);
  double cx = 0;
  double cy = 0;
  double startX = 0;
  double startY = 0;
  double lastCtrlX = 0;
  double lastCtrlY = 0;
  String lastCmd = '';
  String cmd = '';

  while (t.hasMore) {
    final String? c = t.peekCommand();
    if (c != null) {
      cmd = c;
      t.next();
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final bool rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final double x = t.number();
        final double y = t.number();
        cx = rel ? cx + x : x;
        cy = rel ? cy + y : y;
        path.moveTo(cx, cy);
        startX = cx;
        startY = cy;
        break;
      case 'L':
        final double x = t.number();
        final double y = t.number();
        cx = rel ? cx + x : x;
        cy = rel ? cy + y : y;
        path.lineTo(cx, cy);
        break;
      case 'H':
        final double x = t.number();
        cx = rel ? cx + x : x;
        path.lineTo(cx, cy);
        break;
      case 'V':
        final double y = t.number();
        cy = rel ? cy + y : y;
        path.lineTo(cx, cy);
        break;
      case 'C':
        double x1 = t.number();
        double y1 = t.number();
        double x2 = t.number();
        double y2 = t.number();
        double x = t.number();
        double y = t.number();
        if (rel) {
          x1 += cx;
          y1 += cy;
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        break;
      case 'S':
        double x2 = t.number();
        double y2 = t.number();
        double x = t.number();
        double y = t.number();
        if (rel) {
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        double x1 = cx;
        double y1 = cy;
        if (lastCmd.toUpperCase() == 'C' || lastCmd.toUpperCase() == 'S') {
          x1 = 2 * cx - lastCtrlX;
          y1 = 2 * cy - lastCtrlY;
        }
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        break;
      case 'Q':
        double x1 = t.number();
        double y1 = t.number();
        double x = t.number();
        double y = t.number();
        if (rel) {
          x1 += cx;
          y1 += cy;
          x += cx;
          y += cy;
        }
        path.quadraticBezierTo(x1, y1, x, y);
        lastCtrlX = x1;
        lastCtrlY = y1;
        cx = x;
        cy = y;
        break;
      case 'T':
        double x = t.number();
        double y = t.number();
        if (rel) {
          x += cx;
          y += cy;
        }
        double x1 = cx;
        double y1 = cy;
        if (lastCmd.toUpperCase() == 'Q' || lastCmd.toUpperCase() == 'T') {
          x1 = 2 * cx - lastCtrlX;
          y1 = 2 * cy - lastCtrlY;
        }
        path.quadraticBezierTo(x1, y1, x, y);
        lastCtrlX = x1;
        lastCtrlY = y1;
        cx = x;
        cy = y;
        break;
      case 'Z':
        path.close();
        cx = startX;
        cy = startY;
        break;
      default:
        // Comando no soportado (por ejemplo arcos): se ignoran sus números.
        while (t.hasMore && t.peekCommand() == null) {
          t.number();
        }
    }
    lastCmd = cmd;
  }
  return path;
}

class _Tokens {
  _Tokens(this.src);

  final String src;
  int pos = 0;

  static const String _cmds = 'MmLlHhVvCcSsQqTtZzAa';

  bool get hasMore {
    _skip();
    return pos < src.length;
  }

  void _skip() {
    while (pos < src.length) {
      final String ch = src[pos];
      if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t' || ch == '\r') {
        pos++;
      } else {
        break;
      }
    }
  }

  String? peekCommand() {
    _skip();
    if (pos >= src.length) {
      return null;
    }
    final String ch = src[pos];
    return _cmds.contains(ch) ? ch : null;
  }

  void next() {
    pos++;
  }

  double number() {
    _skip();
    final int start = pos;
    if (pos < src.length && (src[pos] == '-' || src[pos] == '+')) {
      pos++;
    }
    bool seenDot = false;
    bool seenExp = false;
    while (pos < src.length) {
      final String ch = src[pos];
      final int code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        pos++;
      } else if (ch == '.' && !seenDot && !seenExp) {
        seenDot = true;
        pos++;
      } else if ((ch == 'e' || ch == 'E') && !seenExp) {
        seenExp = true;
        pos++;
        if (pos < src.length && (src[pos] == '-' || src[pos] == '+')) {
          pos++;
        }
      } else {
        break;
      }
    }
    if (start == pos) {
      // Evita bucles infinitos con entradas raras.
      pos++;
      return 0;
    }
    return double.tryParse(src.substring(start, pos)) ?? 0;
  }
}
