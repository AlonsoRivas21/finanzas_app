// lib/screens/movimientos_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/movimiento.dart';
import '../models/movimientos_provider.dart';
import '../widgets/movimiento_tile.dart';
import '../widgets/resumen_bar.dart';
import 'form_movimiento_screen.dart';
import 'importar_excel_screen.dart';

class MovimientosScreen extends StatefulWidget {
  const MovimientosScreen({super.key});

  @override
  State<MovimientosScreen> createState() => _MovimientosScreenState();
}

class _MovimientosScreenState extends State<MovimientosScreen> {
  final _searchCtrl = TextEditingController();
  bool _mostrarBusqueda = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovimientosProvider>().cargar();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _abrirImportar() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ImportarExcelScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MovimientosProvider>();
    final meses = [
      'Enero','Febrero','Marzo','Abril','Mayo','Junio',
      'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
    ];

    return Scaffold(
      appBar: AppBar(
        title: _mostrarBusqueda
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => prov.setBusqueda(v),
              )
            : const Text('Movimientos'),
        actions: [
          // Búsqueda
          IconButton(
            icon: Icon(_mostrarBusqueda ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _mostrarBusqueda = !_mostrarBusqueda);
              if (!_mostrarBusqueda) {
                _searchCtrl.clear();
                prov.setBusqueda(null);
              }
            },
          ),
          if (!_mostrarBusqueda) ...[
            // Selector año
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: prov.anioActual,
                style: Theme.of(context).textTheme.bodyMedium,
                items: List.generate(5, (i) {
                  final anio = DateTime.now().year - i;
                  return DropdownMenuItem(
                      value: anio, child: Text('$anio'));
                }),
                onChanged: (a) { if (a != null) prov.setAnio(a); },
              ),
            ),
            // Selector mes
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: prov.mesActual,
                style: Theme.of(context).textTheme.bodyMedium,
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(meses[i]),
                )),
                onChanged: (m) { if (m != null) prov.setMes(m); },
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'importar') _abrirImportar();
                if (value == 'limpiar') prov.limpiarFiltros();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'importar',
                  child: ListTile(
                    leading: Icon(Icons.upload_file),
                    title: Text('Importar Excel'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (prov.filtroCuenta != null || prov.filtroTipo != null)
                  const PopupMenuItem(
                    value: 'limpiar',
                    child: ListTile(
                      leading: Icon(Icons.filter_alt_off),
                      title: Text('Limpiar filtros'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          ResumenBar(mes: prov.mesActual),
          _FiltrosRapidos(prov: prov),
          Expanded(
            child: prov.cargando
                ? const Center(child: CircularProgressIndicator())
                : prov.error != null
                    ? _ErrorWidget(mensaje: prov.error!)
                    : prov.movimientos.isEmpty
                        ? _EmptyState(mes: meses[prov.mesActual - 1])
                        : _ListaMovimientos(movimientos: prov.movimientos),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FormMovimientoScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }
}

class _FiltrosRapidos extends StatelessWidget {
  final MovimientosProvider prov;
  const _FiltrosRapidos({required this.prov});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _Chip(label: 'Todos',
              selected: prov.filtroTipo == null && prov.filtroCuenta == null,
              onTap: () => prov.limpiarFiltros()),
          const SizedBox(width: 8),
          _Chip(label: 'Ingresos', selected: prov.filtroTipo == 'ingreso',
              color: Colors.green,
              onTap: () => prov.setFiltroTipo(
                  prov.filtroTipo == 'ingreso' ? null : 'ingreso')),
          const SizedBox(width: 8),
          _Chip(label: 'Egresos', selected: prov.filtroTipo == 'egreso',
              color: Colors.red,
              onTap: () => prov.setFiltroTipo(
                  prov.filtroTipo == 'egreso' ? null : 'egreso')),
          const SizedBox(width: 8),
          ...Cuenta.values.map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Chip(
              label: c.nombre,
              selected: prov.filtroCuenta == c.nombre,
              onTap: () => prov.setFiltroCuenta(
                  prov.filtroCuenta == c.nombre ? null : c.nombre),
            ),
          )),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected,
      required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: selected ? c : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? c : Colors.grey.shade600,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }
}

class _ListaMovimientos extends StatelessWidget {
  final List<Movimiento> movimientos;
  const _ListaMovimientos({required this.movimientos});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Movimiento>> agrupados = {};
    for (final m in movimientos) {
      final key = DateFormat('yyyy-MM-dd').format(m.fecha);
      agrupados.putIfAbsent(key, () => []).add(m);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: agrupados.length,
      itemBuilder: (context, i) {
        final fecha = agrupados.keys.elementAt(i);
        final lista = agrupados[fecha]!;
        final dt = DateTime.parse(fecha);
        final label = DateFormat('EEEE d MMM', 'es').format(dt);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                label.substring(0, 1).toUpperCase() + label.substring(1),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500, letterSpacing: 0.5),
              ),
            ),
            ...lista.map((m) => MovimientoTile(movimiento: m)),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String mes;
  const _EmptyState({required this.mes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Sin movimientos en $mes',
              style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => FormMovimientoScreen())),
            icon: const Icon(Icons.add),
            label: const Text('Agregar primero'),
          ),
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String mensaje;
  const _ErrorWidget({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(mensaje, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}
