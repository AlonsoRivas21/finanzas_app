// lib/database/catalogo_service.dart
// Gestiona cuentas y categorías dinámicas en Supabase
// Con caché local para no hacer requests en cada build

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/cuenta_model.dart';
import '../models/categoria_model.dart';

class CatalogoService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();

  // Caché en memoria
  static List<CuentaModel>?    _cuentasCache;
  static List<CategoriaModel>? _categoriasCache;

  static String get _uid => _client.auth.currentUser?.id ?? '';

  // ── Cuentas ───────────────────────────────────────────────────────────────

  static Future<List<CuentaModel>> getCuentas({bool forceRefresh = false}) async {
    if (_cuentasCache != null && !forceRefresh) return _cuentasCache!;

    final res = await _client
        .from('cuentas')
        .select()
        .eq('usuario_id', _uid)
        .eq('activa', true)
        .order('orden');

    _cuentasCache = (res as List).map((r) => CuentaModel.fromMap(r)).toList();

    // Si no tiene cuentas, crear las predeterminadas
    if (_cuentasCache!.isEmpty) {
      await _crearCuentasPredeterminadas();
      return getCuentas(forceRefresh: true);
    }

    return _cuentasCache!;
  }

  static Future<void> _crearCuentasPredeterminadas() async {
    final predeterminadas = [
      {'nombre': 'BILLETERA',   'tipo': 'efectivo', 'saldo_inicial': 0.0, 'orden': 0},
      {'nombre': 'DEBITO BA',   'tipo': 'debito',   'saldo_inicial': 0.0, 'orden': 1},
      {'nombre': 'DEBITO NIU',  'tipo': 'debito',   'saldo_inicial': 0.0, 'orden': 2},
      {'nombre': 'CREDITO BA',  'tipo': 'credito',  'saldo_inicial': 0.0, 'orden': 3},
      {'nombre': 'CREDITO NIU', 'tipo': 'credito',  'saldo_inicial': 0.0, 'orden': 4},
      {'nombre': 'MULTIMONEY',  'tipo': 'ahorro',   'saldo_inicial': 0.0, 'orden': 5},
    ];

    final rows = predeterminadas.map((c) => {
      ...c,
      'id': _uuid.v4(),
      'usuario_id': _uid,
      'activa': true,
    }).toList();

    await _client.from('cuentas').insert(rows);
  }

  static Future<CuentaModel> crearCuenta({
    required String nombre,
    required String tipo,
    double saldoInicial = 0,
  }) async {
    final cuentas = await getCuentas();
    final cuenta = CuentaModel(
      id: _uuid.v4(),
      nombre: nombre.toUpperCase(),
      tipo: tipo,
      saldoInicial: saldoInicial,
      activa: true,
      orden: cuentas.length,
    );
    await _client.from('cuentas').insert(cuenta.toMap(_uid));
    _cuentasCache = null;
    return cuenta;
  }

  static Future<void> actualizarCuenta(CuentaModel cuenta) async {
    await _client.from('cuentas')
        .update(cuenta.toMap(_uid))
        .eq('id', cuenta.id);
    _cuentasCache = null;
  }

  static Future<void> eliminarCuenta(String id) async {
    await _client.from('cuentas')
        .update({'activa': false})
        .eq('id', id);
    _cuentasCache = null;
  }

  // ── Categorías ────────────────────────────────────────────────────────────

  static Future<List<CategoriaModel>> getCategorias({
    bool forceRefresh = false,
    String? tipo,
  }) async {
    if (_categoriasCache == null || forceRefresh) {
      final res = await _client
          .from('categorias')
          .select()
          .eq('usuario_id', _uid)
          .eq('activa', true)
          .order('orden');

      _categoriasCache =
          (res as List).map((r) => CategoriaModel.fromMap(r)).toList();

      if (_categoriasCache!.isEmpty) {
        await _crearCategoriasPredeterminadas();
        return getCategorias(forceRefresh: true, tipo: tipo);
      }
    }

    if (tipo != null) {
      return _categoriasCache!
          .where((c) => c.tipo == tipo || c.tipo == 'ambos')
          .toList();
    }
    return _categoriasCache!;
  }

  static Future<void> _crearCategoriasPredeterminadas() async {
    final predeterminadas = [
      {'nombre': 'INGRESOS',        'tipo': 'ingreso', 'icono': 'savings',          'orden': 0},
      {'nombre': 'TRANSPORTE',      'tipo': 'egreso',  'icono': 'directions_bus',    'orden': 1},
      {'nombre': 'COMER FUERA',     'tipo': 'egreso',  'icono': 'restaurant',        'orden': 2},
      {'nombre': 'TRANSFERENCIA',   'tipo': 'ambos',   'icono': 'swap_horiz',        'orden': 3},
      {'nombre': 'SERVICIOS',       'tipo': 'egreso',  'icono': 'receipt',           'orden': 4},
      {'nombre': 'SHOPPING',        'tipo': 'egreso',  'icono': 'shopping_bag',      'orden': 5},
      {'nombre': 'SALDO',           'tipo': 'ambos',   'icono': 'account_balance_wallet', 'orden': 6},
      {'nombre': 'HOGAR',           'tipo': 'egreso',  'icono': 'home',              'orden': 7},
      {'nombre': 'PROVICIONES',     'tipo': 'egreso',  'icono': 'shopping_cart',     'orden': 8},
      {'nombre': 'PERDIDO',         'tipo': 'egreso',  'icono': 'money_off',         'orden': 9},
      {'nombre': 'ENTRETENIMIENTO', 'tipo': 'egreso',  'icono': 'movie',             'orden': 10},
      {'nombre': 'PELO',            'tipo': 'egreso',  'icono': 'content_cut',       'orden': 11},
    ];

    final rows = predeterminadas.map((c) => {
      ...c,
      'id': _uuid.v4(),
      'usuario_id': _uid,
      'activa': true,
    }).toList();

    await _client.from('categorias').insert(rows);
  }

  static Future<CategoriaModel> crearCategoria({
    required String nombre,
    required String tipo,
    String icono = 'label',
  }) async {
    final cats = await getCategorias();
    final cat = CategoriaModel(
      id: _uuid.v4(),
      nombre: nombre.toUpperCase(),
      tipo: tipo,
      icono: icono,
      activa: true,
      orden: cats.length,
    );
    await _client.from('categorias').insert(cat.toMap(_uid));
    _categoriasCache = null;
    return cat;
  }

  static Future<void> actualizarCategoria(CategoriaModel cat) async {
    await _client.from('categorias')
        .update(cat.toMap(_uid))
        .eq('id', cat.id);
    _categoriasCache = null;
  }

  static Future<void> eliminarCategoria(String id) async {
    await _client.from('categorias')
        .update({'activa': false})
        .eq('id', id);
    _categoriasCache = null;
  }

  static void limpiarCache() {
    _cuentasCache = null;
    _categoriasCache = null;
  }
}
