/// Un grupo de aula para el modo docente: un nombre y los perfiles que lo forman.
class ClassGroup {
  ClassGroup({
    required this.id,
    required this.nombre,
    List<String>? profileIds,
    DateTime? createdAt,
  })  : profileIds = profileIds ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String nombre;
  final List<String> profileIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nombre': nombre,
        'profileIds': profileIds,
        'createdAt': createdAt.toIso8601String(),
      };

  static ClassGroup fromJson(Map<String, dynamic> json) {
    final List<dynamic> ids = (json['profileIds'] as List<dynamic>?) ?? <dynamic>[];
    return ClassGroup(
      id: json['id'] as String,
      nombre: (json['nombre'] as String?) ?? '',
      profileIds: ids.map((dynamic e) => e as String).toList(),
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? DateTime.now(),
    );
  }
}
