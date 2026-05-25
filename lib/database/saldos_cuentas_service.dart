// lib/database/saldos_cuentas_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'catalogo_service.dart';

class SaldosCuentasService {
  static SupabaseClient? get _clientSafe {
    try { return Supabase.instance.client; } catch (_) { return null; }
  }
  static SupabaseClient get _client => Supabase.instance.client;
  static String get _uid => _clientSafe?.auth.currentUser?.id ?? '';
  static bool get _autenticado => _clientSafe?.auth.currentUser != null;

  // ── Operaciones locales (sin internet) ───────────────────────────────────

  /// Aplica un movimiento al saldo local calculado desde SQLite
  /// No toca Supabase — solo se usa para refrescar la UI offline
  static Future<void> aplicarMovimientoLocal(Movimiento m) async {
    // Los saldos en móvil se calculan directo desde SQLite
    // No necesitamos hacer nada aquí — getSaldosPorCuentaLocal() los calcula
  }

  static Future<void> revertirMovimientoLocal(Movimiento m) async {
    // Igual — getSaldosPorCuentaLocal() lo calcula desde SQLite
  }

  static Future<void> actualizarPorEdicionLocal({
    required Movimiento anterior,
    required Movimiento nuevo,
  }) async {
    // Igual — SQLite ya tiene el movimiento actualizado
  }

  // ── Supabase — se usa al sincronizar ─────────────────────────────────────

  /// Recalcula saldos en Supabase sumando el historial completo
  /// Se llama al sincronizar para mantener saldos_cuentas actualizado
  static Future<void> recalcularDesdeHistorial() async {
    if (!_autenticado) return;

    // 1. Obtener cuentas para tener mapeo ID -> Saldo Inicial
    final cuentas = await CatalogoService.getCuentas();
    final saldos = <String, double>{
      for (final c in cuentas)
        c['id'] as String: (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0
    };

    final res = await _client
        .from('movimientos')
        .select('cuenta_id, tipo, monto')
        .eq('usuario_id', _uid);

    for (final row in res as List) {
      final id = row['cuenta_id'] as String?;
      if (id == null || !saldos.containsKey(id)) continue;

      final monto  = (row['monto'] as num).toDouble();
      final delta  = row['tipo'] == 'ingreso' ? monto : -monto;
      saldos[id] = (saldos[id] ?? 0) + delta;
    }

    await _guardarTodos(saldos);
  }

  /// Lee saldos actuales desde Supabase (solo web o post-sincronización)
  static Future<Map<String, double>> getSaldosActuales() async {
    final saldosFinales = <String, double>{};
    final cuentas = await CatalogoService.getCuentas();
    
    // Valores por defecto basados en saldo inicial
    for (var c in cuentas) {
      saldosFinales[c['nombre'] as String] = (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0;
    }

    if (!_autenticado) return saldosFinales;

    try {
      final res = await _client
          .from('saldos_cuentas')
          .select('cuenta_id, saldo_actual')
          .eq('usuario_id', _uid);

      final mapSaldos = {
        for (final row in res as List)
          row['cuenta_id'] as String: (row['saldo_actual'] as num).toDouble()
      };

      // Mapear de vuelta a nombres para la UI
      for (var c in cuentas) {
        final id = c['id'] as String;
        if (mapSaldos.containsKey(id)) {
          saldosFinales[c['nombre'] as String] = mapSaldos[id]!;
        }
      }
    } catch (e) {
      print('Error en getSaldosActuales: $e');
    }

    return saldosFinales;
  }

  static Future<void> bajarSaldos() async {
    if (!_autenticado) return;
    await getSaldosActuales();
  }

  static Future<void> _guardarTodos(Map<String, double> saldos) async {
    if (_uid.isEmpty) return;
    final rows = saldos.entries.map((e) => {
      'usuario_id':   _uid,
      'cuenta_id':    e.key,
      'saldo_actual': e.value,
      'updated_at':   DateTime.now().toIso8601String(),
    }).toList();

    await _client.from('saldos_cuentas')
        .upsert(rows, onConflict: 'usuario_id,cuenta_id');
  }
}
