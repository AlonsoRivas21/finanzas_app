// lib/database/excel_resumen.dart
// Cálculos puros para las hojas de análisis del Excel.
// No dependen de SQLite ni de Supabase, por lo que son fáciles de probar.

import '../models/movimiento.dart';

const List<String> mesesNombre = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

String mesNombre(int mes) =>
    (mes >= 1 && mes <= 12) ? mesesNombre[mes - 1] : '';

String nombreCategoria(Movimiento m, Map<String, String> mapaCategorias) {
  final nombre = m.categoriaNombre;
  if (nombre != null && nombre.isNotEmpty) return nombre;
  final id = m.categoriaId;
  if (id == null || id.isEmpty) return 'Sin categoría';
  return mapaCategorias[id] ?? id;
}

String nombreCuenta(Movimiento m, Map<String, String> mapaCuentas) {
  final nombre = m.cuentaNombre;
  if (nombre != null && nombre.isNotEmpty) return nombre;
  final id = m.cuentaId;
  if (id == null || id.isEmpty) return 'Sin cuenta';
  return mapaCuentas[id] ?? id;
}

String claveMes(int anio, int mes) =>
    '$anio-${mes.toString().padLeft(2, '0')}';

class ResumenMes {
  final int anio;
  final int mes;
  double ingresos = 0;
  double egresosBrutos = 0;
  double reembolsos = 0;

  ResumenMes(this.anio, this.mes);

  double get egresosNetos => egresosBrutos - reembolsos;
  double get balance => ingresos - egresosNetos;
}

/// Aplica las mismas reglas del dashboard:
/// - Los ingresos de la categoría INGRESOS son ingresos reales.
/// - Los ingresos de otras categorías son reembolsos de gastos.
/// - TRANSFERENCIA y SALDO no cuentan como ingreso/egreso.
Map<String, ResumenMes> calcularResumenMensual(
  List<Movimiento> movimientos,
  Map<String, String> mapaCategorias,
) {
  final resumen = <String, ResumenMes>{};

  for (final m in movimientos) {
    final cat = nombreCategoria(m, mapaCategorias).toUpperCase().trim();
    final esIngreso = m.tipo == TipoMovimiento.ingreso;

    // No se crea la fila del mes si solo contiene movimientos técnicos.
    if (esIngreso) {
      if (cat == 'TRANSFERENCIA' || cat == 'SALDO' || cat.isEmpty) continue;
    } else if (cat == 'TRANSFERENCIA') {
      continue;
    }

    final key = claveMes(m.anio, m.mes);
    final r = resumen.putIfAbsent(key, () => ResumenMes(m.anio, m.mes));

    if (esIngreso) {
      if (cat == 'INGRESOS') {
        r.ingresos += m.monto;
      } else {
        r.reembolsos += m.monto;
      }
    } else {
      r.egresosBrutos += m.monto;
    }
  }

  return resumen;
}

class ResumenCategoria {
  final int anio;
  final int mes;
  final TipoMovimiento tipo;
  final String categoria;
  double total = 0;

  ResumenCategoria(this.anio, this.mes, this.tipo, this.categoria);
}

Map<String, ResumenCategoria> calcularResumenCategorias(
  List<Movimiento> movimientos,
  Map<String, String> mapaCategorias,
) {
  final resumen = <String, ResumenCategoria>{};

  for (final m in movimientos) {
    final cat = nombreCategoria(m, mapaCategorias);
    final catUpper = cat.toUpperCase().trim();
    if (catUpper == 'TRANSFERENCIA' || catUpper == 'SALDO') continue;

    final key = '${claveMes(m.anio, m.mes)}|${m.tipo.name}|$cat';
    final r = resumen.putIfAbsent(
      key,
      () => ResumenCategoria(m.anio, m.mes, m.tipo, cat),
    );
    r.total += m.monto;
  }

  return resumen;
}

/// Totales por cuenta para el rango exportado.
/// Incluye transferencias: reflejan entradas/salidas reales de cada cuenta.
Map<String, Map<String, double>> calcularResumenCuentas(
  List<Movimiento> movimientos,
  Map<String, String> mapaCuentas,
) {
  final resumen = <String, Map<String, double>>{};

  for (final m in movimientos) {
    final cuenta = nombreCuenta(m, mapaCuentas);
    final r = resumen.putIfAbsent(
      cuenta,
      () => {'ingresos': 0.0, 'egresos': 0.0},
    );

    if (m.tipo == TipoMovimiento.ingreso) {
      r['ingresos'] = r['ingresos']! + m.monto;
    } else {
      r['egresos'] = r['egresos']! + m.monto;
    }
  }

  return resumen;
}
