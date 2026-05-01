// lib/database/web_download.dart
// Solo se usa en web — llama a la función JS para descargar

// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

@JS()
external void downloadExcelFile(List<int> bytes, String filename);

void downloadFile(List<int> bytes, String filename) {
  downloadExcelFile(bytes, filename);
}
