/// Demo de embutimento do [XlsxEditorWidget] em Dart Web puro.
///
/// Em AngularDart (ngdart 8) o padrão é o mesmo: crie o widget em
/// `ngAfterViewInit` com o `@ViewChild('editorHost')` como host e chame
/// `widget.destroy()` em `ngOnDestroy`.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:xlsx_editor/xlsx_editor.dart';

/// Planilha aberta por padrão (servida junto com o app).
const _defaultFile = 'planilha.xlsx';

XlsxEditorWidget? _widget;

Future<void> main() async {
  final host =
      web.document.getElementById('editor-host') as web.HTMLElement;
  final appearanceSelect =
      web.document.getElementById('demo-appearance') as web.HTMLSelectElement;
  final modeSelect =
      web.document.getElementById('demo-mode') as web.HTMLSelectElement;

  Uint8List? bytes;
  try {
    final response = await web.window.fetch(_defaultFile.toJS).toDart;
    if (!response.ok) throw StateError('HTTP ${response.status}');
    final buffer = await response.arrayBuffer().toDart;
    bytes = buffer.toDart.asUint8List();
  } catch (err) {
    web.console.warn('Demo: $_defaultFile indisponível ($err); '
            'abrindo planilha vazia.'
        .toJS);
  }
  web.document.getElementById('loading')?.remove();

  void create() {
    _widget?.destroy();
    _widget = XlsxEditorWidget(
      host,
      config: XlsxEditorConfig(
        appearance: appearanceSelect.value == 'compact'
            ? XlsxEditorAppearance.compact
            : XlsxEditorAppearance.excel,
        mode: modeSelect.value == 'viewer'
            ? XlsxEditorWidgetMode.viewer
            : XlsxEditorWidgetMode.editor,
        height: '100%',
        documentTitle: _defaultFile,
        data: bytes,
        onDocumentLoaded: (name) =>
            web.console.log('Documento carregado: $name'.toJS),
        onError: (err) => web.window.alert('Erro: $err'),
      ),
    );
  }

  // Trocar a aparência reconstrói o widget; trocar o modo usa setMode.
  appearanceSelect.addEventListener('change', ((web.Event _) {
    create();
  }).toJS);
  modeSelect.addEventListener('change', ((web.Event _) {
    _widget?.setMode(modeSelect.value == 'viewer'
        ? XlsxEditorWidgetMode.viewer
        : XlsxEditorWidgetMode.editor);
  }).toJS);

  create();
}
