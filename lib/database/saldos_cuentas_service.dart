// lib/database/saldos_cuentas_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'saldos_service.dart';

class SaldosCuentasService {
  static final _client = Supabase.instance.client;
  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

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

  /// Recalcula saldos en Supabase sumando TODO el historial
  /// Se llama al sincronizar para mantener saldos_cuentas actualizado
  static Future<void> recalcularDesdeHistorial() async {
    if (!_autenticado) return;

    final saldos = await SaldosService.getSaldosIniciales();

    final res = await _client
        .from('movimientos')
        .select('cuenta, tipo, monto')
        .eq('usuario_id', _uid);

    for (final row in res as List) {
      final cuenta = row['cuenta'] as String;
      final monto  = (row['monto'] as num).toDouble();
      final delta  = row['tipo'] == 'ingreso' ? monto : -monto;
      saldos[cuenta] = (saldos[cuenta] ?? 0) + delta;
    }

    await _guardarTodos(saldos);
  }

  /// Lee saldos actuales desde Supabase (solo web o post-sincronización)
  static Future<Map<String, double>> getSaldosActuales() async {
    final saldos = await SaldosService.getSaldosIniciales();
    if (!_autenticado) return saldos;

    try {
      final res = await _client
          .from('saldos_cuentas')
          .select()
          .eq('usuario_id', _uid);

      for (final row in res as List) {
        saldos[row['cuenta'] as String] =
            (row['saldo_actual'] as num).toDouble();
      }
    } catch (_) {}

    return saldos;
  }

  static Future<void> bajarSaldos() async {
    if (!_autenticado) return;
    await getSaldosActuales();
  }

  static Future<void> _guardarTodos(Map<String, double> saldos) async {
    final rows = saldos.entries.map((e) => {
      'usuario_id':   _uid,
      'cuenta':       e.key,
      'saldo_actual': e.value,
      'updated_at':   DateTime.now().toIso8601String(),
    }).toList();

    await _client.from('saldos_cuentas')
        .upsert(rows, onConflict: 'usuario_id,cuenta');
  }
}
