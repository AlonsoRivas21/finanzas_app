// lib/database/web_download_stub.dart
// Stub para compilación en móvil — no hace nada

void downloadFile(List<int> bytes, String filename) {
  // No aplica en móvil
}

Future<String> pickExcelFile(String filename) async => 'unsupported';

Future<String> writeExcelToPickedFile(List<int> bytes) async => 'error';

void cancelPickedFile() {
  // No aplica en móvil
}
