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

  // ── Predeterminados ───────────────────────────────────────────────────────

  static List<Map<String, dynamic>> get _cuentasPredeterminadas => [
    {'id': _uuid.v4(), 'nombre': 'BILLETERA',   'tipo': 'efectivo', 'saldo_inicial': 0.0, 'activa': 1, 'orden': 0, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'DEBITO BA',   'tipo': 'debito',   'saldo_inicial': 0.0, 'activa': 1, 'orden': 1, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'DEBITO NIU',  'tipo': 'debito',   'saldo_inicial': 0.0, 'activa': 1, 'orden': 2, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'CREDITO BA',  'tipo': 'credito',  'saldo_inicial': 0.0, 'activa': 1, 'orden': 3, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'CREDITO NIU', 'tipo': 'credito',  'saldo_inicial': 0.0, 'activa': 1, 'orden': 4, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'MULTIMONEY',  'tipo': 'ahorro',   'saldo_inicial': 0.0, 'activa': 1, 'orden': 5, 'sincronizado': 0},
  ];

  static List<Map<String, dynamic>> get _categoriasPredeterminadas => [
    {'id': _uuid.v4(), 'nombre': 'INGRESOS',        'tipo': 'ingreso', 'icono': 'savings',               'activa': 1, 'orden': 0,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'TRANSPORTE',      'tipo': 'egreso',  'icono': 'directions_bus',         'activa': 1, 'orden': 1,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'COMER FUERA',     'tipo': 'egreso',  'icono': 'restaurant',             'activa': 1, 'orden': 2,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'TRANSFERENCIA',   'tipo': 'ambos',   'icono': 'swap_horiz',             'activa': 1, 'orden': 3,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'SERVICIOS',       'tipo': 'egreso',  'icono': 'receipt',                'activa': 1, 'orden': 4,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'SHOPPING',        'tipo': 'egreso',  'icono': 'shopping_bag',           'activa': 1, 'orden': 5,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'SALDO',           'tipo': 'ambos',   'icono': 'account_balance_wallet', 'activa': 1, 'orden': 6,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'HOGAR',           'tipo': 'egreso',  'icono': 'home',                   'activa': 1, 'orden': 7,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'PROVICIONES',     'tipo': 'egreso',  'icono': 'shopping_cart',          'activa': 1, 'orden': 8,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'PERDIDO',         'tipo': 'egreso',  'icono': 'money_off',              'activa': 1, 'orden': 9,  'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'ENTRETENIMIENTO', 'tipo': 'egreso',  'icono': 'movie',                  'activa': 1, 'orden': 10, 'sincronizado': 0},
    {'id': _uuid.v4(), 'nombre': 'PELO',            'tipo': 'egreso',  'icono': 'content_cut',            'activa': 1, 'orden': 11, 'sincronizado': 0},
  ];

  // ── Cuentas ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCuentas() async {
    if (kIsWeb) return _getCuentasWeb();

    final db = DatabaseHelper();
    var cuentas = await db.getCuentas();

    if (cuentas.isEmpty) {
      // Primera vez — insertar predeterminadas
      for (final c in _cuentasPredeterminadas) {
        await db.insertCuenta(c);
      }
      cuentas = await db.getCuentas();
    }
    return cuentas;
  }

  static Future<List<Map<String, dynamic>>> _getCuentasWeb() async {
    if (!_autenticado) return [];
    final res = await _client
        .from('cuentas')
        .select()
        .eq('usuario_id', _uid)
        .eq('activa', true)
        .order('orden');

    if ((res as List).isEmpty) {
      // Primera vez en web — crear predeterminadas
      await _crearCuentasPredeterminadasEnSupabase();
      return _getCuentasWeb();
    }
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> _crearCuentasPredeterminadasEnSupabase() async {
    final rows = _cuentasPredeterminadas.map((c) => {
      ...c,
      'usuario_id': _uid,
      'activa': true,
    }).toList();
    await _client.from('cuentas').insert(rows);
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
    if (kIsWeb) {
      await _client.from('cuentas')
          .update({...cuenta, 'activa': true})
          .eq('id', cuenta['id']);
    } else {
      await DatabaseHelper().updateCuenta({...cuenta, 'sincronizado': 0});
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
    var cats = await db.getCategorias(tipo: tipo);

    if (cats.isEmpty && tipo == null) {
      for (final c in _categoriasPredeterminadas) {
        await db.insertCategoria(c);
      }
      cats = await db.getCategorias(tipo: tipo);
    }
    return cats;
  }

  static Future<List<Map<String, dynamic>>> _getCategoriasWeb({String? tipo}) async {
    if (!_autenticado) return [];

    var query = _client
        .from('categorias')
        .select()
        .eq('usuario_id', _uid)
        .eq('activa', true);

    final res = await query.order('orden');

    if ((res as List).isEmpty) {
      await _crearCategoriasPredeterminadasEnSupabase();
      return _getCategoriasWeb(tipo: tipo);
    }

    var lista = List<Map<String, dynamic>>.from(res);
    if (tipo != null) {
      lista = lista.where((c) =>
          c['tipo'] == tipo || c['tipo'] == 'ambos').toList();
    }
    return lista;
  }

  static Future<void> _crearCategoriasPredeterminadasEnSupabase() async {
    final rows = _categoriasPredeterminadas.map((c) => {
      ...c,
      'usuario_id': _uid,
      'activa': true,
    }).toList();
    await _client.from('categorias').insert(rows);
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
    if (kIsWeb) {
      await _client.from('categorias')
          .update({...cat, 'activa': true})
          .eq('id', cat['id']);
    } else {
      await DatabaseHelper().updateCategoria({...cat, 'sincronizado': 0});
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
      final rows = cuentasPend.map((c) => {
        ...c, 'usuario_id': _uid,
        'activa': c['activa'] == 1,
        'sincronizado': null,
      }..remove('sincronizado')).toList();
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
      final rows = catsPend.map((c) => {
        ...c, 'usuario_id': _uid,
        'activa': c['activa'] == 1,
        'sincronizado': null,
      }..remove('sincronizado')).toList();
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
        'activa':        c['activa'] == true ? 1 : 0,
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
        'activa':       c['activa'] == true ? 1 : 0,
        'orden':        c['orden'] ?? 0,
        'sincronizado': 1,
      }).toList();
      await db.reemplazarCategorias(cats);
    }
  }
}
