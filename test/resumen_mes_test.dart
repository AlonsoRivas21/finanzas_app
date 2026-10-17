// Prueba de integración del cálculo de "Resumen del mes" en la ruta móvil
// (SQLite). Reproduce el esquema real y verifica que getResumenMes ya no falla
// con "ambiguous column name: tipo" y que netea reembolsos correctamente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'package:finanzas_app/config/app_config.dart';
import 'package:finanzas_app/database/database_helper.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = p.join(await getDatabasesPath(), AppConfig.dbName);
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  Future<void> insertarMovimiento(
    Database db,
    String id,
    String tipo,
    double monto,
    String categoriaId, {
    int mes = 10,
  }) {
    return db.insert('movimientos', {
      'id': id,
      'fecha': '2026-10-01T00:00:00.000',
      'tipo': tipo,
      'monto': monto,
      'comentario': null,
      'mes': mes,
      'anio': 2026,
      'sincronizado': 0,
      'cuenta_id': 'a1',
      'categoria_id': categoriaId,
    });
  }

  test('getResumenMes no falla por columna tipo ambigua y netea reembolsos',
      () async {
    final db = await DatabaseHelper().db;

    await db.insert('cuentas', {
      'id': 'a1',
      'nombre': 'EFECTIVO',
      'tipo': 'efectivo',
      'saldo_inicial': 0.0,
      'activa': 1,
      'orden': 0,
      'sincronizado': 0,
    });

    await db.insert('categorias', {
      'id': 'c1',
      'nombre': 'Ingresos',
      'tipo': 'ingreso',
      'icono': 'label',
      'activa': 1,
      'orden': 0,
      'sincronizado': 0,
    });
    await db.insert('categorias', {
      'id': 'c2',
      'nombre': 'Comida',
      'tipo': 'egreso',
      'icono': 'label',
      'activa': 1,
      'orden': 1,
      'sincronizado': 0,
    });
    await db.insert('categorias', {
      'id': 'c3',
      'nombre': 'Transferencia',
      'tipo': 'egreso',
      'icono': 'label',
      'activa': 1,
      'orden': 2,
      'sincronizado': 0,
    });

    // Mes objetivo (10/2026): ingreso real, egreso, reembolso y transferencia.
    await insertarMovimiento(db, 'm1', 'ingreso', 1000, 'c1');
    await insertarMovimiento(db, 'm2', 'egreso', 300, 'c2');
    await insertarMovimiento(db, 'm3', 'ingreso', 100, 'c2'); // reembolso
    await insertarMovimiento(db, 'm4', 'egreso', 200, 'c3'); // transferencia
    await insertarMovimiento(db, 'm5', 'ingreso', 500, 'c3'); // transferencia
    // Otro mes: no debe contar.
    await insertarMovimiento(db, 'm6', 'egreso', 999, 'c2', mes: 9);

    final res = await DatabaseHelper().getResumenMes(10, 2026);

    expect(res['ingresos'], 1000.0);
    expect(res['egresos_brutos'], 300.0);
    expect(res['reembolsos'], 100.0);
    expect(res['egresos'], 200.0);
    expect(res['balance'], 800.0);
  });
}
