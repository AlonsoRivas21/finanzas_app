// lib/screens/form_movimiento_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/movimiento.dart';
import '../models/movimientos_provider.dart';

enum _ModoFormulario { movimiento, transferencia }

class FormMovimientoScreen extends StatefulWidget {
  final Movimiento? movimiento;
  const FormMovimientoScreen({super.key, this.movimiento});

  @override
  State<FormMovimientoScreen> createState() => _FormMovimientoScreenState();
}

class _FormMovimientoScreenState extends State<FormMovimientoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _comentarioCtrl = TextEditingController();

  _ModoFormulario _modo = _ModoFormulario.movimiento;
  TipoMovimiento _tipo = TipoMovimiento.egreso;
  Categoria _categoria = Categoria.transporte;
  Cuenta _cuenta = Cuenta.billetera;
  Cuenta _cuentaDestino = Cuenta.debitoBa;
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  bool get esEdicion => widget.movimiento != null;

  @override
  void initState() {
    super.initState();
    if (esEdicion) {
      final m = widget.movimiento!;
      _tipo = m.tipo;
      _categoria = m.categoria;
      _cuenta = m.cuenta;
      _fecha = m.fecha;
      _montoCtrl.text = m.monto.toString();
      _comentarioCtrl.text = m.comentario ?? '';
      // Si es transferencia, no permitir cambiar modo
      if (m.categoria == Categoria.transferencia) {
        _modo = _ModoFormulario.transferencia;
      }
    }
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar movimiento' : 'Nuevo movimiento'),
        actions: [
          _guardando
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator()),
                )
              : TextButton(onPressed: _guardar, child: const Text('Guardar')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Selector de modo (solo al crear)
            if (!esEdicion) ...[
              _SectionLabel('Tipo de registro'),
              const SizedBox(height: 8),
              Row(children: [
                _TipoBtn(
                  label: 'Movimiento',
                  icon: Icons.receipt_long,
                  selected: _modo == _ModoFormulario.movimiento,
                  onTap: () => setState(
                      () => _modo = _ModoFormulario.movimiento),
                ),
                const SizedBox(width: 12),
                _TipoBtn(
                  label: 'Transferencia',
                  icon: Icons.swap_horiz,
                  selected: _modo == _ModoFormulario.transferencia,
                  onTap: () => setState(
                      () => _modo = _ModoFormulario.transferencia),
                ),
              ]),
              const SizedBox(height: 20),
            ],

            // Campos según modo
            if (_modo == _ModoFormulario.movimiento)
              ..._camposMovimiento()
            else
              ..._camposTransferencia(),
          ],
        ),
      ),
    );
  }

  List<Widget> _camposMovimiento() {
    return [
      _SectionLabel('Tipo'),
      const SizedBox(height: 8),
      Row(children: [
        _TipoBtn(
          label: 'Egreso',
          icon: Icons.arrow_upward,
          selected: _tipo == TipoMovimiento.egreso,
          color: Colors.red,
          onTap: () => setState(() => _tipo = TipoMovimiento.egreso),
        ),
        const SizedBox(width: 12),
        _TipoBtn(
          label: 'Ingreso',
          icon: Icons.arrow_downward,
          selected: _tipo == TipoMovimiento.ingreso,
          color: Colors.green,
          onTap: () => setState(() => _tipo = TipoMovimiento.ingreso),
        ),
      ]),
      const SizedBox(height: 20),
      ..._camposComunes(),
      const SizedBox(height: 20),
      _SectionLabel('Categoría'),
      const SizedBox(height: 8),
      DropdownButtonFormField<Categoria>(
        value: _categoria,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: Categoria.values
            .map((c) =>
                DropdownMenuItem(value: c, child: Text(c.nombre)))
            .toList(),
        onChanged: (v) => setState(() => _categoria = v!),
      ),
      const SizedBox(height: 20),
      _SectionLabel('Cuenta'),
      const SizedBox(height: 8),
      DropdownButtonFormField<Cuenta>(
        value: _cuenta,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: Cuenta.values
            .map((c) =>
                DropdownMenuItem(value: c, child: Text(c.nombre)))
            .toList(),
        onChanged: (v) => setState(() => _cuenta = v!),
      ),
      const SizedBox(height: 20),
      _SectionLabel('Comentario (opcional)'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _comentarioCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'Nota adicional...',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _camposTransferencia() {
    return [
      // Indicador visual del flujo
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CuentaPill(nombre: _cuenta.nombre, color: Colors.red),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: Colors.blue.shade400),
            const SizedBox(width: 8),
            _CuentaPill(nombre: _cuentaDestino.nombre, color: Colors.green),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ..._camposComunes(),
      const SizedBox(height: 20),
      _SectionLabel('Cuenta origen'),
      const SizedBox(height: 8),
      DropdownButtonFormField<Cuenta>(
        value: _cuenta,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.arrow_upward, color: Colors.red),
        ),
        items: Cuenta.values
            .map((c) =>
                DropdownMenuItem(value: c, child: Text(c.nombre)))
            .toList(),
        onChanged: (v) {
          if (v == _cuentaDestino) return; // no permitir misma cuenta
          setState(() => _cuenta = v!);
        },
      ),
      const SizedBox(height: 16),
      _SectionLabel('Cuenta destino'),
      const SizedBox(height: 8),
      DropdownButtonFormField<Cuenta>(
        value: _cuentaDestino,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.arrow_downward, color: Colors.green),
        ),
        items: Cuenta.values
            .map((c) =>
                DropdownMenuItem(value: c, child: Text(c.nombre)))
            .toList(),
        onChanged: (v) {
          if (v == _cuenta) return; // no permitir misma cuenta
          setState(() => _cuentaDestino = v!);
        },
      ),
      const SizedBox(height: 20),
      _SectionLabel('Comentario (opcional)'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _comentarioCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'Ej: pago de tarjeta...',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _camposComunes() {
    return [
      _SectionLabel('Monto'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _montoCtrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          prefixText: '\$ ',
          hintText: '0.00',
          border: OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Ingresa el monto';
          if (double.tryParse(v.replaceAll(',', '.')) == null) {
            return 'Monto inválido';
          }
          return null;
        },
      ),
      const SizedBox(height: 20),
      _SectionLabel('Fecha'),
      const SizedBox(height: 8),
      InkWell(
        onTap: _seleccionarFecha,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 10),
            Text(DateFormat('dd/MM/yyyy').format(_fecha)),
          ]),
        ),
      ),
    ];
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_modo == _ModoFormulario.transferencia && _cuenta == _cuentaDestino) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cuenta origen y destino no pueden ser iguales')),
      );
      return;
    }

    setState(() => _guardando = true);
    final monto = double.parse(_montoCtrl.text.replaceAll(',', '.'));
    final comentario = _comentarioCtrl.text.trim();
    final prov = context.read<MovimientosProvider>();

    try {
      if (_modo == _ModoFormulario.transferencia) {
        await prov.agregarTransferencia(
          fecha: _fecha,
          monto: monto,
          cuentaOrigen: _cuenta,
          cuentaDestino: _cuentaDestino,
          comentario: comentario.isEmpty ? null : comentario,
        );
      } else if (esEdicion) {
        await prov.editar(widget.movimiento!.copyWith(
          fecha: _fecha,
          tipo: _tipo,
          monto: monto,
          categoria: _categoria,
          cuenta: _cuenta,
          comentario: comentario.isEmpty ? null : comentario,
          mes: _fecha.month,
          anio: _fecha.year,
        ));
      } else {
        await prov.agregar(
          fecha: _fecha,
          tipo: _tipo,
          monto: monto,
          categoria: _categoria,
          cuenta: _cuenta,
          comentario: comentario.isEmpty ? null : comentario,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600));
  }
}

class _TipoBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _TipoBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.12) : Colors.transparent,
            border: Border.all(
                color: selected ? c : Colors.grey.shade300, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? c : Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? c : Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuentaPill extends StatelessWidget {
  final String nombre;
  final Color color;
  const _CuentaPill({required this.nombre, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(nombre,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8))),
    );
  }
}
