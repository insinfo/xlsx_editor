/// Editor de planilhas XLSX like-Excel em Dart puro (web/canvas),
/// embutível em Dart Web puro e AngularDart (ngdart 8).
///
/// Ponto de entrada recomendado: [XlsxEditorWidget] — recebe um elemento
/// host, auto-injeta CSS/ícones e expõe `destroy()` para `ngOnDestroy`.
library;

// Fachada embutível (widget + toolbars + componentes de UI).
export 'src/components/core/ui_component.dart';
export 'src/components/xlsx_editor/widget_toolbar.dart';
export 'src/components/xlsx_editor/xlsx_editor_widget.dart';

// Núcleo: modelo, fórmulas, render, I/O.
export 'src/formula/engine.dart';
export 'src/formula/localization.dart';
export 'src/layout/sheet_layout.dart';
export 'src/model/styles.dart';
export 'src/model/workbook.dart';
export 'src/numfmt/number_format.dart';
export 'src/render/grid_renderer.dart';
export 'src/ui/app.dart';
export 'src/ui/commands.dart';
export 'src/util/cell_ref.dart';
export 'src/xlsx/xlsx_blank.dart';
export 'src/xlsx/xlsx_reader.dart';
export 'src/xlsx/xlsx_writer.dart';
export 'src/xml/dom.dart';
export 'src/zip/zip_archive.dart';
