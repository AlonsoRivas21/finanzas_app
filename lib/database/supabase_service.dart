// lib/database/supabase_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'database_helper.dart';
import 'saldos_service.dart';
import 'presupuesto_service.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  static User? get usuarioActual => _client.auth.currentUser;
  static bool get estaAutenticado => usuarioActual != null;

  static Future<void> registrar(String email, String password) async {
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.user == null) throw Exception('No se pudo crear la cuenta');
  }

  static Future<void> iniciarSesion(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> cerrarSesion() async {
    await _client.auth.signOut();
  }

  // ── Subida: local → Supabase ──────────────────────────────────────────────

  static Future<int> subir() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');
    final db  = DatabaseHelper();
    final uid = usuarioActual!.id;

    // 1. Movimientos nuevos/editados
    final pendientes = await db.getNoSincronizados();
    if (pendientes.isNotEmpty) {
      final datos = pendientes.map((m) {
        final map = m.toMap();
        map['usuario_id'] = uid;
        map.remove('sincronizado');
        return map;
      }).toList();
      await _client.from('movimientos').upsert(datos, onConflict: 'id');
      await db.marcarSincronizados(pendientes.map((m) => m.id).toList());
    }

    // 2. Eliminaciones pendientes
    final eliminados = await db.getEliminadosPendientes();
    if (eliminados.isNotEmpty) {
      for (final id in eliminados) {
        await _client.from('movimientos').delete().eq('id', id);
      }
      await db.limpiarEliminados();
    }

    // 3. Presupuestos
    await PresupuestoService.subirPresupuestos();

    // 4. Saldos iniciales
    await SaldosService.subirSaldos();

    // 5. Recalcular saldos_cuentas en Supabase desde historial completo
    // Esto garantiza consistencia después de subir movimientos offline
    await _recalcularSaldosEnSupabase(uid);

    return pendientes.length;
  }

  // ── Bajada: Supabase → local ──────────────────────────────────────────────

  static Future<int> bajar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');
    final db = DatabaseHelper();

    // 1. Movimientos
    final response = await _client
        .from('movimientos')
        .select()
        .eq('usuario_id', usuarioActual!.id)
        .order('fecha', ascending: false)
        .limit(50); // <-- Cambiar despues

    final movimientos = (response as List).map((row) => Movimiento.fromMap({
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
    })).toList();

    await db.clearAll();
    if (movimientos.isNotEmpty) await db.insertMovimientos(movimientos);

    // 2. Presupuestos
    await PresupuestoService.bajarPresupuestos();

    // 3. Saldos iniciales
    await SaldosService.bajarSaldos();

    // 4. Bajar saldos_cuentas de Supabase al local
    // Así el cel tiene saldos correctos sin recalcular desde historial
    await _bajarSaldosAlLocal();

    return movimientos.length;
  }

  /// Baja saldos_cuentas de Supabase y los guarda en SQLite local
  static Future<void> _bajarSaldosAlLocal() async {
    try {
      final res = await _client
          .from('saldos_cuentas')
          .select('cuenta, saldo_actual')
          .eq('usuario_id', usuarioActual!.id);

      if ((res as List).isNotEmpty) {
        final saldos = <String, double>{};
        for (final row in res) {
          saldos[row['cuenta'] as String] =
              (row['saldo_actual'] as num).toDouble();
        }
        await DatabaseHelper().guardarSaldosDesdeNube(saldos);
      }
    } catch (_) {}
  }

  /// Recalcula saldos_cuentas en Supabase sumando historial completo
  static Future<void> _recalcularSaldosEnSupabase(String uid) async {
    try {
      final initRes = await _client
          .from('saldos_iniciales')
          .select()
          .eq('usuario_id', uid);

      final saldos = <String, double>{};
      for (final row in initRes as List) {
        saldos[row['cuenta'] as String] = (row['saldo'] as num).toDouble();
      }

      final movRes = await _client
          .from('movimientos')
          .select('cuenta, tipo, monto')
          .eq('usuario_id', uid);

      for (final row in movRes as List) {
        final cuenta = row['cuenta'] as String;
        final monto  = (row['monto'] as num).toDouble();
        final delta  = row['tipo'] == 'ingreso' ? monto : -monto;
        saldos[cuenta] = (saldos[cuenta] ?? 0) + delta;
      }

      if (saldos.isEmpty) return;

      final rows = saldos.entries.map((e) => {
        'usuario_id':   uid,
        'cuenta':       e.key,
        'saldo_actual': e.value,
        'updated_at':   DateTime.now().toIso8601String(),
      }).toList();

      await _client.from('saldos_cuentas')
          .upsert(rows, onConflict: 'usuario_id,cuenta');
    } catch (_) {}
  }

  // ── Sincronización inteligente ────────────────────────────────────────────

  static Future<({String accion, int cantidad})> sincronizar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final db = DatabaseHelper();
    final hayPendientes = (await db.getNoSincronizados()).isNotEmpty;
    final hayEliminados = (await db.getEliminadosPendientes()).isNotEmpty;
    final hayPresupPend = (await PresupuestoService.getNoSincronizados()).isNotEmpty;
    final hayPresupElim = (await PresupuestoService.getEliminadosPendientes()).isNotEmpty;

    if (hayPendientes || hayEliminados || hayPresupPend || hayPresupElim) {
      final cantidad = await subir();
      return (accion: 'subida', cantidad: cantidad);
    } else {
      final cantidad = await bajar();
      return (accion: 'bajada', cantidad: cantidad);
    }
  }
}
