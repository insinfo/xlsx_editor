/// Toolbars da fachada embutível (aparência compacta e excel), com ícones
/// Tabler e estado espelhado da seleção — mesmo padrão visual e de código
/// do canvas-editor-port.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../ui/app.dart' show SelectionStyleState;
import '../core/ui_component.dart';

/// Ações que as toolbars invocam na fachada (contrato desacoplado).
abstract class XlsxEditorShellActions {
  void openFilePicker();
  void downloadXlsx();
  void undo();
  void redo();
  void toggleBold();
  void toggleItalic();
  void toggleUnderline();
  void setAlignment({String? horizontal, String? vertical});
  void toggleWrapText();
  void toggleMergeSelection();
  void setBorderPreset(String preset);
  void applyFontName(String name);
  void applyFontSize(double size);
  void applyFontColor(String rgbHex);
  void applyFillColor(String rgbHex);
  void applyNumberFormat(String code);
  void focusGrid();
}

const List<String> _fontNames = [
  'Arial', 'Calibri', 'Cambria', 'Courier New', 'Segoe UI', 'Tahoma',
  'Times New Roman', 'Verdana',
];

const List<String> _fontSizes = [
  '8', '9', '10', '11', '12', '14', '16', '18', '22', '26',
];

const List<(String, String)> _numberFormats = [
  ('Geral', ''),
  ('Número 1.234,56', '#,##0.00'),
  ('Moeda R\$', '"R\$"\\ #,##0.00;[Red]\\-"R\$"\\ #,##0.00'),
  ('Percentual', '0.00%'),
  ('Data', 'dd/mm/yyyy'),
  ('Texto', '@'),
];

/// Base compartilhada: criação de botões com ícone Tabler, selects, botões
/// de cor e sincronização `active`/`disabled` a partir do estado da seleção.
abstract class XlsxToolbarBase extends UiComponent {
  XlsxToolbarBase(this.actions, String className)
      : super(web.document.createElement('div') as web.HTMLDivElement) {
    root.className = className;
    root.setAttribute('role', 'toolbar');
  }

  final XlsxEditorShellActions actions;
  final Map<String, web.HTMLButtonElement> _commandButtons = {};
  web.HTMLSelectElement? _fontSelect;
  web.HTMLSelectElement? _sizeSelect;
  web.HTMLSelectElement? _fmtSelect;

  web.HTMLDivElement group() {
    final g = web.document.createElement('div') as web.HTMLDivElement;
    g.className = 'xe-group';
    root.appendChild(g);
    return g;
  }

  web.HTMLButtonElement button(web.HTMLElement parent, String command,
      String iconClass, String label, void Function() action) {
    final b = web.document.createElement('button') as web.HTMLButtonElement;
    b.type = 'button';
    b.className = 'xe-btn';
    b.title = label;
    b.setAttribute('aria-label', label);
    b.setAttribute('data-xe-command', command);
    final icon = web.document.createElement('span') as web.HTMLSpanElement;
    icon.className = 'ti $iconClass';
    b.appendChild(icon);
    // Preserva a seleção da grade: o clique na toolbar não pode roubar foco.
    listen(b, 'mousedown', ((web.MouseEvent e) => e.preventDefault()).toJS);
    listen(b, 'click', ((web.Event _) {
      action();
      actions.focusGrid();
    }).toJS);
    parent.appendChild(b);
    _commandButtons[command] = b;
    return b;
  }

  web.HTMLSelectElement select(
      web.HTMLElement parent,
      String className,
      String label,
      List<(String, String)> entries,
      void Function(String value) onChange) {
    final s = web.document.createElement('select') as web.HTMLSelectElement;
    s.className = 'xe-select $className';
    s.title = label;
    s.setAttribute('aria-label', label);
    for (final (text, value) in entries) {
      final opt = web.document.createElement('option') as web.HTMLOptionElement;
      opt.value = value;
      opt.textContent = text;
      s.appendChild(opt);
    }
    listen(s, 'change', ((web.Event _) {
      onChange(s.value);
      actions.focusGrid();
    }).toJS);
    parent.appendChild(s);
    return s;
  }

  /// Botão de cor: ícone com barra da cor atual + `input type=color`
  /// invisível por cima (clicar abre o seletor nativo).
  void colorButton(web.HTMLElement parent, String command, String iconClass,
      String label, String initialHex, void Function(String rgbHex) onPick) {
    final wrap = web.document.createElement('span') as web.HTMLSpanElement;
    wrap.className = 'xe-colorbtn';
    wrap.title = label;
    wrap.setAttribute('data-xe-command', command);
    final icon = web.document.createElement('span') as web.HTMLSpanElement;
    icon.className = 'ti $iconClass';
    final bar = web.document.createElement('span') as web.HTMLSpanElement;
    bar.className = 'xe-colorbtn__bar';
    bar.style.background = initialHex;
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'color';
    input.value = initialHex;
    input.setAttribute('aria-label', label);
    listen(input, 'change', ((web.Event _) {
      bar.style.background = input.value;
      onPick(input.value.substring(1));
      actions.focusGrid();
    }).toJS);
    wrap.appendChild(icon);
    wrap.appendChild(bar);
    wrap.appendChild(input);
    parent.appendChild(wrap);
  }

  void _setActive(String command, bool active) {
    _commandButtons[command]?.classList.toggle('active', active);
  }

  void _setDisabled(String command, bool disabled) {
    _commandButtons[command]?.classList.toggle('disabled', disabled);
  }

  static String _sizeText(double size) => size == size.roundToDouble()
      ? '${size.round()}'
      : '$size';

  /// Espelha o estado da célula ativa nos botões/selects.
  void syncSelection(SelectionStyleState state) {
    _setActive('bold', state.bold);
    _setActive('italic', state.italic);
    _setActive('underline', state.underline);
    _setActive('align-left', state.horizontal == 'left');
    _setActive('align-center', state.horizontal == 'center');
    _setActive('align-right', state.horizontal == 'right');
    _setActive('valign-top', state.vertical == 'top');
    _setActive('valign-middle', state.vertical == 'center');
    _setActive('valign-bottom', state.vertical == 'bottom');
    _setActive('wrap', state.wrapText);
    _setActive('merge', state.merged);
    _setDisabled('undo', !state.canUndo);
    _setDisabled('redo', !state.canRedo);

    final font = _fontSelect;
    if (font != null) {
      for (var i = 0; i < font.options.length; i++) {
        final opt = font.options.item(i) as web.HTMLOptionElement;
        if (opt.value.toLowerCase() == state.fontName.toLowerCase()) {
          font.value = opt.value;
          break;
        }
      }
    }
    final size = _sizeSelect;
    if (size != null) {
      final text = _sizeText(state.fontSize);
      for (var i = 0; i < size.options.length; i++) {
        final opt = size.options.item(i) as web.HTMLOptionElement;
        if (opt.value == text) {
          size.value = text;
          break;
        }
      }
    }
    final fmt = _fmtSelect;
    if (fmt != null) {
      for (var i = 0; i < fmt.options.length; i++) {
        final opt = fmt.options.item(i) as web.HTMLOptionElement;
        if (opt.value == state.numFmtCode) {
          fmt.value = opt.value;
          break;
        }
      }
    }
  }
}

/// Toolbar completa (aparência "excel"): arquivo, histórico, fonte, estilo,
/// cores, alinhamento, célula e formato numérico.
class XlsxExcelToolbar extends XlsxToolbarBase {
  XlsxExcelToolbar(XlsxEditorShellActions actions)
      : super(actions, 'xe-toolbar') {
    final gFile = group();
    button(gFile, 'open', 'ti-folder-open', 'Abrir (.xlsx)',
        actions.openFilePicker);
    button(gFile, 'save', 'ti-device-floppy', 'Salvar como .xlsx (Ctrl+S)',
        actions.downloadXlsx);

    final gHistory = group();
    button(gHistory, 'undo', 'ti-arrow-back-up', 'Desfazer (Ctrl+Z)',
        actions.undo);
    button(gHistory, 'redo', 'ti-arrow-forward-up', 'Refazer (Ctrl+Y)',
        actions.redo);

    final gFont = group();
    _fontSelect = select(gFont, 'xe-font', 'Fonte',
        [for (final f in _fontNames) (f, f)], actions.applyFontName);
    _sizeSelect = select(gFont, 'xe-size', 'Tamanho da fonte',
        [for (final s in _fontSizes) (s, s)],
        (v) => actions.applyFontSize(double.tryParse(v) ?? 11));

    final gStyle = group();
    button(gStyle, 'bold', 'ti-bold', 'Negrito (Ctrl+B)', actions.toggleBold);
    button(gStyle, 'italic', 'ti-italic', 'Itálico (Ctrl+I)',
        actions.toggleItalic);
    button(gStyle, 'underline', 'ti-underline', 'Sublinhado (Ctrl+U)',
        actions.toggleUnderline);

    final gColor = group();
    colorButton(gColor, 'font-color', 'ti-typography', 'Cor da fonte',
        '#26364d', actions.applyFontColor);
    colorButton(gColor, 'fill-color', 'ti-bucket', 'Cor de preenchimento',
        '#ffff00', actions.applyFillColor);

    final gAlign = group();
    button(gAlign, 'align-left', 'ti-align-left', 'Alinhar à esquerda',
        () => actions.setAlignment(horizontal: 'left'));
    button(gAlign, 'align-center', 'ti-align-center', 'Centralizar',
        () => actions.setAlignment(horizontal: 'center'));
    button(gAlign, 'align-right', 'ti-align-right', 'Alinhar à direita',
        () => actions.setAlignment(horizontal: 'right'));
    button(gAlign, 'valign-top', 'ti-layout-align-top', 'Alinhar ao topo',
        () => actions.setAlignment(vertical: 'top'));
    button(gAlign, 'valign-middle', 'ti-layout-align-middle',
        'Centralizar na vertical',
        () => actions.setAlignment(vertical: 'center'));
    button(gAlign, 'valign-bottom', 'ti-layout-align-bottom',
        'Alinhar abaixo', () => actions.setAlignment(vertical: 'bottom'));
    button(gAlign, 'wrap', 'ti-text-wrap', 'Quebrar texto',
        actions.toggleWrapText);

    final gCell = group();
    button(gCell, 'merge', 'ti-arrows-join', 'Mesclar / desfazer mesclagem',
        actions.toggleMergeSelection);
    button(gCell, 'border-all', 'ti-border-all', 'Bordas (todas)',
        () => actions.setBorderPreset('all'));
    button(gCell, 'border-outline', 'ti-border-outer', 'Bordas (contorno)',
        () => actions.setBorderPreset('outline'));
    button(gCell, 'border-none', 'ti-border-none', 'Remover bordas',
        () => actions.setBorderPreset('none'));

    final gFmt = group();
    _fmtSelect = select(gFmt, 'xe-fmt', 'Formato numérico', _numberFormats,
        actions.applyNumberFormat);
  }
}

/// Toolbar reduzida (aparência "compact"): apenas o essencial em uma linha.
class XlsxCompactToolbar extends XlsxToolbarBase {
  XlsxCompactToolbar(XlsxEditorShellActions actions)
      : super(actions, 'xe-toolbar xe-toolbar--compact') {
    final gFile = group();
    button(gFile, 'open', 'ti-folder-open', 'Abrir (.xlsx)',
        actions.openFilePicker);
    button(gFile, 'save', 'ti-device-floppy', 'Salvar como .xlsx',
        actions.downloadXlsx);

    final gHistory = group();
    button(gHistory, 'undo', 'ti-arrow-back-up', 'Desfazer (Ctrl+Z)',
        actions.undo);
    button(gHistory, 'redo', 'ti-arrow-forward-up', 'Refazer (Ctrl+Y)',
        actions.redo);

    final gStyle = group();
    button(gStyle, 'bold', 'ti-bold', 'Negrito (Ctrl+B)', actions.toggleBold);
    button(gStyle, 'italic', 'ti-italic', 'Itálico (Ctrl+I)',
        actions.toggleItalic);
    button(gStyle, 'underline', 'ti-underline', 'Sublinhado (Ctrl+U)',
        actions.toggleUnderline);

    final gAlign = group();
    button(gAlign, 'align-left', 'ti-align-left', 'Alinhar à esquerda',
        () => actions.setAlignment(horizontal: 'left'));
    button(gAlign, 'align-center', 'ti-align-center', 'Centralizar',
        () => actions.setAlignment(horizontal: 'center'));
    button(gAlign, 'align-right', 'ti-align-right', 'Alinhar à direita',
        () => actions.setAlignment(horizontal: 'right'));

    final gCell = group();
    button(gCell, 'merge', 'ti-arrows-join', 'Mesclar / desfazer mesclagem',
        actions.toggleMergeSelection);
    button(gCell, 'border-all', 'ti-border-all', 'Bordas (todas)',
        () => actions.setBorderPreset('all'));
  }
}
