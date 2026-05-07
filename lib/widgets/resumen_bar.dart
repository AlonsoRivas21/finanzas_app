// lib/widgets/resumen_bar.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/movimientos_provider.dart';

class ResumenBar extends StatelessWidget {
  final int mes;
  const ResumenBar({super.key, required this.mes});

  @override
  Widget build(BuildContext context) {
    final prov = context.read<MovimientosProvider>();
    final fmt = NumberFormat('#,##0.00', 'es');

    return FutureBuilder<Map<String, double>>(
      future: prov.getSaldosPorCuenta(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 8);

        final saldos = snap.data!;

        final efectivo  = saldos['BILLETERA'] ?? 0;
        final bancos    = (saldos['DEBITO BA'] ?? 0) +
                          (saldos['DEBITO NIU'] ?? 0);
        final ahorro    = saldos['MULTIMONEY'] ?? 0;
        final deudaBa   = saldos['CREDITO BA'] ?? 0;
        final deudaNiu  = saldos['CREDITO NIU'] ?? 0;
        final deudaTotal = (deudaBa + deudaNiu).abs();
        final hayDeuda  = deudaBa < 0 || deudaNiu < 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            children: [
              // Fila 1: Efectivo, Bancos, Ahorro, Deuda TDC
              Row(children: [
                _SaldoItem(
                  icono: Icons.account_balance_wallet_outlined,
                  label: 'Efectivo',
                  valor: '\$${fmt.format(efectivo)}',
                  color: efectivo >= 0 ? Colors.green : Colors.red,
                ),
                _Separador(),
                _SaldoItem(
                  icono: Icons.account_balance_outlined,
                  label: 'Bancos',
                  valor: '\$${fmt.format(bancos)}',
                  color: bancos >= 0 ? Colors.blue : Colors.red,
                ),
                _Separador(),
                _SaldoItem(
                  icono: Icons.savings_outlined,
                  label: 'Ahorro',
                  valor: '\$${fmt.format(ahorro)}',
                  color: Colors.teal,
                ),
                _Separador(),
                _SaldoItem(
                  icono: Icons.credit_card_outlined,
                  label: 'Deuda TDC',
                  valor: hayDeuda
                      ? '-\$${fmt.format(deudaTotal)}'
                      : '\$0.00',
                  color: hayDeuda ? Colors.red : Colors.green,
                ),
              ]),

              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 8),

              // Fila 2: Resumen del mes
              FutureBuilder<Map<String, double>>(
                future: prov.getResumenMes(),
                builder: (context, snapMes) {
                  final ingresos = snapMes.data?['ingresos'] ?? 0;
                  final egresos  = snapMes.data?['egresos'] ?? 0;
                  final balance  = ingresos - egresos;
                  return Row(children: [
                    _StatMes(
                        label: 'Ingresos',
                        valor: '\$${fmt.format(ingresos)}',
                        color: Colors.green),
                    _Separador(),
                    _StatMes(
                        label: 'Egresos',
                        valor: '\$${fmt.format(egresos)}',
                        color: Colors.red),
                    _Separador(),
                    _StatMes(
                        label: 'Balance',
                        valor: '${balance >= 0 ? '+' : ''}\$${fmt.format(balance)}',
                        color: balance >= 0 ? Colors.green : Colors.red,
                        bold: true),
                  ]);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SaldoItem extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  final Color color;
  const _SaldoItem({
    required this.icono,
    required this.label,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: Colors.grey.shade500)),
          Text(valor,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _StatMes extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  final bool bold;
  const _StatMes({
    required this.label,
    required this.valor,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade500)),
          const SizedBox(height: 1),
          Text(valor,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 28, color: Colors.grey.shade200);
  }
}