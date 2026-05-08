// lib/widgets/movimiento_tile.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/movimiento.dart';
import '../models/movimientos_provider.dart';
import '../screens/form_movimiento_screen.dart';

class MovimientoTile extends StatelessWidget {
  final Movimiento movimiento;
  const MovimientoTile({super.key, required this.movimiento});

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final esIngreso = m.tipo == TipoMovimiento.ingreso;
    final color = esIngreso ? Colors.green : Colors.red;
    final fmt = NumberFormat('#,##0.00', 'es');

    return Dismissible(
      key: Key(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Eliminar movimiento'),
            content: const Text('¿Seguro que quieres eliminarlo?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Eliminar',
                      style: TextStyle(color: Colors.red))),
            ],
          ),
        );
      },
      onDismissed: (_) =>
          context.read<MovimientosProvider>().eliminar(m.id),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => FormMovimientoScreen(movimiento: m)),
        ),
        leading: CircleAvatar(
          // ignore: deprecated_member_use
          backgroundColor: color.withOpacity(0.12),
          child: Icon(_iconoCategoria(m.categoriaNombre), color: color, size: 20),
        ),

        title: Text(
          m.categoriaNombre,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          '${m.cuentaNombre}${m.comentario != null ? ' · ${m.comentario}' : ''}',
          maxLines: 1,

          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${esIngreso ? '+' : '-'}\$${fmt.format(m.monto)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (!m.sincronizado)
              const Icon(Icons.cloud_off, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

IconData _iconoCategoria(String catNombre) {
    switch (catNombre) {
      case 'INGRESOS':        return Icons.savings;
      case 'TRANSPORTE':      return Icons.directions_bus;
      case 'COMER FUERA':     return Icons.restaurant;
      case 'TRANSFERENCIA':   return Icons.swap_horiz;
      case 'SERVICIOS':       return Icons.receipt;
      case 'SHOPPING':        return Icons.shopping_bag;
      case 'SALDO':           return Icons.account_balance_wallet;
      case 'HOGAR':           return Icons.home;
      case 'PROVICIONES':     return Icons.shopping_cart;
      case 'PERDIDO':         return Icons.money_off;
      case 'ENTRETENIMIENTO': return Icons.movie;
      case 'PELO':            return Icons.content_cut;
      default:                return Icons.label;
    }
  }
}