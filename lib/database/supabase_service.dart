// lib/database/supabase_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'database_helper.dart';
import 'presupuesto_service.dart';
import 'catalogo_service.dart';

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

  // ── Subida ────────────────────────────────────────────────────────────────

  static Future<int> subir() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');
    final db  = DatabaseHelper();
    final uid = usuarioActual!.id;

    // 1. Movimientos
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

    // 2. Eliminaciones
    final eliminados = await db.getEliminadosPendientes();
    if (eliminados.isNotEmpty) {
      for (final id in eliminados) {
        await _client.from('movimientos').delete().eq('id', id);
      }
      await db.limpiarEliminados();
    }

    // 3. Catálogo (cuentas y categorías)
    await CatalogoService.subirCatalogo();

    // 4. Presupuestos
    await PresupuestoService.subirPresupuestos();

    // 5. Recalcular saldos_cuentas en Supabase
    await recalcularSaldosEnSupabase(uid);

    return pendientes.length;
  }

  static Future<void> _bajarSaldosAlLocal() async {
    try {
      final res = await _client
          .from('saldos_cuentas')
          .select('cuenta, saldo_actual')
          .eq('usuario_id', usuarioActual!.id);

      if ((res as List).isNotEmpty) {
        final saldos = <String, double>{
          for (final row in res)
            row['cuenta'] as String: (row['saldo_actual'] as num).toDouble()
        };
        await DatabaseHelper().guardarSaldosDesdeNube(saldos);
      }
    } catch (_) {}
  }

  // ── Bajada ────────────────────────────────────────────────────────────────

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

    // 2. Catálogo
    await CatalogoService.bajarCatalogo();

    // 3. Presupuestos
    await PresupuestoService.bajarPresupuestos();

    // 4. Descargar los saldos calculados en la nube (que tienen el historial 100% completo)
    await _bajarSaldosAlLocal();

    return movimientos.length;
  }

  static Future<void> recalcularSaldosEnSupabase(String uid) async {
    try {
      // 1. Obtener saldos iniciales desde la tabla 'cuentas'
      final cuentasRes = await _client
          .from('cuentas')
          .select('nombre, saldo_inicial')
          .eq('usuario_id', uid)
          .eq('activa', true);

      final saldos = <String, double>{
        for (final row in cuentasRes as List)
          row['nombre'] as String: (row['saldo_inicial'] as num?)?.toDouble() ?? 0.0
      };

      // 2. Sumar movimientos desde la nube
      final movRes = await _client
          .from('movimientos')
          .select('cuenta, tipo, monto')
          .eq('usuario_id', uid);

      for (final row in movRes as List) {
        final cuenta = row['cuenta'] as String;
        if (!saldos.containsKey(cuenta)) continue;
        final monto  = (row['monto'] as num).toDouble();
        final delta  = row['tipo'] == 'ingreso' ? monto : -monto;
        saldos[cuenta] = (saldos[cuenta] ?? 0) + delta;
      }

      // 3. Limpiar saldos actuales del usuario
      await _client.from('saldos_cuentas').delete().eq('usuario_id', uid);

      if (saldos.isEmpty) return;

      final rows = saldos.entries.map((e) => {
        'usuario_id':   uid,
        'cuenta':       e.key,
        'saldo_actual': e.value,
        'updated_at':   DateTime.now().toIso8601String(),
      }).toList();

      await _client.from('saldos_cuentas')
          .insert(rows);
    } catch (_) {}
  }

  // ── Sincronización ────────────────────────────────────────────────────────

  static Future<({String accion, int cantidad})> sincronizar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final db = DatabaseHelper();
    final hayMovPend   = (await db.getNoSincronizados()).isNotEmpty;
    final hayMovElim   = (await db.getEliminadosPendientes()).isNotEmpty;
    final hayCuentaPend = (await db.getCuentasNoSincronizadas()).isNotEmpty;
    final hayCuentaElim = (await db.getCuentasEliminadasPendientes()).isNotEmpty;
    final hayCatPend   = (await db.getCategoriasNoSincronizadas()).isNotEmpty;
    final hayCatElim   = (await db.getCategoriasEliminadasPendientes()).isNotEmpty;
    final hayPresupPend = (await PresupuestoService.getNoSincronizados()).isNotEmpty;
    final hayPresupElim = (await PresupuestoService.getEliminadosPendientes()).isNotEmpty;

    if (hayMovPend || hayMovElim || hayCuentaPend || hayCuentaElim ||
        hayCatPend || hayCatElim || hayPresupPend || hayPresupElim) {
      final cantidad = await subir();
      return (accion: 'subida', cantidad: cantidad);
    } else {
      final cantidad = await bajar();
      return (accion: 'bajada', cantidad: cantidad);
    }
  }
}
