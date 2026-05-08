// lib/screens/importar_excel_screen.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/excel_import.dart';
import '../models/movimientos_provider.dart';

class ImportarExcelScreen extends StatefulWidget {
  const ImportarExcelScreen({super.key});

  @override
  State<ImportarExcelScreen> createState() => _ImportarExcelScreenState();
}

class _ImportarExcelScreenState extends State<ImportarExcelScreen> {
  String? _rutaArchivo;
  bool _importando = false;
  _ResultadoImport? _resultado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar Excel')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instrucciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text('Formato esperado',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Hoja REGISTRO: FECHA · MOVIMIENTO · MONTO · CATEGORÍA · CUENTA · COMENTARIO\n'
                    'Hoja BD (opcional): CUENTA · SALDO INICIAL — se importan automáticamente.',
                    style:
                        TextStyle(fontSize: 13, color: Colors.blue.shade800),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              onPressed: _seleccionarArchivo,
              icon: const Icon(Icons.folder_open),
              label: Text(_rutaArchivo != null
                  ? _rutaArchivo!.split('\\').last
                  : 'Seleccionar archivo .xlsx'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16)),
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed:
                  _rutaArchivo != null && !_importando ? _importar : null,
              icon: _importando
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload),
              label: Text(_importando ? 'Importando...' : 'Importar datos'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16)),
            ),

            // Resultado
            if (_resultado != null) ...[
              const SizedBox(height: 20),
              _ResultadoWidget(resultado: _resultado!),
            ],

            const Spacer(),

            Text(
              'Los registros existentes con el mismo ID no se duplicarán.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result != null) {
      setState(() {
        _rutaArchivo = result.files.single.path;
        _resultado = null;
      });
    }
  }

  Future<void> _importar() async {
    if (_rutaArchivo == null) return;
    setState(() { _importando = true; _resultado = null; });

    try {
      final res = await ExcelImportService.importar(_rutaArchivo!);
      // ignore: use_build_context_synchronously
      final importados = await context
          .read<MovimientosProvider>()
          .importarLista(res.movimientos);

      setState(() {
        _resultado = _ResultadoImport(
          importados: importados,
          ignorados: res.ignorados,
          saldosEncontrados: res.saldosIniciales,
          error: null,
        );
      });
    } catch (e) {
      setState(() {
        _resultado = _ResultadoImport(
          importados: 0,
          ignorados: 0,
          saldosEncontrados: null,
          error: 'Error al importar: $e',
        );
      });
    } finally {
      setState(() => _importando = false);
    }
  }
}

class _ResultadoImport {
  final int importados;
  final int ignorados;
  final Map<String, double>? saldosEncontrados;
  final String? error;

  _ResultadoImport({
    required this.importados,
    required this.ignorados,
    required this.saldosEncontrados,
    required this.error,
  });
}

class _ResultadoWidget extends StatelessWidget {
  final _ResultadoImport resultado;
  const _ResultadoWidget({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');
    final hayError = resultado.error != null;

    return Column(
      children: [
        // Resultado principal
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hayError ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hayError
                    ? Colors.red.shade200
                    : Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(
                hayError
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: hayError ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hayError
                      ? resultado.error!
                      : 'Se importaron ${resultado.importados} movimientos.'
                          '${resultado.ignorados > 0 ? '\n${resultado.ignorados} filas ignoradas.' : ''}',
                  style: TextStyle(
                      color: hayError
                          ? Colors.red.shade700
                          : Colors.green.shade700),
                ),
              ),
            ],
          ),
        ),

        // Saldos iniciales detectados
        if (resultado.saldosEncontrados != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.account_balance_wallet,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text('Saldos iniciales detectados y guardados',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.blue.shade700)),
                ]),
                const SizedBox(height: 10),
                ...resultado.saldosEncontrados!.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade800)),
                      Text(
                        '\$${fmt.format(e.value)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: e.value >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                Text(
                  'Puedes ajustarlos en Ajustes → Saldos iniciales.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
