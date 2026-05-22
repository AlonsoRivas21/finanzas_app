import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import 'catalogo_service.dart';
import 'presupuesto_service.dart';
import '../models/movimiento.dart';
import 'supabase_service.dart';

class SyncService {
  static final _supabase = Supabase.instance.client;
  static final _dbHelper = DatabaseHelper();

  /// Método principal que orquesta la sincronización offline-first.
  /// Estrategia: Push de cambios locales (creaciones/ediciones/borrados) y luego Pull de la nube.
  static Future<void> sincronizarTodo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. PUSH: Subimos lo pendiente para asegurar que la nube tenga nuestros IDs locales.
      // Es vital que los UUIDs generados localmente lleguen primero a Supabase.
      await pushLocalChangesToSupabase();

      // 2. PULL: Traemos la verdad de la nube para actualizar el estado local.
      await pullChangesFromSupabase();
    } catch (e) {
      print('SyncService Error: Sincronización fallida. $e');
    }
  }

  /// Envía los cambios locales a Supabase respetando la integridad referencial.
  static Future<void> pushLocalChangesToSupabase() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    // ORDEN DE EJECUCIÓN PARA EVITAR ERRORES DE LLAVE FORÁNEA:
    // 1. Catálogos (Cuentas y Categorías)
    // 2. Presupuestos y Movimientos
    try {
      // Sincroniza Cuentas y Categorías usando CatalogoService.
      // Este servicio ya maneja los flags 'sincronizado' y las tablas de eliminados.
      await CatalogoService.subirCatalogo();

      // Sincroniza Presupuestos.
      // Importante: Al subirlos ahora, garantizamos que el 'categoria_id' ya existe en Supabase.
      await PresupuestoService.subirPresupuestos();

      // Sincroniza Movimientos.
      await _pushMovimientos(uid);

      // 4. RECALCULAR SALDOS EN SUPABASE:
      // Después de subir movimientos, forzamos que la tabla saldos_cuentas en la nube se actualice.
      await SupabaseService.recalcularSaldosEnSupabase(uid);
    } catch (e) {
      print('SyncService Error durante Push: $e');
    }
  }

  /// Lógica específica para subir movimientos pendientes y procesar borrados físicos.
  static Future<void> _pushMovimientos(String uid) async {
    final pendientes = await _dbHelper.getNoSincronizados();

    if (pendientes.isNotEmpty) {
      final datos = pendientes.map((m) {
        final map = m.toMap();
        map['usuario_id'] = uid;
        map.remove('sincronizado'); // El flag es solo para control local en SQLite
        return map;
      }).toList();

      // Upsert basado en el UUID (id). Si el registro existe, lo actualiza; si no, lo crea.
      await _supabase.from('movimientos').upsert(datos, onConflict: 'id');

      // Marcar en SQLite como sincronizados
      await _dbHelper.marcarSincronizados(pendientes.map((m) => m.id).toList());
    }

    // Procesar eliminaciones de movimientos registradas en la tabla auxiliar
    final eliminados = await _dbHelper.getEliminadosPendientes();
    if (eliminados.isNotEmpty) {
      for (final id in eliminados) {
        try {
          await _supabase.from('movimientos').delete().eq('id', id);
        } catch (e) {
          print('SyncService: No se pudo eliminar el movimiento $id en la nube.');
        }
      }
      await _dbHelper.limpiarEliminados();
    }
  }

  /// Descarga la información de la nube y actualiza la base de datos SQLite.
  static Future<void> pullChangesFromSupabase() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      // 1. Bajar Cuentas y Categorías primero.
      await CatalogoService.bajarCatalogo();

      // 2. Bajar Presupuestos.
      await PresupuestoService.bajarPresupuestos();

      // 3. Bajar Movimientos.
      final response = await _supabase
          .from('movimientos')
          .select()
          .eq('usuario_id', uid)
          .order('fecha', ascending: false);

      final movimientosNube = (response as List).map((row) {
        return Movimiento.fromMap({...row, 'sincronizado': 1});
      }).toList();

      // Estrategia: Solo sobreescribimos si no hay cambios pendientes locales para evitar conflictos.
      final pendientes = await _dbHelper.getNoSincronizados();
      if (pendientes.isEmpty) {
        await _dbHelper.clearAll();
        if (movimientosNube.isNotEmpty) {
          await _dbHelper.insertMovimientos(movimientosNube);
        }

        // RECALIBRAR: Paso crítico para actualizar los saldos calculados (saldos_cuentas)
        await _dbHelper.recalibrarSaldosLocales();
      }
    } catch (e) {
      print('SyncService Error durante Pull: $e');
    }
  }
}