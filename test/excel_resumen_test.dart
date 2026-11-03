// Pruebas de los cálculos puros usados por las hojas de análisis del Excel.

import 'package:flutter_test/flutter_test.dart';

import 'package:finanzas_app/database/excel_resumen.dart';
import 'package:finanzas_app/models/movimiento.dart';

const _categorias = {
  'c-ingresos': 'Ingresos',
  'c-comida': 'Comida',
  'c-transporte': 'Transporte',
  'c-transfer': 'Transferencia',
  'c-saldo': 'Saldo',
};

const _cuentas = {
  'a-efectivo': 'Efectivo',
  'a-banco': 'Banco',
};

Movimiento _mov({
  required String id,
  required TipoMovimiento tipo,
  required double monto,
  String? categoriaId,
  String? cuentaId,
  int mes = 10,
  int anio = 2026,
}) {
  return Movimiento(
    id: id,
    fecha: DateTime(anio, mes, 1),
    tipo: tipo,
    monto: monto,
    categoriaId: categoriaId,
    cuentaId: cuentaId,
    mes: mes,
    anio: anio,
  );
}

void main() {
  group('helpers', () {
    test('mesNombre y claveMes', () {
      expect(mesNombre(1), 'Enero');
      expect(mesNombre(12), 'Diciembre');
      expect(mesNombre(0), '');
      expect(mesNombre(13), '');
      expect(claveMes(2026, 3), '2026-03');
      expect(claveMes(2026, 11), '2026-11');
    });

    test('nombres de categoría y cuenta con fallback', () {
      final m = _mov(
        id: 'm1',
        tipo: TipoMovimiento.egreso,
        monto: 10,
        categoriaId: 'desconocida',
      );

      expect(nombreCategoria(m, _categorias), 'desconocida');
      expect(nombreCuenta(m, _cuentas), 'Sin cuenta');
      expect(nombreCategoria(_mov(
        id: 'm2',
        tipo: TipoMovimiento.egreso,
        monto: 10,
      ), _categorias), 'Sin categoría');
    });

    test('prioriza los nombres del JOIN sobre el catálogo', () {
      final m = Movimiento(
        id: 'm1',
        fecha: DateTime(2026, 10, 1),
        tipo: TipoMovimiento.egreso,
        monto: 10,
        categoriaId: 'c-borrada',
        cuentaId: 'a-borrada',
        categoriaNombre: 'Comida vieja',
        cuentaNombre: 'Cuenta vieja',
        mes: 10,
        anio: 2026,
      );

      expect(nombreCategoria(m, _categorias), 'Comida vieja');
      expect(nombreCuenta(m, _cuentas), 'Cuenta vieja');
    });
  });

  group('calcularResumenMensual', () {
    test('netea reembolsos y excluye transferencias y saldos', () {
      final movimientos = [
        _mov(
          id: 'm1',
          tipo: TipoMovimiento.ingreso,
          monto: 1000,
          categoriaId: 'c-ingresos',
        ),
        _mov(
          id: 'm2',
          tipo: TipoMovimiento.egreso,
          monto: 300,
          categoriaId: 'c-comida',
        ),
        _mov(
          id: 'm3',
          tipo: TipoMovimiento.ingreso,
          monto: 100,
          categoriaId: 'c-comida',
        ),
        _mov(
          id: 'm4',
          tipo: TipoMovimiento.egreso,
          monto: 200,
          categoriaId: 'c-transfer',
        ),
        _mov(
          id: 'm5',
          tipo: TipoMovimiento.ingreso,
          monto: 500,
          categoriaId: 'c-transfer',
        ),
        _mov(
          id: 'm6',
          tipo: TipoMovimiento.ingreso,
          monto: 400,
          categoriaId: 'c-saldo',
        ),
      ];

      final resumen = calcularResumenMensual(movimientos, _categorias);
      final octubre = resumen['2026-10']!;

      expect(octubre.ingresos, 1000.0);
      expect(octubre.egresosBrutos, 300.0);
      expect(octubre.reembolsos, 100.0);
      expect(octubre.egresosNetos, 200.0);
      expect(octubre.balance, 800.0);
    });

    test('no crea filas para meses con solo movimientos técnicos', () {
      final movimientos = [
        _mov(
          id: 'm1',
          tipo: TipoMovimiento.egreso,
          monto: 200,
          categoriaId: 'c-transfer',
          mes: 11,
        ),
        _mov(
          id: 'm2',
          tipo: TipoMovimiento.ingreso,
          monto: 500,
          categoriaId: 'c-transfer',
          mes: 11,
        ),
        _mov(
          id: 'm3',
          tipo: TipoMovimiento.ingreso,
          monto: 400,
          categoriaId: 'c-saldo',
          mes: 11,
        ),
      ];

      final resumen = calcularResumenMensual(movimientos, _categorias);

      expect(resumen.containsKey('2026-11'), isFalse);
    });
  });

  group('calcularResumenCategorias', () {
    test('separa por mes y tipo y excluye transferencias y saldos', () {
      final movimientos = [
        _mov(
          id: 'm1',
          tipo: TipoMovimiento.egreso,
          monto: 300,
          categoriaId: 'c-comida',
        ),
        _mov(
          id: 'm2',
          tipo: TipoMovimiento.ingreso,
          monto: 100,
          categoriaId: 'c-comida',
        ),
        _mov(
          id: 'm3',
          tipo: TipoMovimiento.ingreso,
          monto: 1000,
          categoriaId: 'c-ingresos',
        ),
        _mov(
          id: 'm4',
          tipo: TipoMovimiento.egreso,
          monto: 200,
          categoriaId: 'c-transfer',
        ),
        _mov(
          id: 'm5',
          tipo: TipoMovimiento.ingreso,
          monto: 500,
          categoriaId: 'c-transfer',
        ),
        _mov(
          id: 'm6',
          tipo: TipoMovimiento.ingreso,
          monto: 400,
          categoriaId: 'c-saldo',
        ),
        _mov(
          id: 'm7',
          tipo: TipoMovimiento.egreso,
          monto: 50,
          categoriaId: 'c-transporte',
          mes: 11,
        ),
      ];

      final resumen = calcularResumenCategorias(movimientos, _categorias);

      expect(resumen.length, 4);
      expect(resumen['2026-10|egreso|Comida']!.total, 300.0);
      expect(resumen['2026-10|ingreso|Comida']!.total, 100.0);
      expect(resumen['2026-10|ingreso|Ingresos']!.total, 1000.0);
      expect(resumen['2026-11|egreso|Transporte']!.total, 50.0);
    });
  });

  group('calcularResumenCuentas', () {
    test('suma ingresos y egresos por cuenta, incluyendo transferencias', () {
      final movimientos = [
        _mov(
          id: 'm1',
          tipo: TipoMovimiento.ingreso,
          monto: 1000,
          categoriaId: 'c-ingresos',
          cuentaId: 'a-efectivo',
        ),
        _mov(
          id: 'm2',
          tipo: TipoMovimiento.egreso,
          monto: 300,
          categoriaId: 'c-comida',
          cuentaId: 'a-efectivo',
        ),
        _mov(
          id: 'm3',
          tipo: TipoMovimiento.egreso,
          monto: 200,
          categoriaId: 'c-comida',
          cuentaId: 'a-banco',
        ),
        _mov(
          id: 'm4',
          tipo: TipoMovimiento.ingreso,
          monto: 500,
          categoriaId: 'c-transfer',
          cuentaId: 'a-banco',
        ),
        _mov(
          id: 'm5',
          tipo: TipoMovimiento.ingreso,
          monto: 100,
          categoriaId: 'c-transfer',
          cuentaId: 'a-banco',
        ),
        _mov(
          id: 'm6',
          tipo: TipoMovimiento.egreso,
          monto: 50,
          categoriaId: 'c-comida',
        ),
      ];

      final resumen = calcularResumenCuentas(movimientos, _cuentas);

      expect(resumen['Efectivo']!['ingresos'], 1000.0);
      expect(resumen['Efectivo']!['egresos'], 300.0);
      expect(resumen['Banco']!['ingresos'], 600.0);
      expect(resumen['Banco']!['egresos'], 200.0);
      expect(resumen['Sin cuenta']!['ingresos'], 0.0);
      expect(resumen['Sin cuenta']!['egresos'], 50.0);
    });
  });
}
