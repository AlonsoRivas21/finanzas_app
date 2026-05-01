// lib/screens/configuracion_screen.dart

import 'package:flutter/material.dart';
import '../screens/exportar_screen.dart';
import 'saldos_screen.dart';
import '../widgets/sincronizar_widget.dart';

class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Nube ──────────────────────────────────────────────────────
          const _SeccionTitulo('Nube'),
          const SizedBox(height: 8),
          const SincronizarWidget(),

          const SizedBox(height: 24),

          // ── Datos ─────────────────────────────────────────────────────
          const _SeccionTitulo('Datos'),
          const SizedBox(height: 8),
          _OpcionTile(
            icono: Icons.account_balance_wallet_outlined,
            color: Colors.blue,
            titulo: 'Saldos iniciales',
            subtitulo: 'Configura el saldo de partida por cuenta',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SaldosScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _OpcionTile(
            icono: Icons.download_outlined,
            color: Colors.green,
            titulo: 'Exportar a Excel',
            subtitulo: 'Genera y comparte tu archivo .xlsx',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExportarScreen()),
            ),
          ),

          const SizedBox(height: 24),

          // ── App ───────────────────────────────────────────────────────
          const _SeccionTitulo('App'),
          const SizedBox(height: 8),
          _OpcionTile(
            icono: Icons.install_mobile_outlined,
            color: Colors.purple,
            titulo: 'Generar APK',
            subtitulo: 'Instrucciones para compilar e instalar',
            onTap: () => _mostrarInstruccionesApk(context),
          ),

          const SizedBox(height: 24),

          // Versión
          Center(
            child: Text(
              'Mis Finanzas v1.0.0',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarInstruccionesApk(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ApkSheet(),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SeccionTitulo extends StatelessWidget {
  final String text;
  const _SeccionTitulo(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.8));
  }
}

class _OpcionTile extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _OpcionTile({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icono, color: color, size: 20),
      ),
      title: Text(titulo,
          style: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text(subtitulo,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}

class _ApkSheet extends StatelessWidget {
  const _ApkSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.install_mobile,
                  color: Colors.purple.shade700),
            ),
            const SizedBox(width: 12),
            const Text('Generar APK',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),
          const _Paso('1', 'Abre una terminal en la carpeta del proyecto'),
          const _Paso('2', 'Ejecuta este comando:'),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'flutter build apk --release',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 13),
            ),
          ),
          const _Paso('3', 'El APK quedará en:'),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'build/app/outputs/flutter-apk/app-release.apk',
              style: TextStyle(
                  color: Colors.lightBlueAccent,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
          ),
          const _Paso('4',
              'Copia el APK a tu teléfono e instálalo. '
              'Puede que necesites activar "Instalar apps de fuentes desconocidas" en Ajustes del teléfono.'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  final String numero;
  final String texto;
  const _Paso(this.numero, this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: Colors.purple.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(numero,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple.shade700)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
