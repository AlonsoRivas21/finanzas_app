// lib/database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/movimiento.dart';
import 'saldos_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'finanzas.db');
    return openDatabase(path, version: 3,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE movimientos (
        id TEXT PRIMARY KEY,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        categoria TEXT NOT NULL,
        cuenta TEXT NOT NULL,
        comentario TEXT,
        mes INTEGER NOT NULL,
        anio INTEGER NOT NULL DEFAULT ${DateTime.now().year},
        sincronizado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE movimientos_eliminados (
        id TEXT PRIMARY KEY,
        eliminado_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_fecha ON movimientos(fecha DESC)');
    await db.execute('CREATE INDEX idx_mes_anio ON movimientos(mes, anio)');
    await db.execute('CREATE INDEX idx_cuenta ON movimientos(cuenta)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE movimientos ADD COLUMN anio INTEGER NOT NULL DEFAULT ${DateTime.now().year}');
      await db.execute(
          "UPDATE movimientos SET anio = CAST(strftime('%Y', fecha) AS INTEGER)");
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS movimientos_eliminados (
          id TEXT PRIMARY KEY,
          eliminado_at TEXT NOT NULL
        )
      ''');
    }
  }

  // ── CRUD movimientos ──────────────────────────────────────────────────────

  Future<void> insertMovimiento(Movimiento m) async {
    final database = await db;
    await database.insert('movimientos', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMovimientos(List<Movimiento> lista) async {
    final database = await db;
    final batch = database.batch();
    for (final m in lista) {
      batch.insert('movimientos', m.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateMovimiento(Movimiento m) async {
    final database = await db;
    await database.update('movimientos', m.toMap(),
        where: 'id = ?', whereArgs: [m.id]);
  }

  Future<void> deleteMovimiento(String id) async {
    final database = await db;
    await database.delete('movimientos', where: 'id = ?', whereArgs: [id]);
    // Registrar en eliminados para sincronizar después
    await database.insert(
      'movimientos_eliminados',
      {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Eliminados pendientes ─────────────────────────────────────────────────

  Future<List<String>> getEliminadosPendientes() async {
    final database = await db;
    final rows = await database.query('movimientos_eliminados');
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<void> limpiarEliminados() async {
    final database = await db;
    await database.delete('movimientos_eliminados');
  }

  // ── Consultas ─────────────────────────────────────────────────────────────

  Future<List<Movimiento>> getMovimientos({
    int? mes, int? anio, String? cuenta,
    String? tipo, String? busqueda,
    int limit = 300, int offset = 0,
  }) async {
    final database = await db;
    final where = <String>[];
    final args = <dynamic>[];

    if (mes != null)    { where.add('mes = ?');    args.add(mes); }
    if (anio != null)   { where.add('anio = ?');   args.add(anio); }
    if (cuenta != null) { where.add('cuenta = ?'); args.add(cuenta); }
    if (tipo != null)   { where.add('tipo = ?');   args.add(tipo); }
    if (busqueda != null && busqueda.isNotEmpty) {
      where.add('(categoria LIKE ? OR comentario LIKE ? OR cuenta LIKE ?)');
      final q = '%$busqueda%';
      args.addAll([q, q, q]);
    }

    final rows = await database.query(
      'movimientos',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'fecha DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Movimiento.fromMap).toList();
  }

  Future<int> countMovimientos() async {
    final database = await db;
    final result = await database
        .rawQuery('SELECT COUNT(*) as total FROM movimientos');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, double>> getResumenMes(int mes, int anio) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT tipo, SUM(monto) as total
      FROM movimientos WHERE mes = ? AND anio = ?
      GROUP BY tipo
    ''', [mes, anio]);

    double ingresos = 0, egresos = 0;
    for (final row in result) {
      if (row['tipo'] == 'ingreso') {
        ingresos = (row['total'] as num).toDouble();
      } else {
        egresos = (row['total'] as num).toDouble();
      }
    }
    return {'ingresos': ingresos, 'egresos': egresos};
  }

  Future<Map<String, double>> getSaldosPorCuentaLocal() async {
    final database = await db;
    final saldos = await SaldosService.getSaldosIniciales();
    final result = await database.rawQuery('''
      SELECT cuenta,
        SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END) as movimientos
      FROM movimientos
      GROUP BY cuenta
    ''');
    for (final row in result) {
      final cuenta = row['cuenta'] as String;
      final movs = (row['movimientos'] as num).toDouble();
      saldos[cuenta] = (saldos[cuenta] ?? 0) + movs;
    }
    return saldos;
  }

  Future<Map<String, Map<String, double>>> getResumenPorCuenta(int anio) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT cuenta, tipo, SUM(monto) as total
      FROM movimientos WHERE anio = ?
      GROUP BY cuenta, tipo
    ''', [anio]);

    final mapa = <String, Map<String, double>>{};
    for (final row in result) {
      final cuenta = row['cuenta'] as String;
      final tipo   = row['tipo'] as String;
      final total  = (row['total'] as num).toDouble();
      mapa.putIfAbsent(cuenta, () => {'ingresos': 0.0, 'egresos': 0.0});
      if (tipo == 'ingreso') {
        mapa[cuenta]!['ingresos'] = total;
      } else {
        mapa[cuenta]!['egresos'] = total;
      }
    }
    return mapa;
  }

  Future<List<Map<String, dynamic>>> getGastosPorCategoria(
      int mes, int anio) async {
    final database = await db;
    return database.rawQuery('''
      SELECT categoria, SUM(monto) as total
      FROM movimientos
      WHERE mes = ? AND anio = ? AND tipo = 'egreso'
      GROUP BY categoria ORDER BY total DESC
    ''', [mes, anio]);
  }

  Future<List<Map<String, dynamic>>> getResumenPorSemana(
      int mes, int anio) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT
        CASE
          WHEN CAST(strftime('%d', fecha) AS INTEGER) <= 7  THEN 0
          WHEN CAST(strftime('%d', fecha) AS INTEGER) <= 14 THEN 1
          WHEN CAST(strftime('%d', fecha) AS INTEGER) <= 21 THEN 2
          ELSE 3
        END as semana,
        tipo,
        SUM(monto) as total
      FROM movimientos
      WHERE mes = ? AND anio = ?
        AND categoria NOT IN ('TRANSFERENCIA', 'SALDO')
      GROUP BY semana, tipo
      ORDER BY semana
    ''', [mes, anio]);

    final semanas = List.generate(4, (i) =>
        <String, dynamic>{'semana': i, 'ingresos': 0.0, 'egresos': 0.0});

    for (final row in result) {
      final s = row['semana'] as int;
      final tipo = row['tipo'] as String;
      final total = (row['total'] as num).toDouble();
      if (tipo == 'ingreso') {
        semanas[s]['ingresos'] = total;
      } else {
        semanas[s]['egresos'] = total;
      }
    }

    return semanas.where((s) =>
        (s['ingresos'] as double) > 0 ||
        (s['egresos'] as double) > 0).toList();
  }

  Future<List<int>> getAniosDisponibles() async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT DISTINCT anio FROM movimientos ORDER BY anio DESC');
    return result.map((r) => r['anio'] as int).toList();
  }

  Future<List<Movimiento>> getNoSincronizados() async {
    final database = await db;
    final rows = await database.query('movimientos',
        where: 'sincronizado = ?', whereArgs: [0]);
    return rows.map(Movimiento.fromMap).toList();
  }

  Future<void> marcarSincronizados(List<String> ids) async {
    final database = await db;
    final batch = database.batch();
    for (final id in ids) {
      batch.update('movimientos', {'sincronizado': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearAnio(int anio) async {
    final database = await db;
    await database.delete('movimientos',
        where: 'anio = ?', whereArgs: [anio]);
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('movimientos');
    await database.delete('movimientos_eliminados');
  }
}
