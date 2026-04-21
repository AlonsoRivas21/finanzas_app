// lib/screens/saldos_screen.dart
// Reemplaza saldos_iniciales_screen.dart
// Ahora maneja saldos ACTUALES directamente

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../database/catalogo_service.dart';

class SaldosScreen extends StatefulWidget {
  const SaldosScreen({super.key});

  @override
  State<SaldosScreen> createState() => _SaldosScreenState();
}

class _SaldosScreenState extends State<SaldosScreen> {
  final Map<String, TextEditingController> _controllers = {};
  List<Map<String, dynamic>> _cuentas = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final cuentas = await CatalogoService.getCuentas();
    final saldos  = await DatabaseHelper().getSaldosActualesLocal();

    for (final c in cuentas) {
      final nombre = c['nombre'] as String;
      _controllers[nombre] = TextEditingController(
        text: saldos[nombre] == null || saldos[nombre] == 0
            ? '' : saldos[nombre]!.toString(),
      );
    }
    setState(() { _cuentas = cuentas; _cargando = false; });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final db = DatabaseHelper();
    for (final c in _cuentas) {
      final nombre = c['nombre'] as String;
      final val = double.tryParse(
              _controllers[nombre]?.text.replaceAll(',', '.') ?? '0') ??
          0.0;
      await db.setSaldoCuenta(nombre, val);
    }
    setState(() => _guardando = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saldos guardados'),
            backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldos actuales'),
        actions: [
          _guardando
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator()))
              : TextButton(
                  onPressed: _guardar,
                  child: const Text('Guardar')),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    'Ingresa el saldo actual de cada cuenta. '
                    'Este valor se usará como base para los cálculos.',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                  ),
                ),
                const SizedBox(height: 20),
                ..._cuentas.map((c) {
                  final nombre = c['nombre'] as String;
                  final tipo   = c['tipo'] as String;
                  final esTarjeta = tipo == 'credito';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            esTarjeta
                                ? Icons.credit_card
                                : Icons.account_balance_wallet,
                            size: 16, color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          if (esTarjeta) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('negativo si debes',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade800)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _controllers[nombre],
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                          decoration: InputDecoration(
                            prefixText: '\$ ',
                            hintText: esTarjeta ? 'ej: -59.83' : 'ej: 24.17',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
