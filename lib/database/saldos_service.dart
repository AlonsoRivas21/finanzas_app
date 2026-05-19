// lib/database/saldos_service.dart
// Saldos iniciales: guardados en la tabla 'cuentas' y en Supabase
// Los saldos ACTUALES se calculan en database_helper sumando movimientos locales

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/catalogo_service.dart';
import 'database_helper.dart';

class SaldosService {
  static final _client = Supabase.instance.client;
  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

  // ── Lectura ───────────────────────────────────────────────────────────────

  /// Lee saldos iniciales desde la tabla de cuentas
  /// Son la base para calcular el saldo actual
  static Future<Map<String, double>> getSaldosIniciales() async {
    final saldos = <String, double>{};
    final cuentas = await CatalogoService.getCuentas();
    for (final c in cuentas) {
      final nombre = c['nombre'] as String;
      saldos[nombre] = (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0;
    }
    return saldos;
  }

  // ── Escritura ─────────────────────────────────────────────────────────────

  static Future<void> setSaldosIniciales(Map<String, double> saldos) async {
    // Siempre guardar local primero
    await _guardarLocal(saldos);
    if (!kIsWeb) {
      await DatabaseHelper().recalibrarSaldosLocales();
    }
    // No hace falta subir aquí, CatalogoService.subirCatalogo lo hará
  }

  static Future<void> setSaldoInicial(String cuenta, double saldo) async {
    await setSaldosIniciales({cuenta: saldo});
  }

  /// Lee saldos iniciales desde la tabla 'cuentas' en Supabase.
  /// Se usa para recalcular saldos en la nube.
  static Future<Map<String, double>> getSaldosInicialesSupabase() async {
    if (!_autenticado) return {};
    final saldos = <String, double>{};
    try {
      final res = await _client
          .from('cuentas') // Fetch from accounts table
          .select('nombre, saldo_inicial')
          .eq('usuario_id', _uid)
          .eq('activa', true); // Only active accounts

      for (final row in res as List) {
        saldos[row['nombre'] as String] = (row['saldo_inicial'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    return saldos;
  }

  // ── Privados ──────────────────────────────────────────────────────────────

  static Future<void> _guardarLocal(Map<String, double> saldos) async {
    if (kIsWeb) return;
    for (final entry in saldos.entries) {
      await DatabaseHelper().updateSaldoInicial(entry.key, entry.value);
    }
  }
}
