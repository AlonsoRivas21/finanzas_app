// lib/screens/exportar_screen.dart
// Versión unificada app + web

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
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
  String? _mensajeExito;
  int _mensajeExitoId = 0;
  List<FileSystemEntity> _archivos = [];

  static const int _todosLosAnios = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    List<int> anios;
    try {
      anios = await ExcelExportService.getAniosDisponibles();
    } catch (_) {
      anios = [];
    }
    if (anios.isEmpty) anios = [DateTime.now().year];

    List<FileSystemEntity> archivos;
    try {
      archivos = await ExcelExportService.listarExports();
    } catch (e) {
      debugPrint('No se pudieron listar los archivos exportados: $e');
      archivos = [];
    }

    setState(() {
      _anios = anios;
      _anioSeleccionado = anios.first;
      _archivos = archivos;
      _cargando = false;
    });
  }

  Future<void> _exportar() async {
    if (_exportando || _anioSeleccionado == null) return;
    setState(() {
      _exportando = true;
      _rutaArchivo = null;
      _error = null;
      _mensajeExito = null;
    });

    final anio = _anioSeleccionado == _todosLosAnios ? null : _anioSeleccionado;

    try {
      if (kIsWeb) {
        final filename = ExcelExportService.nombreArchivo(anio);
        final destino = await ExcelExportService.elegirDestinoWeb(filename);
        if (!mounted) return;

        if (destino == 'cancelled') {
          setState(() => _exportando = false);
          return;
        }

        if (destino == 'picked') {
          ExcelExportResult result;
          try {
            result = await ExcelExportService.generar(anio: anio);
          } catch (_) {
            ExcelExportService.cancelarDestinoWeb();
            rethrow;
          }

          final escrito =
              await ExcelExportService.escribirDestinoWeb(result.bytes);
          if (escrito == 'saved') {
            _mostrarExitoTemporal('Archivo guardado: ${result.filename}');
          } else {
            ExcelExportService.descargarEnWeb(result);
            _mostrarExitoTemporal('Descarga iniciada: ${result.filename}');
          }
          return;
        }

        // Picker no disponible o con error: descarga normal.
        final result = await ExcelExportService.generar(anio: anio);
        ExcelExportService.descargarEnWeb(result);
        _mostrarExitoTemporal('Descarga iniciada: ${result.filename}');
        return;
      }

      final result = await ExcelExportService.generar(anio: anio);

      final destino = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar Excel',
        fileName: result.filename,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: result.bytes,
      );

      if (destino == null) {
        // El usuario canceló el diálogo.
        setState(() => _exportando = false);
        return;
      }

      // En escritorio file_picker solo devuelve la ruta: escribimos los bytes.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(destino).writeAsBytes(result.bytes, flush: true);
      }

      String? copia;
      try {
        copia = await ExcelExportService.guardarCopiaLocal(result);
      } catch (e) {
        debugPrint('No se pudo crear la copia local del Excel: $e');
      }

      List<FileSystemEntity> archivos = _archivos;
      try {
        archivos = await ExcelExportService.listarExports();
      } catch (e) {
        debugPrint('No se pudieron listar los archivos exportados: $e');
      }

      setState(() {
        _rutaArchivo = copia;
        _archivos = archivos;
      });
      _mostrarExitoTemporal(copia == null
          ? 'Archivo guardado.'
          : 'Archivo guardado. También creamos una copia para compartir.');
    } catch (e) {
      setState(() {
        _error = _mensajeErrorExportacion(e);
        _exportando = false;
      });
    }
  }

  String _mensajeErrorExportacion(Object e) {
    debugPrint('Error al exportar: $e');

    if (e is PathAccessException || e is FileSystemException) {
      return 'No se pudo guardar el archivo. Verifica el espacio disponible e inténtalo de nuevo.';
    }
    if (e is SocketException ||
        e.toString().contains('Failed host lookup') ||
        e.toString().contains('SocketException')) {
      return 'No hay conexión a internet. Inténtalo de nuevo.';
    }
    if (e is PlatformException) {
      return 'No se pudo abrir el selector de archivos. Inténtalo de nuevo.';
    }
    return 'No se pudo exportar. Inténtalo de nuevo.';
  }

  void _mostrarExitoTemporal(String mensaje) {
    final id = ++_mensajeExitoId;
    if (!mounted) return;
    setState(() {
      _mensajeExito = mensaje;
      _exportando = false;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || id != _mensajeExitoId) return;
      setState(() => _mensajeExito = null);
    });
  }

  Future<void> _eliminar(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('¿Eliminar ${p.basename(path)}?'),
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
                            ? 'En Chrome/Edge podrás elegir dónde guardarlo. En otros navegadores se descargará a tu carpeta de Descargas.'
                            : 'Se abrirá el diálogo Guardar como para elegir la carpeta (Descargas, Drive, etc.).',
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
                  items: [
                    const DropdownMenuItem<int>(
                        value: _todosLosAnios,
                        child: Text('Todos los años')),
                    ..._anios.map((a) => DropdownMenuItem(
                        value: a, child: Text('$a'))),
                  ],
                  onChanged: (v) => setState(() {
                    _anioSeleccionado = v;
                    _rutaArchivo = null;
                    _error = null;
                    _mensajeExito = null;
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
                      : _anioSeleccionado == _todosLosAnios
                          ? 'Exportar todo el historial'
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

                // Éxito
                if (_mensajeExito != null) ...[
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
                        child: Text(_mensajeExito!,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700)),
                      ),
                    ]),
                  ),
                ],

                // Copia local para abrir/compartir (solo app)
                if (_rutaArchivo != null && !kIsWeb) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.table_chart, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Copia para compartir',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700)),
                            Text(p.basename(_rutaArchivo!),
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
                        final nombre = p.basename(f.path);
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
