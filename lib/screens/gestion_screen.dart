// lib/screens/gestion_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/catalogo_service.dart';
import '../models/cuenta_model.dart';
import '../models/categoria_model.dart';

class GestionScreen extends StatefulWidget {
  const GestionScreen({super.key});

  @override
  State<GestionScreen> createState() => _GestionScreenState();
}

class _GestionScreenState extends State<GestionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Cuentas'),
            Tab(icon: Icon(Icons.category), text: 'Categorías'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CuentasTab(),
          _CategoriasTab(),
        ],
      ),
    );
  }
}

// ── Tab Cuentas ───────────────────────────────────────────────────────────────

class _CuentasTab extends StatefulWidget {
  const _CuentasTab();

  @override
  State<_CuentasTab> createState() => _CuentasTabState();
}

class _CuentasTabState extends State<_CuentasTab> {
  List<CuentaModel> _cuentas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final cuentas = await CatalogoService.getCuentas(forceRefresh: true);
    setState(() { _cuentas = cuentas; _cargando = false; });
  }

  Future<void> _mostrarFormCuenta({CuentaModel? cuenta}) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (_) => _FormCuentaDialog(cuenta: cuenta),
    );
    if (resultado == true) _cargar();
  }

  Future<void> _eliminar(CuentaModel cuenta) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text('¿Eliminar "${cuenta.nombre}"? Los movimientos existentes se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmado == true) {
      await CatalogoService.eliminarCuenta(cuenta.id);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');

    return _cargando
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_cuentas.length} cuentas activas',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    FilledButton.icon(
                      onPressed: () => _mostrarFormCuenta(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nueva cuenta'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _cuentas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = _cuentas[i];
                    final color = c.esTarjeta ? Colors.red
                        : c.esAhorro ? Colors.teal : Colors.blue;
                    final icono = c.esTarjeta ? Icons.credit_card
                        : c.esAhorro ? Icons.savings : Icons.account_balance;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.1),
                          child: Icon(icono, color: color, size: 20),
                        ),
                        title: Text(c.nombre,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          '${_tipoLabel(c.tipo)} · Saldo inicial: \$${fmt.format(c.saldoInicial)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _mostrarFormCuenta(cuenta: c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              onPressed: () => _eliminar(c),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'efectivo': return 'Efectivo';
      case 'debito':   return 'Débito';
      case 'credito':  return 'Crédito';
      case 'ahorro':   return 'Ahorro';
      default:         return tipo;
    }
  }
}

// ── Formulario de Cuenta ──────────────────────────────────────────────────────

class _FormCuentaDialog extends StatefulWidget {
  final CuentaModel? cuenta;
  const _FormCuentaDialog({this.cuenta});

  @override
  State<_FormCuentaDialog> createState() => _FormCuentaDialogState();
}

class _FormCuentaDialogState extends State<_FormCuentaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _saldoCtrl = TextEditingController();
  String _tipo = 'debito';
  bool _guardando = false;

  bool get esEdicion => widget.cuenta != null;

  @override
  void initState() {
    super.initState();
    if (esEdicion) {
      _nombreCtrl.text = widget.cuenta!.nombre;
      _saldoCtrl.text = widget.cuenta!.saldoInicial == 0
          ? '' : widget.cuenta!.saldoInicial.toString();
      _tipo = widget.cuenta!.tipo;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _saldoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final nombre = _nombreCtrl.text.trim();
    final saldo = double.tryParse(_saldoCtrl.text.replaceAll(',', '.')) ?? 0.0;

    try {
      if (esEdicion) {
        await CatalogoService.actualizarCuenta(
          widget.cuenta!.copyWith(
            nombre: nombre.toUpperCase(),
            tipo: _tipo,
            saldoInicial: saldo,
          ),
        );
      } else {
        await CatalogoService.crearCuenta(
          nombre: nombre,
          tipo: _tipo,
          saldoInicial: saldo,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(esEdicion ? 'Editar cuenta' : 'Nueva cuenta'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la cuenta',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
              DropdownMenuItem(value: 'debito',   child: Text('Débito')),
              DropdownMenuItem(value: 'credito',  child: Text('Crédito')),
              DropdownMenuItem(value: 'ahorro',   child: Text('Ahorro')),
            ],
            onChanged: (v) => setState(() => _tipo = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _saldoCtrl,
            decoration: const InputDecoration(
              labelText: 'Saldo inicial',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
              helperText: 'Negativo si es deuda (ej: -59.83)',
            ),
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(esEdicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

// ── Tab Categorías ────────────────────────────────────────────────────────────

class _CategoriasTab extends StatefulWidget {
  const _CategoriasTab();

  @override
  State<_CategoriasTab> createState() => _CategoriasTabState();
}

class _CategoriasTabState extends State<_CategoriasTab> {
  List<CategoriaModel> _categorias = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final cats = await CatalogoService.getCategorias(forceRefresh: true);
    setState(() { _categorias = cats; _cargando = false; });
  }

  Future<void> _mostrarForm({CategoriaModel? cat}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => _FormCategoriaDialog(categoria: cat),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminar(CategoriaModel cat) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${cat.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmado == true) {
      await CatalogoService.eliminarCategoria(cat.id);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cargando
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_categorias.length} categorías activas',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    FilledButton.icon(
                      onPressed: () => _mostrarForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nueva categoría'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categorias.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final cat = _categorias[i];
                    final color = cat.tipo == 'ingreso'
                        ? Colors.green
                        : cat.tipo == 'ambos'
                            ? Colors.blue
                            : Colors.orange;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.1),
                          child: Icon(_iconoDesdeString(cat.icono),
                              color: color, size: 18),
                        ),
                        title: Text(cat.nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          _tipoLabel(cat.tipo),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _mostrarForm(cat: cat),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              onPressed: () => _eliminar(cat),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'ingreso': return 'Solo ingresos';
      case 'egreso':  return 'Solo egresos';
      case 'ambos':   return 'Ingresos y egresos';
      default:        return tipo;
    }
  }

  IconData _iconoDesdeString(String nombre) {
    const mapa = {
      'savings': Icons.savings,
      'directions_bus': Icons.directions_bus,
      'restaurant': Icons.restaurant,
      'swap_horiz': Icons.swap_horiz,
      'receipt': Icons.receipt,
      'shopping_bag': Icons.shopping_bag,
      'account_balance_wallet': Icons.account_balance_wallet,
      'home': Icons.home,
      'shopping_cart': Icons.shopping_cart,
      'money_off': Icons.money_off,
      'movie': Icons.movie,
      'content_cut': Icons.content_cut,
      'label': Icons.label,
      'sports': Icons.sports,
      'health_and_safety': Icons.health_and_safety,
      'school': Icons.school,
      'pets': Icons.pets,
      'flight': Icons.flight,
      'wifi': Icons.wifi,
      'phone': Icons.phone,
    };
    return mapa[nombre] ?? Icons.label;
  }
}

// ── Formulario de Categoría ───────────────────────────────────────────────────

class _FormCategoriaDialog extends StatefulWidget {
  final CategoriaModel? categoria;
  const _FormCategoriaDialog({this.categoria});

  @override
  State<_FormCategoriaDialog> createState() => _FormCategoriaDialogState();
}

class _FormCategoriaDialogState extends State<_FormCategoriaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  String _tipo = 'egreso';
  String _icono = 'label';
  bool _guardando = false;

  bool get esEdicion => widget.categoria != null;

  static const _iconos = {
    'label': Icons.label,
    'savings': Icons.savings,
    'directions_bus': Icons.directions_bus,
    'restaurant': Icons.restaurant,
    'swap_horiz': Icons.swap_horiz,
    'receipt': Icons.receipt,
    'shopping_bag': Icons.shopping_bag,
    'account_balance_wallet': Icons.account_balance_wallet,
    'home': Icons.home,
    'shopping_cart': Icons.shopping_cart,
    'money_off': Icons.money_off,
    'movie': Icons.movie,
    'content_cut': Icons.content_cut,
    'sports': Icons.sports,
    'health_and_safety': Icons.health_and_safety,
    'school': Icons.school,
    'pets': Icons.pets,
    'flight': Icons.flight,
    'wifi': Icons.wifi,
    'phone': Icons.phone,
  };

  @override
  void initState() {
    super.initState();
    if (esEdicion) {
      _nombreCtrl.text = widget.categoria!.nombre;
      _tipo  = widget.categoria!.tipo;
      _icono = widget.categoria!.icono;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      if (esEdicion) {
        await CatalogoService.actualizarCategoria(
          widget.categoria!.copyWith(
            nombre: _nombreCtrl.text.trim().toUpperCase(),
            tipo: _tipo,
            icono: _icono,
          ),
        );
      } else {
        await CatalogoService.crearCategoria(
          nombre: _nombreCtrl.text.trim(),
          tipo: _tipo,
          icono: _icono,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(esEdicion ? 'Editar categoría' : 'Nueva categoría'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(
              labelText: 'Aplica a',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'egreso',  child: Text('Solo egresos')),
              DropdownMenuItem(value: 'ingreso', child: Text('Solo ingresos')),
              DropdownMenuItem(value: 'ambos',   child: Text('Ambos')),
            ],
            onChanged: (v) => setState(() => _tipo = v!),
          ),
          const SizedBox(height: 12),
          // Selector de ícono
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Ícono',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _iconos.entries.map((e) {
              final selected = e.key == _icono;
              return GestureDetector(
                onTap: () => setState(() => _icono = e.key),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(e.value, size: 20),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(esEdicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
