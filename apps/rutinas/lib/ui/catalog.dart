import 'package:flutter/material.dart';

/// Un ícono de Material para los hábitos, con su nombre para los lectores de
/// pantalla.
class HabitIcon {
  const HabitIcon(this.id, this.icon, this.es, this.en);

  final String id;
  final IconData icon;
  final String es;
  final String en;

  String label(bool spanish) => spanish ? es : en;
}

/// Íconos para elegir en los hábitos (todos de Material, ya incluidos en la app).
const List<HabitIcon> kHabitIcons = <HabitIcon>[
  HabitIcon('task_alt', Icons.task_alt, 'Marca de hecho', 'Check mark'),
  HabitIcon('water_drop', Icons.water_drop, 'Gota de agua', 'Water drop'),
  HabitIcon('local_drink', Icons.local_drink, 'Vaso', 'Glass'),
  HabitIcon('fitness_center', Icons.fitness_center, 'Pesas', 'Weights'),
  HabitIcon('directions_run', Icons.directions_run, 'Correr', 'Running'),
  HabitIcon('directions_walk', Icons.directions_walk, 'Caminar', 'Walking'),
  HabitIcon('directions_bike', Icons.directions_bike, 'Bicicleta', 'Cycling'),
  HabitIcon('pool', Icons.pool, 'Natación', 'Swimming'),
  HabitIcon('hiking', Icons.hiking, 'Caminata', 'Hiking'),
  HabitIcon('sports_soccer', Icons.sports_soccer, 'Fútbol', 'Soccer'),
  HabitIcon('sports_basketball', Icons.sports_basketball, 'Baloncesto', 'Basketball'),
  HabitIcon('sports_tennis', Icons.sports_tennis, 'Tenis', 'Tennis'),
  HabitIcon('sports_gymnastics', Icons.sports_gymnastics, 'Estiramientos', 'Stretching'),
  HabitIcon('sports_martial_arts', Icons.sports_martial_arts, 'Artes marciales', 'Martial arts'),
  HabitIcon('self_improvement', Icons.self_improvement, 'Meditar', 'Meditation'),
  HabitIcon('spa', Icons.spa, 'Relajación', 'Relaxation'),
  HabitIcon('psychology', Icons.psychology, 'Mente', 'Mind'),
  HabitIcon('bedtime', Icons.bedtime, 'Dormir', 'Sleep'),
  HabitIcon('wb_sunny', Icons.wb_sunny, 'Mañana', 'Morning'),
  HabitIcon('alarm', Icons.alarm, 'Despertador', 'Alarm clock'),
  HabitIcon('menu_book', Icons.menu_book, 'Leer', 'Reading'),
  HabitIcon('auto_stories', Icons.auto_stories, 'Libro', 'Book'),
  HabitIcon('school', Icons.school, 'Estudiar', 'Studying'),
  HabitIcon('translate', Icons.translate, 'Idiomas', 'Languages'),
  HabitIcon('edit_note', Icons.edit_note, 'Diario', 'Journal'),
  HabitIcon('draw', Icons.draw, 'Dibujar', 'Drawing'),
  HabitIcon('palette', Icons.palette, 'Pintar', 'Painting'),
  HabitIcon('music_note', Icons.music_note, 'Música', 'Music'),
  HabitIcon('piano', Icons.piano, 'Piano', 'Piano'),
  HabitIcon('code', Icons.code, 'Programar', 'Coding'),
  HabitIcon('restaurant', Icons.restaurant, 'Comida', 'Meals'),
  HabitIcon('eco', Icons.eco, 'Verduras', 'Vegetables'),
  HabitIcon('egg_alt', Icons.egg_alt, 'Desayuno', 'Breakfast'),
  HabitIcon('medication', Icons.medication, 'Medicina', 'Medicine'),
  HabitIcon('monitor_heart', Icons.monitor_heart, 'Salud', 'Health'),
  HabitIcon('clean_hands', Icons.clean_hands, 'Higiene', 'Hygiene'),
  HabitIcon('shower', Icons.shower, 'Ducha', 'Shower'),
  HabitIcon('cleaning_services', Icons.cleaning_services, 'Limpieza', 'Cleaning'),
  HabitIcon('local_laundry_service', Icons.local_laundry_service, 'Ropa', 'Laundry'),
  HabitIcon('local_florist', Icons.local_florist, 'Plantas', 'Plants'),
  HabitIcon('pets', Icons.pets, 'Mascota', 'Pet'),
  HabitIcon('savings', Icons.savings, 'Ahorrar', 'Saving'),
  HabitIcon('account_balance_wallet', Icons.account_balance_wallet, 'Gastos', 'Spending'),
  HabitIcon('work', Icons.work, 'Trabajo', 'Work'),
  HabitIcon('call', Icons.call, 'Llamar', 'Calling'),
  HabitIcon('family_restroom', Icons.family_restroom, 'Familia', 'Family'),
  HabitIcon('volunteer_activism', Icons.volunteer_activism, 'Gratitud', 'Gratitude'),
  HabitIcon('favorite', Icons.favorite, 'Corazón', 'Heart'),
  HabitIcon('star', Icons.star, 'Estrella', 'Star'),
  HabitIcon('emoji_events', Icons.emoji_events, 'Trofeo', 'Trophy'),
  HabitIcon('lightbulb', Icons.lightbulb, 'Idea', 'Idea'),
  HabitIcon('timer', Icons.timer, 'Cronómetro', 'Timer'),
  HabitIcon('smoke_free', Icons.smoke_free, 'Sin fumar', 'No smoking'),
  HabitIcon('no_drinks', Icons.no_drinks, 'Sin alcohol', 'No alcohol'),
  HabitIcon('no_food', Icons.no_food, 'Sin comida chatarra', 'No junk food'),
  HabitIcon('phonelink_off', Icons.phonelink_off, 'Menos pantalla', 'Less screen time'),
  HabitIcon('tv_off', Icons.tv_off, 'Sin televisión', 'No TV'),
  HabitIcon('local_cafe', Icons.local_cafe, 'Café', 'Coffee'),
  HabitIcon('fastfood', Icons.fastfood, 'Comida rápida', 'Fast food'),
  HabitIcon('sports_esports', Icons.sports_esports, 'Videojuegos', 'Video games'),
  HabitIcon('block', Icons.block, 'Evitar', 'Avoid'),
];

HabitIcon habitIconFor(String id) {
  for (final HabitIcon i in kHabitIcons) {
    if (i.id == id) {
      return i;
    }
  }
  return kHabitIcons.first;
}

/// Un color con nombre, para hábitos e intervalos. Todos dejan leer texto
/// blanco encima con contraste AA (4,5:1 o más); la prueba lo verifica.
class NamedColor {
  const NamedColor(this.value, this.es, this.en);

  final int value;
  final String es;
  final String en;

  Color get color => Color(value);

  String label(bool spanish) => spanish ? es : en;
}

const List<NamedColor> kColors = <NamedColor>[
  NamedColor(0xFF3949AB, 'Índigo', 'Indigo'),
  NamedColor(0xFF1565C0, 'Azul', 'Blue'),
  NamedColor(0xFF00727D, 'Cian', 'Cyan'),
  NamedColor(0xFF00796B, 'Verde azulado', 'Teal'),
  NamedColor(0xFF2E7D32, 'Verde', 'Green'),
  NamedColor(0xFF556B2F, 'Oliva', 'Olive'),
  NamedColor(0xFF8A5A00, 'Ámbar', 'Amber'),
  NamedColor(0xFFB2410C, 'Naranja', 'Orange'),
  NamedColor(0xFFC62828, 'Rojo', 'Red'),
  NamedColor(0xFFAD1457, 'Rosa', 'Pink'),
  NamedColor(0xFF6A1B9A, 'Morado', 'Purple'),
  NamedColor(0xFF455A64, 'Gris azulado', 'Blue grey'),
];

NamedColor? namedColorFor(int value) {
  for (final NamedColor c in kColors) {
    if (c.value == value) {
      return c;
    }
  }
  return null;
}

/// Colores de acento de la app.
const List<NamedColor> kAccents = <NamedColor>[
  NamedColor(0xFF3949AB, 'Índigo', 'Indigo'),
  NamedColor(0xFF1565C0, 'Azul', 'Blue'),
  NamedColor(0xFF00796B, 'Verde azulado', 'Teal'),
  NamedColor(0xFF2E7D32, 'Verde', 'Green'),
  NamedColor(0xFFB2410C, 'Naranja', 'Orange'),
  NamedColor(0xFFC62828, 'Rojo', 'Red'),
  NamedColor(0xFFAD1457, 'Rosa', 'Pink'),
  NamedColor(0xFF6A1B9A, 'Morado', 'Purple'),
];

/// Relación de contraste WCAG entre dos colores (1 a 21).
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Texto que se lee mejor sobre [background]: blanco o casi negro.
Color onColor(Color background) => contrastRatio(background, Colors.white) >= contrastRatio(background, const Color(0xFF111111)) ? Colors.white : const Color(0xFF111111);
