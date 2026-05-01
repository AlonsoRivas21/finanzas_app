// lib/database/data_repository.dart

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
  String get _uid => _client.auth.currentUser?.id ?? '';

  // ── Movimientos ───────────────────────────────────────────────────────────

  Future<List<Movimiento>> getMovimientos({
    int? mes, int? anio, String? cuenta,
    String? tipo, String? busqueda,
    int limit = 300, int offset = 0,
  }) async {
    if (!kIsWeb) {
      return DatabaseHelper().getMovimientos(
        mes: mes, anio: anio, cuenta: cuenta,
        tipo: tipo, busqueda: busqueda,
        limit: limit, offset: offset,
      );
    }
    var query = _client.from('movimientos').select().eq('usuario_id', _uid);
    if (mes != null)    query = query.eq('mes', mes);
    if (anio != null)   query = query.eq('anio', anio);
    if (cuenta != null) query = query.eq('cuenta', cuenta);
    if (tipo != null)   query = query.eq('tipo', tipo);

    final response = await query.order('fecha', ascending: false).limit(limit);
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
    if (!kIsWeb) {
      await DatabaseHelper().insertMovimiento(m);
      return;
    }
    await _client.from('movimientos').upsert(_toRow(m));
    // Aplicar delta: sumar el monto al saldo de la cuenta
    final delta = m.tipo == TipoMovimiento.ingreso ? m.monto : -m.monto;
    await _aplicarDeltaSaldo(m.cuenta.nombre, delta);
  }

  Future<void> insertMovimientos(List<Movimiento> lista) async {
    if (!kIsWeb) {
      await DatabaseHelper().insertMovimientos(lista);
      return;
    }
    await _client.from('movimientos').upsert(lista.map(_toRow).toList());
    // Aplicar delta por cada movimiento
    for (final m in lista) {
      final delta = m.tipo == TipoMovimiento.ingreso ? m.monto : -m.monto;
      await _aplicarDeltaSaldo(m.cuenta.nombre, delta);
    }
  }

  Future<void> updateMovimiento(Movimiento nuevo) async {
    if (!kIsWeb) {
      await DatabaseHelper().updateMovimiento(nuevo);
      return;
    }
    // Obtener el movimiento anterior para calcular la diferencia
    final anteriorRes = await _client
        .from('movimientos')
        .select('tipo, monto, cuenta')
        .eq('id', nuevo.id)
        .maybeSingle();

    await _client.from('movimientos').update(_toRow(nuevo)).eq('id', nuevo.id);

    if (anteriorRes != null) {
      // Revertir el efecto del movimiento anterior
      final deltaAnterior = anteriorRes['tipo'] == 'ingreso'
          ? -(anteriorRes['monto'] as num).toDouble()
          : (anteriorRes['monto'] as num).toDouble();
      await _aplicarDeltaSaldo(anteriorRes['cuenta'] as String, deltaAnterior);
    }
    // Aplicar el efecto del movimiento nuevo
    final deltaNuevo = nuevo.tipo == TipoMovimiento.ingreso ? nuevo.monto : -nuevo.monto;
    await _aplicarDeltaSaldo(nuevo.cuenta.nombre, deltaNuevo);
  }

  Future<void> deleteMovimiento(String id) async {
    if (!kIsWeb) {
      await DatabaseHelper().deleteMovimiento(id);
      return;
    }

    if (id.endsWith('_out') || id.endsWith('_in')) {
      final base = id.replaceAll('_out', '').replaceAll('_in', '');
      // Revertir ambos lados de la transferencia
      await _revertirMovimientoEnSupabase('${base}_out');
      await _revertirMovimientoEnSupabase('${base}_in');
      await _client.from('movimientos').delete().eq('id', '${base}_out');
      await _client.from('movimientos').delete().eq('id', '${base}_in');
    } else {
      await _revertirMovimientoEnSupabase(id);
      await _client.from('movimientos').delete().eq('id', id);
    }
  }

  /// Revierte el efecto de un movimiento en saldos_cuentas antes de borrarlo
  Future<void> _revertirMovimientoEnSupabase(String id) async {
    final res = await _client
        .from('movimientos')
        .select('tipo, monto, cuenta')
        .eq('id', id)
        .maybeSingle();
    if (res == null) return;
    final delta = res['tipo'] == 'ingreso'
        ? -(res['monto'] as num).toDouble()
        : (res['monto'] as num).toDouble();
    await _aplicarDeltaSaldo(res['cuenta'] as String, delta);
  }

  /// Aplica un delta al saldo_actual de una cuenta en saldos_cuentas
  Future<void> _aplicarDeltaSaldo(String cuenta, double delta) async {
    try {
      // Leer saldo actual
      final res = await _client
          .from('saldos_cuentas')
          .select('saldo_actual')
          .eq('usuario_id', _uid)
          .eq('cuenta', cuenta)
          .maybeSingle();

      double saldoActual;
      if (res == null) {
        // No existe — partir del saldo inicial
        final iniciales = await SaldosService.getSaldosIniciales();
        saldoActual = iniciales[cuenta] ?? 0;
      } else {
        saldoActual = (res['saldo_actual'] as num).toDouble();
      }

      await _client.from('saldos_cuentas').upsert({
        'usuario_id':   _uid,
        'cuenta':       cuenta,
        'saldo_actual': saldoActual + delta,
        'updated_at':   DateTime.now().toIso8601String(),
      }, onConflict: 'usuario_id,cuenta');
    } catch (_) {}
  }

  Future<int> countMovimientos() async {
    if (!kIsWeb) return DatabaseHelper().countMovimientos();
    final res = await _client.from('movimientos')
        .select('id').eq('usuario_id', _uid);
    return (res as List).length;
  }

  Future<List<Movimiento>> getNoSincronizados() async {
    if (!kIsWeb) return DatabaseHelper().getNoSincronizados();
    return [];
  }

  Future<void> marcarSincronizados(List<String> ids) async {
    if (!kIsWeb) await DatabaseHelper().marcarSincronizados(ids);
  }

  // ── Resúmenes ─────────────────────────────────────────────────────────────

  Future<Map<String, double>> getResumenMes(int mes, int anio) async {
    if (!kIsWeb) return DatabaseHelper().getResumenMes(mes, anio);

    final res = await _client.from('movimientos')
        .select('tipo, monto')
        .eq('usuario_id', _uid)
        .eq('mes', mes)
        .eq('anio', anio);

    double ingresos = 0, egresos = 0;
    for (final row in res as List) {
      final monto = (row['monto'] as num).toDouble();
      if (row['tipo'] == 'ingreso') {
        ingresos += monto;
      } else {
        egresos += monto;
      }
    }
    return {'ingresos': ingresos, 'egresos': egresos};
  }

  Future<Map<String, double>> getSaldosPorCuenta() async {
    if (!kIsWeb) {
      // Móvil: 100% offline — saldo_inicial + movimientos SQLite
      return DatabaseHelper().getSaldosPorCuentaLocal();
    }

    // Web: leer saldos_cuentas (actualizado con delta en cada operación)
    final saldos = await SaldosService.getSaldosIniciales();
    try {
      final res = await _client
          .from('saldos_cuentas')
          .select('cuenta, saldo_actual')
          .eq('usuario_id', _uid);

      if ((res as List).isNotEmpty) {
        for (final row in res) {
          saldos[row['cuenta'] as String] =
              (row['saldo_actual'] as num).toDouble();
        }
        return saldos;
      }
    } catch (_) {}

    // Fallback: calcular desde movimientos si saldos_cuentas está vacío
    final movRes = await _client
        .from('movimientos')
        .select('cuenta, tipo, monto')
        .eq('usuario_id', _uid);

    for (final row in movRes as List) {
      final cuenta = row['cuenta'] as String;
      final monto  = (row['monto'] as num).toDouble();
      saldos[cuenta] = (saldos[cuenta] ?? 0) +
          (row['tipo'] == 'ingreso' ? monto : -monto);
    }
    return saldos;
  }

  Future<List<Map<String, dynamic>>> getGastosPorCategoria(
      int mes, int anio) async {
    if (!kIsWeb) return DatabaseHelper().getGastosPorCategoria(mes, anio);

    final res = await _client.from('movimientos')
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
    return mapa.entries
        .map((e) => {'categoria': e.key, 'total': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total'] as double).compareTo(a['total'] as double));
  }

  Future<List<Map<String, dynamic>>> getResumenPorSemana(
      int mes, int anio) async {
    if (!kIsWeb) return DatabaseHelper().getResumenPorSemana(mes, anio);

    final res = await _client.from('movimientos')
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
      final s   = dia <= 7 ? 0 : dia <= 14 ? 1 : dia <= 21 ? 2 : 3;
      final monto = (row['monto'] as num).toDouble();
      if (row['tipo'] == 'ingreso') {
        semanas[s]['ingresos'] = (semanas[s]['ingresos'] as double) + monto;
      } else {
        semanas[s]['egresos'] = (semanas[s]['egresos'] as double) + monto;
      }
    }
    return semanas.where((s) =>
        (s['ingresos'] as double) > 0 ||
        (s['egresos'] as double) > 0).toList();
  }

  Future<Map<String, Map<String, double>>> getResumenPorCuenta(
      int anio) async {
    if (!kIsWeb) return DatabaseHelper().getResumenPorCuenta(anio);

    final res = await _client.from('movimientos')
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
    if (!kIsWeb) return DatabaseHelper().getAniosDisponibles();
    final res = await _client.from('movimientos')
        .select('anio').eq('usuario_id', _uid);
    return (res as List)
        .map((r) => r['anio'] as int)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _toRow(Movimiento m) => {
    ...m.toMap(), 'usuario_id': _uid, 'sincronizado': 1,
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
    'anio':        row['anio'] ?? DateTime.parse(row['fecha']).year,
    'sincronizado': 1,
  });
}
