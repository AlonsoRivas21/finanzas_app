// lib/database/presupuesto_service.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';

class PresupuestoModel {
  final String id;
  final String tipo; // 'categoria' o 'cuenta'
  final String? categoriaId; // UUID de la categoría o cuenta
  final String? cuentaId; // UUID de la cuenta
  final double limite;
  final int mes;
  final int anio;
  final bool sincronizado;
  final String? nombre; // Nombre descriptivo (obtenido por join)

  PresupuestoModel({
    required this.id,
    required this.tipo,
    this.categoriaId,
    this.cuentaId,
    required this.limite,
    required this.mes,
    required this.anio,
    this.sincronizado = false,
    this.nombre,
  });

  factory PresupuestoModel.fromMap(Map<String, dynamic> map) {
    String? displayNombre;
    final tipo = map['tipo']?.toString() ?? 'categoria';

    // Prioridad por tipo para obtener el nombre correcto
    if (tipo == 'categoria') {
      if (map['categorias'] != null && map['categorias'] is Map) {
        displayNombre = map['categorias']['nombre']?.toString();
      } else if (map['nombre_display'] != null) {
        displayNombre = map['nombre_display']?.toString();
      }
    } else if (tipo == 'cuenta') {
      if (map['cuentas'] != null && map['cuentas'] is Map) {
        displayNombre = map['cuentas']['nombre']?.toString();
      } else if (map['nombre_display'] != null) {
        displayNombre = map['nombre_display']?.toString();
      }
    }

    displayNombre ??= 'Sin nombre'; // Fallback

    return PresupuestoModel(
      id:          map['id']?.toString() ?? '',
      tipo:        tipo,
      categoriaId: map['categoria_id']?.toString(),
      cuentaId:    map['cuenta_id']?.toString(),
      limite:       (map['limite'] as num? ?? 0.0).toDouble(),
      mes:          map['mes'] as int? ?? 0,
      anio:         map['anio'] as int? ?? 0,
      sincronizado: (map['sincronizado'] == 1 || map['sincronizado'] == true),
      nombre:       displayNombre,
    );
  }

  Map<String, dynamic> toLocalMap() => {
    'id':           id,
    'tipo':         tipo,
    'categoria_id': categoriaId,
    'cuenta_id':    cuentaId,
    'limite':     limite,
    'mes':          mes,
    'anio':         anio,
    'sincronizado': sincronizado ? 1 : 0,
  };

  Map<String, dynamic> toSupabaseMap(String userId) => {
    'id':         id,
    'usuario_id': userId,
    'tipo':     tipo,
    'categoria_id': categoriaId,
    'cuenta_id':    cuentaId,
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

  static Future<Database> get _db => DatabaseHelper().db;

  static Future<List<PresupuestoModel>> getPresupuestos(
      int mes, int anio) async {
    if (kIsWeb) {
      if (!_autenticado) return [];
      final res = await _client // Fetch both category and account names for display
          .from('presupuestos')
          .select('*, categorias(nombre), cuentas(nombre)')
          .eq('usuario_id', _uid)
          .eq('mes', mes)
          .eq('anio', anio)
          .order('tipo');
      return List<Map<String, dynamic>>.from(res as List).map(PresupuestoModel.fromMap).toList();
    }
    // Use rawQuery with LEFT JOINs to get the display name
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        p.id, p.tipo, p.categoria_id, p.cuenta_id, p.limite, p.mes, p.anio, p.sincronizado,
        CASE
          WHEN p.tipo = 'categoria' THEN c.nombre
          WHEN p.tipo = 'cuenta' THEN cu.nombre
          ELSE NULL
        END AS nombre_display
      FROM presupuestos AS p
      LEFT JOIN categorias AS c ON p.categoria_id = c.id
      LEFT JOIN cuentas AS cu ON p.cuenta_id = cu.id
      WHERE p.mes = ? AND p.anio = ?
      ORDER BY p.tipo
    ''', [mes, anio]);

    return rows.map((row) => PresupuestoModel.fromMap({
      ...row,
      'nombre_display': row['nombre_display'], // Map the joined name to 'nombre_display' for fromMap
    })).toList();
  }

  static Future<void> guardar(PresupuestoModel p) async {
    if (kIsWeb) {
      await _client.from('presupuestos')
          .upsert(p.toSupabaseMap(_uid), onConflict: 'id'); // Conflict target is 'id'
      return;
    }
    final db = await _db;
    await db.insert(
      'presupuestos',
      p.copyWith(sincronizado: false).toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> eliminar(String id) async {
    if (kIsWeb) {
      await _client.from('presupuestos').delete().eq('id', id);
      return;
    }
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
    if (kIsWeb) return [];
    final db = await _db; // Rely on DatabaseHelper for table creation
    final rows = await db.query('presupuestos',
        where: 'sincronizado = ?', whereArgs: [0]);
    return rows.map(PresupuestoModel.fromMap).toList();
  }

  static Future<List<String>> getEliminadosPendientes() async {
    if (kIsWeb) return []; // Rely on DatabaseHelper for table creation
    final db = await _db; 
    final rows = await db.query('presupuestos_eliminados');
    return rows.map((r) => r['id'] as String).toList();
  }

  static Future<void> marcarSincronizados(List<String> ids) async {
    if (kIsWeb) return;
    final db = await _db;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('presupuestos', {'sincronizado': 1},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> limpiarEliminados() async {
    if (kIsWeb) return;
    final db = await _db;
    await db.delete('presupuestos_eliminados');
  }

  // ── Supabase ──────────────────────────────────────────────────────────────

  static Future<void> subirPresupuestos() async {
    if (!_autenticado || kIsWeb) return;

    final pendientes = await getNoSincronizados();
    if (pendientes.isNotEmpty) {
      final rows = pendientes
          .map((p) => p.toSupabaseMap(_uid))
          .toList();
      await _client.from('presupuestos')
          .upsert(rows, onConflict: 'id');
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
    if (!_autenticado || kIsWeb) return;

    final res = await _client
        .from('presupuestos')
        .select('*, categorias(nombre), cuentas(nombre)') // Fetch both category and account names for display
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
    if (kIsWeb) {
      if (!_autenticado) return {};
      final res = await _client.from('movimientos')
          .select('monto, categorias(nombre)')
          .eq('usuario_id', _uid)
          .eq('mes', mes)
          .eq('anio', anio)
          .eq('tipo', 'egreso');
          
      final map = <String, double>{};
      for (final row in res as List) {
        final cat = (row['categorias'] as Map)['nombre'] as String;
        if (cat == 'TRANSFERENCIA') continue;
        final monto = (row['monto'] as num).toDouble();
        map[cat] = (map[cat] ?? 0) + monto;
      }
      return map;
    }
    final db = await DatabaseHelper().db;
    final rows = await db.rawQuery('''
      SELECT c.nombre as categoria, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN categorias c ON m.categoria_id = c.id
      WHERE m.mes = ? AND m.anio = ? AND m.tipo = 'egreso' AND c.nombre NOT IN ('TRANSFERENCIA')
      GROUP BY c.nombre
    ''', [mes, anio]);

    return {
      for (final r in rows)
        r['categoria'] as String: (r['total'] as num).toDouble()
    };
  }

  static Future<Map<String, double>> getGastosRealesCuentas(
      int mes, int anio) async {
    if (kIsWeb) {
      if (!_autenticado) return {};
      final res = await _client.from('movimientos')
          .select('monto, cuentas(nombre)')
          .eq('usuario_id', _uid)
          .eq('mes', mes)
          .eq('anio', anio)
          .eq('tipo', 'egreso');

      final map = <String, double>{};
      for (final row in res as List) {
        final cuenta = (row['cuentas'] as Map)['nombre'] as String;
        final monto = (row['monto'] as num).toDouble();
        map[cuenta] = (map[cuenta] ?? 0) + monto;
      }
      return map;
    }
    final db = await DatabaseHelper().db;
    final rows = await db.rawQuery('''
      SELECT c.nombre as cuenta, SUM(m.monto) as total
      FROM movimientos m
      INNER JOIN cuentas c ON m.cuenta_id = c.id
      WHERE m.mes = ? AND m.anio = ? AND m.tipo = 'egreso' AND c.nombre NOT IN ('TRANSFERENCIA')
      GROUP BY c.nombre
    ''', [mes, anio]);

    return {
      for (final r in rows)
        r['cuenta'] as String: (r['total'] as num).toDouble()
    };
  }

  static PresupuestoModel crear({
    required String tipo,
    String? categoriaId,
    String? cuentaId,
    required double limite,
    required int mes,
    required int anio, String? id,
  }) {
    return PresupuestoModel(
      id:     id ?? _uuid.v4(),
      tipo:   tipo,
      categoriaId: tipo == 'categoria' ? categoriaId : null,
      cuentaId:    tipo == 'cuenta' ? (cuentaId ?? categoriaId) : null,
      limite: limite,
      mes:    mes,
      anio:   anio,
      sincronizado: false,
    );
  }
}

extension _PresupuestoModelCopyWith on PresupuestoModel {
  PresupuestoModel copyWith({
    String? id,
    String? tipo,
    String? categoriaId,
    String? cuentaId,
    double? limite,
    int? mes,
    int? anio,
    bool? sincronizado,
    String? nombre,
  }) {
    return PresupuestoModel(
      id:           id ?? this.id,
      tipo:         tipo ?? this.tipo,
      categoriaId:  categoriaId ?? this.categoriaId,
      cuentaId:     cuentaId ?? this.cuentaId,
      limite:       limite ?? this.limite,
      mes:          mes ?? this.mes,
      anio:         anio ?? this.anio,
      sincronizado: sincronizado ?? this.sincronizado,
      nombre:       nombre ?? this.nombre,
    );
  }
}
