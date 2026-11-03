// lib/database/web_download.dart
// Solo se usa en web — llama a las funciones JS para guardar el Excel

// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:typed_data';

@JS()
external void downloadExcelFile(JSUint8Array bytes, String filename);

@JS('pickExcelFile')
external JSPromise<JSString> _pickExcelFile(String filename);

@JS('writeExcelToPickedFile')
external JSPromise<JSString> _writeExcelToPickedFile(JSUint8Array bytes);

@JS('cancelPickedFile')
external void _cancelPickedFile();

void downloadFile(List<int> bytes, String filename) {
  final uint8List = Uint8List.fromList(bytes);
  downloadExcelFile(uint8List.toJS, filename);
}

Future<String> pickExcelFile(String filename) async {
  final result = await _pickExcelFile(filename).toDart;
  return result.toDart;
}

Future<String> writeExcelToPickedFile(List<int> bytes) async {
  final uint8List = Uint8List.fromList(bytes);
  final result = await _writeExcelToPickedFile(uint8List.toJS).toDart;
  return result.toDart;
}

void cancelPickedFile() {
  _cancelPickedFile();
}
