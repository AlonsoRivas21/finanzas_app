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

    // 3. Saldos iniciales
    await SaldosService.bajarSaldos();

    return movimientos.length;
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
