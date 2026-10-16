import 'age_band.dart';

/// Un niño o niña que usa la app. Vive solo en el dispositivo.
class Profile {
  Profile({
    required this.id,
    required this.nombre,
    required this.avatar,
    required this.birthYear,
    required this.birthMonth,
    this.bandOverride,
    this.leftHanded = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String nombre;

  /// Código Twemoji del avatar, por ejemplo '1f431'.
  String avatar;
  int birthYear;
  int birthMonth;

  /// Si el adulto fija un tramo distinto al de la edad.
  AgeBand? bandOverride;
  bool leftHanded;
  final DateTime createdAt;

  int ageOn(DateTime now) {
    int age = now.year - birthYear;
    if (now.month < birthMonth) {
      age -= 1;
    }
    if (age < 0) {
      return 0;
    }
    return age;
  }

  AgeBand bandOn(DateTime now) => bandOverride ?? AgeBandX.forAge(ageOn(now));

  AgeBand get band => bandOn(DateTime.now());

  int get age => ageOn(DateTime.now());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nombre': nombre,
        'avatar': avatar,
        'birthYear': birthYear,
        'birthMonth': birthMonth,
        'bandOverride': bandOverride?.id,
        'leftHanded': leftHanded,
        'createdAt': createdAt.toIso8601String(),
      };

  static Profile fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      nombre: (json['nombre'] as String?) ?? '',
      avatar: (json['avatar'] as String?) ?? '1f431',
      birthYear: (json['birthYear'] as num?)?.toInt() ?? DateTime.now().year - 5,
      birthMonth: (json['birthMonth'] as num?)?.toInt() ?? 1,
      bandOverride: AgeBandX.fromId(json['bandOverride'] as String?),
      leftHanded: (json['leftHanded'] as bool?) ?? false,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  /// Avatares disponibles (códigos Twemoji).
  static const List<String> avatares = <String>[
    '1f431', // gato
    '1f436', // perro
    '1f430', // conejo
    '1f43c', // panda
    '1f981', // león
    '1f438', // rana
    '1f427', // pingüino
    '1f989', // búho
    '1f99c', // loro
    '1f422', // tortuga
    '1f98b', // mariposa
    '1f419', // pulpo
    '1f999', // llama
    '1f9a5', // perezoso
    '1f42c', // delfín
    '1f98a', // zorro
  ];
}
