// lib/database/catalogo_service.dart
// Cuentas y categorías dinámicas — local primero, sync con Supabase

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';

class CatalogoService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();
  static String get _uid => _client.auth.currentUser?.id ?? '';
  static bool get _autenticado => _client.auth.currentUser != null;

  // Auxiliares para conversión segura entre SQLite (int) y Supabase (bool)
  static bool _toBool(dynamic val) {
    if (val is bool) return val;
    if (val is int) return val == 1;
    return false;
  }

  static int _toInt(dynamic val) {
    if (val is int) return val;
    if (val is bool) return val ? 1 : 0;
    return 0;
  }

  // Normalización para que la UI reciba siempre los mismos tipos
  static Map<String, dynamic> _normCuenta(Map<String, dynamic> c) => {
    ...c,
    'activa': _toBool(c['activa']),
    'saldo_inicial': (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0,
    'orden': c['orden'] ?? 0,
  };

  static Map<String, dynamic> _normCat(Map<String, dynamic> c) => {
    ...c,
    'activa': _toBool(c['activa']),
    'orden': c['orden'] ?? 0,
  };

  // ── Predeterminados ───────────────────────────────────────────────────────

  // ── Cuentas ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCuentas() async {
    if (kIsWeb) return _getCuentasWeb();

    final db = DatabaseHelper();
    final cuentas = await db.getCuentas();
    return cuentas.map(_normCuenta).toList();
  }

  static Future<List<Map<String, dynamic>>> _getCuentasWeb() async {
    if (!_autenticado) return [];
    final res = await _client
        .from('cuentas')
        .select()
        .eq('usuario_id', _uid)
        .eq('activa', true)
        .order('orden');

    return List<Map<String, dynamic>>.from(res).map(_normCuenta).toList();
  }

  static Future<void> crearCuenta({
    required String nombre,
    required String tipo,
    double saldoInicial = 0,
  }) async {
    final cuentas = await getCuentas();
    final cuenta = {
      'id':            _uuid.v4(),
      'nombre':        nombre.toUpperCase(),
      'tipo':          tipo,
      'saldo_inicial': saldoInicial,
      'activa':        1,
      'orden':         cuentas.length,
      'sincronizado':  0,
    };

    if (kIsWeb) {
      await _client.from('cuentas').insert({...cuenta, 'usuario_id': _uid, 'activa': true});
    } else {
      await DatabaseHelper().insertCuenta(cuenta);
    }
  }

  static Future<void> actualizarCuenta(Map<String, dynamic> cuenta) async {
    final newNombre = (cuenta['nombre'] as String).toUpperCase();

    if (kIsWeb) {
      final oldData = await _client.from('cuentas')
          .select('nombre').eq('id', cuenta['id']).maybeSingle();
      final oldNombre = oldData?['nombre'] as String?;
      
      await _client.from('cuentas')
          .update({
            'nombre': newNombre,
            'tipo': cuenta['tipo'],
            'saldo_inicial': cuenta['saldo_inicial'],
            'activa': _toBool(cuenta['activa']),
          })
          .eq('id', cuenta['id']);

      if (oldNombre != null && oldNombre != newNombre) {
        await _client.from('movimientos').update({'cuenta': newNombre})
            .eq('usuario_id', _uid).eq('cuenta', oldNombre);
        await _client.from('saldos_cuentas').update({'cuenta': newNombre})
            .eq('usuario_id', _uid).eq('cuenta', oldNombre);
      }
    } else {
      final db = DatabaseHelper();
      await db.updateCuenta({
        ...cuenta,
        'activa': _toInt(cuenta['activa']),
        'sincronizado': 0
      });
      await db.recalibrarSaldosLocales();
    }
  }

  static Future<void> eliminarCuenta(String id) async {
    if (kIsWeb) {
      await _client.from('cuentas').update({'activa': false}).eq('id', id);
    } else {
      await DatabaseHelper().deleteCuenta(id);
    }
  }

  // ── Categorías ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCategorias({String? tipo}) async {
    if (kIsWeb) return _getCategoriasWeb(tipo: tipo);

    final db = DatabaseHelper();
    final cats = await db.getCategorias(tipo: tipo);
    return cats.map(_normCat).toList();
  }

  static Future<List<Map<String, dynamic>>> _getCategoriasWeb({String? tipo}) async {
    if (!_autenticado) return [];

    var query = _client
        .from('categorias')
        .select()
        .eq('usuario_id', _uid)
        .eq('activa', true);

    final res = await query.order('orden');

    var lista = List<Map<String, dynamic>>.from(res as List).map(_normCat).toList();
    if (tipo != null) {
      lista = lista.where((c) =>
          c['tipo'] == tipo || c['tipo'] == 'ambos').toList();
    }
    return lista.toList();
  }

  static Future<void> crearCategoria({
    required String nombre,
    required String tipo,
    String icono = 'label',
  }) async {
    final cats = await getCategorias();
    final cat = {
      'id':           _uuid.v4(),
      'nombre':       nombre.toUpperCase(),
      'tipo':         tipo,
      'icono':        icono,
      'activa':       1,
      'orden':        cats.length,
      'sincronizado': 0,
    };

    if (kIsWeb) {
      await _client.from('categorias').insert({...cat, 'usuario_id': _uid, 'activa': true});
    } else {
      await DatabaseHelper().insertCategoria(cat);
    }
  }

  static Future<void> actualizarCategoria(Map<String, dynamic> cat) async {
    final newNombre = (cat['nombre'] as String).toUpperCase();

    if (kIsWeb) {
      final oldData = await _client.from('categorias')
          .select('nombre').eq('id', cat['id']).maybeSingle();
      final oldNombre = oldData?['nombre'] as String?;

      await _client.from('categorias')
          .update({
            'nombre': newNombre,
            'tipo': cat['tipo'],
            'icono': cat['icono'],
            'activa': _toBool(cat['activa']),
          })
          .eq('id', cat['id']);

      if (oldNombre != null && oldNombre != newNombre) {
        await _client.from('movimientos').update({'categoria': newNombre})
            .eq('usuario_id', _uid).eq('categoria', oldNombre);
      }
    } else {
      final db = DatabaseHelper();
      await db.updateCategoria({
        ...cat,
        'activa': _toInt(cat['activa']),
        'sincronizado': 0
      });
    }
  }

  static Future<void> eliminarCategoria(String id) async {
    if (kIsWeb) {
      await _client.from('categorias').update({'activa': false}).eq('id', id);
    } else {
      await DatabaseHelper().deleteCategoria(id);
    }
  }

  // ── Sincronización ────────────────────────────────────────────────────────

  static Future<void> subirCatalogo() async {
    if (!_autenticado || kIsWeb) return;
    final db = DatabaseHelper();

    // Cuentas
    final cuentasPend = await db.getCuentasNoSincronizadas();
    if (cuentasPend.isNotEmpty) {
      // Verificar cambios de nombre antes del upsert para no perder historial en nube
      for (final c in cuentasPend) {
        final cloudData = await _client.from('cuentas')
            .select('nombre').eq('id', c['id']).maybeSingle();
        final oldNameCloud = cloudData?['nombre'] as String?;
        final newNameLocal = (c['nombre'] as String).toUpperCase();

        if (oldNameCloud != null && oldNameCloud != newNameLocal) {
          await _client.from('movimientos').update({'cuenta': newNameLocal})
              .eq('usuario_id', _uid).eq('cuenta', oldNameCloud);
          await _client.from('saldos_cuentas').update({'cuenta': newNameLocal})
              .eq('usuario_id', _uid).eq('cuenta', oldNameCloud);
        }
      }

      final rows = cuentasPend.map((c) {
        final map = Map<String, dynamic>.from(c);
        map['usuario_id'] = _uid;
        map['activa'] = _toBool(c['activa']);
        map.remove('sincronizado');
        return map;
      }).toList();
      
      await _client.from('cuentas').upsert(rows, onConflict: 'id');
      await db.marcarCuentasSincronizadas(
          cuentasPend.map((c) => c['id'] as String).toList());
    }

    final cuentasElim = await db.getCuentasEliminadasPendientes();
    if (cuentasElim.isNotEmpty) {
      for (final id in cuentasElim) {
        await _client.from('cuentas').update({'activa': false}).eq('id', id);
      }
      await db.limpiarCuentasEliminadas();
    }

    // Categorías
    final catsPend = await db.getCategoriasNoSincronizadas();
    if (catsPend.isNotEmpty) {
      for (final c in catsPend) {
        final cloudData = await _client.from('categorias')
            .select('nombre').eq('id', c['id']).maybeSingle();
        final oldNameCloud = cloudData?['nombre'] as String?;
        final newNameLocal = (c['nombre'] as String).toUpperCase();

        if (oldNameCloud != null && oldNameCloud != newNameLocal) {
          await _client.from('movimientos').update({'categoria': newNameLocal})
              .eq('usuario_id', _uid).eq('categoria', oldNameCloud);
        }
      }

      final rows = catsPend.map((c) {
        final map = Map<String, dynamic>.from(c);
        map['usuario_id'] = _uid;
        map['activa'] = _toBool(c['activa']);
        map.remove('sincronizado');
        return map;
      }).toList();

      await _client.from('categorias').upsert(rows, onConflict: 'id');
      await db.marcarCategoriasSincronizadas(
          catsPend.map((c) => c['id'] as String).toList());
    }

    final catsElim = await db.getCategoriasEliminadasPendientes();
    if (catsElim.isNotEmpty) {
      for (final id in catsElim) {
        await _client.from('categorias').update({'activa': false}).eq('id', id);
      }
      await db.limpiarCategoriasEliminadas();
    }
  }

  static Future<void> bajarCatalogo() async {
    if (!_autenticado || kIsWeb) return;
    final db = DatabaseHelper();

    // Bajar cuentas
    final cuentasRes = await _client
        .from('cuentas')
        .select()
        .eq('usuario_id', _uid);

    if ((cuentasRes as List).isNotEmpty) {
      final cuentas = cuentasRes.map((c) => {
        'id':            c['id'],
        'nombre':        c['nombre'],
        'tipo':          c['tipo'],
        'saldo_inicial': (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0,
        'activa':        _toBool(c['activa']) ? 1 : 0,
        'orden':         c['orden'] ?? 0,
        'sincronizado':  1,
      }).toList();
      await db.reemplazarCuentas(cuentas);
    }

    // Bajar categorías
    final catsRes = await _client
        .from('categorias')
        .select()
        .eq('usuario_id', _uid);

    if ((catsRes as List).isNotEmpty) {
      final cats = catsRes.map((c) => {
        'id':           c['id'],
        'nombre':       c['nombre'],
        'tipo':         c['tipo'],
        'icono':        c['icono'] ?? 'label',
        'activa':       _toBool(c['activa']) ? 1 : 0,
        'orden':        c['orden'] ?? 0,
        'sincronizado': 1,
      }).toList();
      await db.reemplazarCategorias(cats);
    }
  }
}
