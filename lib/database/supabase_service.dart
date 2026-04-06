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
    final db = DatabaseHelper();

    // 1. Movimientos nuevos/editados
    final pendientes = await db.getNoSincronizados();
    if (pendientes.isNotEmpty) {
      final datos = pendientes.map((m) {
        final map = m.toMap();
        map['usuario_id'] = usuarioActual!.id;
        map.remove('sincronizado');
        return map;
      }).toList();
      await _client.from('movimientos').upsert(datos, onConflict: 'id');
      await db.marcarSincronizados(pendientes.map((m) => m.id).toList());
    }

    // 2. Movimientos eliminados
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

    // 5. Recalcular saldos actuales en Supabase desde historial completo
    await _recalcularSaldosEnSupabase();

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
        .limit(5000);

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

    // 3. Saldos iniciales → se guardan en shared_prefs
    await SaldosService.bajarSaldos();

    return movimientos.length;
  }

  // ── Recalcular saldos en Supabase ─────────────────────────────────────────
  // Suma saldo_inicial + todos los movimientos en Supabase
  // Así saldos_cuentas siempre refleja el estado real del historial completo

  static Future<void> _recalcularSaldosEnSupabase() async {
    try {
      // Leer saldos iniciales desde Supabase
      final initRes = await _client
          .from('saldos_iniciales')
          .select()
          .eq('usuario_id', usuarioActual!.id);

      final saldos = <String, double>{};
      for (final row in initRes as List) {
        saldos[row['cuenta'] as String] = (row['saldo'] as num).toDouble();
      }

      // Sumar todos los movimientos del historial completo en Supabase
      final movRes = await _client
          .from('movimientos')
          .select('cuenta, tipo, monto')
          .eq('usuario_id', usuarioActual!.id);

      for (final row in movRes as List) {
        final cuenta = row['cuenta'] as String;
        final monto  = (row['monto'] as num).toDouble();
        final delta  = row['tipo'] == 'ingreso' ? monto : -monto;
        saldos[cuenta] = (saldos[cuenta] ?? 0) + delta;
      }

      // Guardar en saldos_cuentas
      if (saldos.isNotEmpty) {
        final rows = saldos.entries.map((e) => {
          'usuario_id':   usuarioActual!.id,
          'cuenta':       e.key,
          'saldo_actual': e.value,
          'updated_at':   DateTime.now().toIso8601String(),
        }).toList();

        await _client.from('saldos_cuentas')
            .upsert(rows, onConflict: 'usuario_id,cuenta');
      }
    } catch (_) {
      // Si falla no detiene la sincronización
    }
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
