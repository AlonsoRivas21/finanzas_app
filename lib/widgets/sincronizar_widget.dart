// lib/widgets/sincronizar_widget.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/supabase_service.dart';
import '../models/movimientos_provider.dart';
import '../screens/auth_screen.dart';

class SincronizarWidget extends StatefulWidget {
  const SincronizarWidget({super.key});

  @override
  State<SincronizarWidget> createState() => _SincronizarWidgetState();
}

class _SincronizarWidgetState extends State<SincronizarWidget> {
  bool _sincronizando = false;

  Future<void> _sincronizar() async {
    // Si no está autenticado, abrir login primero
    if (!SupabaseService.estaAutenticado) {
      final resultado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (resultado != true) return;
    }

    setState(() => _sincronizando = true);

    try {
      final res = await SupabaseService.sincronizar();
      if (mounted) {
        context.read<MovimientosProvider>().cargar();

        final esSubida = res.accion == 'subida';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(
                esSubida ? Icons.cloud_upload : Icons.cloud_download,
                color: Colors.white, size: 18,
              ),
              const SizedBox(width: 8),
              Text(res.cantidad == 0
                  ? 'Todo está sincronizado'
                  : esSubida
                      ? '${res.cantidad} movimientos subidos a la nube'
                      : '${res.cantidad} movimientos descargados'),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autenticado = SupabaseService.estaAutenticado;
    final usuario = SupabaseService.usuarioActual?.email ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Estado de sesión
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: autenticado
                ? Colors.green.shade50
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: autenticado
                  ? Colors.green.shade200
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(children: [
            Icon(
              autenticado ? Icons.cloud_done : Icons.cloud_off,
              color: autenticado ? Colors.green : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                autenticado
                    ? 'Conectado como $usuario'
                    : 'Sin sesión iniciada',
                style: TextStyle(
                  fontSize: 13,
                  color: autenticado
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ),
            if (autenticado)
              TextButton(
                onPressed: () async {
                  await SupabaseService.cerrarSesion();
                  setState(() {});
                },
                child: const Text('Salir',
                    style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),

        const SizedBox(height: 12),

        // Botón sincronizar
        FilledButton.icon(
          onPressed: _sincronizando ? null : _sincronizar,
          icon: _sincronizando
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
          label: Text(_sincronizando
              ? 'Sincronizando...'
              : autenticado
                  ? 'Sincronizar'
                  : 'Iniciar sesión y sincronizar'),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16)),
        ),

        const SizedBox(height: 8),

        // Explicación
        Text(
          autenticado
              ? 'Si tienes datos locales los sube. Si no, los descarga de la nube.'
              : 'Crea una cuenta gratis para guardar tus datos en la nube.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
