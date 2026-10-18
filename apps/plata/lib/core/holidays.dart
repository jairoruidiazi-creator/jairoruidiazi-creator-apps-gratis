/// Festivos de Colombia y días hábiles, para correr la fecha límite de pago
/// de una tarjeta.
///
/// El art. 829 del Código de Comercio dice que «el plazo que venza en día
/// feriado se prorrogará hasta el día siguiente», y los bancos corren la
/// fecha límite que cae en sábado, domingo o festivo al siguiente día hábil
/// (ver docs/DECISIONES.md). Los festivos son:
///
/// - fijos: 1 de enero, 1 de mayo, 20 de julio, 7 de agosto, 8 y 25 de
///   diciembre;
/// - de Semana Santa: jueves y viernes santos;
/// - los que la Ley Emiliani (Ley 51 de 1983) pasa al lunes siguiente: Reyes
///   (6 ene), San José (19 mar), San Pedro y San Pablo (29 jun), Asunción
///   (15 ago), Día de la Raza (12 oct), Todos los Santos (1 nov),
///   Independencia de Cartagena (11 nov) y, desde 2026, la Virgen de
///   Chiquinquirá (9 jul, Ley 2578 de 2026);
/// - los que dependen de la Pascua y también van al lunes: Ascensión
///   (Pascua + 43 días), Corpus Christi (+ 64) y Sagrado Corazón (+ 71).
class ColombianHolidays {
  ColombianHolidays._();

  static final Map<int, Set<DateTime>> _cache = <int, Set<DateTime>>{};

  /// Domingo de Pascua (algoritmo anónimo gregoriano, de Meeus).
  static DateTime easter(int year) {
    final int a = year % 19;
    final int b = year ~/ 100;
    final int c = year % 100;
    final int d = b ~/ 4;
    final int e = b % 4;
    final int f = (b + 8) ~/ 25;
    final int g = (b - f + 1) ~/ 3;
    final int h = (19 * a + b - d - g + 15) % 30;
    final int i = c ~/ 4;
    final int k = c % 4;
    final int l = (32 + 2 * e + 2 * i - h - k) % 7;
    final int m = (a + 11 * h + 22 * l) ~/ 451;
    final int month = (h + l - 7 * m + 114) ~/ 31;
    final int day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// El lunes siguiente (o el mismo día si ya es lunes).
  static DateTime _monday(DateTime d) => d.weekday == DateTime.monday ? d : DateTime(d.year, d.month, d.day + (8 - d.weekday));

  /// Festivos del año, como fechas sin hora.
  static Set<DateTime> of(int year) => _cache.putIfAbsent(year, () {
        final DateTime e = easter(year);
        DateTime fromEaster(int days) => DateTime(e.year, e.month, e.day + days);
        return <DateTime>{
          DateTime(year, 1, 1),
          DateTime(year, 5, 1),
          DateTime(year, 7, 20),
          DateTime(year, 8, 7),
          DateTime(year, 12, 8),
          DateTime(year, 12, 25),
          fromEaster(-3),
          fromEaster(-2),
          for (final DateTime d in <DateTime>[
            DateTime(year, 1, 6),
            DateTime(year, 3, 19),
            DateTime(year, 6, 29),
            DateTime(year, 8, 15),
            DateTime(year, 10, 12),
            DateTime(year, 11, 1),
            DateTime(year, 11, 11),
            if (year >= 2026) DateTime(year, 7, 9),
          ])
            _monday(d),
          fromEaster(43),
          fromEaster(64),
          fromEaster(71),
        };
      });

  static bool isHoliday(DateTime d) => of(d.year).contains(DateTime(d.year, d.month, d.day));

  /// Hábil: de lunes a viernes y no festivo (los bancos no cuentan el sábado).
  static bool isBusinessDay(DateTime d) => d.weekday != DateTime.saturday && d.weekday != DateTime.sunday && !isHoliday(d);

  /// El mismo día si es hábil; si no, el siguiente día hábil.
  static DateTime nextBusinessDay(DateTime d) {
    DateTime x = DateTime(d.year, d.month, d.day);
    for (int i = 0; i < 10 && !isBusinessDay(x); i++) {
      x = DateTime(x.year, x.month, x.day + 1);
    }
    return x;
  }
}
