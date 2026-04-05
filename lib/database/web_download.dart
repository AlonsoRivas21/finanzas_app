// lib/database/web_download.dart
// Solo se usa en web — llama a la función JS para descargar

// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void downloadFile(List<int> bytes, String filename) {
  js.context.callMethod('downloadExcelFile', [bytes, filename]);
}
