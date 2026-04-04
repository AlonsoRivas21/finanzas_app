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
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.user == null) throw Exception('No se pudo crear la cuenta');
  }

  static Future<void> iniciarSesion(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> cerrarSesion() async {
    await _client.auth.signOut();
  }

  // ── Sincronización ────────────────────────────────────────────────────────

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

    await _client.from('movimientos').upsert(datos, onConflict: 'id');
    await db.marcarSincronizados(pendientes.map((m) => m.id).toList());
    return pendientes.length;
  }

  static Future<int> bajar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final response = await _client
        .from('movimientos')
        .select()
        .eq('usuario_id', usuarioActual!.id);

    if ((response as List).isEmpty) return 0;

    final movimientos = response.map((row) => Movimiento.fromMap({
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

    final db = DatabaseHelper();
    // Limpiar primero para evitar duplicados huérfanos
    await db.clearAll();
    await db.insertMovimientos(movimientos);
    return movimientos.length;
  }

  static Future<({String accion, int cantidad})> sincronizar() async {
    if (!estaAutenticado) throw Exception('Debes iniciar sesión primero');

    final db = DatabaseHelper();
    final pendientes = await db.getNoSincronizados();

    if (pendientes.isNotEmpty) {
      // Hay datos sin subir — subir primero
      final cantidad = await subir();
      return (accion: 'subida', cantidad: cantidad);
    } else {
      // Todo sincronizado o vacío — bajar desde la nube
      final cantidad = await bajar();
      return (accion: 'bajada', cantidad: cantidad);
    }
  }
}
