import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:xlsx_editor/xlsx_editor.dart';

/// Planilha aberta por padrão (servida junto com o app).
const _defaultFile = 'planilha.xlsx';

Future<void> main() async {
  final body = web.document.body!;
  final loading = web.document.getElementById('loading');

  try {
    final response = await web.window.fetch(_defaultFile.toJS).toDart;
    if (!response.ok) {
      throw StateError('HTTP ${response.status}');
    }
    final buffer = await response.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    loading?.remove();
    SpreadsheetApp(body, bytes);
  } catch (err) {
    if (loading != null) {
      loading.textContent = 'Falha ao carregar $_defaultFile: $err';
    }
  }
}
