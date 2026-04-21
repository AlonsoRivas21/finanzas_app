// lib/config/app_config.dart
// Cambia _env para alternar entre dev y producción

enum Entorno { dev, prod }

class AppConfig {
  // ── CAMBIAR AQUÍ PARA ALTERNAR ENTORNO ──────────────────────────────────
  static const Entorno _env = Entorno.dev; // ← cambiar a Entorno.dev para pruebas y .prod para producción
  // ────────────────────────────────────────────────────────────────────────

  static bool get esDev  => _env == Entorno.dev;
  static bool get esProd => _env == Entorno.prod;

  static String get supabaseUrl {
    switch (_env) {
      case Entorno.dev:
        return 'https://rmzyvidgcyoduvlnlecl.supabase.co';
      case Entorno.prod:
        return 'https://deqkrupzguxsszcrpkcv.supabase.co';
    }
  }

  static String get supabaseAnonKey {
    switch (_env) {
      case Entorno.dev:
        return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtenl2aWRnY3lvZHV2bG5sZWNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1MTY0MzgsImV4cCI6MjA5MTA5MjQzOH0.ar32Le-OQuPNh3IuZx01Oin21fz-xE1V0ZY9QxNEoAM';
      case Entorno.prod:
        return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRlcWtydXB6Z3V4c3N6Y3Jwa2N2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxMTk1MDEsImV4cCI6MjA5MDY5NTUwMX0.DImUPQPhjX8rTxI05scNHLJE_0PI342rJcr0BpivCb0';
    }
  }

  // Nombre de la BD local — diferente por entorno para no mezclar datos
  static String get dbName {
    switch (_env) {
      case Entorno.dev:  return 'finanzas_dev.db';
      case Entorno.prod: return 'finanzas.db';
    }
  }

  static String get nombreEntorno {
    switch (_env) {
      case Entorno.dev:  return 'DEV';
      case Entorno.prod: return 'PROD';
    }
  }
}
