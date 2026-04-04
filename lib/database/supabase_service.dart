// lib/database/supabase_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'database_helper.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  static User? get usuarioActual => _client.auth.currentUser;
  static bool get estaAutenticado => usuarioActual != null;

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<void> registrar(String email, String password) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
    );
    if (res.user == null) throw Exception('No se pudo crear la cuenta');
  }

  static Future<void> iniciarSesion(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> cerrarSesion() async {
    await _client.auth.signOut();
  }

  // ── Sincronización ────────────────────────────────────────────────────────

  /// SUBIDA: sube los movimientos locales no sincronizados a Supabase
  static Future<int> subir() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final db = DatabaseHelper();
    final pendientes = await db.getNoSincronizados();
    if (pendientes.isEmpty) return 0;

    final userId = usuarioActual!.id;
    final datos = pendientes.map((m) {
      final map = m.toMap();
      map['usuario_id'] = userId;
      map.remove('sincronizado');
      return map;
    }).toList();

    await _client
        .from('movimientos')
        .upsert(datos, onConflict: 'id');

    await db.marcarSincronizados(pendientes.map((m) => m.id).toList());
    return pendientes.length;
  }

  /// BAJADA: descarga todos los movimientos de Supabase a SQLite local
  static Future<int> bajar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final response = await _client
        .from('movimientos')
        .select()
        .eq('usuario_id', usuarioActual!.id);

    if (response.isEmpty) return 0;

    final movimientos = (response as List)
        .map((row) => Movimiento.fromMap({
              'id':           row['id'],
              'fecha':        row['fecha'],
              'tipo':         row['tipo'],
              'monto':        (row['monto'] as num).toDouble(),
              'categoria':    row['categoria'],
              'cuenta':       row['cuenta'],
              'comentario':   row['comentario'],
              'mes':          row['mes'],
              'anio':         row['anio'],
              'sincronizado': 1,
            }))
        .toList();

    final db = DatabaseHelper();
    await db.insertMovimientos(movimientos);
    return movimientos.length;
  }

  /// Sincronización inteligente:
  /// - Si hay datos locales sin sincronizar → sube
  /// - Si no hay datos locales → baja
  static Future<({String accion, int cantidad})> sincronizar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final db = DatabaseHelper();
    final total = await db.countMovimientos();
    final pendientes = await db.getNoSincronizados();

    if (total == 0 || pendientes.isEmpty && total == 0) {
      // No hay nada local — bajar desde la nube
      final cantidad = await bajar();
      return (accion: 'bajada', cantidad: cantidad);
    } else if (pendientes.isNotEmpty) {
      // Hay pendientes — subir
      final cantidad = await subir();
      return (accion: 'subida', cantidad: cantidad);
    } else {
      // Todo sincronizado — bajar por si hay cambios en la nube
      final cantidad = await bajar();
      return (accion: 'bajada', cantidad: cantidad);
    }
  }
}
