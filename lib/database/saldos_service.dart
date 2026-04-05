// lib/database/saldos_service.dart
// Saldos iniciales: guardados en shared_preferences Y en Supabase
// Los saldos ACTUALES se calculan en database_helper sumando movimientos locales

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';

class SaldosService {
  static const _prefix = 'saldo_inicial_';
  static final _client = Supabase.instance.client;
  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

  // ── Lectura ───────────────────────────────────────────────────────────────

  /// Lee saldos iniciales desde local (shared_prefs)
  /// Son la base para calcular el saldo actual
  static Future<Map<String, double>> getSaldosIniciales() async {
    final prefs = await SharedPreferences.getInstance();
    final saldos = <String, double>{};
    for (final c in Cuenta.values) {
      saldos[c.nombre] = prefs.getDouble('$_prefix${c.nombre}') ?? 0.0;
    }
    return saldos;
  }

  // ── Escritura ─────────────────────────────────────────────────────────────

  static Future<void> setSaldosIniciales(Map<String, double> saldos) async {
    // Siempre guardar local primero
    await _guardarLocal(saldos);
    // Si hay sesión, subir a Supabase también
    if (_autenticado) {
      await _guardarSupabase(saldos);
    }
  }

  static Future<void> setSaldoInicial(String cuenta, double saldo) async {
    await setSaldosIniciales({cuenta: saldo});
  }

  // ── Sync subida ───────────────────────────────────────────────────────────

  static Future<void> subirSaldos() async {
    if (!_autenticado) return;
    final saldos = await getSaldosIniciales();
    if (saldos.values.every((v) => v == 0)) return;
    await _guardarSupabase(saldos);
  }

  // ── Sync bajada ───────────────────────────────────────────────────────────

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
        // Guardar en local
        await _guardarLocal(saldos);
      }
    } catch (_) {}
  }

  // ── Privados ──────────────────────────────────────────────────────────────

  static Future<void> _guardarLocal(Map<String, double> saldos) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in saldos.entries) {
      await prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }

  static Future<void> _guardarSupabase(Map<String, double> saldos) async {
    final rows = saldos.entries.map((e) => {
      'usuario_id': _uid,
      'cuenta':     e.key,
      'saldo':      e.value,
    }).toList();
    await _client.from('saldos_iniciales')
        .upsert(rows, onConflict: 'usuario_id,cuenta');
  }
}
