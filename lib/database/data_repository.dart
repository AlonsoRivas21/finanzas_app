// lib/database/data_repository.dart
//
// Capa de abstracción: en móvil usa SQLite, en web usa Supabase directamente.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'database_helper.dart';
import 'saldos_service.dart';

class DataRepository {
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal();

  static final _client = Supabase.instance.client;

  bool get esWeb => kIsWeb;

  // ── Movimientos ───────────────────────────────────────────────────────────

  Future<List<Movimiento>> getMovimientos({
    int? mes, int? anio, String? cuenta,
    String? tipo, String? busqueda,
    int limit = 300, int offset = 0,
  }) async {
    if (!esWeb) {
      return DatabaseHelper().getMovimientos(
        mes: mes, anio: anio, cuenta: cuenta,
        tipo: tipo, busqueda: busqueda,
        limit: limit, offset: offset,
      );
    }

    // Web: consulta directo a Supabase
    var query = _client
        .from('movimientos')
        .select()
        .eq('usuario_id', _uid);

    if (mes != null)    query = query.eq('mes', mes);
    if (anio != null)   query = query.eq('anio', anio);
    if (cuenta != null) query = query.eq('cuenta', cuenta);
    if (tipo != null)   query = query.eq('tipo', tipo);

    final response = await query
        .order('fecha', ascending: false)
        .limit(limit);

    var lista = (response as List).map(_fromRow).toList();

    if (busqueda != null && busqueda.isNotEmpty) {
      final q = busqueda.toLowerCase();
      lista = lista.where((m) =>
        m.categoria.nombre.toLowerCase().contains(q) ||
        m.cuenta.nombre.toLowerCase().contains(q) ||
        (m.comentario?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    return lista;
  }

  Future<void> insertMovimiento(Movimiento m) async {
    if (!esWeb) {
      await DatabaseHelper().insertMovimiento(m);
      return;
    }
    await _client.from('movimientos').upsert(_toRow(m));
  }

  Future<void> insertMovimientos(List<Movimiento> lista) async {
    if (!esWeb) {
      await DatabaseHelper().insertMovimientos(lista);
      return;
    }
    await _client.from('movimientos').upsert(lista.map(_toRow).toList());
  }

  Future<void> updateMovimiento(Movimiento m) async {
    if (!esWeb) {
      await DatabaseHelper().updateMovimiento(m);
      return;
    }
    await _client.from('movimientos')
        .update(_toRow(m))
        .eq('id', m.id);
  }

  Future<void> deleteMovimiento(String id) async {
    if (!esWeb) {
      await DatabaseHelper().deleteMovimiento(id);
      return;
    }
    await _client.from('movimientos').delete().eq('id', id);
    // Si es transferencia eliminar el par
    if (id.endsWith('_out') || id.endsWith('_in')) {
      final base = id.replaceAll('_out', '').replaceAll('_in', '');
      await _client.from('movimientos').delete().eq('id', '${base}_out');
      await _client.from('movimientos').delete().eq('id', '${base}_in');
    }
  }

  Future<int> countMovimientos() async {
    if (!esWeb) return DatabaseHelper().countMovimientos();
    final res = await _client
        .from('movimientos')
        .select('id')
        .eq('usuario_id', _uid);
    return (res as List).length;
  }

  // ── Resúmenes ─────────────────────────────────────────────────────────────

  Future<Map<String, double>> getResumenMes(int mes, int anio) async {
    if (!esWeb) return DatabaseHelper().getResumenMes(mes, anio);

    final res = await _client
        .from('movimientos')
        .select('tipo, monto')
        .eq('usuario_id', _uid)
        .eq('mes', mes)
        .eq('anio', anio);

    double ingresos = 0, egresos = 0;
    for (final row in res as List) {
      final monto = (row['monto'] as num).toDouble();
      if (row['tipo'] == 'ingreso') ingresos += monto;
      else egresos += monto;
    }
    return {'ingresos': ingresos, 'egresos': egresos};
  }

  Future<Map<String, double>> getSaldosPorCuenta() async {
    final saldos = await SaldosService.getSaldosIniciales();

    final source = esWeb
        ? await _client.from('movimientos').select('cuenta, tipo, monto')
            .eq('usuario_id', _uid)
        : await DatabaseHelper().db.then((db) => db.rawQuery('''
            SELECT cuenta,
              SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END) as movimientos
            FROM movimientos GROUP BY cuenta
          '''));

    if (esWeb) {
      for (final row in source as List) {
        final cuenta = row['cuenta'] as String;
        final monto = (row['monto'] as num).toDouble();
        final factor = row['tipo'] == 'ingreso' ? 1.0 : -1.0;
        saldos[cuenta] = (saldos[cuenta] ?? 0) + monto * factor;
      }
    } else {
      for (final row in source as List<Map<String, dynamic>>) {
        final cuenta = row['cuenta'] as String;
        final movs = (row['movimientos'] as num).toDouble();
        saldos[cuenta] = (saldos[cuenta] ?? 0) + movs;
      }
    }
    return saldos;
  }

  Future<List<Map<String, dynamic>>> getGastosPorCategoria(
      int mes, int anio) async {
    if (!esWeb) return DatabaseHelper().getGastosPorCategoria(mes, anio);

    final res = await _client
        .from('movimientos')
        .select('categoria, monto')
        .eq('usuario_id', _uid)
        .eq('mes', mes)
        .eq('anio', anio)
        .eq('tipo', 'egreso');

    final mapa = <String, double>{};
    for (final row in res as List) {
      final cat = row['categoria'] as String;
      mapa[cat] = (mapa[cat] ?? 0) + (row['monto'] as num).toDouble();
    }

    final lista = mapa.entries
        .map((e) => {'categoria': e.key, 'total': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total'] as double).compareTo(a['total'] as double));
    return lista;
  }

  Future<List<Map<String, dynamic>>> getResumenPorSemana(
      int mes, int anio) async {
    if (!esWeb) return DatabaseHelper().getResumenPorSemana(mes, anio);

    final res = await _client
        .from('movimientos')
        .select('fecha, tipo, monto, categoria')
        .eq('usuario_id', _uid)
        .eq('mes', mes)
        .eq('anio', anio);

    final semanas = List.generate(4, (i) =>
        <String, dynamic>{'semana': i, 'ingresos': 0.0, 'egresos': 0.0});

    for (final row in res as List) {
      final cat = row['categoria'] as String;
      if (cat == 'TRANSFERENCIA' || cat == 'SALDO') continue;
      final dia = int.parse((row['fecha'] as String).substring(8, 10));
      final s = dia <= 7 ? 0 : dia <= 14 ? 1 : dia <= 21 ? 2 : 3;
      final monto = (row['monto'] as num).toDouble();
      if (row['tipo'] == 'ingreso') {
        semanas[s]['ingresos'] =
            (semanas[s]['ingresos'] as double) + monto;
      } else {
        semanas[s]['egresos'] =
            (semanas[s]['egresos'] as double) + monto;
      }
    }

    return semanas.where((s) =>
        (s['ingresos'] as double) > 0 ||
        (s['egresos'] as double) > 0).toList();
  }

  Future<Map<String, Map<String, double>>> getResumenPorCuenta(
      int anio) async {
    if (!esWeb) return DatabaseHelper().getResumenPorCuenta(anio);

    final res = await _client
        .from('movimientos')
        .select('cuenta, tipo, monto')
        .eq('usuario_id', _uid)
        .eq('anio', anio);

    final mapa = <String, Map<String, double>>{};
    for (final row in res as List) {
      final cuenta = row['cuenta'] as String;
      final tipo   = row['tipo'] as String;
      final total  = (row['monto'] as num).toDouble();
      mapa.putIfAbsent(cuenta, () => {'ingresos': 0.0, 'egresos': 0.0});
      if (tipo == 'ingreso') {
        mapa[cuenta]!['ingresos'] = mapa[cuenta]!['ingresos']! + total;
      } else {
        mapa[cuenta]!['egresos'] = mapa[cuenta]!['egresos']! + total;
      }
    }
    return mapa;
  }

  Future<List<int>> getAniosDisponibles() async {
    if (!esWeb) return DatabaseHelper().getAniosDisponibles();

    final res = await _client
        .from('movimientos')
        .select('anio')
        .eq('usuario_id', _uid);

    final anios = (res as List)
        .map((r) => r['anio'] as int)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return anios;
  }

  Future<List<Movimiento>> getNoSincronizados() async {
    if (!esWeb) return DatabaseHelper().getNoSincronizados();
    return []; // En web todo está en Supabase
  }

  Future<void> marcarSincronizados(List<String> ids) async {
    if (!esWeb) await DatabaseHelper().marcarSincronizados(ids);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _uid => _client.auth.currentUser?.id ?? '';

  Map<String, dynamic> _toRow(Movimiento m) => {
    ...m.toMap(),
    'usuario_id': _uid,
    'sincronizado': 1,
  };

  Movimiento _fromRow(dynamic row) => Movimiento.fromMap({
    'id':          row['id'],
    'fecha':       row['fecha'],
    'tipo':        row['tipo'],
    'monto':       (row['monto'] as num).toDouble(),
    'categoria':   row['categoria'],
    'cuenta':      row['cuenta'],
    'comentario':  row['comentario'],
    'mes':         row['mes'],
    'anio':        row['anio'],
    'sincronizado': 1,
  });
}
