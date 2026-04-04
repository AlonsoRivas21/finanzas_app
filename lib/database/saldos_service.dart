// lib/database/saldos_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import '../models/movimiento.dart';

class SaldosService {
  static const _prefix = 'saldo_inicial_';

  static Future<Map<String, double>> getSaldosIniciales() async {
    final prefs = await SharedPreferences.getInstance();
    final saldos = <String, double>{};
    for (final cuenta in Cuenta.values) {
      final key = '$_prefix${cuenta.nombre}';
      saldos[cuenta.nombre] = prefs.getDouble(key) ?? 0.0;
    }
    return saldos;
  }

  static Future<void> setSaldoInicial(String cuenta, double saldo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_prefix$cuenta', saldo);
  }

  static Future<void> setSaldosIniciales(Map<String, double> saldos) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in saldos.entries) {
      await prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }
}
