// lib/database/presupuesto_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';

class PresupuestoModel {
  final String id;
  final String tipo; // 'categoria' o 'cuenta'
  final String nombre; // nombre de la categoría o cuenta
  final double limite;
  final int mes;
  final int anio;
  final bool sincronizado;

  PresupuestoModel({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.limite,
    required this.mes,
    required this.anio,
    this.sincronizado = false,
  });

  factory PresupuestoModel.fromMap(Map<String, dynamic> map) {
    return PresupuestoModel(
      id:           map['id'] as String,
      tipo:         map['tipo'] as String? ?? 'categoria',
      nombre:       (map['categoria'] ?? map['nombre']) as String,
      limite:       (map['limite'] as num).toDouble(),
      mes:          map['mes'] as int,
      anio:         map['anio'] as int,
      sincronizado: (map['sincronizado'] == 1 || map['sincronizado'] == true),
    );
  }

  Map<String, dynamic> toLocalMap() => {
    'id':           id,
    'tipo':         tipo,
    'nombre':       nombre,
    'limite':       limite,
    'mes':          mes,
    'anio':         anio,
    'sincronizado': sincronizado ? 1 : 0,
  };

  Map<String, dynamic> toSupabaseMap(String userId) => {
    'id':         id,
    'usuario_id': userId,
    'tipo':       tipo,
    'categoria':  nombre,
    'limite':     limite,
    'mes':        mes,
    'anio':       anio,
  };
}

class PresupuestoService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();
  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

  // ── BD Local ──────────────────────────────────────────────────────────────

  static Future<Database> get _db async {
    final db = await DatabaseHelper().db;
    // Crear tabla si no existe
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuestos (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL DEFAULT 'categoria',
        nombre TEXT NOT NULL,
        limite REAL NOT NULL,
        mes INTEGER NOT NULL,
        anio INTEGER NOT NULL,
        sincronizado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    return db;
  }

  static Future<List<PresupuestoModel>> getPresupuestos(
      int mes, int anio) async {
    final db = await _db;
    final rows = await db.query(
      'presupuestos',
      where: 'mes = ? AND anio = ?',
      whereArgs: [mes, anio],
      orderBy: 'tipo, nombre',
    );
    return rows.map(PresupuestoModel.fromMap).toList();
  }

  static Future<void> guardar(PresupuestoModel p) async {
    final db = await _db;
    await db.insert(
      'presupuestos',
      p.copyWith(sincronizado: false).toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> eliminar(String id) async {
    final db = await _db;
    await db.delete('presupuestos', where: 'id = ?', whereArgs: [id]);
    // Registrar eliminación para sync
    await db.insert(
      'presupuestos_eliminados',
      {'id': id, 'eliminado_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<PresupuestoModel>> getNoSincronizados() async {
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuestos_eliminados (
        id TEXT PRIMARY KEY,
        eliminado_at TEXT NOT NULL
      )
    ''');
    final rows = await db.query('presupuestos',
        where: 'sincronizado = ?', whereArgs: [0]);
    return rows.map(PresupuestoModel.fromMap).toList();
  }

  static Future<List<String>> getEliminadosPendientes() async {
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuestos_eliminados (
        id TEXT PRIMARY KEY,
        eliminado_at TEXT NOT NULL
      )
    ''');
    final rows = await db.query('presupuestos_eliminados');
    return rows.map((r) => r['id'] as String).toList();
  }

  static Future<void> marcarSincronizados(List<String> ids) async {
    final db = await _db;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('presupuestos', {'sincronizado': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> limpiarEliminados() async {
    final db = await _db;
    await db.delete('presupuestos_eliminados');
  }

  // ── Supabase ──────────────────────────────────────────────────────────────

  static Future<void> subirPresupuestos() async {
    if (!_autenticado) return;

    final pendientes = await getNoSincronizados();
    if (pendientes.isNotEmpty) {
      final rows = pendientes
          .map((p) => p.toSupabaseMap(_uid))
          .toList();
      await _client.from('presupuestos')
          .upsert(rows, onConflict: 'usuario_id,tipo,categoria,mes,anio');
      await marcarSincronizados(pendientes.map((p) => p.id).toList());
    }

    final eliminados = await getEliminadosPendientes();
    if (eliminados.isNotEmpty) {
      for (final id in eliminados) {
        await _client.from('presupuestos').delete().eq('id', id);
      }
      await limpiarEliminados();
    }
  }

  static Future<void> bajarPresupuestos() async {
    if (!_autenticado) return;

    final res = await _client
        .from('presupuestos')
        .select()
        .eq('usuario_id', _uid);

    if ((res as List).isEmpty) return;

    final db = await _db;
    await db.delete('presupuestos');
    final batch = db.batch();
    for (final row in res) {
      final p = PresupuestoModel.fromMap({
        ...row,
        'sincronizado': 1,
      });
      batch.insert('presupuestos', p.toLocalMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Gastos reales ─────────────────────────────────────────────────────────

  static Future<Map<String, double>> getGastosRealesCategorias(
      int mes, int anio) async {
    final db = await DatabaseHelper().db;
    final rows = await db.rawQuery('''
      SELECT categoria, SUM(monto) as total
      FROM movimientos
      WHERE mes = ? AND anio = ? AND tipo = 'egreso'
      GROUP BY categoria
    ''', [mes, anio]);

    return {
      for (final r in rows)
        r['categoria'] as String: (r['total'] as num).toDouble()
    };
  }

  static Future<Map<String, double>> getGastosRealesCuentas(
      int mes, int anio) async {
    final db = await DatabaseHelper().db;
    final rows = await db.rawQuery('''
      SELECT cuenta, SUM(monto) as total
      FROM movimientos
      WHERE mes = ? AND anio = ? AND tipo = 'egreso'
      GROUP BY cuenta
    ''', [mes, anio]);

    return {
      for (final r in rows)
        r['cuenta'] as String: (r['total'] as num).toDouble()
    };
  }

  static PresupuestoModel crear({
    required String tipo,
    required String nombre,
    required double limite,
    required int mes,
    required int anio, String? id,
  }) {
    return PresupuestoModel(
      id:     id ?? _uuid.v4(),
      tipo:   tipo,
      nombre: nombre,
      limite: limite,
      mes:    mes,
      anio:   anio,
      sincronizado: false,
    );
  }
}

extension _PresupuestoModelCopyWith on PresupuestoModel {
  PresupuestoModel copyWith({bool? sincronizado}) {
    return PresupuestoModel(
      id:           id,
      tipo:         tipo,
      nombre:       nombre,
      limite:       limite,
      mes:          mes,
      anio:         anio,
      sincronizado: sincronizado ?? this.sincronizado,
    );
  }
}
