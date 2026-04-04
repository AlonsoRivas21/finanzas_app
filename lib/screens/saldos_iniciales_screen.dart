// lib/screens/saldos_iniciales_screen.dart

import 'package:flutter/material.dart';
import '../database/saldos_service.dart';
import '../models/movimiento.dart';

class SaldosInicialesScreen extends StatefulWidget {
  const SaldosInicialesScreen({super.key});

  @override
  State<SaldosInicialesScreen> createState() => _SaldosInicialesScreenState();
}

class _SaldosInicialesScreenState extends State<SaldosInicialesScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    for (final c in Cuenta.values) {
      _controllers[c.nombre] = TextEditingController();
    }
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final saldos = await SaldosService.getSaldosIniciales();
    for (final entry in saldos.entries) {
      _controllers[entry.key]?.text =
          entry.value == 0 ? '' : entry.value.toString();
    }
    setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final saldos = <String, double>{};
    for (final entry in _controllers.entries) {
      final val =
          double.tryParse(entry.value.text.replaceAll(',', '.')) ?? 0.0;
      saldos[entry.key] = val;
    }
    await SaldosService.setSaldosIniciales(saldos);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldos iniciales'),
        actions: [
          _guardando
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator()),
                )
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
                    'Ingresa el saldo que tenías en cada cuenta antes de '
                    'empezar a registrar movimientos. '
                    'Si importaste un Excel con pestaña BD se llenaron automáticamente.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.blue.shade800),
                  ),
                ),
                const SizedBox(height: 20),
                ...Cuenta.values.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _CampoSaldo(
                    cuenta: c,
                    controller: _controllers[c.nombre]!,
                  ),
                )),
              ],
            ),
    );
  }
}

class _CampoSaldo extends StatelessWidget {
  final Cuenta cuenta;
  final TextEditingController controller;
  const _CampoSaldo({required this.cuenta, required this.controller});

  @override
  Widget build(BuildContext context) {
    final esTarjeta =
        cuenta == Cuenta.creditoBa || cuenta == Cuenta.creditoNiu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            esTarjeta ? Icons.credit_card : Icons.account_balance_wallet,
            size: 16, color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Text(cuenta.nombre,
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
                      fontSize: 10, color: Colors.orange.shade800)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
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
    );
  }
}
