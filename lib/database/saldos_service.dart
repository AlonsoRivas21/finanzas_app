// lib/database/saldos_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';

class SaldosService {
  static const _prefix = 'saldo_inicial_';
  static final _client = Supabase.instance.client;

  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

  // ── Lectura ───────────────────────────────────────────────────────────────

  /// Obtiene saldos: primero intenta Supabase, cae en local si no hay sesión
  static Future<Map<String, double>> getSaldosIniciales() async {
    if (_autenticado) {
      try {
        final res = await _client
            .from('saldos_iniciales')
            .select()
            .eq('usuario_id', _uid);

        if ((res as List).isNotEmpty) {
          final saldos = <String, double>{};
          for (final row in res) {
            saldos[row['cuenta'] as String] =
                (row['saldo'] as num).toDouble();
          }
          // Sincronizar al local también
          await _guardarLocal(saldos);
          return saldos;
        }
      } catch (_) {}
    }

    // Fallback: leer desde local
    return _leerLocal();
  }

  // ── Escritura ─────────────────────────────────────────────────────────────

  static Future<void> setSaldoInicial(String cuenta, double saldo) async {
    await setSaldosIniciales({cuenta: saldo});
  }

  /// Guarda saldos localmente Y en Supabase si hay sesión
  static Future<void> setSaldosIniciales(Map<String, double> saldos) async {
    await _guardarLocal(saldos);
    if (_autenticado) {
      await _guardarSupabase(saldos);
    }
  }

  // ── Sincronización explícita ──────────────────────────────────────────────

  /// Sube los saldos locales a Supabase
  static Future<void> subirSaldos() async {
    if (!_autenticado) return;
    final saldos = await _leerLocal();
    if (saldos.isEmpty) return;
    await _guardarSupabase(saldos);
  }

  /// Baja los saldos de Supabase al local
  static Future<void> bajarSaldos() async {
    if (!_autenticado) return;
    try {
      final res = await _client
          .from('saldos_iniciales')
          .select()
          .eq('usuario_id', _uid);

      if ((res as List).isNotEmpty) {
        final saldos = <String, double>{};
        for (final row in res) {
          saldos[row['cuenta'] as String] =
              (row['saldo'] as num).toDouble();
        }
        await _guardarLocal(saldos);
      }
    } catch (_) {}
  }

  // ── Privados ──────────────────────────────────────────────────────────────

  static Future<Map<String, double>> _leerLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final saldos = <String, double>{};
    for (final cuenta in Cuenta.values) {
      final key = '$_prefix${cuenta.nombre}';
      saldos[cuenta.nombre] = prefs.getDouble(key) ?? 0.0;
    }
    return saldos;
  }

  static Future<void> _guardarLocal(Map<String, double> saldos) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in saldos.entries) {
      await prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }

  static Future<void> _guardarSupabase(Map<String, double> saldos) async {
    final rows = saldos.entries.map((e) => {
      'usuario_id': _uid,
      'cuenta': e.key,
      'saldo': e.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).toList();

    await _client
        .from('saldos_iniciales')
        .upsert(rows, onConflict: 'usuario_id,cuenta');
  }
}
