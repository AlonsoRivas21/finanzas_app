// lib/database/excel_export.dart

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/movimiento.dart';
import 'database_helper.dart';
import 'saldos_service.dart';

class ExcelExportService {
  /// Devuelve la carpeta donde se guardan los exports
  static Future<Directory> getExportDir() async {
    // Intentar guardar en Descargas públicas
    final downloads = Directory('/storage/emulated/0/Download/FinanzasApp');
    try {
      if (!downloads.existsSync()) downloads.createSync(recursive: true);
      // Verificar que tenemos permisos escribiendo un archivo de prueba
      final test = File('${downloads.path}/.test');
      test.writeAsBytesSync([]);
      test.deleteSync();
      return downloads;
    } catch (_) {
      // Sin permisos — usar carpeta privada de la app
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/exports');
      if (!appDir.existsSync()) appDir.createSync(recursive: true);
      return appDir;
    }
  }

  static Future<String> exportar(int anio) async {
    final db = DatabaseHelper();
    final movimientos = await db.getMovimientos(anio: anio, limit: 99999);
    final saldos = await SaldosService.getSaldosIniciales();
    final resumenCuentas = await db.getResumenPorCuenta(anio);

    final excel = Excel.createExcel();

    // ── Hoja REGISTRO ─────────────────────────────────────────────────────
    final registro = excel['REGISTRO'];
    excel.setDefaultSheet('REGISTRO');

    _cell(registro, 0, 1, 'BILLETERA');
    _cell(registro, 0, 2, 'DEBITO BA');
    _cell(registro, 0, 3, 'DEBITO NIU');
    _cell(registro, 0, 4, 'DISPONIBLE');
    _cell(registro, 0, 5, 'TDC');

    _cell(registro, 1, 1, saldos['BILLETERA'] ?? 0.0);
    _cell(registro, 1, 2, saldos['DEBITO BA'] ?? 0.0);
    _cell(registro, 1, 3, saldos['DEBITO NIU'] ?? 0.0);
    _cell(registro, 1, 4,
        (saldos['BILLETERA'] ?? 0.0) +
        (saldos['DEBITO BA'] ?? 0.0) +
        (saldos['DEBITO NIU'] ?? 0.0));
    _cell(registro, 1, 5,
        (saldos['CREDITO BA'] ?? 0.0) +
        (saldos['CREDITO NIU'] ?? 0.0));

    _headerCell(registro, 2, 0, 'FECHA');
    _headerCell(registro, 2, 1, 'MOVIMIENTO');
    _headerCell(registro, 2, 2, 'MONTO');
    _headerCell(registro, 2, 3, 'CATEGORIA');
    _headerCell(registro, 2, 4, 'CUENTA');
    _headerCell(registro, 2, 5, 'COMENTARIO');
    _headerCell(registro, 2, 6, 'MES');

    final fmt = DateFormat('yyyy-MM-dd');
    for (int i = 0; i < movimientos.length; i++) {
      final m = movimientos[i];
      final row = i + 3;
      _cell(registro, row, 0, fmt.format(m.fecha));
      _cell(registro, row, 1,
          m.tipo == TipoMovimiento.ingreso ? 'INGRESO' : 'EGRESO');
      _cell(registro, row, 2, m.monto);
      _cell(registro, row, 3, m.categoria.nombre);
      _cell(registro, row, 4, m.cuenta.nombre);
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

    // ── Hoja BD ───────────────────────────────────────────────────────────
    final bd = excel['BD'];

    _headerCell(bd, 0, 0, 'CUENTA');
    _headerCell(bd, 0, 1, 'SALDO INICIAL');
    _headerCell(bd, 0, 2, 'INGRESO');
    _headerCell(bd, 0, 3, 'EGRESO');
    _headerCell(bd, 0, 4, 'SALDO REAL');

    int row = 1;
    for (final cuenta in Cuenta.values) {
      final saldoInicial = saldos[cuenta.nombre] ?? 0.0;
      final ingresos = resumenCuentas[cuenta.nombre]?['ingresos'] ?? 0.0;
      final egresos  = resumenCuentas[cuenta.nombre]?['egresos']  ?? 0.0;
      _cell(bd, row, 0, cuenta.nombre);
      _cell(bd, row, 1, saldoInicial);
      _cell(bd, row, 2, ingresos);
      _cell(bd, row, 3, egresos);
      _cell(bd, row, 4, saldoInicial + ingresos - egresos);
      row++;
    }

    bd.setColumnWidth(0, 16);
    bd.setColumnWidth(1, 16);
    bd.setColumnWidth(2, 14);
    bd.setColumnWidth(3, 14);
    bd.setColumnWidth(4, 14);

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    // ── Guardar ───────────────────────────────────────────────────────────
    final dir = await getExportDir();
    final path = '${dir.path}/finanzas_$anio.xlsx';
    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el archivo');
    File(path).writeAsBytesSync(bytes);

    return path;
  }

  /// Lista todos los archivos exportados
  static Future<List<FileSystemEntity>> listarExports() async {
    final dir = await getExportDir();
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .where((f) => f.path.endsWith('.xlsx'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Elimina un archivo exportado
  static Future<void> eliminar(String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  static void _cell(Sheet sheet, int row, int col, dynamic value) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    if (value is String) {
      cell.value = TextCellValue(value);
    } else if (value is int) {
      cell.value = IntCellValue(value);
    } else if (value is double) {
      cell.value = DoubleCellValue(value);
    }
  }

  static void _headerCell(Sheet sheet, int row, int col, String text) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#2563EB'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
  }
}
