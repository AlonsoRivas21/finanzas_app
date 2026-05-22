// lib/database/supabase_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/movimiento.dart';
import 'database_helper.dart';
import 'presupuesto_service.dart';
import 'catalogo_service.dart';

class SupabaseService {
  static SupabaseClient? get _clientSafe {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static User? get usuarioActual => _clientSafe?.auth.currentUser;
  static bool get estaAutenticado => usuarioActual != null;
  static SupabaseClient get _client => Supabase.instance.client;

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
    if (kIsWeb) return 0;
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
          .select('cuenta_id, saldo_actual')
          .eq('usuario_id', usuarioActual!.id);

      if ((res as List).isNotEmpty) {
        final saldos = <String, double>{
          for (final row in res)
            row['cuenta_id'] as String: (row['saldo_actual'] as num).toDouble()
        };
        await DatabaseHelper().guardarSaldosDesdeNube(saldos);
      }
    } catch (_) {}
  }

  // ── Bajada ────────────────────────────────────────────────────────────────

  static Future<int> bajar() async {
    if (kIsWeb) return 0;
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
      'categoria_id': row['categoria_id'],
      'cuenta_id':    row['cuenta_id'],
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
    if (uid.isEmpty || !estaAutenticado) return;
    try {
      // Usamos el saldo ya calculado localmente en el celular.
      final db = DatabaseHelper();
      final saldosLocales = await db.getSaldosActualesPorId();

      if (saldosLocales.isEmpty) return;

      final rows = saldosLocales.entries.map((e) => {
        'usuario_id':   uid,
        'cuenta_id':    e.key,
        'saldo_actual': e.value,
        'updated_at':   DateTime.now().toIso8601String(),
      }).toList();

      await _client.from('saldos_cuentas')
          .upsert(rows, onConflict: 'usuario_id,cuenta_id');
    } catch (e) {
      print('Error en recalcularSaldosEnSupabase: $e');
    }
  }

  // ── Sincronización ────────────────────────────────────────────────────────

  static Future<({String accion, int cantidad})> sincronizar() async {
    if (kIsWeb) {
      // En web no hay base de datos local que sincronizar
      return (accion: 'web', cantidad: 0);
    }

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
