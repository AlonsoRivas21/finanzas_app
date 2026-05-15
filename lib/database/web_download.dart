// lib/database/web_download.dart
// Solo se usa en web — llama a la función JS para descargar

// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:typed_data';

@JS()
external void downloadExcelFile(JSUint8Array bytes, String filename);

void downloadFile(List<int> bytes, String filename) {
  final uint8List = Uint8List.fromList(bytes);
  downloadExcelFile(uint8List.toJS, filename);
}
