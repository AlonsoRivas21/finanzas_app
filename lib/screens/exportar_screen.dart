// lib/screens/exportar_screen.dart
// Versión unificada app + web

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../database/excel_export.dart';

class ExportarScreen extends StatefulWidget {
  const ExportarScreen({super.key});

  @override
  State<ExportarScreen> createState() => _ExportarScreenState();
}

class _ExportarScreenState extends State<ExportarScreen> {
  List<int> _anios = [];
  int? _anioSeleccionado;
  bool _cargando = false;
  bool _exportando = false;
  String? _rutaArchivo;
  String? _error;
  List<FileSystemEntity> _archivos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final anios = kIsWeb
        ? _aniosWeb()
        : await DatabaseHelper().getAniosDisponibles();
    final archivos = await ExcelExportService.listarExports();
    setState(() {
      _anios = anios.isNotEmpty ? anios : [DateTime.now().year];
      _anioSeleccionado = _anios.first;
      _archivos = archivos;
      _cargando = false;
    });
  }

  List<int> _aniosWeb() {
    final now = DateTime.now().year;
    return [now, now - 1, now - 2];
  }

  Future<void> _exportar() async {
    if (_anioSeleccionado == null) return;
    setState(() { _exportando = true; _rutaArchivo = null; _error = null; });

    try {
      final path = await ExcelExportService.exportar(_anioSeleccionado!);
      final archivos = await ExcelExportService.listarExports();
      setState(() {
        _rutaArchivo = path;
        _archivos = archivos;
        _exportando = false;
      });

      if (kIsWeb && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Descargando finanzas_$_anioSeleccionado.xlsx...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() { _error = 'Error al exportar: $e'; _exportando = false; });
    }
  }

  Future<void> _eliminar(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('¿Eliminar ${path.split('/').last}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ExcelExportService.eliminar(path);
      if (_rutaArchivo == path) setState(() => _rutaArchivo = null);
      final archivos = await ExcelExportService.listarExports();
      setState(() => _archivos = archivos);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar Excel')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Info
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kIsWeb
                            ? 'El archivo se descargará directo a tu carpeta de Descargas.'
                            : 'Los archivos se guardan en:\nDescargas / FinanzasApp',
                        style: TextStyle(
                            fontSize: 13, color: Colors.blue.shade800),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Selector año
                Text('Seleccionar año',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _anioSeleccionado,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder()),
                  items: _anios
                      .map((a) => DropdownMenuItem(
                          value: a, child: Text('$a')))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _anioSeleccionado = v;
                    _rutaArchivo = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: _anioSeleccionado != null && !_exportando
                      ? _exportar : null,
                  icon: _exportando
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  label: Text(_exportando
                      ? 'Generando...'
                      : 'Exportar $_anioSeleccionado'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16)),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                ],

                // Éxito en app
                if (_rutaArchivo != null && !kIsWeb) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline,
                          color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Archivo generado',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700)),
                            Text(_rutaArchivo!.split('/').last,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade600)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => OpenFile.open(_rutaArchivo!),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.all(14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Share.shareXFiles(
                            [XFile(_rutaArchivo!)]),
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(14)),
                      ),
                    ),
                  ]),
                ],

                // Archivos guardados (solo app)
                if (!kIsWeb && _archivos.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Archivos guardados',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: _archivos.map((f) {
                        final nombre = f.path.split('/').last;
                        final stat   = File(f.path).statSync();
                        final fecha  = DateFormat('dd/MM/yyyy HH:mm')
                            .format(stat.modified);
                        final kb = (stat.size / 1024).toStringAsFixed(1);

                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.table_chart,
                                color: Colors.green.shade700, size: 20),
                          ),
                          title: Text(nombre,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text('$fecha · $kb KB',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 20),
                                onPressed: () => OpenFile.open(f.path),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share, size: 20),
                                onPressed: () =>
                                    Share.shareXFiles([XFile(f.path)]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: Colors.red),
                                onPressed: () => _eliminar(f.path),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
