/// Shell da aplicação: toolbar, barra de fórmulas, grade (canvas + scroll),
/// editor de célula (overlay DOM), abas, barra de status e eventos.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../formula/engine.dart';
import '../formula/localization.dart';
import '../layout/sheet_layout.dart';
import '../model/styles.dart';
import '../model/workbook.dart';
import '../render/grid_renderer.dart';
import '../util/cell_ref.dart';
import '../xlsx/xlsx_reader.dart';
import '../xlsx/xlsx_writer.dart';
import 'commands.dart';

/// Opções da shell interna ([SpreadsheetApp]).
///
/// A fachada embutível ([XlsxEditorWidget]) monta a toolbar externamente e
/// controla a shell por estas opções + API pública.
class SpreadsheetOptions {
  final bool showFormulaBar;
  final bool showSheetTabs;
  final bool showStatusBar;
  final bool showZoom;
  final bool readOnly;

  /// Confirma saída da página com alterações não salvas (apenas para apps
  /// standalone; em embed deixe `false` para não sequestrar o `window`).
  final bool confirmOnUnload;
  final GridTheme theme;
  final void Function()? onChange;
  final void Function(SelectionStyleState state)? onSelectionChanged;
  final void Function(Object error)? onError;
  final void Function(String fileName)? onFileOpened;

  const SpreadsheetOptions({
    this.showFormulaBar = true,
    this.showSheetTabs = true,
    this.showStatusBar = true,
    this.showZoom = true,
    this.readOnly = false,
    this.confirmOnUnload = false,
    this.theme = GridTheme.blue,
    this.onChange,
    this.onSelectionChanged,
    this.onError,
    this.onFileOpened,
  });
}

/// Estado de estilo da seleção ativa, espelhado na toolbar da fachada.
class SelectionStyleState {
  final String fontName;
  final double fontSize;
  final bool bold;
  final bool italic;
  final bool underline;
  final String horizontal;
  final String vertical;
  final bool wrapText;
  final bool merged;
  final String numFmtCode;
  final bool canUndo;
  final bool canRedo;

  const SelectionStyleState({
    required this.fontName,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.horizontal,
    required this.vertical,
    required this.wrapText,
    required this.merged,
    required this.numFmtCode,
    required this.canUndo,
    required this.canRedo,
  });
}

/// Estado de visualização por planilha.
class _SheetView {
  double scrollX = 0;
  double scrollY = 0;
  CellRange selection = const CellRange(0, 0, 0, 0);
  CellRef active = const CellRef(0, 0);
  CellRef anchor = const CellRef(0, 0);
}

class _WorkbookAccess extends WorkbookAccess {
  final Workbook wb;
  _WorkbookAccess(this.wb);

  @override
  int get sheetCount => wb.sheets.length;

  @override
  int sheetIndexByName(String name) => wb.sheetIndexByName(name);

  @override
  Object? valueAt(int sheet, int row, int col) {
    if (sheet < 0 || sheet >= wb.sheets.length) return null;
    final cell = wb.sheets[sheet].cellAt(row, col);
    return switch (cell?.value) {
      NumberValue(:final value) => value,
      TextValue(:final value) => value,
      BoolValue(:final value) => value,
      ErrorValue(:final code) => FormulaError(code),
      null => null,
    };
  }
}

class SpreadsheetApp {
  XlsxDocument doc;
  late FormulaEngine engine;
  final SpreadsheetOptions options;

  // DOM
  final web.HTMLElement host;
  late web.HTMLDivElement _root;
  late web.HTMLDivElement _formulaBar;
  late web.HTMLInputElement _nameBox;
  late web.HTMLInputElement _formulaInput;
  late web.HTMLDivElement _gridWrap;
  late web.HTMLCanvasElement _canvas;
  late web.HTMLDivElement _scroller;
  late web.HTMLDivElement _spacer;
  late web.HTMLTextAreaElement _editor;
  late web.HTMLDivElement _footer;
  late web.HTMLDivElement _tabs;
  late web.HTMLDivElement _status;
  late web.HTMLDivElement _zoomWrap;
  late web.HTMLSelectElement _zoomSelect;
  late web.HTMLInputElement _fileInput;

  late GridRenderer _renderer;
  late List<SheetLayout> _layouts;
  late List<_SheetView> _views;

  int _sheetIndex = 0;
  double _zoom = 1.0;
  bool _painting = false;
  bool _editing = false;
  bool _editorFromTyping = false;
  bool _dirty = false;
  bool _readOnly = false;
  bool _disposed = false;
  web.ResizeObserver? _resizeObserver;

  final CommandStack _commands = CommandStack();

  /// Listeners registrados em `window`/`document` (removidos no [dispose]).
  final List<(web.EventTarget, String, JSFunction)> _globalListeners = [];

  // Drag de seleção / resize.
  bool _selecting = false;
  int _resizingCol = -1;
  int _resizingRow = -1;
  double _resizeStartPos = 0;
  double _resizeStartSize = 0;

  Workbook get wb => doc.workbook;
  Worksheet get sheet => wb.sheets[_sheetIndex];
  SheetLayout get layout => _layouts[_sheetIndex];
  _SheetView get view => _views[_sheetIndex];
  bool get readOnly => _readOnly;
  bool get isDirty => _dirty;

  SpreadsheetApp(this.host, Uint8List xlsxBytes, {SpreadsheetOptions? options})
      : options = options ?? const SpreadsheetOptions(),
        doc = readXlsx(xlsxBytes) {
    _readOnly = this.options.readOnly;
    _initModel();
    _buildDom();
    _renderer = GridRenderer(
      wb,
      _canvas.getContext('2d') as web.CanvasRenderingContext2D,
      ImageStore(_schedulePaint),
      (path) => doc.mediaBytes(path),
      theme: this.options.theme,
    );
    _wireEvents();
    _resizeObserver = web.ResizeObserver(
        ((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver __) {
      if (_disposed) return;
      _resizeCanvas();
      _schedulePaint();
    }).toJS);
    _resizeObserver!.observe(_gridWrap);
    _sheetIndex = wb.activeSheet;
    _zoom = sheet.zoomScale.clamp(0.5, 2.0);
    _zoomSelect.value = '${(_zoom * 100).round()}';
    _rebuildTabs();
    _syncSpacer();
    _resizeCanvas();
    _updateFormulaBar();
    _schedulePaint();
  }

  void _initModel() {
    engine = FormulaEngine(_WorkbookAccess(wb));
    for (var s = 0; s < wb.sheets.length; s++) {
      for (final entry in wb.sheets[s].cells.entries) {
        final cell = entry.value;
        final formula = cell.formula;
        if (formula != null) {
          final ref = CellRef.fromPacked(entry.key);
          try {
            engine.setFormula(s, ref.row, ref.col, formula,
                isArray: cell.isArrayFormula);
          } catch (_) {
            // Fórmula não suportada: mantém apenas o valor em cache.
          }
        }
      }
    }
    _layouts = [for (final s in wb.sheets) SheetLayout(s)];
    _views = [for (final _ in wb.sheets) _SheetView()];
  }

  // ---------------------------------------------------------------------
  // DOM
  // ---------------------------------------------------------------------

  T _el<T extends web.HTMLElement>(String tag, String className,
      [web.HTMLElement? parent]) {
    final el = web.document.createElement(tag) as T;
    if (className.isNotEmpty) el.className = className;
    (parent ?? _root).appendChild(el);
    return el;
  }

  void _buildDom() {
    _root = web.document.createElement('div') as web.HTMLDivElement;
    _root.className = 'xe-root';
    host.appendChild(_root);

    // ---- Barra de fórmulas ----
    _formulaBar = _el<web.HTMLDivElement>('div', 'xe-formulabar');
    if (!options.showFormulaBar) _formulaBar.classList.add('xe-hidden');
    _nameBox = _el<web.HTMLInputElement>('input', 'xe-namebox', _formulaBar);
    _nameBox.spellcheck = false;
    final fx = _el<web.HTMLDivElement>('div', 'xe-fx', _formulaBar);
    fx.textContent = 'fx';
    _formulaInput =
        _el<web.HTMLInputElement>('input', 'xe-formulainput', _formulaBar);
    _formulaInput.spellcheck = false;
    _formulaInput.readOnly = _readOnly;

    // ---- Grade ----
    _gridWrap = _el<web.HTMLDivElement>('div', 'xe-grid');
    _canvas = _el<web.HTMLCanvasElement>('canvas', 'xe-canvas', _gridWrap);
    _scroller = _el<web.HTMLDivElement>('div', 'xe-scroller', _gridWrap);
    _scroller.tabIndex = 0;
    _spacer = _el<web.HTMLDivElement>('div', 'xe-spacer', _scroller);
    _editor = _el<web.HTMLTextAreaElement>('textarea', 'xe-editor', _gridWrap);
    _editor.spellcheck = false;
    _editor.style.display = 'none';

    // ---- Rodapé: abas + status ----
    _footer = _el<web.HTMLDivElement>('div', 'xe-footer');
    if (!options.showSheetTabs && !options.showStatusBar && !options.showZoom) {
      _footer.classList.add('xe-hidden');
    }
    _tabs = _el<web.HTMLDivElement>('div', 'xe-tabs', _footer);
    if (!options.showSheetTabs) _tabs.classList.add('xe-hidden');
    _status = _el<web.HTMLDivElement>('div', 'xe-status', _footer);
    if (!options.showStatusBar) _status.classList.add('xe-hidden');
    _zoomWrap = _el<web.HTMLDivElement>('div', 'xe-zoom', _footer);
    if (!options.showZoom) _zoomWrap.classList.add('xe-hidden');
    _zoomSelect = _el<web.HTMLSelectElement>('select', 'xe-zoomsel', _zoomWrap);
    for (final z in ['50', '75', '90', '100', '125', '150', '200']) {
      final opt = web.document.createElement('option') as web.HTMLOptionElement;
      opt.value = z;
      opt.textContent = '$z%';
      _zoomSelect.appendChild(opt);
    }

    // input de arquivo oculto
    _fileInput = _el<web.HTMLInputElement>('input', 'xe-file');
    _fileInput.type = 'file';
    _fileInput.accept = '.xlsx';
    _fileInput.style.display = 'none';
  }

  // ---------------------------------------------------------------------
  // Eventos
  // ---------------------------------------------------------------------

  /// Listener global (window/document) rastreado para remoção no [dispose].
  void _listenGlobal(web.EventTarget target, String type, JSFunction handler) {
    target.addEventListener(type, handler);
    _globalListeners.add((target, type, handler));
  }

  void _wireEvents() {
    _listenGlobal(
        web.window,
        'resize',
        ((web.Event _) {
          _resizeCanvas();
          _schedulePaint();
        }).toJS);

    _scroller.addEventListener(
        'scroll',
        ((web.Event _) {
          view.scrollX = _scroller.scrollLeft / _zoom;
          view.scrollY = _scroller.scrollTop / _zoom;
          if (_editing) _positionEditor();
          _schedulePaint();
        }).toJS);

    // Ctrl+roda = zoom (como no Excel).
    _scroller.addEventListener(
        'wheel',
        ((web.WheelEvent e) {
          if (!e.ctrlKey) return;
          e.preventDefault();
          final steps = ['50', '75', '90', '100', '125', '150', '200'];
          final current = '${(_zoom * 100).round()}';
          var idx = steps.indexOf(current);
          if (idx < 0) idx = 3;
          idx = (e.deltaY < 0 ? idx + 1 : idx - 1).clamp(0, steps.length - 1);
          _zoom = int.parse(steps[idx]) / 100.0;
          sheet.zoomScale = _zoom;
          _zoomSelect.value = steps[idx];
          _syncSpacer();
          _schedulePaint();
        }).toJS,
        web.AddEventListenerOptions(passive: false));

    _scroller.addEventListener(
        'mousedown', ((web.MouseEvent e) => _onMouseDown(e)).toJS);
    _listenGlobal(
        web.window, 'mousemove', ((web.MouseEvent e) => _onMouseMove(e)).toJS);
    _listenGlobal(
        web.window, 'mouseup', ((web.MouseEvent e) => _onMouseUp(e)).toJS);
    _scroller.addEventListener(
        'dblclick', ((web.MouseEvent e) => _onDblClick(e)).toJS);
    _scroller.addEventListener(
        'keydown', ((web.KeyboardEvent e) => _onKeyDown(e)).toJS);

    _editor.addEventListener(
        'keydown', ((web.KeyboardEvent e) => _onEditorKey(e)).toJS);

    _formulaInput.addEventListener(
        'keydown',
        ((web.KeyboardEvent e) {
          if (e.key == 'Enter') {
            e.preventDefault();
            _commitText(_formulaInput.value, 1, 0);
            _focusGrid();
          } else if (e.key == 'Escape') {
            e.preventDefault();
            _updateFormulaBar();
            _focusGrid();
          }
        }).toJS);

    _nameBox.addEventListener(
        'keydown',
        ((web.KeyboardEvent e) {
          if (e.key == 'Enter') {
            e.preventDefault();
            final ref = CellRef.tryParse(_nameBox.value.trim());
            if (ref != null) {
              _select(ref.row, ref.col);
              _scrollIntoView(ref.row, ref.col);
            }
            _focusGrid();
          }
        }).toJS);

    _zoomSelect.addEventListener(
        'change',
        ((web.Event _) {
          _zoom = (int.tryParse(_zoomSelect.value) ?? 100) / 100.0;
          sheet.zoomScale = _zoom;
          _syncSpacer();
          _schedulePaint();
          _focusGrid();
        }).toJS);

    _fileInput.addEventListener(
        'change',
        ((web.Event _) {
          final files = _fileInput.files;
          if (files == null || files.length == 0) return;
          final file = files.item(0)!;
          final reader = web.FileReader();
          reader.onload = ((web.Event _) {
            final buffer = reader.result as JSArrayBuffer;
            loadBytes(buffer.toDart.asUint8List(), fileName: file.name);
          }).toJS;
          reader.readAsArrayBuffer(file);
        }).toJS);

    // Clipboard.
    _listenGlobal(
        web.document,
        'copy',
        ((web.ClipboardEvent e) {
          if (_editing || !_gridHasFocus()) return;
          e.preventDefault();
          e.clipboardData?.setData('text/plain', _selectionToTsv());
        }).toJS);
    _listenGlobal(
        web.document,
        'cut',
        ((web.ClipboardEvent e) {
          if (_editing || _readOnly || !_gridHasFocus()) return;
          e.preventDefault();
          e.clipboardData?.setData('text/plain', _selectionToTsv());
          _clearSelection();
        }).toJS);
    _listenGlobal(
        web.document,
        'paste',
        ((web.ClipboardEvent e) {
          if (_editing || _readOnly || !_gridHasFocus()) return;
          final text = e.clipboardData?.getData('text/plain');
          if (text == null || text.isEmpty) return;
          e.preventDefault();
          _pasteTsv(text);
        }).toJS);

    if (options.confirmOnUnload) {
      _listenGlobal(
          web.window,
          'beforeunload',
          ((web.Event e) {
            if (_dirty) (e as web.BeforeUnloadEvent).returnValue = 'sair?';
          }).toJS);
    }
  }

  bool _gridHasFocus() {
    // Restrito ao scroller: em páginas host (embed) o `body` focado não
    // pode capturar copy/cut/paste de outros componentes.
    return web.document.activeElement == _scroller;
  }

  void _focusGrid() => _scroller.focus();

  /// Devolve o foco à grade (após interações com a toolbar externa).
  void focusGrid() => _focusGrid();

  // ---------------------------------------------------------------------
  // Coordenadas e hit-test
  // ---------------------------------------------------------------------

  ({double x, double y}) _localPos(web.MouseEvent e) {
    final rect = _scroller.getBoundingClientRect();
    return (x: e.clientX - rect.left, y: e.clientY - rect.top);
  }

  /// -2 = fora, -1 = header, >=0 índice de célula.
  ({int row, int col, bool inColHeader, bool inRowHeader}) _hit(
      double x, double y) {
    final headerW = kHeaderW * _zoom;
    final headerH = kHeaderH * _zoom;
    final inColHeader = y < headerH;
    final inRowHeader = x < headerW;
    final cx = (x - headerW) / _zoom + view.scrollX;
    final cy = (y - headerH) / _zoom + view.scrollY;
    return (
      row: inColHeader ? -1 : layout.rows.indexAt(cy),
      col: inRowHeader ? -1 : layout.cols.indexAt(cx),
      inColHeader: inColHeader,
      inRowHeader: inRowHeader,
    );
  }

  /// Retorna a coluna cuja borda direita está a ±4px de x (para resize).
  int _colBoundaryAt(double x) {
    final headerW = kHeaderW * _zoom;
    final cx = (x - headerW) / _zoom + view.scrollX;
    final c = layout.cols.indexAt(cx);
    for (final cand in [c - 1, c]) {
      if (cand < 0) continue;
      final edge = layout.cols.posOf(cand + 1);
      if (((edge - cx) * _zoom).abs() <= 4) return cand;
    }
    return -1;
  }

  int _rowBoundaryAt(double y) {
    final headerH = kHeaderH * _zoom;
    final cy = (y - headerH) / _zoom + view.scrollY;
    final r = layout.rows.indexAt(cy);
    for (final cand in [r - 1, r]) {
      if (cand < 0) continue;
      final edge = layout.rows.posOf(cand + 1);
      if (((edge - cy) * _zoom).abs() <= 4) return cand;
    }
    return -1;
  }

  // ---------------------------------------------------------------------
  // Mouse
  // ---------------------------------------------------------------------

  void _onMouseDown(web.MouseEvent e) {
    if (e.button != 0) return;
    final pos = _localPos(e);
    // Ignora cliques na área das scrollbars nativas.
    if (pos.x > _scroller.clientWidth || pos.y > _scroller.clientHeight) {
      return;
    }
    if (_editing) _commitEditor(0, 0);
    _focusGrid();
    e.preventDefault();

    final hit = _hit(pos.x, pos.y);

    if (hit.inColHeader && !hit.inRowHeader) {
      final boundary = _colBoundaryAt(pos.x);
      if (boundary >= 0) {
        _resizingCol = boundary;
        _resizeStartPos = pos.x;
        _resizeStartSize = layout.cols.sizeOf(boundary);
        return;
      }
      final c = hit.col;
      view.anchor = CellRef(0, c);
      view.active =
          CellRef(view.scrollY > 0 ? layout.rows.indexAt(view.scrollY) : 0, c);
      view.selection = CellRange(0, c, layout.rowCount - 1, c);
      _selecting = true;
      _afterSelectionChange();
      return;
    }
    if (hit.inRowHeader && !hit.inColHeader) {
      final boundary = _rowBoundaryAt(pos.y);
      if (boundary >= 0) {
        _resizingRow = boundary;
        _resizeStartPos = pos.y;
        _resizeStartSize = layout.rows.sizeOf(boundary);
        return;
      }
      final r = hit.row;
      view.anchor = CellRef(r, 0);
      view.active = CellRef(r, 0);
      view.selection = CellRange(r, 0, r, layout.colCount - 1);
      _selecting = true;
      _afterSelectionChange();
      return;
    }
    if (hit.inColHeader && hit.inRowHeader) {
      view.selection =
          CellRange(0, 0, layout.rowCount - 1, layout.colCount - 1);
      view.active = const CellRef(0, 0);
      _afterSelectionChange();
      return;
    }

    final row = hit.row, col = hit.col;
    if (e.shiftKey) {
      view.selection =
          CellRange.normalized(view.anchor.row, view.anchor.col, row, col);
      _expandSelectionToMerges();
    } else {
      _select(row, col);
      _selecting = true;
    }
    _afterSelectionChange();
  }

  void _onMouseMove(web.MouseEvent e) {
    final pos = _localPos(e);

    if (_resizingCol >= 0) {
      final delta = (pos.x - _resizeStartPos) / _zoom;
      final px = (_resizeStartSize + delta).clamp(0.0, 800.0);
      sheet.colProps[_resizingCol] =
          ColProps(width: (px - 5) / 7, hidden: px <= 0);
      layout.rebuild();
      _syncSpacer();
      _schedulePaint();
      return;
    }
    if (_resizingRow >= 0) {
      final delta = (pos.y - _resizeStartPos) / _zoom;
      final px = (_resizeStartSize + delta).clamp(0.0, 600.0);
      sheet.rowProps[_resizingRow] =
          RowProps(height: px * 72 / 96, hidden: px <= 0);
      layout.rebuild();
      _syncSpacer();
      _schedulePaint();
      return;
    }

    // Cursor de resize nos headers.
    if (!_selecting) {
      final headerH = kHeaderH * _zoom;
      final headerW = kHeaderW * _zoom;
      String cursor = 'cell';
      if (pos.y < headerH && pos.x > headerW) {
        cursor = _colBoundaryAt(pos.x) >= 0 ? 'col-resize' : 'default';
      } else if (pos.x < headerW && pos.y > headerH) {
        cursor = _rowBoundaryAt(pos.y) >= 0 ? 'row-resize' : 'default';
      } else if (pos.y < headerH || pos.x < headerW) {
        cursor = 'default';
      }
      _scroller.style.cursor = cursor;
    }

    if (!_selecting) return;
    final hit = _hit(
        pos.x.clamp(kHeaderW * _zoom + 1, _scroller.clientWidth.toDouble()),
        pos.y.clamp(kHeaderH * _zoom + 1, _scroller.clientHeight.toDouble()));
    if (hit.row < 0 || hit.col < 0) return;
    final sel = CellRange.normalized(
        view.anchor.row, view.anchor.col, hit.row, hit.col);
    if (sel != view.selection) {
      view.selection = sel;
      _expandSelectionToMerges();
      _afterSelectionChange(updateBar: false);
    }
  }

  void _onMouseUp(web.MouseEvent e) {
    if (_resizingCol >= 0) {
      final p = sheet.colProps[_resizingCol];
      _commands.push(ResizeCommand('Largura de coluna', _sheetIndex, true,
          _resizingCol, (_resizeStartSize - 5) / 7, p?.width));
      _resizingCol = -1;
      _markDirty();
    }
    if (_resizingRow >= 0) {
      final p = sheet.rowProps[_resizingRow];
      _commands.push(ResizeCommand('Altura de linha', _sheetIndex, false,
          _resizingRow, _resizeStartSize * 72 / 96, p?.height));
      _resizingRow = -1;
      _markDirty();
    }
    _selecting = false;
  }

  void _onDblClick(web.MouseEvent e) {
    final pos = _localPos(e);
    final hit = _hit(pos.x, pos.y);
    if (hit.row >= 0 && hit.col >= 0) _startEdit(fromTyping: false);
  }

  // ---------------------------------------------------------------------
  // Teclado
  // ---------------------------------------------------------------------

  void _onKeyDown(web.KeyboardEvent e) {
    if (_editing) return;
    final key = e.key;
    final ctrl = e.ctrlKey || e.metaKey;

    if (ctrl) {
      switch (key.toLowerCase()) {
        case 'z':
          e.preventDefault();
          undo();
          return;
        case 'y':
          e.preventDefault();
          redo();
          return;
        case 's':
          e.preventDefault();
          download();
          return;
        case 'b':
          e.preventDefault();
          toggleBold();
          return;
        case 'i':
          e.preventDefault();
          toggleItalic();
          return;
        case 'u':
          e.preventDefault();
          toggleUnderline();
          return;
        case 'a':
          e.preventDefault();
          view.selection = CellRange(0, 0, sheet.maxRow, sheet.maxCol);
          _afterSelectionChange();
          return;
        // c/x/v ficam com os eventos nativos de clipboard.
      }
    }

    switch (key) {
      case 'ArrowUp':
      case 'ArrowDown':
      case 'ArrowLeft':
      case 'ArrowRight':
        e.preventDefault();
        _moveActive(key, extend: e.shiftKey, jump: ctrl);
        return;
      case 'Enter':
        e.preventDefault();
        _moveActiveBy(e.shiftKey ? -1 : 1, 0);
        return;
      case 'Tab':
        e.preventDefault();
        _moveActiveBy(0, e.shiftKey ? -1 : 1);
        return;
      case 'Home':
        e.preventDefault();
        _select(view.active.row, 0);
        _scrollIntoView(view.active.row, 0);
        return;
      case 'Delete':
      case 'Backspace':
        e.preventDefault();
        _clearSelection();
        return;
      case 'F2':
        e.preventDefault();
        _startEdit(fromTyping: false);
        return;
      case 'Escape':
        return;
    }

    // Digitação inicia edição substituindo o conteúdo.
    if (key.length == 1 && !ctrl && !e.altKey) {
      e.preventDefault();
      _startEdit(fromTyping: true, initial: key);
    }
  }

  void _moveActive(String arrow, {required bool extend, required bool jump}) {
    var (dr, dc) = switch (arrow) {
      'ArrowUp' => (-1, 0),
      'ArrowDown' => (1, 0),
      'ArrowLeft' => (0, -1),
      _ => (0, 1),
    };
    if (extend) {
      // Estende a partir da célula ativa mantendo a âncora.
      final sel = view.selection;
      var r2 = dr != 0
          ? (dr < 0
                  ? (sel.r1 == view.anchor.row ? sel.r2 : sel.r1)
                  : (sel.r2 == view.anchor.row ? sel.r1 : sel.r2)) +
              dr
          : (sel.r1 == view.anchor.row ? sel.r2 : sel.r1);
      var c2 = dc != 0
          ? (dc < 0
                  ? (sel.c1 == view.anchor.col ? sel.c2 : sel.c1)
                  : (sel.c2 == view.anchor.col ? sel.c1 : sel.c2)) +
              dc
          : (sel.c1 == view.anchor.col ? sel.c2 : sel.c1);
      r2 = r2.clamp(0, layout.rowCount - 1);
      c2 = c2.clamp(0, layout.colCount - 1);
      view.selection =
          CellRange.normalized(view.anchor.row, view.anchor.col, r2, c2);
      _expandSelectionToMerges();
      _scrollIntoView(r2, c2);
      _afterSelectionChange();
      return;
    }

    var row = view.active.row;
    var col = view.active.col;
    // Sai de um merge pelo lado correspondente.
    final merge = sheet.mergeAt(row, col);
    if (merge != null) {
      if (dr > 0) row = merge.r2;
      if (dr < 0) row = merge.r1;
      if (dc > 0) col = merge.c2;
      if (dc < 0) col = merge.c1;
    }
    if (jump) {
      (row, col) = _jumpTarget(row, col, dr, dc);
    } else {
      row = (row + dr).clamp(0, layout.rowCount - 1);
      col = (col + dc).clamp(0, layout.colCount - 1);
    }
    _select(row, col);
    _scrollIntoView(row, col);
  }

  (int, int) _jumpTarget(int row, int col, int dr, int dc) {
    bool hasValue(int r, int c) {
      final cell = sheet.cellAt(r, c);
      return cell != null && cell.value != null;
    }

    var r = row, c = col;
    final startHas = hasValue(r, c);
    final nextHas = hasValue(r + dr, c + dc);
    if (startHas && nextHas) {
      while (hasValue(r + dr, c + dc)) {
        r += dr;
        c += dc;
        if (r < 0 ||
            c < 0 ||
            r > layout.rowCount - 2 ||
            c > layout.colCount - 2) break;
      }
    } else {
      r += dr;
      c += dc;
      while (r >= 0 &&
          c >= 0 &&
          r < layout.rowCount &&
          c < layout.colCount &&
          !hasValue(r, c)) {
        r += dr;
        c += dc;
      }
      r = r.clamp(0, layout.rowCount - 1);
      c = c.clamp(0, layout.colCount - 1);
      if (!hasValue(r, c)) {
        r = dr != 0 ? (dr > 0 ? sheet.maxRow : 0) : r;
        c = dc != 0 ? (dc > 0 ? sheet.maxCol : 0) : c;
      }
    }
    return (r, c);
  }

  void _moveActiveBy(int dr, int dc) {
    var row = view.active.row;
    var col = view.active.col;
    final merge = sheet.mergeAt(row, col);
    if (merge != null) {
      if (dr > 0) row = merge.r2;
      if (dc > 0) col = merge.c2;
    }
    row = (row + dr).clamp(0, layout.rowCount - 1);
    col = (col + dc).clamp(0, layout.colCount - 1);
    _select(row, col);
    _scrollIntoView(row, col);
  }

  void _select(int row, int col) {
    final merge = sheet.mergeAt(row, col);
    view.active = CellRef(row, col);
    view.anchor = CellRef(row, col);
    view.selection = merge ?? CellRange.single(view.active);
    _afterSelectionChange();
  }

  void _expandSelectionToMerges() {
    // Expande até estabilizar (merges parcialmente cobertos).
    for (var i = 0; i < 8; i++) {
      var sel = view.selection;
      var changed = false;
      for (final m in sheet.merges) {
        if (m.intersects(sel)) {
          final r1 = m.r1 < sel.r1 ? m.r1 : sel.r1;
          final c1 = m.c1 < sel.c1 ? m.c1 : sel.c1;
          final r2 = m.r2 > sel.r2 ? m.r2 : sel.r2;
          final c2 = m.c2 > sel.c2 ? m.c2 : sel.c2;
          final next = CellRange(r1, c1, r2, c2);
          if (next != sel) {
            sel = next;
            changed = true;
          }
        }
      }
      view.selection = sel;
      if (!changed) break;
    }
  }

  void _afterSelectionChange({bool updateBar = true}) {
    if (updateBar) _updateFormulaBar();
    _notifySelectionStyle();
    _updateStatus();
    _schedulePaint();
  }

  /// Publica o estado de estilo da célula ativa (a toolbar da fachada
  /// espelha fonte/tamanho/negrito/alinhamento etc., como o Excel).
  void _notifySelectionStyle() {
    final callback = options.onSelectionChanged;
    if (callback == null) return;
    final st = wb.styles;
    final xf =
        st.xfAt(sheet.effectiveStyleIndex(view.active.row, view.active.col));
    final font = st.fontOf(xf);
    final align = xf.alignment ?? const XlsxAlignment();
    callback(SelectionStyleState(
      fontName: font.name,
      fontSize: font.size,
      bold: font.bold,
      italic: font.italic,
      underline: font.underline,
      horizontal: align.horizontal,
      vertical: align.vertical,
      wrapText: align.wrapText,
      merged: sheet.mergeAt(view.active.row, view.active.col) != null,
      numFmtCode: st.numFmtCodeOf(xf) ?? '',
      canUndo: _commands.canUndo,
      canRedo: _commands.canRedo,
    ));
  }

  void _scrollIntoView(int row, int col) {
    final rect = layout.cellRect(row, col);
    final headerW = kHeaderW * _zoom;
    final headerH = kHeaderH * _zoom;
    final viewW = (_scroller.clientWidth - headerW) / _zoom;
    final viewH = (_scroller.clientHeight - headerH) / _zoom;
    var sx = view.scrollX, sy = view.scrollY;
    if (rect.x < sx) sx = rect.x;
    if (rect.x + rect.w > sx + viewW) sx = rect.x + rect.w - viewW;
    if (rect.y < sy) sy = rect.y;
    if (rect.y + rect.h > sy + viewH) sy = rect.y + rect.h - viewH;
    if (sx != view.scrollX || sy != view.scrollY) {
      _scroller.scrollLeft = (sx * _zoom).roundToDouble();
      _scroller.scrollTop = (sy * _zoom).roundToDouble();
    }
  }

  // ---------------------------------------------------------------------
  // Edição
  // ---------------------------------------------------------------------

  void _startEdit({required bool fromTyping, String initial = ''}) {
    if (_readOnly) return;
    final cell = sheet.cellAt(view.active.row, view.active.col);
    _editing = true;
    _editorFromTyping = fromTyping;
    String text;
    if (fromTyping) {
      text = initial;
    } else {
      text = _editableTextOf(cell);
    }
    _editor.value = text;
    _editor.style.display = 'block';
    _positionEditor();
    _editor.focus();
    // Cursor no fim.
    _editor.setSelectionRange(text.length, text.length);
  }

  String _editableTextOf(Cell? cell) {
    if (cell == null) return '';
    final formula = cell.formula;
    if (formula != null) return '=${formulaToPtBr(formula)}';
    return switch (cell.value) {
      NumberValue(:final value) => _numToEditable(value),
      TextValue(:final value) => value,
      BoolValue(:final value) => value ? 'VERDADEIRO' : 'FALSO',
      ErrorValue(:final code) => code,
      null => '',
    };
  }

  String _numToEditable(double v) {
    var s = v == v.roundToDouble() && v.abs() < 1e15
        ? v.round().toString()
        : v.toString();
    return s.replaceAll('.', ',');
  }

  void _positionEditor() {
    final rect = layout.cellRect(view.active.row, view.active.col);
    final headerW = kHeaderW * _zoom;
    final headerH = kHeaderH * _zoom;
    final x = headerW + (rect.x - view.scrollX) * _zoom;
    final y = headerH + (rect.y - view.scrollY) * _zoom;
    final style = _renderer.resolveStyle(
        sheet.effectiveStyleIndex(view.active.row, view.active.col));
    _editor.style.left = '${x - 1}px';
    _editor.style.top = '${y - 1}px';
    _editor.style.minWidth = '${rect.w * _zoom + 1}px';
    _editor.style.minHeight = '${rect.h * _zoom + 1}px';
    _editor.style.font = style.fontCss;
    _editor.style.fontSize = '${style.fontSizePx * _zoom}px';
  }

  void _onEditorKey(web.KeyboardEvent e) {
    switch (e.key) {
      case 'Enter':
        if (e.altKey) {
          // Alt+Enter: quebra de linha.
          final v = _editor.value;
          _editor.value = '$v\n';
          e.preventDefault();
          return;
        }
        e.preventDefault();
        _commitEditor(e.shiftKey ? -1 : 1, 0);
      case 'Tab':
        e.preventDefault();
        _commitEditor(0, e.shiftKey ? -1 : 1);
      case 'Escape':
        e.preventDefault();
        _cancelEditor();
      case 'ArrowUp':
      case 'ArrowDown':
      case 'ArrowLeft':
      case 'ArrowRight':
        // Em modo digitação, setas confirmam e navegam (como no Excel).
        if (_editorFromTyping && !_editor.value.startsWith('=')) {
          e.preventDefault();
          _commitEditor(
              e.key == 'ArrowUp'
                  ? -1
                  : e.key == 'ArrowDown'
                      ? 1
                      : 0,
              e.key == 'ArrowLeft'
                  ? -1
                  : e.key == 'ArrowRight'
                      ? 1
                      : 0);
        }
    }
  }

  void _cancelEditor() {
    _editing = false;
    _editor.style.display = 'none';
    _focusGrid();
  }

  void _commitEditor(int dr, int dc) {
    if (!_editing) return;
    final text = _editor.value;
    _editing = false;
    _editor.style.display = 'none';
    _commitText(text, dr, dc);
    _focusGrid();
  }

  /// Converte texto digitado em valor/fórmula e grava na célula ativa.
  void _commitText(String text, int dr, int dc) {
    if (_readOnly) return;
    final row = view.active.row, col = view.active.col;
    final cell = sheet.cellAt(row, col);
    final before = CellSnapshot.of(cell);

    String? formula;
    CellValue? value;
    final trimmed = text.trim();
    if (trimmed.startsWith('=') && trimmed.length > 1) {
      try {
        formula = formulaFromPtBr(trimmed.substring(1));
      } catch (_) {
        formula = null;
        value = TextValue(text);
      }
    } else if (trimmed.isEmpty) {
      value = null;
    } else {
      value = _parseLiteral(trimmed) ?? TextValue(text);
    }

    final target = sheet.ensureCell(row, col);
    target
      ..formula = formula
      ..isArrayFormula = false
      ..value = formula != null ? target.value : value
      ..invalidateFormat();

    // Sincroniza motor de fórmulas.
    if (formula != null) {
      try {
        engine.setFormula(_sheetIndex, row, col, formula);
      } catch (_) {
        target
          ..formula = null
          ..value = TextValue(text);
        engine.removeFormula(_sheetIndex, row, col);
      }
    } else {
      engine.removeFormula(_sheetIndex, row, col);
    }
    engine.invalidateCell(_sheetIndex, row, col);
    _applyRecalc();

    _commands.push(CellsCommand('Editar célula', [
      CellPatch(_sheetIndex, CellRef(row, col), before, CellSnapshot.of(target))
    ]));
    _markDirty();

    if (row > sheet.maxRow || col > sheet.maxCol) layout.rebuild();
    _syncSpacer();
    if (dr != 0 || dc != 0) _moveActiveBy(dr, dc);
    _updateFormulaBar();
    _updateStatus();
    _schedulePaint();
  }

  CellValue? _parseLiteral(String text) {
    if (text == 'VERDADEIRO' || text == 'TRUE') return const BoolValue(true);
    if (text == 'FALSO' || text == 'FALSE') return const BoolValue(false);
    var t = text;
    var percent = false;
    if (t.endsWith('%')) {
      percent = true;
      t = t.substring(0, t.length - 1).trim();
    }
    // Aceita "1.234,56" (pt-BR) e "1234.56" (en).
    String normalized;
    if (t.contains(',')) {
      normalized = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = t;
    }
    final n = double.tryParse(normalized);
    if (n == null) return null;
    return NumberValue(percent ? n / 100 : n);
  }

  /// Aplica os resultados de engine.recalc() ao modelo.
  void _applyRecalc() {
    List<(int, int, int, Object?)> changed;
    try {
      changed = engine.recalc();
    } catch (_) {
      return;
    }
    for (final (s, r, c, v) in changed) {
      if (s < 0 || s >= wb.sheets.length) continue;
      final cell = wb.sheets[s].ensureCell(r, c);
      cell.value = switch (v) {
        double d => NumberValue(d),
        int i => NumberValue(i.toDouble()),
        String s2 => TextValue(s2),
        bool b => BoolValue(b),
        FormulaError err => ErrorValue(err.code),
        _ => null,
      };
      cell.invalidateFormat();
    }
  }

  // ---------------------------------------------------------------------
  // Operações de estilo / merge / limpar
  // ---------------------------------------------------------------------

  Iterable<(int, int)> _selectionCells() sync* {
    final sel = view.selection;
    final r2 = sel.r2.clamp(0, sheet.maxRow + 100);
    final c2 = sel.c2.clamp(0, sheet.maxCol + 40);
    for (var r = sel.r1; r <= r2; r++) {
      for (var c = sel.c1; c <= c2; c++) {
        final m = sheet.mergeAt(r, c);
        if (m != null && (m.r1 != r || m.c1 != c)) continue;
        yield (r, c);
      }
    }
  }

  void _applyStyle(int Function(StyleTable st, int xf) derive) {
    if (_readOnly) return;
    final patches = <CellPatch>[];
    for (final (r, c) in _selectionCells()) {
      final cell = sheet.ensureCell(r, c);
      final before = CellSnapshot.of(cell);
      cell.styleIndex = derive(wb.styles, cell.styleIndex);
      cell.invalidateFormat();
      patches.add(
          CellPatch(_sheetIndex, CellRef(r, c), before, CellSnapshot.of(cell)));
    }
    if (patches.isNotEmpty) {
      _commands.push(CellsCommand('Formatar', patches));
      _markDirty();
    }
    _renderer.invalidateStyles();
    _schedulePaint();
  }

  void _toggleFont(XlsxFont Function(XlsxFont) transform) {
    _applyStyle(
        (st, xf) => st.deriveXf(xf, font: transform(st.fontOf(st.xfAt(xf)))));
  }

  void _setAlign({String? h, String? v}) {
    _applyStyle((st, xf) {
      final base = st.xfAt(xf).alignment ?? const XlsxAlignment();
      return st.deriveXf(xf,
          alignment: XlsxAlignment(
            horizontal: h ?? base.horizontal,
            vertical: v ?? base.vertical,
            wrapText: base.wrapText,
            textRotation: base.textRotation,
            indent: base.indent,
            shrinkToFit: base.shrinkToFit,
          ));
    });
  }

  void _toggleWrap() {
    _applyStyle((st, xf) {
      final base = st.xfAt(xf).alignment ?? const XlsxAlignment();
      return st.deriveXf(xf,
          alignment: XlsxAlignment(
            horizontal: base.horizontal,
            vertical: base.vertical,
            wrapText: !base.wrapText,
            textRotation: base.textRotation,
            indent: base.indent,
            shrinkToFit: base.shrinkToFit,
          ));
    });
  }

  void _setBorders(String mode) {
    if (_readOnly) return;
    const side = BorderSide(style: 'thin', color: XlsxColor.rgbHex('FF000000'));
    final sel = view.selection;
    if (mode == 'all') {
      _applyStyle((st, xf) => st.deriveXf(xf,
          border: const XlsxBorder(
              left: side, right: side, top: side, bottom: side)));
      return;
    }
    if (mode == 'none') {
      _applyStyle((st, xf) => st.deriveXf(xf, border: const XlsxBorder()));
      return;
    }
    // outline: cada célula recebe só os lados externos.
    final patches = <CellPatch>[];
    for (final (r, c) in _selectionCells()) {
      final cell = sheet.ensureCell(r, c);
      final before = CellSnapshot.of(cell);
      final st = wb.styles;
      final old = st.borderOf(st.xfAt(cell.styleIndex));
      final merge = sheet.mergeAt(r, c);
      final rEnd = merge?.r2 ?? r, cEnd = merge?.c2 ?? c;
      cell.styleIndex = st.deriveXf(cell.styleIndex,
          border: XlsxBorder(
            left: c == sel.c1 ? side : old.left,
            right: cEnd == sel.c2 ? side : old.right,
            top: r == sel.r1 ? side : old.top,
            bottom: rEnd == sel.r2 ? side : old.bottom,
          ));
      cell.invalidateFormat();
      patches.add(
          CellPatch(_sheetIndex, CellRef(r, c), before, CellSnapshot.of(cell)));
    }
    if (patches.isNotEmpty) {
      _commands.push(CellsCommand('Bordas', patches));
      _markDirty();
    }
    _renderer.invalidateStyles();
    _schedulePaint();
  }

  void _toggleMerge() {
    if (_readOnly) return;
    final sel = view.selection;
    final existing = sheet.mergeAt(sel.r1, sel.c1);
    if (existing != null && existing == sel) {
      sheet.removeMerge(sel);
      _commands.push(
          MergeCommand('Desfazer mesclagem', _sheetIndex, sel, isMerge: false));
    } else if (!sel.isSingle) {
      sheet.addMerge(sel);
      _commands.push(MergeCommand('Mesclar', _sheetIndex, sel, isMerge: true));
    }
    _markDirty();
    _schedulePaint();
  }

  void _clearSelection() {
    if (_readOnly) return;
    final patches = <CellPatch>[];
    for (final (r, c) in _selectionCells()) {
      final cell = sheet.cellAt(r, c);
      if (cell == null || (cell.value == null && cell.formula == null)) {
        continue;
      }
      final before = CellSnapshot.of(cell);
      cell
        ..value = null
        ..formula = null
        ..isArrayFormula = false
        ..invalidateFormat();
      engine.removeFormula(_sheetIndex, r, c);
      engine.invalidateCell(_sheetIndex, r, c);
      patches.add(
          CellPatch(_sheetIndex, CellRef(r, c), before, CellSnapshot.of(cell)));
    }
    if (patches.isNotEmpty) {
      _commands.push(CellsCommand('Limpar', patches));
      _applyRecalc();
      _markDirty();
    }
    _updateFormulaBar();
    _updateStatus();
    _schedulePaint();
  }

  // ---------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------

  String _selectionToTsv() {
    final sel = view.selection;
    final sb = StringBuffer();
    for (var r = sel.r1; r <= sel.r2; r++) {
      if (r > sel.r1) sb.write('\n');
      for (var c = sel.c1; c <= sel.c2; c++) {
        if (c > sel.c1) sb.write('\t');
        final cell = sheet.cellAt(r, c);
        if (cell == null) continue;
        sb.write(_editableTextOf(cell));
      }
    }
    return sb.toString();
  }

  void _pasteTsv(String text) {
    if (_readOnly) return;
    final lines =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final startR = view.active.row, startC = view.active.col;
    final patches = <CellPatch>[];
    for (var i = 0; i < lines.length; i++) {
      final cols = lines[i].split('\t');
      for (var j = 0; j < cols.length; j++) {
        final r = startR + i, c = startC + j;
        final cell = sheet.ensureCell(r, c);
        final before = CellSnapshot.of(cell);
        final t = cols[j];
        String? formula;
        CellValue? value;
        if (t.startsWith('=') && t.length > 1) {
          try {
            formula = formulaFromPtBr(t.substring(1));
          } catch (_) {
            value = TextValue(t);
          }
        } else if (t.isEmpty) {
          value = null;
        } else {
          value = _parseLiteral(t) ?? TextValue(t);
        }
        cell
          ..formula = formula
          ..isArrayFormula = false
          ..value = value
          ..invalidateFormat();
        if (formula != null) {
          try {
            engine.setFormula(_sheetIndex, r, c, formula);
          } catch (_) {
            cell
              ..formula = null
              ..value = TextValue(t);
            engine.removeFormula(_sheetIndex, r, c);
          }
        } else {
          engine.removeFormula(_sheetIndex, r, c);
        }
        engine.invalidateCell(_sheetIndex, r, c);
        patches.add(CellPatch(
            _sheetIndex, CellRef(r, c), before, CellSnapshot.of(cell)));
      }
    }
    if (patches.isNotEmpty) {
      _commands.push(CellsCommand('Colar', patches));
      _applyRecalc();
      _markDirty();
      view.selection = CellRange(
          startR,
          startC,
          startR + lines.length - 1,
          startC +
              (lines.isEmpty
                  ? 0
                  : lines
                          .map((l) => l.split('\t').length)
                          .reduce((a, b) => a > b ? a : b) -
                      1));
      layout.rebuild();
      _syncSpacer();
      _afterSelectionChange();
    }
  }

  // ---------------------------------------------------------------------
  // Undo / redo
  // ---------------------------------------------------------------------

  void _applyCommand(Command command, {required bool undo}) {
    switch (command) {
      case CellsCommand(:final patches):
        for (final p in patches) {
          final ws = wb.sheets[p.sheetIndex];
          final snap = undo ? p.before : p.after;
          snap.applyTo(ws, p.ref.row, p.ref.col);
          final formula = snap.formula;
          if (formula != null) {
            try {
              engine.setFormula(p.sheetIndex, p.ref.row, p.ref.col, formula,
                  isArray: snap.isArrayFormula);
            } catch (_) {}
          } else {
            engine.removeFormula(p.sheetIndex, p.ref.row, p.ref.col);
          }
          engine.invalidateCell(p.sheetIndex, p.ref.row, p.ref.col);
        }
        _applyRecalc();
      case MergeCommand(:final sheetIndex, :final range, :final isMerge):
        final ws = wb.sheets[sheetIndex];
        final doMerge = undo ? !isMerge : isMerge;
        if (doMerge) {
          ws.addMerge(range);
        } else {
          ws.removeMerge(range);
        }
      case ResizeCommand(
          :final sheetIndex,
          :final isColumn,
          :final index,
          :final before,
          :final after
        ):
        final ws = wb.sheets[sheetIndex];
        final size = undo ? before : after;
        if (isColumn) {
          ws.colProps[index] = ColProps(width: size);
        } else {
          ws.rowProps[index] = RowProps(height: size);
        }
        _layouts[sheetIndex].rebuild();
        _syncSpacer();
    }
    _renderer.invalidateStyles();
    _updateFormulaBar();
    _notifySelectionStyle();
    _updateStatus();
    _schedulePaint();
  }

  void undo() {
    if (_readOnly) return;
    final c = _commands.popUndo();
    if (c != null) _applyCommand(c, undo: true);
  }

  void redo() {
    if (_readOnly) return;
    final c = _commands.popRedo();
    if (c != null) _applyCommand(c, undo: false);
  }

  // ---------------------------------------------------------------------
  // Abas / status / barra de fórmulas
  // ---------------------------------------------------------------------

  void _rebuildTabs() {
    _tabs.innerHTML = ''.toJS;
    for (var i = 0; i < wb.sheets.length; i++) {
      final tab = web.document.createElement('button') as web.HTMLButtonElement;
      tab.className = i == _sheetIndex ? 'xe-tab xe-tab-active' : 'xe-tab';
      tab.textContent = wb.sheets[i].name;
      final index = i;
      tab.addEventListener(
          'click',
          ((web.Event _) {
            if (_editing) _commitEditor(0, 0);
            _sheetIndex = index;
            _rebuildTabs();
            _syncSpacer();
            _scroller.scrollLeft = (view.scrollX * _zoom).roundToDouble();
            _scroller.scrollTop = (view.scrollY * _zoom).roundToDouble();
            _updateFormulaBar();
            _updateStatus();
            _schedulePaint();
            _focusGrid();
          }).toJS);
      _tabs.appendChild(tab);
    }
  }

  void _updateFormulaBar() {
    _nameBox.value = view.active.a1;
    // Numa célula mesclada, o conteúdo mora na âncora.
    final merge = sheet.mergeAt(view.active.row, view.active.col);
    final cell = merge != null
        ? sheet.cellAt(merge.r1, merge.c1)
        : sheet.cellAt(view.active.row, view.active.col);
    _formulaInput.value = _editableTextOf(cell);
  }

  void _updateStatus() {
    final sel = view.selection;
    var count = 0;
    var numCount = 0;
    var sum = 0.0;
    final r2 = sel.r2.clamp(0, sheet.maxRow);
    final c2 = sel.c2.clamp(0, sheet.maxCol);
    for (var r = sel.r1; r <= r2; r++) {
      for (var c = sel.c1; c <= c2; c++) {
        final v = sheet.cellAt(r, c)?.value;
        if (v == null) continue;
        count++;
        if (v is NumberValue) {
          numCount++;
          sum += v.value;
        }
      }
    }
    String fmt(double v) {
      final fixed = v.toStringAsFixed(2);
      final parts = fixed.split('.');
      final intPart = parts[0]
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
      return '$intPart,${parts[1]}';
    }

    if (numCount > 0) {
      _status.textContent =
          'Média: ${fmt(sum / numCount)}   Contagem: $count   Soma: ${fmt(sum)}';
    } else {
      _status.textContent = count > 1 ? 'Contagem: $count' : 'Pronto';
    }
  }

  // ---------------------------------------------------------------------
  // Pintura / dimensões
  // ---------------------------------------------------------------------

  void _syncSpacer() {
    _spacer.style.width =
        '${((layout.totalWidth + kHeaderW + 200) * _zoom).round()}px';
    _spacer.style.height =
        '${((layout.totalHeight + kHeaderH + 200) * _zoom).round()}px';
  }

  void _resizeCanvas() {
    final rect = _gridWrap.getBoundingClientRect();
    final dpr = web.window.devicePixelRatio;
    _canvas.width = (rect.width * dpr).round();
    _canvas.height = (rect.height * dpr).round();
    _canvas.style.width = '${rect.width}px';
    _canvas.style.height = '${rect.height}px';
  }

  void _schedulePaint() {
    if (_painting || _disposed) return;
    _painting = true;
    web.window.requestAnimationFrame(((double _) {
      _painting = false;
      _paint();
    }).toJS);
  }

  void _paint() {
    if (_disposed) return;
    final rect = _gridWrap.getBoundingClientRect();
    if (rect.width == 0) return;
    _renderer.paint(
      sheet: sheet,
      layout: layout,
      viewW: rect.width,
      viewH: rect.height,
      scrollX: view.scrollX,
      scrollY: view.scrollY,
      zoom: _zoom,
      dpr: web.window.devicePixelRatio,
      selection: view.selection,
      active: view.active,
    );
  }

  void _markDirty() {
    _dirty = true;
    _notifySelectionStyle();
    options.onChange?.call();
  }

  // ---------------------------------------------------------------------
  // API pública (usada pela fachada XlsxEditorWidget e por hosts diretos)
  // ---------------------------------------------------------------------

  /// Abre o seletor de arquivo .xlsx nativo.
  void openFilePicker() => _fileInput.click();

  /// Carrega um novo workbook a partir dos bytes de um .xlsx.
  void loadBytes(Uint8List bytes, {String? fileName}) {
    try {
      doc = readXlsx(bytes);
    } catch (err) {
      final onError = options.onError;
      if (onError != null) {
        onError(err);
      } else {
        web.window.alert('Falha ao abrir o arquivo: $err');
      }
      return;
    }
    _sheetIndex = wb.activeSheet;
    _initModel();
    _renderer = GridRenderer(
      wb,
      _canvas.getContext('2d') as web.CanvasRenderingContext2D,
      ImageStore(_schedulePaint),
      (path) => doc.mediaBytes(path),
      theme: options.theme,
    );
    _dirty = false;
    _zoom = sheet.zoomScale.clamp(0.5, 2.0);
    _zoomSelect.value = '${(_zoom * 100).round()}';
    _rebuildTabs();
    _syncSpacer();
    _updateFormulaBar();
    _notifySelectionStyle();
    _updateStatus();
    _schedulePaint();
    if (fileName != null) options.onFileOpened?.call(fileName);
  }

  /// Serializa o workbook atual como bytes de um .xlsx.
  Uint8List saveBytes() {
    if (_editing) _commitEditor(0, 0);
    return writeXlsx(doc);
  }

  /// Baixa o workbook atual como arquivo .xlsx.
  void download([String? fileName]) {
    final bytes = saveBytes();
    final blob = web.Blob(
      [bytes.toJS as web.BlobPart].toJS,
      web.BlobPropertyBag(
          type:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    );
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = url;
    a.download = fileName ?? 'planilha_editada.xlsx';
    a.click();
    web.URL.revokeObjectURL(url);
    _dirty = false;
  }

  /// Alterna edição/somente-leitura em runtime (modo visualizador).
  void setReadOnly(bool value) {
    if (_readOnly == value) return;
    _readOnly = value;
    if (value && _editing) _cancelEditor();
    _formulaInput.readOnly = value;
  }

  void toggleBold() => _toggleFont((f) => f.copyWith(bold: !f.bold));
  void toggleItalic() => _toggleFont((f) => f.copyWith(italic: !f.italic));
  void toggleUnderline() =>
      _toggleFont((f) => f.copyWith(underline: !f.underline));

  /// Alinhamento horizontal ('left'|'center'|'right') e/ou vertical
  /// ('top'|'center'|'bottom') da seleção.
  void setAlignment({String? horizontal, String? vertical}) =>
      _setAlign(h: horizontal, v: vertical);

  void toggleWrapText() => _toggleWrap();
  void toggleMergeSelection() => _toggleMerge();

  /// Bordas da seleção: 'all' | 'outline' | 'none'.
  void setBorderPreset(String preset) => _setBorders(preset);

  void applyFontName(String name) => _applyStyle((st, xf) =>
      st.deriveXf(xf, font: st.fontOf(st.xfAt(xf)).copyWith(name: name)));

  void applyFontSize(double size) => _applyStyle((st, xf) =>
      st.deriveXf(xf, font: st.fontOf(st.xfAt(xf)).copyWith(size: size)));

  /// Cor da fonte, hex `RRGGBB` (sem `#`).
  void applyFontColor(String rgbHex) => _applyStyle((st, xf) => st.deriveXf(xf,
      font: st
          .fontOf(st.xfAt(xf))
          .copyWith(color: XlsxColor.rgbHex('FF${rgbHex.toUpperCase()}'))));

  /// Cor de preenchimento, hex `RRGGBB` (sem `#`).
  void applyFillColor(String rgbHex) => _applyStyle((st, xf) => st.deriveXf(xf,
      fill: XlsxFill(
          patternType: 'solid',
          fgColor: XlsxColor.rgbHex('FF${rgbHex.toUpperCase()}'))));

  /// Formato numérico da seleção (código OOXML; vazio = Geral).
  void applyNumberFormat(String code) => _applyStyle((st, xf) =>
      st.deriveXf(xf, numFmtId: code.isEmpty ? 0 : st.ensureNumFmt(code)));

  /// Remove listeners globais e o DOM da shell (para `ngOnDestroy`).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    for (final (target, type, handler) in _globalListeners) {
      target.removeEventListener(type, handler);
    }
    _globalListeners.clear();
    _root.remove();
  }
}
