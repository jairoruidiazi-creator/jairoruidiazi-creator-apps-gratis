import '../model/models.dart';

/// Categorías de serie, pensadas para Colombia. Cada entrada: nombre, icono,
/// color y subcategorías.
class Defaults {
  Defaults._();

  static List<Category> categories({bool spanish = true}) {
    final List<Category> out = <Category>[];
    int order = 0;
    void group(String es, String en, String icon, int color, CategoryKind kind, List<List<String>> subs) {
      final Category parent = Category(id: 'c_${_slug(en)}', name: spanish ? es : en, kind: kind, icon: icon, color: color, order: order++);
      out.add(parent);
      for (final List<String> s in subs) {
        out.add(Category(id: 'c_${_slug(en)}_${_slug(s[1])}', name: spanish ? s[0] : s[1], kind: kind, icon: s.length > 2 ? s[2] : icon, color: color, parentId: parent.id, order: order++));
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
    return out;
  }

  static List<Account> accounts({bool spanish = true}) => <Account>[
        Account(id: 'a_cash', name: spanish ? 'Efectivo' : 'Cash', type: AccountType.cash, icon: 'cash', color: 0xFF2E7D32, order: 0),
      ];

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
