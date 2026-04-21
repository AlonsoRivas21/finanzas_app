// lib/main.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'models/movimientos_provider.dart';
import 'screens/configuracion_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/movimientos_screen.dart';
import 'screens/gestion_screen.dart';
import 'screens/presupuestos_screen.dart';
import 'screens/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const FinanzasApp());
}

class FinanzasApp extends StatelessWidget {
  const FinanzasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MovimientosProvider()),
      ],
      child: MaterialApp(
        title: 'Mis Finanzas${AppConfig.esDev ? ' [DEV]' : ''}',
        debugShowCheckedModeBanner: AppConfig.esDev,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConfig.esDev
                ? const Color(0xFF7C3AED) // Morado en DEV
                : const Color(0xFF2563EB), // Azul en PROD
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
              centerTitle: false, elevation: 0, scrolledUnderElevation: 1),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConfig.esDev
                ? const Color(0xFF7C3AED)
                : const Color(0xFF2563EB),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: kIsWeb ? const _WebHome() : const _MobileHome(),
      ),
    );
  }
}

// ── Móvil ─────────────────────────────────────────────────────────────────────

class _MobileHome extends StatefulWidget {
  const _MobileHome();

  @override
  State<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<_MobileHome> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    MovimientosScreen(),
    PresupuestosScreen(),
  ];

  Future<void> _abrirConfiguracion() async {
    final huboambios = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
    );
    if (huboambios == true && mounted) {
      context.read<MovimientosProvider>().cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 3) {
            _abrirConfiguracion();
          } else {
            setState(() => _index = i);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Movimientos',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Presupuestos',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

// ── Web ───────────────────────────────────────────────────────────────────────

class _WebHome extends StatefulWidget {
  const _WebHome();

  @override
  State<_WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<_WebHome> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    MovimientosScreen(),
    PresupuestosScreen(),
    GestionScreen(),
    ConfiguracionScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: const AuthScreen(),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            minWidth: 80,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Movimientos'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: Text('Presupuestos'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.manage_accounts_outlined),
                selectedIcon: Icon(Icons.manage_accounts),
                label: Text('Gestión'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Ajustes'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Indicador de entorno
                      if (AppConfig.esDev)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('DEV',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.purple.shade700)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Cerrar sesión',
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _screens[_index]),
        ],
      ),
    );
  }
}
