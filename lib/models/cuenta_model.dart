// lib/models/cuenta_model.dart

class CuentaModel {
  final String id;
  final String nombre;
  final String tipo; // debito, credito, ahorro, efectivo
  final double saldoInicial;
  final bool activa;
  final int orden;

  CuentaModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.saldoInicial,
    required this.activa,
    required this.orden,
  });

  factory CuentaModel.fromMap(Map<String, dynamic> map) {
    return CuentaModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      tipo: map['tipo'] as String? ?? 'debito',
      saldoInicial: (map['saldo_inicial'] as num?)?.toDouble() ?? 0.0,
      activa: map['activa'] as bool? ?? true,
      orden: map['orden'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap(String userId) => {
    'id': id,
    'usuario_id': userId,
    'nombre': nombre,
    'tipo': tipo,
    'saldo_inicial': saldoInicial,
    'activa': activa,
    'orden': orden,
  };

  CuentaModel copyWith({
    String? nombre,
    String? tipo,
    double? saldoInicial,
    bool? activa,
    int? orden,
  }) {
    return CuentaModel(
      id: id,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      saldoInicial: saldoInicial ?? this.saldoInicial,
      activa: activa ?? this.activa,
      orden: orden ?? this.orden,
    );
  }

  bool get esTarjeta => tipo == 'credito';
  bool get esAhorro  => tipo == 'ahorro';
}
