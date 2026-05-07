import 'package:flutter/material.dart';
import '../database/catalogo_service.dart';

class CuentasScreen extends StatefulWidget {
  const CuentasScreen({super.key});

  @override
  State<CuentasScreen> createState() => _CuentasScreenState();
}

class _CuentasScreenState extends State<CuentasScreen> {
  List<Map<String, dynamic>> _cuentas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final datos = await CatalogoService.getCuentas();
    setState(() {
      _cuentas = datos;
      _cargando = false;
    });
  }

  Future<void> _eliminar(Map<String, dynamic> cuenta) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cuenta?'),
        content: Text('Se eliminará "${cuenta['nombre']}". Los movimientos asociados podrían quedar sin cuenta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmar == true) {
      await CatalogoService.eliminarCuenta(cuenta['id']);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis Cuentas')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogo(),
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _cuentas.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final c = _cuentas[index];
                final esCredito = c['tipo'] == 'credito';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: esCredito ? Colors.orange.shade100 : Colors.blue.shade100,
                      child: Icon(esCredito ? Icons.credit_card : Icons.account_balance_wallet, 
                                 color: esCredito ? Colors.orange : Colors.blue),
                    ),
                    title: Text(c['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(esCredito ? 'Tarjeta de Crédito' : 'Efectivo / Débito'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _eliminar(c),
                    ),
                    onTap: () => _mostrarDialogo(cuenta: c),
                  ),
                );
              },
            ),
    );
  }

  void _mostrarDialogo({Map<String, dynamic>? cuenta}) {
    final nombreCtrl = TextEditingController(text: cuenta?['nombre'] ?? '');
    String tipo = cuenta?['tipo'] ?? 'debito';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(cuenta == null ? 'Nueva Cuenta' : 'Editar Cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la cuenta'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'debito', child: Text('Débito / Efectivo')),
                  DropdownMenuItem(value: 'credito', child: Text('Tarjeta de Crédito')),
                  DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'ahorro', child: Text('Ahorro')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nombreCtrl.text.isEmpty) return;
                if (cuenta == null) {
                  await CatalogoService.crearCuenta(
                    nombre: nombreCtrl.text.toUpperCase(),
                    tipo: tipo,
                  );
                } else {
                  await CatalogoService.actualizarCuenta({
                    'id': cuenta['id'],
                    'nombre': nombreCtrl.text.toUpperCase(),
                    'tipo': tipo,
                  });
                }
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pop(ctx);
                  _cargar();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}