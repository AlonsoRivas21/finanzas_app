enum TipoMovimiento { ingreso, egreso }

class Movimiento {
  final String id;
  final DateTime fecha;
  final TipoMovimiento tipo;
  final double monto;
  final String categoriaNombre;
  final String cuentaNombre;
  final String? comentario;
  final int mes;
  final int anio;
  final bool sincronizado;

  Movimiento({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.monto,
    required this.categoriaNombre,
    required this.cuentaNombre,
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
      'categoria': categoriaNombre,
      'cuenta': cuentaNombre,
      'comentario': comentario,
      'mes': mes,
      'anio': anio,
      'sincronizado': sincronizado ? 1 : 0,
    };
  }

  factory Movimiento.fromMap(Map<String, dynamic> map) {
    final fecha = DateTime.parse(map['fecha']);
    return Movimiento(
      id: map['id'],
      fecha: fecha,
      tipo: TipoMovimiento.values.firstWhere((t) => t.name == map['tipo']),
      monto: (map['monto'] as num).toDouble(),
      categoriaNombre: map['categoria'] ?? 'INGRESOS',
      cuentaNombre: map['cuenta'] ?? 'BILLETERA',
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
      categoriaNombre: categoriaNombre ?? this.categoriaNombre,
      cuentaNombre: cuentaNombre ?? this.cuentaNombre,
      comentario: comentario ?? this.comentario,
      mes: mes ?? this.mes,
      anio: anio ?? this.anio,
      sincronizado: sincronizado ?? this.sincronizado,
    );
  }

  String get categoria => categoriaNombre;
  String get cuenta => cuentaNombre;
}

