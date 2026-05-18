// lib/database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../config/app_config.dart';
import '../models/movimiento.dart';

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
    final path = join(dbPath, AppConfig.dbName);
    return openDatabase(path, version: 6,
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
    await db.execute('''
      CREATE TABLE saldos_cuentas (
        cuenta TEXT PRIMARY KEY,
        saldo_actual REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cuentas (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL DEFAULT 'debito',
        saldo_inicial REAL NOT NULL DEFAULT 0,
        activa INTEGER NOT NULL DEFAULT 1,
        orden INTEGER NOT NULL DEFAULT 0,
        sincronizado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE cuentas_eliminadas (
        id TEXT PRIMARY KEY,
        eliminado_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE categorias (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL DEFAULT 'egreso',
        icono TEXT NOT NULL DEFAULT 'label',
        activa INTEGER NOT NULL DEFAULT 1,
        orden INTEGER NOT NULL DEFAULT 0,
        sincronizado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categorias_eliminadas (
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
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS saldos_cuentas (
          cuenta TEXT PRIMARY KEY,
          saldo_actual REAL NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      // Cuentas dinámicas
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cuentas (
          id TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          tipo TEXT NOT NULL DEFAULT 'debito',
          saldo_inicial REAL NOT NULL DEFAULT 0,
          activa INTEGER NOT NULL DEFAULT 1,
          orden INTEGER NOT NULL DEFAULT 0,
          sincronizado INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cuentas_eliminadas (
          id TEXT PRIMARY KEY,
          eliminado_at TEXT NOT NULL
        )
      ''');
      // Categorías dinámicas
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categorias (
          id TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          tipo TEXT NOT NULL DEFAULT 'egreso',
          icono TEXT NOT NULL DEFAULT 'label',
          activa INTEGER NOT NULL DEFAULT 1,
          orden INTEGER NOT NULL DEFAULT 0,
          sincronizado INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categorias_eliminadas (
          id TEXT PRIMARY KEY,
          eliminado_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      // Migración para usar IDs como llaves en lugar de nombres
      await db.execute('ALTER TABLE movimientos ADD COLUMN cuenta_id TEXT');
      await db.execute('ALTER TABLE movimientos ADD COLUMN categoria_id TEXT');
      
      // Vincular datos existentes por nombre
      await db.execute('''
        UPDATE movimientos SET 
          cuenta_id = (SELECT id FROM cuentas WHERE nombre = movimientos.cuenta),
          categoria_id = (SELECT id FROM categorias WHERE nombre = movimientos.categoria)
      ''');
      
      await db.execute('CREATE INDEX idx_cuenta_id ON movimientos(cuenta_id)');
    }
  }

  // ── Saldos cuentas (delta) ────────────────────────────────────────────────

  Future<void> aplicarDeltaSaldo(String cuenta, double delta) async {
    final database = await db;
    final rows = await database.query('saldos_cuentas',
        where: 'cuenta = ?', whereArgs: [cuenta]);

    final saldoActual = rows.isEmpty
        ? 0.0
        : (rows.first['saldo_actual'] as num).toDouble();

    await database.insert('saldos_cuentas', {
      'cuenta':       cuenta,
      'saldo_actual': saldoActual + delta,
      'updated_at':   DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, double>> getSaldosActualesLocal() async {
    final database = await db;
    final rows = await database.query('saldos_cuentas');
    return {
      for (final row in rows)
        row['cuenta'] as String: (row['saldo_actual'] as num).toDouble()
    };
  }

  /// Recalcula los saldos de todas las cuentas desde cero: Saldo Inicial + Movimientos
  Future<void> recalibrarSaldosLocales() async {
    final database = await db;
    
    // 1. Obtener saldos iniciales de cuentas activas
    final cuentas = await getCuentas();
    final saldos = <String, double>{
      for (var c in cuentas) 
        c['nombre'] as String: (c['saldo_inicial'] as num).toDouble()
    };

    // 2. Sumar el neto de movimientos agrupados por cuenta y tipo
    final rows = await database.rawQuery('''
      SELECT cuenta, tipo, SUM(monto) as total
      FROM movimientos
      GROUP BY cuenta, tipo
    ''');

    for (final row in rows) {
      final cuenta = row['cuenta'] as String;
      if (saldos.containsKey(cuenta)) {
        final monto = (row['total'] as num).toDouble();
        final delta = row['tipo'] == 'ingreso' ? monto : -monto;
        saldos[cuenta] = (saldos[cuenta] ?? 0) + delta;
      }
    }

    // 3. Actualizar la tabla de saldos actuales (Limpiar e Insertar)
    final batch = database.batch();
    batch.delete('saldos_cuentas');
    for (final entry in saldos.entries) {
      batch.insert('saldos_cuentas', {
        'cuenta': entry.key,
        'saldo_actual': entry.value,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateSaldoInicial(String nombreCuenta, double saldo) async {
    final database = await db;
    await database.update(
      'cuentas',
      {'saldo_inicial': saldo, 'sincronizado': 0},
      where: 'nombre = ?',
      whereArgs: [nombreCuenta],
    );
  }

  Future<void> setSaldoCuenta(String cuenta, double saldo) async {
    final database = await db;
    await database.insert('saldos_cuentas', {
      'cuenta':       cuenta,
      'saldo_actual': saldo,
      'updated_at':   DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> guardarSaldosDesdeNube(Map<String, double> saldos) async {
    final database = await db;
    final batch = database.batch();
    for (final entry in saldos.entries) {
      batch.insert('saldos_cuentas', {
        'cuenta':       entry.key,
        'saldo_actual': entry.value,
        'updated_at':   DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Cuentas dinámicas ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCuentas() async {
    final database = await db;
    return database.query('cuentas',
        where: 'activa = ?', whereArgs: [1], orderBy: 'orden');
  }

  Future<void> insertCuenta(Map<String, dynamic> cuenta) async {
    final database = await db;
    await database.insert('cuentas', cuenta,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateCuenta(Map<String, dynamic> cuenta) async {
    final database = await db;

    // 1. Obtener el nombre actual antes de actualizar para saber si cambió
    final existing = await database.query('cuentas',
        columns: ['nombre'], where: 'id = ?', whereArgs: [cuenta['id']]);

    if (existing.isNotEmpty) {
      final oldNombre = existing.first['nombre'] as String;
      final newNombre = (cuenta['nombre'] as String).toUpperCase();

      if (oldNombre != newNombre) {
        // 2. Propagar el cambio a movimientos y marcar para re-sincronizar
        // Es vital poner sincronizado = 0 para que la nube se entere del cambio de nombre
        await database.update('movimientos', {
          'cuenta': newNombre,
          'sincronizado': 0 
        },
            where: 'cuenta = ?', whereArgs: [oldNombre]);

        await database.update('saldos_cuentas', {'cuenta': newNombre},
            where: 'cuenta = ?', whereArgs: [oldNombre]);
      }
    }

    await database.update('cuentas', cuenta,
        where: 'id = ?', whereArgs: [cuenta['id']]); // Actualiza otros campos de la cuenta
    await database.update('cuentas', {'sincronizado': 0}, where: 'id = ?', whereArgs: [cuenta['id']]); // Asegura que la cuenta misma se marque como no sincronizada
  }

  Future<void> deleteCuenta(String id) async {
    final database = await db;
    await database.update('cuentas', {'activa': 0, 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
    await database.insert('cuentas_eliminadas',
        {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCuentasNoSincronizadas() async {
    final database = await db;
    return database.query('cuentas',
        where: 'sincronizado = ?', whereArgs: [0]);
  }

  Future<List<String>> getCuentasEliminadasPendientes() async {
    final database = await db;
    final rows = await database.query('cuentas_eliminadas');
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<void> marcarCuentasSincronizadas(List<String> ids) async {
    final database = await db;
    final batch = database.batch();
    for (final id in ids) {
      batch.update('cuentas', {'sincronizado': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> limpiarCuentasEliminadas() async {
    final database = await db;
    await database.delete('cuentas_eliminadas');
  }

  Future<void> reemplazarCuentas(List<Map<String, dynamic>> cuentas) async {
    final database = await db;
    await database.delete('cuentas');
    final batch = database.batch();
    for (final c in cuentas) {
      batch.insert('cuentas', c,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Categorías dinámicas ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCategorias({String? tipo}) async {
    final database = await db;
    if (tipo == null) {
      return database.query('categorias',
          where: 'activa = ?', whereArgs: [1], orderBy: 'orden');
    }
    return database.query('categorias',
        where: 'activa = ? AND (tipo = ? OR tipo = ?)',
        whereArgs: [1, tipo, 'ambos'],
        orderBy: 'orden');
  }

  Future<void> insertCategoria(Map<String, dynamic> cat) async {
    final database = await db;
    await database.insert('categorias', cat,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateCategoria(Map<String, dynamic> cat) async {
    final database = await db;

    // 1. Obtener el nombre actual antes de actualizar
    final existing = await database.query('categorias',
        columns: ['nombre'], where: 'id = ?', whereArgs: [cat['id']]);

    if (existing.isNotEmpty) {
      final oldNombre = existing.first['nombre'] as String;
      final newNombre = (cat['nombre'] as String).toUpperCase();

      if (oldNombre != newNombre) {
        // 2. Propagar a movimientos y marcar para re-sincronizar
        await database.update('movimientos', {
          'categoria': newNombre,
          'sincronizado': 0
        },
            where: 'categoria = ?', whereArgs: [oldNombre]);
      }
    }

    await database.update('categorias', cat,
        where: 'id = ?', whereArgs: [cat['id']]); // Actualiza otros campos de la categoría
    await database.update('categorias', {'sincronizado': 0}, where: 'id = ?', whereArgs: [cat['id']]); // Asegura que la categoría misma se marque como no sincronizada
  }

  Future<void> deleteCategoria(String id) async {
    final database = await db;
    await database.update('categorias', {'activa': 0, 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
    await database.insert('categorias_eliminadas',
        {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCategoriasNoSincronizadas() async {
    final database = await db;
    return database.query('categorias',
        where: 'sincronizado = ?', whereArgs: [0]);
  }

  Future<List<String>> getCategoriasEliminadasPendientes() async {
    final database = await db;
    final rows = await database.query('categorias_eliminadas');
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<void> marcarCategoriasSincronizadas(List<String> ids) async {
    final database = await db;
    final batch = database.batch();
    for (final id in ids) {
      batch.update('categorias', {'sincronizado': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> limpiarCategoriasEliminadas() async {
    final database = await db;
    await database.delete('categorias_eliminadas');
  }

  Future<void> reemplazarCategorias(List<Map<String, dynamic>> cats) async {
    final database = await db;
    await database.delete('categorias');
    final batch = database.batch();
    for (final c in cats) {
      batch.insert('categorias', c,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── CRUD movimientos ──────────────────────────────────────────────────────

  Future<void> insertMovimiento(Movimiento m) async {
    final database = await db;
    await database.insert('movimientos', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    final delta = m.tipo == TipoMovimiento.ingreso ? m.monto : -m.monto;
    await aplicarDeltaSaldo(m.cuentaNombre, delta);
  }

  Future<void> insertMovimientos(List<Movimiento> lista) async {
    final database = await db;
    final batch = database.batch();
    for (final m in lista) {
      batch.insert('movimientos', m.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    for (final m in lista) {
      final delta = m.tipo == TipoMovimiento.ingreso ? m.monto : -m.monto;
      await aplicarDeltaSaldo(m.cuentaNombre, delta);
    }
  }

  Future<void> updateMovimiento(Movimiento nuevo) async {
    final database = await db;
    final rows = await database.query('movimientos',
        where: 'id = ?', whereArgs: [nuevo.id]);
    if (rows.isNotEmpty) {
      final anterior = Movimiento.fromMap(rows.first);
      final deltaAnterior = anterior.tipo == TipoMovimiento.ingreso
          ? -anterior.monto : anterior.monto;
      await aplicarDeltaSaldo(anterior.cuentaNombre, deltaAnterior);
    }
    await database.update('movimientos', nuevo.toMap(),
        where: 'id = ?', whereArgs: [nuevo.id]);
    await database.update('movimientos', {'sincronizado': 0}, where: 'id = ?', whereArgs: [nuevo.id]); // Marcar como no sincronizado para que se suba
    final deltaNuevo = nuevo.tipo == TipoMovimiento.ingreso
        ? nuevo.monto : -nuevo.monto;
    await aplicarDeltaSaldo(nuevo.cuentaNombre, deltaNuevo);
  }

  Future<void> deleteMovimiento(String id) async {
    final database = await db;
    final rows = await database.query('movimientos',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final m = Movimiento.fromMap(rows.first);
      final delta = m.tipo == TipoMovimiento.ingreso ? -m.monto : m.monto;
      await aplicarDeltaSaldo(m.cuentaNombre, delta);
    }
    await database.delete('movimientos', where: 'id = ?', whereArgs: [id]);
    await database.insert('movimientos_eliminados',
        {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
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
    final args  = <dynamic>[];

    if (mes != null)    { where.add('mes = ?');    args.add(mes); }
    if (anio != null)   { where.add('anio = ?');   args.add(anio); }
    if (cuenta != null) { where.add('cuenta = ?'); args.add(cuenta); }
    if (tipo != null)   { where.add('tipo = ?');   args.add(tipo); }
    if (busqueda != null && busqueda.isNotEmpty) {
      where.add('(categoria LIKE ? OR comentario LIKE ? OR cuenta LIKE ?)');
      final q = '%$busqueda%';
      args.addAll([q, q, q]);
    }

    final rows = await database.query('movimientos',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'fecha DESC', limit: limit, offset: offset);
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
      FROM movimientos 
      WHERE mes = ? 
        AND anio = ?
        AND (
          (tipo = 'egreso' AND UPPER(TRIM(categoria)) != 'TRANSFERENCIA')
          OR (tipo = 'ingreso' AND UPPER(TRIM(categoria)) = 'INGRESOS')
        )
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

  Future<Map<String, double>> getSaldosPorCuentaLocal() async =>
      getSaldosActualesLocal();

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
        tipo, SUM(monto) as total
      FROM movimientos
      WHERE mes = ? AND anio = ?
        AND categoria NOT IN ('TRANSFERENCIA', 'SALDO')
      GROUP BY semana, tipo ORDER BY semana
    ''', [mes, anio]);

    final semanas = List.generate(4, (i) =>
        <String, dynamic>{'semana': i, 'ingresos': 0.0, 'egresos': 0.0});
    for (final row in result) {
      final s     = row['semana'] as int;
      final tipo  = row['tipo'] as String;
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

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('movimientos');
    await database.delete('movimientos_eliminados');
    // NO limpiar saldos_cuentas, cuentas ni categorias
  }
}
