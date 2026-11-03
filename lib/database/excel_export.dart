// lib/database/excel_export.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento.dart';
import 'catalogo_service.dart';
import 'database_helper.dart';
import 'excel_resumen.dart';
import 'saldos_service.dart';
// ignore: uri_does_not_exist
import 'web_download.dart' if (dart.library.io) 'web_download_stub.dart';

class ExcelExportResult {
  final Uint8List bytes;
  final String filename;
  final int totalMovimientos;

  const ExcelExportResult({
    required this.bytes,
    required this.filename,
    required this.totalMovimientos,
  });
}

class ExcelExportService {
  static final _client = Supabase.instance.client;
  static String get _uid => _client.auth.currentUser?.id ?? '';

  static const int _pageSize = 1000;

  static final _headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('#2563EB'),
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    horizontalAlign: HorizontalAlign.Center,
  );

  static final _moneyStyle = CellStyle(numberFormat: NumFormat.standard_4);

  static final _dateStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: 'dd/mm/yyyy'),
  );

  // ── Generación ────────────────────────────────────────────────────────────

  static String nombreArchivo(int? anio) =>
      anio == null ? 'finanzas_todos.xlsx' : 'finanzas_$anio.xlsx';

  /// Genera el libro completo en memoria. [anio] = null exporta todo el historial.
  static Future<ExcelExportResult> generar({int? anio}) async {
    final movimientos = await _cargarMovimientos(anio);

    final cuentasList = await CatalogoService.getCuentas();
    final categoriasList = await CatalogoService.getCategorias();

    final mapaCuentas = <String, String>{
      for (final c in cuentasList) (c['id'] as String): c['nombre'] as String,
    };
    final mapaCategorias = <String, String>{
      for (final c in categoriasList)
        (c['id'] as String): c['nombre'] as String,
    };

    final saldos = await SaldosService.getSaldosIniciales();
    final resumenCuentas = calcularResumenCuentas(movimientos, mapaCuentas);

    final excel = Excel.createExcel();

    final hojaMovimientos = excel['MOVIMIENTOS'];
    excel.setDefaultSheet('MOVIMIENTOS');
    _escribirMovimientos(
      hojaMovimientos,
      movimientos,
      mapaCategorias,
      mapaCuentas,
    );

    _escribirResumenMensual(
      excel['RESUMEN_MENSUAL'],
      movimientos,
      mapaCategorias,
    );
    _escribirResumenCategorias(
      excel['RESUMEN_CATEGORIA'],
      movimientos,
      mapaCategorias,
    );
    _escribirResumenCuentas(
      excel['RESUMEN_CUENTA'],
      movimientos,
      cuentasList,
      mapaCuentas,
    );

    // Hojas legacy: solo para exportaciones de un año, para no romper la importación.
    if (anio != null) {
      _escribirRegistro(
        excel['REGISTRO'],
        movimientos,
        mapaCategorias,
        mapaCuentas,
        saldos,
      );
      _escribirBD(
        excel['BD'],
        cuentasList,
        saldos,
        resumenCuentas,
      );
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final encoded = excel.encode();
    if (encoded == null) throw Exception('No se pudo generar el archivo');

    return ExcelExportResult(
      bytes: Uint8List.fromList(encoded),
      filename: nombreArchivo(anio),
      totalMovimientos: movimientos.length,
    );
  }

  /// Mantiene la API anterior: genera y guarda/descarga según la plataforma.
  static Future<String> exportar({int? anio}) async {
    final result = await generar(anio: anio);
    if (kIsWeb) {
      descargarEnWeb(result);
      return result.filename;
    }
    return guardarCopiaLocal(result);
  }

  static void descargarEnWeb(ExcelExportResult result) {
    downloadFile(result.bytes, result.filename);
  }

  static Future<String> elegirDestinoWeb(String filename) =>
      pickExcelFile(filename);

  static Future<String> escribirDestinoWeb(List<int> bytes) =>
      writeExcelToPickedFile(bytes);

  static void cancelarDestinoWeb() => cancelPickedFile();

  // ── Carga de movimientos ──────────────────────────────────────────────────

  static Future<List<Movimiento>> _cargarMovimientos(int? anio) async {
    if (kIsWeb) return _cargarMovimientosWeb(anio);

    final movimientos = await DatabaseHelper().getMovimientos(
      anio: anio,
      limit: 99999,
    );
    movimientos.sort((a, b) => a.fecha.compareTo(b.fecha));
    return movimientos;
  }

  static Future<List<Movimiento>> _cargarMovimientosWeb(int? anio) async {
    if (_uid.isEmpty) return [];

    final resultado = <Movimiento>[];
    var from = 0;

    while (true) {
      var query = _client
          .from('movimientos')
          .select('*, categorias(nombre), cuentas(nombre)')
          .eq('usuario_id', _uid);

      if (anio != null) query = query.eq('anio', anio);

      final res = await query
          .order('fecha', ascending: true)
          .order('id', ascending: true)
          .range(from, from + _pageSize - 1);

      final rows = res as List;
      resultado.addAll(rows.map(_movimientoDesdeFilaWeb));

      if (rows.length < _pageSize) break;
      from += _pageSize;
    }

    return resultado;
  }

  static Movimiento _movimientoDesdeFilaWeb(dynamic row) {
    final map = Map<String, dynamic>.from(row as Map);
    final fecha = DateTime.parse(
      map['fecha']?.toString() ?? DateTime.now().toIso8601String(),
    );

    return Movimiento.fromMap({
      'id': map['id'],
      'fecha': map['fecha'],
      'tipo': map['tipo'],
      'monto': (map['monto'] as num?)?.toDouble() ?? 0.0,
      'categoria_id': map['categoria_id'],
      'cuenta_id': map['cuenta_id'],
      'categorias': map['categorias'],
      'cuentas': map['cuentas'],
      'comentario': map['comentario'],
      'mes': map['mes'] ?? fecha.month,
      'anio': map['anio'] ?? fecha.year,
      'sincronizado': 1,
    });
  }

  static Future<List<int>> getAniosDisponibles() async {
    if (kIsWeb) return _getAniosWeb();
    return DatabaseHelper().getAniosDisponibles();
  }

  static Future<List<int>> _getAniosWeb() async {
    if (_uid.isEmpty) return [];

    final anios = <int>{};
    var from = 0;

    while (true) {
      final res = await _client
          .from('movimientos')
          .select('anio, id')
          .eq('usuario_id', _uid)
          .order('anio', ascending: false)
          .order('id', ascending: true)
          .range(from, from + _pageSize - 1);

      final rows = res as List;
      for (final row in rows) {
        final anio = row['anio'];
        if (anio is int) {
          anios.add(anio);
        } else if (anio is num) {
          anios.add(anio.toInt());
        }
      }

      if (rows.length < _pageSize) break;
      from += _pageSize;
    }

    return anios.toList()..sort((a, b) => b.compareTo(a));
  }

  // ── Hojas ─────────────────────────────────────────────────────────────────

  static void _escribirMovimientos(
    Sheet sheet,
    List<Movimiento> movimientos,
    Map<String, String> mapaCategorias,
    Map<String, String> mapaCuentas,
  ) {
    const headers = [
      'ID',
      'FECHA',
      'AÑO',
      'MES',
      'MES_NOMBRE',
      'TIPO',
      'MONTO',
      'MONTO_FIRMADO',
      'CATEGORIA',
      'CUENTA',
      'COMENTARIO',
    ];

    for (var i = 0; i < headers.length; i++) {
      _headerCell(sheet, 0, i, headers[i]);
    }

    for (var i = 0; i < movimientos.length; i++) {
      final m = movimientos[i];
      final row = i + 1;

      _cell(sheet, row, 0, m.id);
      _cell(sheet, row, 1, m.fecha, style: _dateStyle);
      _cell(sheet, row, 2, m.anio);
      _cell(sheet, row, 3, m.mes);
      _cell(sheet, row, 4, mesNombre(m.mes));
      _cell(
        sheet,
        row,
        5,
        m.tipo == TipoMovimiento.ingreso ? 'INGRESO' : 'EGRESO',
      );
      _cell(sheet, row, 6, m.monto, style: _moneyStyle);
      _cell(
        sheet,
        row,
        7,
        m.tipo == TipoMovimiento.ingreso ? m.monto : -m.monto,
        style: _moneyStyle,
      );
      _cell(sheet, row, 8, nombreCategoria(m, mapaCategorias));
      _cell(sheet, row, 9, nombreCuenta(m, mapaCuentas));
      _cell(sheet, row, 10, m.comentario ?? '');
    }

    sheet.setColumnWidth(0, 38);
    sheet.setColumnWidth(1, 13);
    sheet.setColumnWidth(2, 8);
    sheet.setColumnWidth(3, 7);
    sheet.setColumnWidth(4, 13);
    sheet.setColumnWidth(5, 11);
    sheet.setColumnWidth(6, 13);
    sheet.setColumnWidth(7, 15);
    sheet.setColumnWidth(8, 20);
    sheet.setColumnWidth(9, 18);
    sheet.setColumnWidth(10, 32);
  }

  static void _escribirResumenMensual(
    Sheet sheet,
    List<Movimiento> movimientos,
    Map<String, String> mapaCategorias,
  ) {
    const headers = [
      'AÑO',
      'MES',
      'MES_NOMBRE',
      'INGRESOS',
      'EGRESOS_BRUTOS',
      'REEMBOLSOS',
      'EGRESOS_NETOS',
      'BALANCE',
    ];

    for (var i = 0; i < headers.length; i++) {
      _headerCell(sheet, 0, i, headers[i]);
    }

    final resumen = calcularResumenMensual(movimientos, mapaCategorias);
    final filas = resumen.values.toList()
      ..sort((a, b) => claveMes(a.anio, a.mes).compareTo(
            claveMes(b.anio, b.mes),
          ));

    for (var i = 0; i < filas.length; i++) {
      final r = filas[i];
      final row = i + 1;

      _cell(sheet, row, 0, r.anio);
      _cell(sheet, row, 1, r.mes);
      _cell(sheet, row, 2, mesNombre(r.mes));
      _cell(sheet, row, 3, r.ingresos, style: _moneyStyle);
      _cell(sheet, row, 4, r.egresosBrutos, style: _moneyStyle);
      _cell(sheet, row, 5, r.reembolsos, style: _moneyStyle);
      _cell(sheet, row, 6, r.egresosNetos, style: _moneyStyle);
      _cell(sheet, row, 7, r.balance, style: _moneyStyle);
    }

    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 7);
    sheet.setColumnWidth(2, 13);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 16);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 16);
    sheet.setColumnWidth(7, 14);
  }

  static void _escribirResumenCategorias(
    Sheet sheet,
    List<Movimiento> movimientos,
    Map<String, String> mapaCategorias,
  ) {
    const headers = ['AÑO', 'MES', 'TIPO', 'CATEGORIA', 'TOTAL'];

    for (var i = 0; i < headers.length; i++) {
      _headerCell(sheet, 0, i, headers[i]);
    }

    final resumen = calcularResumenCategorias(movimientos, mapaCategorias);
    final filas = resumen.values.toList()
      ..sort((a, b) {
        final porMes = claveMes(a.anio, a.mes).compareTo(
          claveMes(b.anio, b.mes),
        );
        if (porMes != 0) return porMes;

        final porTipo = a.tipo.index.compareTo(b.tipo.index);
        if (porTipo != 0) return porTipo;

        return a.categoria.compareTo(b.categoria);
      });

    for (var i = 0; i < filas.length; i++) {
      final r = filas[i];
      final row = i + 1;

      _cell(sheet, row, 0, r.anio);
      _cell(sheet, row, 1, r.mes);
      _cell(
        sheet,
        row,
        2,
        r.tipo == TipoMovimiento.ingreso ? 'INGRESO' : 'EGRESO',
      );
      _cell(sheet, row, 3, r.categoria);
      _cell(sheet, row, 4, r.total, style: _moneyStyle);
    }

    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 7);
    sheet.setColumnWidth(2, 11);
    sheet.setColumnWidth(3, 24);
    sheet.setColumnWidth(4, 14);
  }

  static void _escribirResumenCuentas(
    Sheet sheet,
    List<Movimiento> movimientos,
    List<Map<String, dynamic>> cuentasList,
    Map<String, String> mapaCuentas,
  ) {
    const headers = [
      'CUENTA',
      'SALDO_INICIAL',
      'INGRESOS',
      'EGRESOS',
      'SALDO_PERIODO',
    ];

    for (var i = 0; i < headers.length; i++) {
      _headerCell(sheet, 0, i, headers[i]);
    }

    final resumen = calcularResumenCuentas(movimientos, mapaCuentas);
    final nombresCatalogo = <String>{};
    var row = 1;

    for (final c in cuentasList) {
      final nombre = c['nombre'] as String;
      nombresCatalogo.add(nombre);

      final saldoInicial = (c['saldo_inicial'] as num?)?.toDouble() ?? 0.0;
      final ingresos = resumen[nombre]?['ingresos'] ?? 0.0;
      final egresos = resumen[nombre]?['egresos'] ?? 0.0;

      _cell(sheet, row, 0, nombre);
      _cell(sheet, row, 1, saldoInicial, style: _moneyStyle);
      _cell(sheet, row, 2, ingresos, style: _moneyStyle);
      _cell(sheet, row, 3, egresos, style: _moneyStyle);
      _cell(sheet, row, 4, saldoInicial + ingresos - egresos,
          style: _moneyStyle);
      row++;
    }

    // Cuentas que ya no están activas pero tienen movimientos en el rango.
    for (final entry in resumen.entries) {
      if (nombresCatalogo.contains(entry.key)) continue;

      final ingresos = entry.value['ingresos'] ?? 0.0;
      final egresos = entry.value['egresos'] ?? 0.0;

      _cell(sheet, row, 0, entry.key);
      _cell(sheet, row, 1, 0.0, style: _moneyStyle);
      _cell(sheet, row, 2, ingresos, style: _moneyStyle);
      _cell(sheet, row, 3, egresos, style: _moneyStyle);
      _cell(sheet, row, 4, ingresos - egresos, style: _moneyStyle);
      row++;
    }

    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 14);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 16);
  }

  static void _escribirRegistro(
    Sheet registro,
    List<Movimiento> movimientos,
    Map<String, String> mapaCategorias,
    Map<String, String> mapaCuentas,
    Map<String, double> saldos,
  ) {
    _cell(registro, 0, 1, 'BILLETERA');
    _cell(registro, 0, 2, 'DEBITO BA');
    _cell(registro, 0, 3, 'DEBITO NIU');
    _cell(registro, 0, 4, 'DISPONIBLE');
    _cell(registro, 0, 5, 'TDC');
    _cell(registro, 1, 1, saldos['BILLETERA'] ?? 0.0);
    _cell(registro, 1, 2, saldos['DEBITO BA'] ?? 0.0);
    _cell(registro, 1, 3, saldos['DEBITO NIU'] ?? 0.0);
    _cell(
      registro,
      1,
      4,
      (saldos['BILLETERA'] ?? 0.0) +
          (saldos['DEBITO BA'] ?? 0.0) +
          (saldos['DEBITO NIU'] ?? 0.0),
    );
    _cell(
      registro,
      1,
      5,
      (saldos['CREDITO BA'] ?? 0.0) + (saldos['CREDITO NIU'] ?? 0.0),
    );

    _headerCell(registro, 2, 0, 'FECHA');
    _headerCell(registro, 2, 1, 'MOVIMIENTO');
    _headerCell(registro, 2, 2, 'MONTO');
    _headerCell(registro, 2, 3, 'CATEGORIA');
    _headerCell(registro, 2, 4, 'CUENTA');
    _headerCell(registro, 2, 5, 'COMENTARIO');
    _headerCell(registro, 2, 6, 'MES');

    final fmt = DateFormat('yyyy-MM-dd');
    for (var i = 0; i < movimientos.length; i++) {
      final m = movimientos[i];
      final row = i + 3;

      _cell(registro, row, 0, fmt.format(m.fecha));
      _cell(
        registro,
        row,
        1,
        m.tipo == TipoMovimiento.ingreso ? 'INGRESO' : 'EGRESO',
      );
      _cell(registro, row, 2, m.monto, style: _moneyStyle);
      _cell(registro, row, 3, nombreCategoria(m, mapaCategorias));
      _cell(registro, row, 4, nombreCuenta(m, mapaCuentas));
      _cell(registro, row, 5, m.comentario ?? '');
      _cell(registro, row, 6, m.mes);
    }

    registro.setColumnWidth(0, 18);
    registro.setColumnWidth(1, 14);
    registro.setColumnWidth(2, 12);
    registro.setColumnWidth(3, 18);
    registro.setColumnWidth(4, 16);
    registro.setColumnWidth(5, 30);
    registro.setColumnWidth(6, 8);
  }

  static void _escribirBD(
    Sheet bd,
    List<Map<String, dynamic>> cuentasList,
    Map<String, double> saldos,
    Map<String, Map<String, double>> resumenCuentas,
  ) {
    _headerCell(bd, 0, 0, 'CUENTA');
    _headerCell(bd, 0, 1, 'SALDO INICIAL');
    _headerCell(bd, 0, 2, 'INGRESO');
    _headerCell(bd, 0, 3, 'EGRESO');
    _headerCell(bd, 0, 4, 'SALDO REAL');

    var row = 1;
    for (final c in cuentasList) {
      final cuentaNombre = c['nombre'] as String;
      final saldoInicial = saldos[cuentaNombre] ?? 0.0;
      final ingresos = resumenCuentas[cuentaNombre]?['ingresos'] ?? 0.0;
      final egresos = resumenCuentas[cuentaNombre]?['egresos'] ?? 0.0;

      _cell(bd, row, 0, cuentaNombre);
      _cell(bd, row, 1, (c['saldo_inicial'] as num).toDouble(),
          style: _moneyStyle);
      _cell(bd, row, 2, ingresos, style: _moneyStyle);
      _cell(bd, row, 3, egresos, style: _moneyStyle);
      _cell(bd, row, 4, saldoInicial + ingresos - egresos,
          style: _moneyStyle);
      row++;
    }

    bd.setColumnWidth(0, 16);
    bd.setColumnWidth(1, 16);
    bd.setColumnWidth(2, 14);
    bd.setColumnWidth(3, 14);
    bd.setColumnWidth(4, 14);
  }

  // ── Guardado local ────────────────────────────────────────────────────────

  static Future<String> guardarCopiaLocal(ExcelExportResult result) async {
    if (kIsWeb) {
      throw UnsupportedError('guardarCopiaLocal no aplica en web');
    }

    final dir = await getExportDir();
    final path = p.join(dir.path, result.filename);
    await File(path).writeAsBytes(result.bytes, flush: true);
    return path;
  }

  static Future<Directory> getExportDir() async {
    if (kIsWeb) throw UnsupportedError('getExportDir no aplica en web');

    if (Platform.isAndroid) {
      // En Android 11+ no se puede escribir directamente en Downloads.
      // Usamos el almacenamiento externo propio de la app (sin permisos).
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'FinanzasApp'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }

    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final dir = Directory(p.join(downloads.path, 'FinanzasApp'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final test = File(p.join(dir.path, '.test'));
        test.writeAsBytesSync([]);
        test.deleteSync();
        return dir;
      }
    } catch (_) {
      // getDownloadsDirectory no está disponible en esta plataforma.
    }

    final dir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(dir.path, 'exports'));
    if (!appDir.existsSync()) appDir.createSync(recursive: true);
    return appDir;
  }

  static Future<List<FileSystemEntity>> listarExports() async {
    if (kIsWeb) return [];
    final dir = await getExportDir();
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .where((f) => f.path.endsWith('.xlsx'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  static Future<void> eliminar(String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  // ── Helpers de celdas ─────────────────────────────────────────────────────

  static void _cell(
    Sheet sheet,
    int row,
    int col,
    dynamic value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );

    if (value is String) {
      cell.value = TextCellValue(value);
    } else if (value is int) {
      cell.value = IntCellValue(value);
    } else if (value is double) {
      cell.value = DoubleCellValue(value);
    } else if (value is DateTime) {
      cell.value = DateCellValue.fromDateTime(value);
    } else {
      return;
    }

    if (style != null) cell.cellStyle = style;
  }

  static void _headerCell(Sheet sheet, int row, int col, String text) {
    _cell(sheet, row, col, text, style: _headerStyle);
  }
}
