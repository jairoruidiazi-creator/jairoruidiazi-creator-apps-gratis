import 'dart:ui' show Locale;

import '../model/models.dart';

/// Categorías de serie, pensadas para Colombia. Cada entrada: nombre, icono,
/// color y subcategorías.
class Defaults {
  Defaults._();

  static List<Category> categories({bool spanish = true}) {
    final List<Category> out = <Category>[];
    _eachCategory((String id, String es, String en, String icon, int color, CategoryKind kind, String? parentId, int order) {
      out.add(Category(id: id, name: spanish ? es : en, kind: kind, icon: icon, color: color, parentId: parentId, order: order));
    });
    return out;
  }

  /// Nombres de fábrica de cada categoría: id → [español, inglés]. Sirven para
  /// cambiar de idioma las que el usuario no renombró.
  static Map<String, List<String>> categoryNames() {
    final Map<String, List<String>> out = <String, List<String>>{};
    _eachCategory((String id, String es, String en, String icon, int color, CategoryKind kind, String? parentId, int order) {
      out[id] = <String>[es, en];
    });
    return out;
  }

  /// Nombres de fábrica de las cuentas que crea la app: id → [español, inglés].
  static const Map<String, List<String>> accountNames = <String, List<String>>{
    'a_cash': <String>['Efectivo', 'Cash'],
  };

  static void _eachCategory(void Function(String id, String es, String en, String icon, int color, CategoryKind kind, String? parentId, int order) emit) {
    int order = 0;
    void group(String es, String en, String icon, int color, CategoryKind kind, List<List<String>> subs) {
      final String parentId = 'c_${_slug(en)}';
      emit(parentId, es, en, icon, color, kind, null, order++);
      for (final List<String> s in subs) {
        emit('c_${_slug(en)}_${_slug(s[1])}', s[0], s[1], s.length > 2 ? s[2] : icon, color, kind, parentId, order++);
      }
    }

    group('Alimentación', 'Food', 'restaurant', 0xFFEF6C00, CategoryKind.expense, <List<String>>[
      <String>['Mercado', 'Groceries', 'cart'],
      <String>['Restaurantes', 'Restaurants', 'restaurant'],
      <String>['Domicilios', 'Delivery', 'delivery'],
      <String>['Cafetería y antojos', 'Coffee & snacks', 'coffee'],
    ]);
    group('Vivienda', 'Housing', 'home', 0xFF5D4037, CategoryKind.expense, <List<String>>[
      <String>['Arriendo', 'Rent', 'home'],
      <String>['Administración', 'HOA fees', 'apartment'],
      <String>['Cuota hipotecaria', 'Mortgage', 'bank'],
      <String>['Energía', 'Electricity', 'bolt'],
      <String>['Agua y alcantarillado', 'Water', 'water'],
      <String>['Gas', 'Gas', 'fire'],
      <String>['Internet y TV', 'Internet & TV', 'wifi'],
      <String>['Celular', 'Mobile phone', 'phone'],
    ]);
    group('Transporte', 'Transport', 'bus', 0xFF1976D2, CategoryKind.expense, <List<String>>[
      <String>['Transporte público', 'Public transit', 'bus'],
      <String>['Gasolina', 'Fuel', 'fuel'],
      <String>['Taxi y apps', 'Taxi & ride apps', 'taxi'],
      <String>['Parqueadero y peajes', 'Parking & tolls', 'parking'],
      <String>['Mantenimiento y SOAT', 'Maintenance & insurance', 'car'],
    ]);
    group('Salud', 'Health', 'health', 0xFFD32F2F, CategoryKind.expense, <List<String>>[
      <String>['EPS y prepagada', 'Health plan', 'health'],
      <String>['Medicamentos', 'Medicines', 'pill'],
      <String>['Consultas y exámenes', 'Doctor & tests', 'stethoscope'],
      <String>['Gimnasio y deporte', 'Gym & sports', 'fitness'],
    ]);
    group('Educación', 'Education', 'school', 0xFF7B1FA2, CategoryKind.expense, <List<String>>[
      <String>['Matrícula y pensión', 'Tuition', 'school'],
      <String>['Útiles y libros', 'Supplies & books', 'book'],
      <String>['Cursos', 'Courses', 'laptop'],
    ]);
    group('Hogar', 'Household', 'couch', 0xFF00796B, CategoryKind.expense, <List<String>>[
      <String>['Aseo y cocina', 'Cleaning & kitchen', 'soap'],
      <String>['Muebles y electrodomésticos', 'Furniture & appliances', 'couch'],
      <String>['Reparaciones', 'Repairs', 'tools'],
      <String>['Empleada doméstica', 'Domestic help', 'person'],
    ]);
    group('Personal', 'Personal', 'shirt', 0xFFC2185B, CategoryKind.expense, <List<String>>[
      <String>['Ropa y calzado', 'Clothing & shoes', 'shirt'],
      <String>['Peluquería y cuidado', 'Hair & care', 'spa'],
    ]);
    group('Entretenimiento', 'Entertainment', 'movie', 0xFF512DA8, CategoryKind.expense, <List<String>>[
      <String>['Salidas', 'Going out', 'party'],
      <String>['Suscripciones', 'Subscriptions', 'subscriptions'],
      <String>['Viajes', 'Travel', 'flight'],
      <String>['Videojuegos y hobbies', 'Games & hobbies', 'game'],
    ]);
    group('Familia y mascotas', 'Family & pets', 'family', 0xFF689F38, CategoryKind.expense, <List<String>>[
      <String>['Hijos', 'Kids', 'child'],
      <String>['Mascotas', 'Pets', 'pet'],
      <String>['Regalos y ayudas', 'Gifts & support', 'gift'],
    ]);
    group('Impuestos y trámites', 'Taxes & paperwork', 'receipt', 0xFF455A64, CategoryKind.expense, <List<String>>[
      <String>['Predial y vehículo', 'Property & vehicle tax', 'receipt'],
      <String>['Renta y DIAN', 'Income tax', 'gavel'],
      <String>['Trámites y notaría', 'Paperwork', 'stamp'],
    ]);
    group('Financiero', 'Financial', 'bank', 0xFF303F9F, CategoryKind.expense, <List<String>>[
      <String>['Cuota de crédito', 'Loan payment', 'bank'],
      <String>['Intereses y seguros', 'Interest & insurance', 'percent'],
      <String>['Comisiones y 4×1000', 'Fees & 4×1000', 'fees'],
    ]);
    group('Ahorro e inversión', 'Savings & investing', 'savings', 0xFF00838F, CategoryKind.expense, <List<String>>[
      <String>['Ahorro', 'Savings', 'savings'],
      <String>['Inversión', 'Investment', 'trending'],
    ]);
    group('Otros gastos', 'Other expenses', 'more', 0xFF757575, CategoryKind.expense, <List<String>>[]);

    group('Salario', 'Salary', 'work', 0xFF2E7D32, CategoryKind.income, <List<String>>[
      <String>['Quincena', 'Paycheck', 'work'],
      <String>['Prima y cesantías', 'Bonus & severance', 'gift'],
      <String>['Horas extra', 'Overtime', 'clock'],
    ]);
    group('Independiente', 'Freelance & sales', 'store', 0xFF558B2F, CategoryKind.income, <List<String>>[
      <String>['Honorarios', 'Fees', 'work'],
      <String>['Ventas', 'Sales', 'store'],
    ]);
    group('Arriendos recibidos', 'Rental income', 'home', 0xFF827717, CategoryKind.income, <List<String>>[]);
    group('Rendimientos', 'Returns', 'trending', 0xFF00695C, CategoryKind.income, <List<String>>[
      <String>['Intereses', 'Interest', 'percent'],
      <String>['Dividendos', 'Dividends', 'trending'],
    ]);
    group('Regalos y reembolsos', 'Gifts & refunds', 'gift', 0xFF6A1B9A, CategoryKind.income, <List<String>>[
      <String>['Regalos recibidos', 'Gifts received', 'gift'],
      <String>['Reembolsos', 'Refunds', 'undo'],
      <String>['Subsidios', 'Subsidies', 'bank'],
    ]);
    group('Otros ingresos', 'Other income', 'more', 0xFF757575, CategoryKind.income, <List<String>>[]);
  }

  static List<Account> accounts({bool spanish = true, String currency = 'COP'}) => <Account>[
        Account(id: 'a_cash', name: spanish ? accountNames['a_cash']![0] : accountNames['a_cash']![1], type: AccountType.cash, currency: currency, icon: 'cash', color: 0xFF2E7D32, order: 0),
      ];

  /// Moneda de cada país (de los que la app conoce). Los países del euro van
  /// aparte.
  static const Map<String, String> _countryCurrency = <String, String>{
    'CO': 'COP',
    'US': 'USD',
    'EC': 'USD',
    'SV': 'USD',
    'PR': 'USD',
    'PA': 'USD',
    'MX': 'MXN',
    'BR': 'BRL',
    'PE': 'PEN',
    'CL': 'CLP',
    'AR': 'ARS',
    'GB': 'GBP',
    'CA': 'CAD',
    'CH': 'CHF',
    'JP': 'JPY',
    'CN': 'CNY',
    'CR': 'CRC',
    'DO': 'DOP',
    'UY': 'UYU',
    'VE': 'VES',
  };

  static const Set<String> _euro = <String>{'ES', 'FR', 'DE', 'IT', 'PT', 'NL', 'BE', 'AT', 'IE', 'FI', 'GR', 'LU', 'SK', 'SI', 'EE', 'LV', 'LT', 'MT', 'CY', 'HR'};

  /// Moneda base de un libro nuevo: la del país del teléfono (el primero de
  /// sus idiomas que diga un país conocido). Sin país conocido: pesos
  /// colombianos si el teléfono está en español y dólares si no, para que en
  /// inglés "$" no sean pesos sin que nadie lo haya elegido.
  static String currencyForLocales(List<Locale> locales) {
    for (final Locale l in locales) {
      final String? country = l.countryCode?.toUpperCase();
      if (country == null || country.isEmpty) {
        continue;
      }
      if (_euro.contains(country)) {
        return 'EUR';
      }
      final String? c = _countryCurrency[country];
      if (c != null) {
        return c;
      }
    }
    return locales.isNotEmpty && locales.first.languageCode == 'es' ? 'COP' : 'USD';
  }

  /// Cuentas sugeridas al crear una nueva (nombre, tipo, icono, color, banco).
  static List<Account> presets({bool spanish = true}) => <Account>[
        Account(id: '', name: spanish ? 'Cuenta de ahorros' : 'Savings account', type: AccountType.bank, icon: 'bank', color: 0xFF1565C0),
        Account(id: '', name: 'Nequi', type: AccountType.wallet, icon: 'wallet', color: 0xFF6A1B9A, bank: 'nequi'),
        Account(id: '', name: 'Daviplata', type: AccountType.wallet, icon: 'wallet', color: 0xFFC62828, bank: 'daviplata'),
        Account(id: '', name: spanish ? 'Tarjeta de crédito' : 'Credit card', type: AccountType.credit, icon: 'card', color: 0xFF37474F, cutDay: 15, payDay: 5),
        Account(id: '', name: spanish ? 'Tarjeta débito' : 'Debit card', type: AccountType.debit, icon: 'card', color: 0xFF00838F),
        Account(id: '', name: spanish ? 'Bolsillo' : 'Pocket', type: AccountType.pocket, icon: 'savings', color: 0xFF00897B),
        Account(id: '', name: spanish ? 'Préstamo' : 'Loan', type: AccountType.loan, icon: 'bank', color: 0xFF8D6E63),
        Account(id: '', name: spanish ? 'Inversión (CDT, fondo)' : 'Investment', type: AccountType.investment, icon: 'trending', color: 0xFF00695C),
      ];

  static String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}
