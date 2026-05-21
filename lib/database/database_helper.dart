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
    return openDatabase(path, version: 7,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE movimientos (
        id TEXT PRIMARY KEY,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        comentario TEXT,
        mes INTEGER NOT NULL,
        anio INTEGER NOT NULL DEFAULT ${DateTime.now().year},
        sincronizado INTEGER NOT NULL DEFAULT 0,
        cuenta_id TEXT NOT NULL,
        categoria_id TEXT NOT NULL,
        FOREIGN KEY (cuenta_id) REFERENCES cuentas (id),
        FOREIGN KEY (categoria_id) REFERENCES categorias (id)
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
    await db.execute('CREATE INDEX idx_cuenta_id ON movimientos(cuenta_id)');
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
      try {
        await db.execute('ALTER TABLE movimientos ADD COLUMN cuenta_id TEXT');
      } catch (e) { print('Migración: cuenta_id ya existe o falló: $e'); }
      
      try {
        await db.execute('ALTER TABLE movimientos ADD COLUMN categoria_id TEXT');
      } catch (e) { print('Migración: categoria_id ya existe o falló: $e'); }
      
      // Vincular datos existentes por nombre
      try {
        await db.execute('''
          UPDATE movimientos SET 
            cuenta_id = (SELECT id FROM cuentas WHERE nombre = movimientos.cuenta),
            categoria_id = (SELECT id FROM categorias WHERE nombre = movimientos.categoria)
          WHERE cuenta_id IS NULL OR categoria_id IS NULL
        ''');
      } catch (e) { print('Migración: error vinculando IDs: $e'); }
      
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_cuenta_id ON movimientos(cuenta_id)');
      } catch (e) { print('Migración: error creando índice: $e'); }
    }

    if (oldVersion < 7) {
      // MIGRACIÓN ESTRUCTURAL: Recreación de la tabla movimientos
      await db.transaction((txn) async {
        // 1. Crear la tabla nueva con la estructura correcta y Foreign Keys
        await txn.execute('''
          CREATE TABLE movimientos_nuevo (
            id TEXT PRIMARY KEY,
            fecha TEXT NOT NULL,
            tipo TEXT NOT NULL,
            monto REAL NOT NULL,
            comentario TEXT,
            mes INTEGER NOT NULL,
            anio INTEGER NOT NULL,
            sincronizado INTEGER NOT NULL DEFAULT 0,
            cuenta_id TEXT NOT NULL,
            categoria_id TEXT NOT NULL,
            FOREIGN KEY (cuenta_id) REFERENCES cuentas (id),
            FOREIGN KEY (categoria_id) REFERENCES categorias (id)
          )
        ''');

        // 2. Migrar los datos haciendo el mapeo de nombres a IDs
        // Usamos subconsultas con UPPER para asegurar que el match no falle por casing
        // Si no encuentra el ID, se pone '0' o un valor por defecto para no violar el NOT NULL
        await txn.execute('''
          INSERT INTO movimientos_nuevo (
            id, fecha, tipo, monto, comentario, mes, anio, sincronizado, cuenta_id, categoria_id
          )
          SELECT 
            m.id, m.fecha, m.tipo, m.monto, m.comentario, m.mes, m.anio, m.sincronizado,
            COALESCE((SELECT id FROM cuentas WHERE UPPER(nombre) = UPPER(m.cuenta) LIMIT 1), 'default_account_id'),
            COALESCE((SELECT id FROM categorias WHERE UPPER(nombre) = UPPER(m.categoria) LIMIT 1), 'default_category_id')
          FROM movimientos m
        ''');

        // 3. Eliminar tabla vieja y renombrar la nueva
        await txn.execute('DROP TABLE movimientos');
        await txn.execute('ALTER TABLE movimientos_nuevo RENAME TO movimientos');

        // 4. Recrear índices (importante porque se pierden al dropear la tabla)
        await txn.execute('CREATE INDEX idx_fecha ON movimientos(fecha DESC)');
        await txn.execute('CREATE INDEX idx_mes_anio ON movimientos(mes, anio)');
        await txn.execute('CREATE INDEX idx_cuenta_id ON movimientos(cuenta_id)');
      });
    }
  }

  // ── Saldos cuentas (delta) ────────────────────────────────────────────────

  Future<void> aplicarDeltaSaldoPorId(String cuentaId, double delta) async {
    final database = await db;
    // Obtener el nombre de la cuenta para la tabla saldos_cuentas
    final res = await database.query('cuentas', columns: ['nombre'], where: 'id = ?', whereArgs: [cuentaId]);
    if (res.isEmpty) return;
    
    final String cuentaNombre = res.first['nombre'] as String;
    final cuentaNorm = cuentaNombre.toUpperCase();
    
    final rows = await database.query('saldos_cuentas',
        where: 'UPPER(cuenta) = ?', whereArgs: [cuentaNorm]);

    final saldoActual = rows.isEmpty
        ? 0.0
        : (rows.first['saldo_actual'] as num).toDouble();

    await database.insert('saldos_cuentas', {
      'cuenta':       cuentaNorm,
      'saldo_actual': saldoActual + delta,
      'updated_at':   DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, double>> getSaldosActualesLocal() async {
    final database = await db;
    // Usamos UPPER en el JOIN para que no falle si hay diferencias de casing entre tablas
    final rows = await database.rawQuery('''
      SELECT s.cuenta, s.saldo_actual 
      FROM saldos_cuentas s
      INNER JOIN cuentas c ON UPPER(s.cuenta) = UPPER(c.nombre)
      WHERE c.activa = 1
    ''');
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
        (c['nombre'] as String? ?? ''):
            (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0
    };

    // 2. Sumar el neto de movimientos agrupados por cuenta y tipo
    final rows = await database.rawQuery('''
      SELECT UPPER(c.nombre) as cuenta_norm, m.tipo, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN cuentas c ON m.cuenta_id = c.id
      GROUP BY m.cuenta_id, m.tipo
    ''');

    for (final row in rows) {
      final cuenta = row['cuenta_norm'] as String;
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
    batch.delete('saldos_cuentas'); // Limpiar antes de recibir los nuevos de la nube
    for (final entry in saldos.entries) {
      batch.insert('saldos_cuentas', {
        'cuenta':       entry.key.toUpperCase(),
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

    // Asegurar que el nombre en el objeto cuenta sea consistente (Mayúsculas)
    final String newNombre = (cuenta['nombre'] as String).toUpperCase();

    if (existing.isNotEmpty) {
      final oldNombre = existing.first['nombre'] as String;

      if (oldNombre != newNombre) {
        // Ya no es necesario propagar el nombre a 'movimientos' porque usamos IDs
        // Pero sí a la tabla de saldos_cuentas que usa nombres como PK
        await database.update('saldos_cuentas', {'cuenta': newNombre},
            where: 'cuenta = ?', whereArgs: [oldNombre]);
      }
    }

    // Actualizar el mapa que se va a guardar para que sea consistente
    final cuentaParaGuardar = Map<String, dynamic>.from(cuenta);
    cuentaParaGuardar['nombre'] = newNombre;

    await database.update('cuentas', cuentaParaGuardar,
        where: 'id = ?', whereArgs: [cuenta['id']]); // Actualiza otros campos de la cuenta
    await database.update('cuentas', {'sincronizado': 0}, where: 'id = ?', whereArgs: [cuenta['id']]); // Asegura que la cuenta misma se marque como no sincronizada

    // 3. RECALIBRAR: Es vital para limpiar la tabla saldos_cuentas de nombres viejos
    await recalibrarSaldosLocales();
  }

  Future<void> deleteCuenta(String id) async {
    final database = await db;
    await database.update('cuentas', {'activa': 0, 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
    await database.insert('cuentas_eliminadas',
        {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Recalibrar para limpiar la tabla saldos_cuentas de la cuenta eliminada
    await recalibrarSaldosLocales();
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
    // Recalibrar saldos para que coincidan con el nuevo estado de las cuentas (activas/inactivas)
    await recalibrarSaldosLocales();
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
    }
    // Solo actualizamos la categoría, los movimientos ya están vinculados por ID
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
    if (m.cuentaId != null) {
      await aplicarDeltaSaldoPorId(m.cuentaId!, delta);
    }
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
      if (m.cuentaId != null) {
        await aplicarDeltaSaldoPorId(m.cuentaId!, delta);
      }
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
      if (anterior.cuentaId != null) {
        await aplicarDeltaSaldoPorId(anterior.cuentaId!, deltaAnterior);
      }
    }
    await database.update('movimientos', nuevo.toMap(),
        where: 'id = ?', whereArgs: [nuevo.id]);
    await database.update('movimientos', {'sincronizado': 0}, where: 'id = ?', whereArgs: [nuevo.id]); // Marcar como no sincronizado para que se suba
    final deltaNuevo = nuevo.tipo == TipoMovimiento.ingreso
        ? nuevo.monto : -nuevo.monto;
    if (nuevo.cuentaId != null) {
      await aplicarDeltaSaldoPorId(nuevo.cuentaId!, deltaNuevo);
    }
  }

  Future<void> deleteMovimiento(String id) async {
    final database = await db;
    final rows = await database.query('movimientos',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final m = Movimiento.fromMap(rows.first);
      final delta = m.tipo == TipoMovimiento.ingreso ? -m.monto : m.monto;
      if (m.cuentaId != null) {
        await aplicarDeltaSaldoPorId(m.cuentaId!, delta);
      }
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

    if (mes != null)    { where.add('m.mes = ?');    args.add(mes); }
    if (anio != null)   { where.add('m.anio = ?');   args.add(anio); }
    if (cuenta != null) { where.add('m.cuenta_id = ?'); args.add(cuenta); }
    if (tipo != null)   { where.add('m.tipo = ?');   args.add(tipo); }
    if (busqueda != null && busqueda.isNotEmpty) {
      // Búsqueda más eficiente aprovechando los JOINs
      where.add('(m.comentario LIKE ? OR categorias.nombre LIKE ? OR cuentas.nombre LIKE ?)');
      final q = '%$busqueda%';
      args.addAll([q, q, q]);
    }

    final whereString = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    
    final sql = '''
      SELECT m.*, categorias.nombre AS categoria_nombre, cuentas.nombre AS cuenta_nombre
      FROM movimientos AS m
      LEFT JOIN categorias ON m.categoria_id = categorias.id
      LEFT JOIN cuentas ON m.cuenta_id = cuentas.id
      $whereString
      ORDER BY m.fecha DESC
      LIMIT $limit OFFSET $offset
    ''';

    final rows = await database.rawQuery(sql, args);
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
      SELECT m.tipo, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN categorias c ON m.categoria_id = c.id
      WHERE m.mes = ? 
        AND m.anio = ?
        AND (
          (m.tipo = 'egreso' AND UPPER(TRIM(c.nombre)) != 'TRANSFERENCIA')
          OR (m.tipo = 'ingreso' AND UPPER(TRIM(c.nombre)) = 'INGRESOS')
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
      SELECT c.nombre as cuenta, m.tipo, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN cuentas c ON m.cuenta_id = c.id
      WHERE m.anio = ? AND c.activa = 1
      GROUP BY c.nombre, m.tipo
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
      SELECT c.nombre as categoria, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN categorias c ON m.categoria_id = c.id
      WHERE m.mes = ? AND m.anio = ? AND m.tipo = 'egreso'
      GROUP BY c.nombre ORDER BY total DESC
    ''', [mes, anio]);
  }

  Future<List<Map<String, dynamic>>> getResumenPorSemana(
      int mes, int anio) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT
        CASE
          WHEN CAST(strftime('%d', m.fecha) AS INTEGER) <= 7  THEN 0
          WHEN CAST(strftime('%d', m.fecha) AS INTEGER) <= 14 THEN 1
          WHEN CAST(strftime('%d', m.fecha) AS INTEGER) <= 21 THEN 2
          ELSE 3
        END as semana,
        m.tipo, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN categorias c ON m.categoria_id = c.id
      WHERE m.mes = ? AND m.anio = ?
        AND c.nombre NOT IN ('TRANSFERENCIA', 'SALDO')
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
    // Al limpiar movimientos, también debemos reiniciar la tabla de saldos calculados
    await database.delete('saldos_cuentas');
  }
}
