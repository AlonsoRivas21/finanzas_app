enum TipoMovimiento { ingreso, egreso }

class Movimiento {
  final String id;
  final DateTime fecha;
  final TipoMovimiento tipo;
  final double monto;
  final String? categoriaId;
  final String? cuentaId;
  final String? categoriaNombre;
  final String? cuentaNombre;
  final String? comentario;
  final int mes;
  final int anio;
  final bool sincronizado;

  Movimiento({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.monto,
    this.categoriaId,
    this.cuentaId,
    this.categoriaNombre,
    this.cuentaNombre,
    this.comentario,
    required this.mes,
    int? anio,
    this.sincronizado = false,
  }) : anio = anio ?? fecha.year;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'tipo': tipo.name,
      'monto': monto,
      'categoria_id': categoriaId,
      'cuenta_id': cuentaId,
      'comentario': comentario,
      'mes': mes,
      'anio': anio,
      'sincronizado': sincronizado ? 1 : 0,
    };
  }

  factory Movimiento.fromMap(Map<String, dynamic> map) {
    final fecha = DateTime.parse(map['fecha']);

    // Lógica para extraer nombres (Móvil/SQLite: categoria_nombre | Web/Supabase: categorias['nombre'])
    String? catNombre = map['categoria_nombre'];
    if (catNombre == null && map['categorias'] is Map) {
      catNombre = map['categorias']['nombre'];
    }

    String? cueNombre = map['cuenta_nombre'];
    if (cueNombre == null && map['cuentas'] is Map) {
      cueNombre = map['cuentas']['nombre'];
    }

    return Movimiento(
      id: map['id'],
      fecha: fecha,
      tipo: TipoMovimiento.values.firstWhere((t) => t.name == map['tipo']),
      monto: (map['monto'] as num).toDouble(),
      categoriaId: map['categoria_id']?.toString(),
      cuentaId: map['cuenta_id']?.toString(),
      categoriaNombre: catNombre,
      cuentaNombre: cueNombre,
      comentario: map['comentario'],
      mes: map['mes'],
      anio: map['anio'] ?? fecha.year,
      sincronizado: map['sincronizado'] == 1,
    );
  }

  Movimiento copyWith({
    String? id,
    DateTime? fecha,
    TipoMovimiento? tipo,
    double? monto,
    String? categoriaId,
    String? cuentaId,
    String? categoriaNombre,
    String? cuentaNombre,
    String? comentario,
    int? mes,
    int? anio,
    bool? sincronizado,
  }) {
    return Movimiento(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      tipo: tipo ?? this.tipo,
      monto: monto ?? this.monto,
      categoriaId: categoriaId ?? this.categoriaId,
      cuentaId: cuentaId ?? this.cuentaId,
      categoriaNombre: categoriaNombre ?? this.categoriaNombre,
      cuentaNombre: cuentaNombre ?? this.cuentaNombre,
      comentario: comentario ?? this.comentario,
      mes: mes ?? this.mes,
      anio: anio ?? this.anio,
      sincronizado: sincronizado ?? this.sincronizado,
    );
  }

  // Getters auxiliares para la interfaz de usuario
  // Priorizan el nombre descriptivo obtenido del JOIN; si no existe, devuelven un fallback.
  String get displayCategoria => (categoriaNombre != null && categoriaNombre!.isNotEmpty) ? categoriaNombre! : 'Sin Categoría';
  String get displayCuenta => (cuentaNombre != null && cuentaNombre!.isNotEmpty) ? cuentaNombre! : 'Sin Cuenta';

}
