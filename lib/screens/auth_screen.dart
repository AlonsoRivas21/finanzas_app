// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import '../database/supabase_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _esLogin = true;
  bool _cargando = false;
  String? _error;
  bool _verPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _cargando = true; _error = null; });

    try {
      if (_esLogin) {
        await SupabaseService.iniciarSesion(
            _emailCtrl.text.trim(), _passCtrl.text);
      } else {
        await SupabaseService.registrar(
            _emailCtrl.text.trim(), _passCtrl.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = _esLogin
            ? 'Correo o contraseña incorrectos'
            : 'No se pudo crear la cuenta. Intenta con otro correo.';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esLogin ? 'Iniciar sesión' : 'Crear cuenta'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ícono
              const SizedBox(height: 20),
              Icon(Icons.cloud_sync,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                'Sincronización en la nube',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),

              // Email
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa tu correo';
                  if (!v.contains('@')) return 'Correo inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passCtrl,
                obscureText: !_verPassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_verPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _verPassword = !_verPassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
                  if (!_esLogin && v.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700,
                          fontSize: 13)),
                ),
              ],

              const SizedBox(height: 24),

              // Botón principal
              FilledButton(
                onPressed: _cargando ? null : _submit,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16)),
                child: _cargando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_esLogin ? 'Iniciar sesión' : 'Crear cuenta'),
              ),

              const SizedBox(height: 12),

              // Cambiar modo
              TextButton(
                onPressed: () => setState(() {
                  _esLogin = !_esLogin;
                  _error = null;
                }),
                child: Text(_esLogin
                    ? '¿No tienes cuenta? Crear una'
                    : '¿Ya tienes cuenta? Iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
