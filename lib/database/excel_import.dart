// lib/database/excel_import.dart

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import '../models/movimiento.dart';
import 'saldos_service.dart';

class ExcelImportService {
  static const _uuid = Uuid();

  static Future<({
    List<Movimiento> movimientos,
    int ignorados,
    Map<String, double>? saldosIniciales,
  })> importar(String filePath) async {
    final bytes = File(filePath).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    final sheet = excel.tables['REGISTRO'];
    if (sheet == null) {
      throw Exception('No se encontró la hoja REGISTRO en el archivo.');
    }

    final movimientos = <Movimiento>[];
    int ignorados = 0;

    // Fila 0: encabezados de cuentas
    // Fila 1: fórmulas de saldos
    // Fila 2: encabezados (FECHA, MOVIMIENTO, MONTO...)
    // Fila 3+: datos reales
    for (int i = 3; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      if (row.isEmpty) continue;

      try {
        final fecha = _parseDate(row[0]?.value);
        final tipoStr = _str(row[1]?.value);
        final monto = _parseDouble(row[2]?.value);
        final categoriaStr = _str(row[3]?.value);
        final cuentaStr = _str(row[4]?.value);
        final comentario = _strOpt(row[5]?.value);
        final mes = fecha?.month ?? 0;

        if (fecha == null || tipoStr.isEmpty || monto == null || monto <= 0) {
          ignorados++;
          continue;
        }

        final tipo = tipoStr.toUpperCase() == 'INGRESO'
            ? TipoMovimiento.ingreso
            : TipoMovimiento.egreso;

        movimientos.add(Movimiento(
          id: _uuid.v4(),
          fecha: fecha,
          tipo: tipo,
          monto: monto,
          categoria: CategoriaExtension.fromString(categoriaStr),
          cuenta: CuentaExtension.fromString(cuentaStr),
          comentario: comentario,
          mes: mes,
          sincronizado: false,
        ));
      } catch (e) {
        ignorados++;
      }
    }

    // Intentar leer saldos iniciales de la pestaña BD
    final saldosIniciales = await _leerSaldosIniciales(excel);

    // Si encontró saldos, guardarlos automáticamente
    if (saldosIniciales != null) {
      await SaldosService.setSaldosIniciales(saldosIniciales);
    }

    return (
      movimientos: movimientos,
      ignorados: ignorados,
      saldosIniciales: saldosIniciales,
    );
  }

  static Future<Map<String, double>?> _leerSaldosIniciales(
      Excel excel) async {
    final sheet = excel.tables['BD'];
    if (sheet == null) return null;

    final saldos = <String, double>{};

    // La pestaña BD tiene: CUENTA en col 0, SALDO INICIAL en col 1
    // Fila 0 es el encabezado, datos desde fila 1
    for (int i = 1; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      if (row.isEmpty) continue;

      final cuentaStr = _str(row[0]?.value).toUpperCase();
      final saldo = _parseDouble(row[1]?.value);

      if (cuentaStr.isEmpty || saldo == null) continue;

      // Verificar que sea una cuenta válida
      final esValida = Cuenta.values.any((c) => c.nombre == cuentaStr);
      if (esValida) {
        saldos[cuentaStr] = saldo;
      }
    }

    return saldos.isEmpty ? null : saldos;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _textFromCell(TextCellValue cell) =>
      cell.value.text ?? '';

  static DateTime? _parseDate(CellValue? cell) {
    if (cell == null) return null;
    if (cell is DateCellValue) {
      return DateTime(cell.year, cell.month, cell.day);
    }
    if (cell is DateTimeCellValue) {
      return DateTime(cell.year, cell.month, cell.day);
    }
    if (cell is TextCellValue) {
      try { return DateTime.parse(_textFromCell(cell)); } catch (_) {}
    }
    return null;
  }

  static double? _parseDouble(CellValue? cell) {
    if (cell == null) return null;
    if (cell is DoubleCellValue) return cell.value;
    if (cell is IntCellValue) return cell.value.toDouble();
    if (cell is TextCellValue) {
      return double.tryParse(_textFromCell(cell).replaceAll(',', '.'));
    }
    return null;
  }

  static String _str(CellValue? cell) {
    if (cell == null) return '';
    if (cell is TextCellValue) return _textFromCell(cell).trim();
    if (cell is DoubleCellValue) return cell.value.toString();
    if (cell is IntCellValue) return cell.value.toString();
    return '';
  }

  static String? _strOpt(CellValue? cell) {
    final s = _str(cell);
    return s.isEmpty ? null : s;
  }
}
