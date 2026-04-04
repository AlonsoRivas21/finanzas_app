// lib/models/movimiento.dart

enum TipoMovimiento { ingreso, egreso }

enum Categoria {
  ingresos,
  transporte,
  comerFuera,
  transferencia,
  servicios,
  shopping,
  saldo,
  hogar,
  proviciones,
  perdido,
  entretenimiento,
  pelo,
}

extension CategoriaExtension on Categoria {
  String get nombre {
    switch (this) {
      case Categoria.ingresos:        return 'INGRESOS';
      case Categoria.transporte:      return 'TRANSPORTE';
      case Categoria.comerFuera:      return 'COMER FUERA';
      case Categoria.transferencia:   return 'TRANSFERENCIA';
      case Categoria.servicios:       return 'SERVICIOS';
      case Categoria.shopping:        return 'SHOPPING';
      case Categoria.saldo:           return 'SALDO';
      case Categoria.hogar:           return 'HOGAR';
      case Categoria.proviciones:     return 'PROVICIONES';
      case Categoria.perdido:         return 'PERDIDO';
      case Categoria.entretenimiento: return 'ENTRETENIMIENTO';
      case Categoria.pelo:            return 'PELO';
    }
  }

  static Categoria fromString(String s) {
    return Categoria.values.firstWhere(
      (c) => c.nombre == s.toUpperCase(),
      orElse: () => Categoria.ingresos,
    );
  }
}

enum Cuenta {
  billetera,
  debitoBa,
  debitoNiu,
  creditoBa,
  creditoNiu,
  multimoney,
}

extension CuentaExtension on Cuenta {
  String get nombre {
    switch (this) {
      case Cuenta.billetera:   return 'BILLETERA';
      case Cuenta.debitoBa:    return 'DEBITO BA';
      case Cuenta.debitoNiu:   return 'DEBITO NIU';
      case Cuenta.creditoBa:   return 'CREDITO BA';
      case Cuenta.creditoNiu:  return 'CREDITO NIU';
      case Cuenta.multimoney:  return 'MULTIMONEY';
    }
  }

  static Cuenta fromString(String s) {
    return Cuenta.values.firstWhere(
      (c) => c.nombre == s.toUpperCase(),
      orElse: () => Cuenta.billetera,
    );
  }
}

class Movimiento {
  final String id;
  final DateTime fecha;
  final TipoMovimiento tipo;
  final double monto;
  final Categoria categoria;
  final Cuenta cuenta;
  final String? comentario;
  final int mes;
  final int anio;
  final bool sincronizado;

  Movimiento({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.monto,
    required this.categoria,
    required this.cuenta,
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
      'categoria': categoria.nombre,
      'cuenta': cuenta.nombre,
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
      categoria: CategoriaExtension.fromString(map['categoria']),
      cuenta: CuentaExtension.fromString(map['cuenta']),
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
    Categoria? categoria,
    Cuenta? cuenta,
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
      categoria: categoria ?? this.categoria,
      cuenta: cuenta ?? this.cuenta,
      comentario: comentario ?? this.comentario,
      mes: mes ?? this.mes,
      anio: anio ?? this.anio,
      sincronizado: sincronizado ?? this.sincronizado,
    );
  }
}
