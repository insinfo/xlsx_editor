/// Fachada embutível do editor XLSX para Dart Web puro e AngularDart
/// (ngdart 8) — mesmo padrão do `CanvasEditorWidget` do canvas-editor-port:
/// recebe um host, auto-injeta CSS/ícones, monta a shell e expõe `destroy()`.
library;

import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../render/grid_renderer.dart';
import '../../ui/app.dart';
import '../../xlsx/xlsx_blank.dart';
import '../core/ui_component.dart';
import 'widget_toolbar.dart';

/// Modo de interação: edição completa ou visualizador (somente leitura).
enum XlsxEditorWidgetMode { editor, viewer }

/// Quantidade de chrome ao redor da grade: barra única (compact) ou
/// experiência completa com titlebar/fórmulas/abas (excel).
enum XlsxEditorAppearance { compact, excel }

/// Configuração de um editor que pode viver dentro de uma página ou modal.
class XlsxEditorConfig {
  XlsxEditorConfig({
    this.mode = XlsxEditorWidgetMode.editor,
    this.appearance = XlsxEditorAppearance.excel,
    this.height = '520px',
    this.showToolbar = true,
    bool? showFormulaBar,
    this.showStatusBar = true,
    this.showSheetTabs = true,
    this.documentTitle = 'Planilha — XLSX Editor',
    this.confirmOnUnload = false,
    GridTheme? theme,
    this.data,
    this.sheetName = 'Planilha1',
    this.onDocumentLoaded,
    this.onChange,
    this.onError,
  })  : showFormulaBar =
            showFormulaBar ?? appearance == XlsxEditorAppearance.excel,
        // Excel é verde: a aparência excel usa a paleta verde na grade;
        // a compacta segue o azul do canvas-editor-port.
        theme = theme ??
            (appearance == XlsxEditorAppearance.excel
                ? GridTheme.excelGreen
                : GridTheme.blue);

  final XlsxEditorWidgetMode mode;
  final XlsxEditorAppearance appearance;
  final String height;
  final bool showToolbar;
  final bool showFormulaBar;
  final bool showStatusBar;
  final bool showSheetTabs;
  final String documentTitle;
  final bool confirmOnUnload;
  final GridTheme theme;

  /// Bytes de um .xlsx inicial; `null` abre uma planilha vazia ([sheetName]).
  final Uint8List? data;
  final String sheetName;
  final void Function(String fileName)? onDocumentLoaded;
  final void Function()? onChange;
  final void Function(Object error)? onError;
}

/// Fachada embutível: `XlsxEditorWidget(host, config: ...)`.
///
/// O widget é dono apenas do [host]: não depende de scroll do `body` nem de
/// CSS global (a folha de estilo e os ícones Tabler são auto-injetados no
/// `head`, de forma idempotente). Ciclo de vida compatível com AngularDart:
/// crie em `ngAfterViewInit` e chame [destroy] em `ngOnDestroy`.
class XlsxEditorWidget implements XlsxEditorShellActions {
  XlsxEditorWidget(web.HTMLElement host, {XlsxEditorConfig? config})
      : _host = host,
        config = config ?? XlsxEditorConfig() {
    _mount();
  }

  static const String stylesheet =
      'packages/xlsx_editor/assets/xlsx_editor.css';
  static const String iconStylesheet =
      'packages/xlsx_editor/assets/icons/tabler/tabler-icons.css';

  final web.HTMLElement _host;
  final XlsxEditorConfig config;
  late final web.HTMLDivElement root;
  late final SpreadsheetApp app;
  XlsxToolbarBase? _toolbar;
  web.HTMLDivElement? _titlebar;
  web.HTMLSpanElement? _titlebarMode;
  late final UiScheduler _scheduler;
  SelectionStyleState? _pendingSelectionStyle;
  bool _destroyed = false;

  XlsxEditorWidgetMode _mode = XlsxEditorWidgetMode.editor;
  XlsxEditorWidgetMode get mode => _mode;

  void _mount() {
    _ensureStylesheet(stylesheet, 'xlsx-editor-embed');
    _ensureStylesheet(iconStylesheet, 'xlsx-editor-tabler-icons');
    _scheduler = UiScheduler();
    _mode = config.mode;

    root = web.document.createElement('div') as web.HTMLDivElement;
    root.className = 'xe-embed';
    root.style.height = config.height;
    if (config.mode == XlsxEditorWidgetMode.viewer) {
      root.classList.add('xe-embed--viewer');
    }
    if (config.appearance == XlsxEditorAppearance.excel) {
      root.classList.add('xe-embed--excel');
      root.appendChild(_buildTitlebar());
    } else {
      root.classList.add('xe-embed--compact');
    }

    if (config.showToolbar) {
      final toolbar = config.appearance == XlsxEditorAppearance.excel
          ? XlsxExcelToolbar(this)
          : XlsxCompactToolbar(this);
      _toolbar = toolbar;
      root.appendChild(toolbar.root);
    }

    final appHost = web.document.createElement('div') as web.HTMLDivElement;
    appHost.className = 'xe-embed__app';
    root.appendChild(appHost);

    // Monta o host antes da shell (o canvas mede o DOM ao inicializar).
    _host.appendChild(root);

    app = SpreadsheetApp(
      appHost,
      config.data ?? blankXlsxBytes(sheetName: config.sheetName),
      options: SpreadsheetOptions(
        showFormulaBar: config.showFormulaBar,
        showSheetTabs: config.showSheetTabs,
        showStatusBar: config.showStatusBar,
        showZoom: config.showStatusBar,
        readOnly: config.mode == XlsxEditorWidgetMode.viewer,
        confirmOnUnload: config.confirmOnUnload,
        theme: config.theme,
        onChange: config.onChange,
        onError: config.onError,
        onFileOpened: (name) {
          _setTitle(name);
          config.onDocumentLoaded?.call(name);
        },
        // Rajadas de seleção viram UM flush de DOM por frame.
        onSelectionChanged: (state) {
          _pendingSelectionStyle = state;
          _scheduler.schedule(_flushSelectionStyle);
        },
      ),
    );
    _updateModeLabel();
  }

  web.HTMLDivElement _buildTitlebar() {
    final bar = web.document.createElement('div') as web.HTMLDivElement;
    bar.className = 'xe-titlebar';
    final icon = web.document.createElement('span') as web.HTMLSpanElement;
    icon.className = 'ti ti-file-spreadsheet';
    final title = web.document.createElement('span') as web.HTMLSpanElement;
    title.className = 'xe-titlebar__title';
    title.textContent = config.documentTitle;
    final modeLabel = web.document.createElement('span') as web.HTMLSpanElement;
    modeLabel.className = 'xe-titlebar__mode';
    bar.appendChild(icon);
    bar.appendChild(title);
    bar.appendChild(modeLabel);
    _titlebar = bar;
    _titlebarMode = modeLabel;
    return bar;
  }

  void _setTitle(String text) {
    final bar = _titlebar;
    if (bar == null) return;
    (bar.querySelector('.xe-titlebar__title') as web.HTMLSpanElement?)
        ?.textContent = text;
  }

  void _updateModeLabel() {
    _titlebarMode?.textContent =
        _mode == XlsxEditorWidgetMode.viewer ? 'Somente leitura' : 'Editando';
  }

  void _flushSelectionStyle() {
    final state = _pendingSelectionStyle;
    if (state == null || _destroyed) return;
    _pendingSelectionStyle = null;
    _toolbar?.syncSelection(state);
  }

  /// Injeta uma folha de estilo no `head` uma única vez (idempotente).
  static void _ensureStylesheet(String href, String marker) {
    final existing =
        web.document.head?.querySelector('link[data-xe-style="$marker"]');
    if (existing != null) return;
    final link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = 'stylesheet';
    link.href = href;
    link.setAttribute('data-xe-style', marker);
    web.document.head?.appendChild(link);
  }

  // ---------------------------------------------------------------------
  // API pública
  // ---------------------------------------------------------------------

  /// Carrega um novo .xlsx sem recriar o widget.
  void loadXlsx(Uint8List bytes, {String? fileName}) {
    app.loadBytes(bytes, fileName: fileName ?? 'documento.xlsx');
  }

  /// Serializa o conteúdo atual como bytes .xlsx.
  Uint8List saveXlsx() => app.saveBytes();

  /// Alterna editor/visualizador em runtime.
  void setMode(XlsxEditorWidgetMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    root.classList.toggle(
        'xe-embed--viewer', mode == XlsxEditorWidgetMode.viewer);
    app.setReadOnly(mode == XlsxEditorWidgetMode.viewer);
    _updateModeLabel();
  }

  /// Desmonta o widget e remove listeners globais (para `ngOnDestroy`).
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _scheduler.dispose();
    _toolbar?.dispose();
    app.dispose();
    root.remove();
  }

  // ---------------------------------------------------------------------
  // XlsxEditorShellActions (invocadas pela toolbar)
  // ---------------------------------------------------------------------

  @override
  void openFilePicker() => app.openFilePicker();
  @override
  void downloadXlsx() => app.download();
  @override
  void undo() => app.undo();
  @override
  void redo() => app.redo();
  @override
  void toggleBold() => app.toggleBold();
  @override
  void toggleItalic() => app.toggleItalic();
  @override
  void toggleUnderline() => app.toggleUnderline();
  @override
  void setAlignment({String? horizontal, String? vertical}) =>
      app.setAlignment(horizontal: horizontal, vertical: vertical);
  @override
  void toggleWrapText() => app.toggleWrapText();
  @override
  void toggleMergeSelection() => app.toggleMergeSelection();
  @override
  void setBorderPreset(String preset) => app.setBorderPreset(preset);
  @override
  void applyFontName(String name) => app.applyFontName(name);
  @override
  void applyFontSize(double size) => app.applyFontSize(size);
  @override
  void applyFontColor(String rgbHex) => app.applyFontColor(rgbHex);
  @override
  void applyFillColor(String rgbHex) => app.applyFillColor(rgbHex);
  @override
  void applyNumberFormat(String code) => app.applyNumberFormat(code);
  @override
  void focusGrid() => app.focusGrid();
}
