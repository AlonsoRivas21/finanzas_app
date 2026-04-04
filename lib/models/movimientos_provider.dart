// lib/models/movimientos_provider.dart

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'movimiento.dart';
import '../database/data_repository.dart';
import '../database/database_helper.dart';
import '../database/saldos_cuentas_service.dart';

class MovimientosProvider extends ChangeNotifier {
  final _repo = DataRepository();
  final _uuid = const Uuid();

  List<Movimiento> _movimientos = [];
  bool _cargando = false;
  String? _error;
  int _mesActual = DateTime.now().month;
  int _anioActual = DateTime.now().year;
  String? _filtroCuenta;
  String? _filtroTipo;
  String? _busqueda;

  List<Movimiento> get movimientos => _movimientos;
  bool get cargando => _cargando;
  String? get error => _error;
  int get mesActual => _mesActual;
  int get anioActual => _anioActual;
  String? get filtroCuenta => _filtroCuenta;
  String? get filtroTipo => _filtroTipo;
  String? get busqueda => _busqueda;

  Future<void> cargar() async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      _movimientos = await _repo.getMovimientos(
        mes: _mesActual,
        anio: _anioActual,
        cuenta: _filtroCuenta,
        tipo: _filtroTipo,
        busqueda: _busqueda,
      );
    } catch (e) {
      _error = 'Error al cargar movimientos: $e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  void setMes(int mes)    { _mesActual = mes;   cargar(); }
  void setAnio(int anio)  { _anioActual = anio; cargar(); }
  void setFiltroCuenta(String? c) { _filtroCuenta = c; cargar(); }
  void setFiltroTipo(String? t)   { _filtroTipo = t;   cargar(); }

  void setBusqueda(String? texto) {
    _busqueda = (texto == null || texto.isEmpty) ? null : texto;
    cargar();
  }

  void limpiarFiltros() {
    _filtroCuenta = null;
    _filtroTipo = null;
    _busqueda = null;
    cargar();
  }

  Future<void> agregar({
    required DateTime fecha,
    required TipoMovimiento tipo,
    required double monto,
    required Categoria categoria,
    required Cuenta cuenta,
    String? comentario,
  }) async {
    final m = Movimiento(
      id: _uuid.v4(),
      fecha: fecha,
      tipo: tipo,
      monto: monto,
      categoria: categoria,
      cuenta: cuenta,
      comentario: comentario,
      mes: fecha.month,
      anio: fecha.year,
      sincronizado: false,
    );
    await _repo.insertMovimiento(m);
    // Actualizar saldo local inmediatamente
    await SaldosCuentasService.aplicarMovimientoLocal(m);
    await cargar();
  }

  Future<void> agregarTransferencia({
    required DateTime fecha,
    required double monto,
    required Cuenta cuentaOrigen,
    required Cuenta cuentaDestino,
    String? comentario,
  }) async {
    final idBase = _uuid.v4();
    final nota = comentario ??
        'Transferencia ${cuentaOrigen.nombre} → ${cuentaDestino.nombre}';

    final egreso = Movimiento(
      id: '${idBase}_out',
      fecha: fecha,
      tipo: TipoMovimiento.egreso,
      monto: monto,
      categoria: Categoria.transferencia,
      cuenta: cuentaOrigen,
      comentario: nota,
      mes: fecha.month,
      anio: fecha.year,
      sincronizado: false,
    );

    final ingreso = Movimiento(
      id: '${idBase}_in',
      fecha: fecha,
      tipo: TipoMovimiento.ingreso,
      monto: monto,
      categoria: Categoria.transferencia,
      cuenta: cuentaDestino,
      comentario: nota,
      mes: fecha.month,
      anio: fecha.year,
      sincronizado: false,
    );

    await _repo.insertMovimientos([egreso, ingreso]);
    await SaldosCuentasService.aplicarMovimientoLocal(egreso);
    await SaldosCuentasService.aplicarMovimientoLocal(ingreso);
    await cargar();
  }

  Future<void> editar(Movimiento nuevo) async {
    final anterior = _movimientos.firstWhere(
      (m) => m.id == nuevo.id,
      orElse: () => nuevo,
    );
    await _repo.updateMovimiento(nuevo.copyWith(sincronizado: false));
    await SaldosCuentasService.actualizarPorEdicionLocal(
        anterior: anterior, nuevo: nuevo);
    await cargar();
  }

  Future<void> eliminar(String id) async {
    final movimiento = _movimientos.where((m) => m.id == id).firstOrNull;

    // Borrar de SQLite — queda registrado en movimientos_eliminados automáticamente
    await _repo.deleteMovimiento(id);

    // Revertir saldo local
    if (movimiento != null) {
      await SaldosCuentasService.revertirMovimientoLocal(movimiento);
      if (id.endsWith('_out') || id.endsWith('_in')) {
        final base = id.replaceAll('_out', '').replaceAll('_in', '');
        final par = _movimientos
            .where((m) => m.id == '${base}_out' || m.id == '${base}_in')
            .where((m) => m.id != id)
            .firstOrNull;
        if (par != null) {
          await _repo.deleteMovimiento(par.id);
          await SaldosCuentasService.revertirMovimientoLocal(par);
        }
      }
    }
    await cargar();
  }

  Future<Map<String, double>> getResumenMes() async =>
      _repo.getResumenMes(_mesActual, _anioActual);

  /// Saldos calculados localmente — funciona sin internet
  Future<Map<String, double>> getSaldosPorCuenta() async =>
      DatabaseHelper().getSaldosPorCuentaLocal();

  Future<List<Map<String, dynamic>>> getGastosPorCategoria() async =>
      _repo.getGastosPorCategoria(_mesActual, _anioActual);

  Future<List<Map<String, dynamic>>> getResumenPorSemana() async =>
      _repo.getResumenPorSemana(_mesActual, _anioActual);

  Future<int> getTotalRegistros() async =>
      _repo.countMovimientos();

  Future<int> importarLista(List<Movimiento> lista) async {
    await _repo.insertMovimientos(lista);
    await cargar();
    return lista.length;
  }
}
