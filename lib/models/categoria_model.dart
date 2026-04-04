// lib/models/categoria_model.dart

class CategoriaModel {
  final String id;
  final String nombre;
  final String tipo; // ingreso, egreso, ambos
  final String icono;
  final bool activa;
  final int orden;

  CategoriaModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.icono,
    required this.activa,
    required this.orden,
  });

  factory CategoriaModel.fromMap(Map<String, dynamic> map) {
    return CategoriaModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      tipo: map['tipo'] as String? ?? 'egreso',
      icono: map['icono'] as String? ?? 'label',
      activa: map['activa'] as bool? ?? true,
      orden: map['orden'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap(String userId) => {
    'id': id,
    'usuario_id': userId,
    'nombre': nombre,
    'tipo': tipo,
    'icono': icono,
    'activa': activa,
    'orden': orden,
  };

  CategoriaModel copyWith({
    String? nombre,
    String? tipo,
    String? icono,
    bool? activa,
    int? orden,
  }) {
    return CategoriaModel(
      id: id,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      icono: icono ?? this.icono,
      activa: activa ?? this.activa,
      orden: orden ?? this.orden,
    );
  }
}
