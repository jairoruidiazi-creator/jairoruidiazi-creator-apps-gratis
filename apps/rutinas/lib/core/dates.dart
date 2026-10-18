// Fechas como días del calendario local, sin horas. Todas las cuentas de días
// pasan por aquí para no tropezar con los cambios de horario de verano: los
// días se suman con DateTime(año, mes, día + n) y se restan en UTC.

/// El día (a medianoche local) de [d].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] más [days] días de calendario (puede ser negativo).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Días de calendario entre dos fechas (positivo si [to] es posterior).
int daysBetween(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int n) => n.toString().padLeft(2, '0');

/// Clave de un día para los mapas JSON: `2026-10-18`.
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Años que la app acepta en sus datos. Fuera de este rango una fecha viene de
/// un archivo dañado o manipulado: un inicio en el año 1 haría recorrer unos
/// 740 000 días cada vez que se dibuja la pantalla.
const int kFirstYear = 2000;
const int kLastYear = 2199;

/// ¿La fecha cae en los años que la app acepta?
bool isSaneDate(DateTime d) => d.year >= kFirstYear && d.year <= kLastYear;

/// Lee una clave de día; null si no tiene la forma `aaaa-mm-dd` o el año está
/// fuera de [kFirstYear]…[kLastYear]. Se llama muchas veces al calcular
/// rachas, por eso no usa expresiones regulares.
DateTime? parseDayKey(String key) {
  if (key.length != 10 || key.codeUnitAt(4) != 45 || key.codeUnitAt(7) != 45) {
    return null;
  }
  int digits(int from, int to) {
    int v = 0;
    for (int i = from; i < to; i++) {
      final int c = key.codeUnitAt(i) - 48;
      if (c < 0 || c > 9) {
        return -1;
      }
      v = v * 10 + c;
    }
    return v;
  }

  final int y = digits(0, 4);
  final int mo = digits(5, 7);
  final int d = digits(8, 10);
  if (y < kFirstYear || y > kLastYear || mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) {
    return null;
  }
  return DateTime(y, mo, d);
}

bool isLeapYear(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Primer día de la semana que contiene [d]; [weekStart] es 1 (lunes) a 7 (domingo).
DateTime startOfWeek(DateTime d, int weekStart) {
  final int back = (d.weekday - weekStart + 7) % 7;
  return DateTime(d.year, d.month, d.day - back);
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Lunes = 1 … domingo = 7, en el orden en que se muestran según [weekStart].
List<int> orderedWeekdays(int weekStart) => List<int>.generate(7, (int i) => (weekStart - 1 + i) % 7 + 1);

const List<String> _weekdaysEs = <String>['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const List<String> _weekdaysEn = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _weekdaysShortEs = <String>['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const List<String> _weekdaysShortEn = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _weekdaysLetterEs = <String>['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const List<String> _weekdaysLetterEn = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const List<String> _monthsEs = <String>['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const List<String> _monthsEn = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _monthsShortEs = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
const List<String> _monthsShortEn = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String weekdayName(int weekday, {required bool spanish}) => (spanish ? _weekdaysEs : _weekdaysEn)[weekday - 1];

String weekdayShort(int weekday, {required bool spanish}) => (spanish ? _weekdaysShortEs : _weekdaysShortEn)[weekday - 1];

/// Inicial del día (en español, X para el miércoles, como en los calendarios).
String weekdayLetter(int weekday, {required bool spanish}) => (spanish ? _weekdaysLetterEs : _weekdaysLetterEn)[weekday - 1];

String monthName(int month, {required bool spanish}) => (spanish ? _monthsEs : _monthsEn)[month - 1];

String monthShort(int month, {required bool spanish}) => (spanish ? _monthsShortEs : _monthsShortEn)[month - 1];

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "mar 14 oct" / "Tue, Oct 14".
String formatShortDate(DateTime d, {required bool spanish}) => spanish ? '${weekdayShort(d.weekday, spanish: true)} ${d.day} ${monthShort(d.month, spanish: true)}' : '${weekdayShort(d.weekday, spanish: false)}, ${monthShort(d.month, spanish: false)} ${d.day}';

/// "14 de octubre de 2026" / "October 14, 2026".
String formatLongDate(DateTime d, {required bool spanish}) => spanish ? '${d.day} de ${monthName(d.month, spanish: true)} de ${d.year}' : '${monthName(d.month, spanish: false)} ${d.day}, ${d.year}';

/// "Martes 14 de octubre" / "Tuesday, October 14".
String formatWeekdayDate(DateTime d, {required bool spanish}) => spanish ? '${_capitalize(weekdayName(d.weekday, spanish: true))} ${d.day} de ${monthName(d.month, spanish: true)}' : '${weekdayName(d.weekday, spanish: false)}, ${monthName(d.month, spanish: false)} ${d.day}';

/// "Octubre de 2026" / "October 2026".
String formatMonthYear(DateTime d, {required bool spanish}) => spanish ? '${_capitalize(monthName(d.month, spanish: true))} de ${d.year}' : '${monthName(d.month, spanish: false)} ${d.year}';

/// Rango de días: "13 – 19 oct 2026" / "Oct 13 – 19, 2026".
String formatDayRange(DateTime a, DateTime b, {required bool spanish}) {
  if (spanish) {
    if (a.year != b.year) {
      return '${a.day} ${monthShort(a.month, spanish: true)} ${a.year} – ${b.day} ${monthShort(b.month, spanish: true)} ${b.year}';
    }
    if (a.month != b.month) {
      return '${a.day} ${monthShort(a.month, spanish: true)} – ${b.day} ${monthShort(b.month, spanish: true)} ${b.year}';
    }
    return '${a.day} – ${b.day} ${monthShort(b.month, spanish: true)} ${b.year}';
  }
  if (a.year != b.year) {
    return '${monthShort(a.month, spanish: false)} ${a.day}, ${a.year} – ${monthShort(b.month, spanish: false)} ${b.day}, ${b.year}';
  }
  if (a.month != b.month) {
    return '${monthShort(a.month, spanish: false)} ${a.day} – ${monthShort(b.month, spanish: false)} ${b.day}, ${b.year}';
  }
  return '${monthShort(a.month, spanish: false)} ${a.day} – ${b.day}, ${b.year}';
}

/// El teléfono muestra la hora en 24 horas. La app lo lee al abrir y al volver
/// (PlatformDispatcher.alwaysUse24HourFormat), y las pruebas lo fijan.
bool use24HourClock = false;

/// Hora del día con el mismo formato que el selector de hora de la app: en
/// español siempre 24 horas ("7:30", "18:30"), como lo hace Material en
/// español; en inglés, 12 horas ("6:30 PM") salvo que el teléfono use 24 horas
/// ("07:30", "18:30").
String formatTimeOfDay(int hour, int minute, {required bool spanish}) {
  if (spanish) {
    return '$hour:${_two(minute)}';
  }
  if (use24HourClock) {
    return '${_two(hour)}:${_two(minute)}';
  }
  final int h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${_two(minute)} ${hour < 12 ? 'AM' : 'PM'}';
}

String formatTime(DateTime d, {required bool spanish}) => formatTimeOfDay(d.hour, d.minute, spanish: spanish);

/// La hora en español con su artículo: «la 1:30» (de la 1:00 a la 1:59) y
/// «las 18:30» en las demás.
String spanishClock(DateTime d) => '${d.hour == 1 ? 'la' : 'las'} ${formatTime(d, spanish: true)}';

/// Minutos desde la medianoche ("7:30" = 450) como texto.
String formatMinuteOfDay(int minutes, {required bool spanish}) => formatTimeOfDay(minutes ~/ 60, minutes % 60, spanish: spanish);

/// Duración como reloj: "5:07", "12:00", "1:05:30".
String formatClock(int seconds) {
  final int s = seconds < 0 ? 0 : seconds;
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  final int r = s % 60;
  if (h > 0) {
    return '$h:${_two(m)}:${_two(r)}';
  }
  return '$m:${_two(r)}';
}

/// Milisegundos como cronómetro: "1:05.37" o "1:02:05.37".
String formatStopwatch(int ms) {
  final int v = ms < 0 ? 0 : ms;
  final int cs = (v % 1000) ~/ 10;
  return '${formatClock(v ~/ 1000)}.${_two(cs)}';
}

/// Duración en palabras cortas: "45 s", "10 min", "1 h 05 min".
String formatDurationShort(int seconds, {required bool spanish}) {
  if (seconds < 60) {
    return '$seconds s';
  }
  final int minutes = seconds ~/ 60;
  final int rest = seconds % 60;
  if (minutes < 60) {
    return rest == 0 ? '$minutes min' : '$minutes min $rest s';
  }
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${_two(m)} min';
}

/// Duración para la voz: "20 segundos", "1 minuto y 30 segundos".
String spokenDuration(int seconds, {required bool spanish}) {
  final int m = seconds ~/ 60;
  final int s = seconds % 60;
  String unit(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  final String mins = spanish ? unit(m, 'minuto', 'minutos') : unit(m, 'minute', 'minutes');
  final String secs = spanish ? unit(s, 'segundo', 'segundos') : unit(s, 'second', 'seconds');
  if (m == 0) {
    return secs;
  }
  if (s == 0) {
    return mins;
  }
  return spanish ? '$mins y $secs' : '$mins and $secs';
}

/// "hace 5 min", "en 2 h", "mañana", relativo a [now].
String formatRelative(DateTime when, DateTime now, {required bool spanish}) {
  final int diffMin = (when.difference(now).inSeconds / 60).round();
  final bool future = diffMin >= 0;
  final int m = diffMin.abs();
  if (m < 1) {
    return spanish ? 'ahora' : 'now';
  }
  if (m < 60) {
    return future ? (spanish ? 'en $m min' : 'in $m min') : (spanish ? 'hace $m min' : '$m min ago');
  }
  final int days = daysBetween(now, when);
  if (days == 0) {
    final int h = (m / 60).round();
    return future ? (spanish ? 'en $h h' : 'in $h h') : (spanish ? 'hace $h h' : '$h h ago');
  }
  if (days == 1) {
    return spanish ? 'mañana' : 'tomorrow';
  }
  if (days == -1) {
    return spanish ? 'ayer' : 'yesterday';
  }
  if (days > 0) {
    return spanish ? 'en $days días' : 'in $days days';
  }
  return spanish ? 'hace ${-days} días' : '${-days} days ago';
}
