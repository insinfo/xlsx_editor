import 'dart:js_interop';

import 'package:web/web.dart' as web;


void main() {
  // final fileInput = web.document.getElementById('fileInput') as web.HTMLInputElement;
  // final container = web.document.getElementById('container') as web.HTMLElement;

  // fileInput.addEventListener('change', (web.Event e) {
  //   final files = fileInput.files;
  //   if (files != null && files.length > 0) {
  //     final file = files.item(0)!;
  //     final reader = web.FileReader();
      
  //     reader.onload = (web.Event _) {
  //       final buffer = reader.result as JSArrayBuffer;
  //       final bytes = buffer.toDart.asUint8List();
        
  //       container.innerHTML = ''.toJS; // clear
        
  //       // Use docx_rendering to render
  //       renderAsync(bytes, container, null, null).then((_) {
  //         print('Render complete!');
  //       }).catchError((e) {
  //         print('Render error: $e');
  //       });
  //     }.toJS;
      
  //     reader.readAsArrayBuffer(file);
  //   }
  // }.toJS);
}
