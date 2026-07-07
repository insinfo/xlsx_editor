/// Renderizador canvas da grade: virtualização por intervalo visível,
/// fundos, gridlines, texto formatado, bordas, merges, headers e seleção.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../layout/sheet_layout.dart';
import '../model/styles.dart';
import '../model/workbook.dart';
import '../numfmt/number_format.dart';
import '../util/cell_ref.dart';

/// Estilo resolvido (cacheado por índice de xf).
class ResolvedStyle {
  final String fontCss;
  final String fontColor;
  final double fontSizePx;
  final bool underline;
  final bool strike;
  final String? fillColor;
  final XlsxBorder border;
  final XlsxAlignment alignment;
  final NumberFormat numFmt;

  ResolvedStyle({
    required this.fontCss,
    required this.fontColor,
    required this.fontSizePx,
    required this.underline,
    required this.strike,
    required this.fillColor,
    required this.border,
    required this.alignment,
    required this.numFmt,
  });
}

/// Cache de imagens ancoradas (decodificadas pelo browser).
class ImageStore {
  final Map<String, web.HTMLImageElement> _images = {};
  final void Function() onLoaded;

  ImageStore(this.onLoaded);

  web.HTMLImageElement? imageFor(String path, Uint8List? Function() bytesOf) {
    final cached = _images[path];
    if (cached != null) return cached.complete ? cached : null;
    final bytes = bytesOf();
    if (bytes == null) return null;
    final mime = path.endsWith('.png')
        ? 'image/png'
        : path.endsWith('.gif')
            ? 'image/gif'
            : 'image/jpeg';
    final blob = web.Blob(
      [bytes.toJS as web.BlobPart].toJS,
      web.BlobPropertyBag(type: mime),
    );
    final url = web.URL.createObjectURL(blob);
    final img = web.HTMLImageElement();
    img.onload = ((web.Event _) => onLoaded()).toJS;
    img.src = url;
    _images[path] = img;
    return null;
  }
}

const double kHeaderW = 46;
const double kHeaderH = 22;
const double kEmuPerPx = 9525;

class GridRenderer {
  final Workbook workbook;
  final web.CanvasRenderingContext2D ctx;
  final ImageStore images;
  final Uint8List? Function(String mediaPath) mediaBytes;

  final Map<int, ResolvedStyle> _styleCache = {};
  final Map<String, double> _measureCache = {};

  GridRenderer(this.workbook, this.ctx, this.images, this.mediaBytes);

  void invalidateStyles() => _styleCache.clear();

  ResolvedStyle resolveStyle(int index) =>
      _styleCache[index] ??= _buildStyle(index);

  ResolvedStyle _buildStyle(int index) {
    final st = workbook.styles;
    final xf = st.xfAt(index);
    final font = st.fontOf(xf);
    final fill = st.fillOf(xf);
    final sizePx = font.size * 96 / 72;
    final fontCss = '${font.italic ? 'italic ' : ''}'
        '${font.bold ? 'bold ' : ''}'
        '${sizePx.toStringAsFixed(1)}px "${font.name}", sans-serif';
    String? fillColor;
    if (fill.patternType == 'solid' && fill.fgColor != null) {
      fillColor = fill.fgColor!.css(workbook.theme, fallback: '#FFFFFF');
    } else if (fill.isVisible && fill.fgColor != null) {
      fillColor = fill.fgColor!.css(workbook.theme, fallback: '#FFFFFF');
    }
    final code = st.numFmtCodeOf(xf);
    return ResolvedStyle(
      fontCss: fontCss,
      fontColor: font.color.css(workbook.theme),
      fontSizePx: sizePx,
      underline: font.underline,
      strike: font.strike,
      fillColor: fillColor,
      border: st.borderOf(xf),
      alignment: xf.alignment ?? const XlsxAlignment(),
      numFmt: code != null
          ? NumberFormat.compile(code)
          : NumberFormat.builtin(xf.numFmtId),
    );
  }

  double measure(String font, String text) {
    final key = '$font|$text';
    final cached = _measureCache[key];
    if (cached != null) return cached;
    if (_measureCache.length > 60000) _measureCache.clear();
    ctx.font = font;
    final w = ctx.measureText(text).width;
    _measureCache[key] = w;
    return w;
  }

  /// Texto formatado + cor de uma célula (com cache na célula).
  (String, String?) formattedText(Cell cell, ResolvedStyle style) {
    final cached = cell.formattedCache;
    if (cached != null) return (cached, cell.formattedColorCache);
    final raw = cell.raw;
    String text;
    String? color;
    if (raw == null) {
      text = '';
    } else if (cell.value is ErrorValue) {
      text = (cell.value as ErrorValue).code;
    } else {
      final result = style.numFmt.format(raw);
      text = result.text;
      final argb = result.colorArgbHex;
      if (argb != null) {
        color = '#${argb.length == 8 ? argb.substring(2) : argb}';
      }
    }
    cell.formattedCache = text;
    cell.formattedColorCache = color;
    return (text, color);
  }

  // -------------------------------------------------------------------------
  // Pintura principal
  // -------------------------------------------------------------------------

  void paint({
    required Worksheet sheet,
    required SheetLayout layout,
    required double viewW,
    required double viewH,
    required double scrollX,
    required double scrollY,
    required double zoom,
    required double dpr,
    required CellRange selection,
    required CellRef active,
  }) {
    ctx.resetTransform();
    ctx.scale(dpr, dpr);
    ctx.fillStyle = '#FFFFFF'.toJS;
    ctx.fillRect(0, 0, viewW, viewH);

    final headerW = kHeaderW * zoom;
    final headerH = kHeaderH * zoom;
    final contentW = (viewW - headerW) / zoom;
    final contentH = (viewH - headerH) / zoom;

    var rowStart = layout.rows.indexAt(scrollY);
    var rowEnd = layout.rows.indexAt(scrollY + contentH) + 1;
    var colStart = layout.cols.indexAt(scrollX);
    var colEnd = layout.cols.indexAt(scrollX + contentW) + 1;
    rowEnd = rowEnd.clamp(0, layout.rowCount - 1);
    colEnd = colEnd.clamp(0, layout.colCount - 1);

    // Merges que intersectam o viewport.
    final visRange = CellRange(rowStart, colStart, rowEnd, colEnd);
    final visibleMerges =
        sheet.merges.where((m) => m.intersects(visRange)).toList();

    // ---- Conteúdo (clip + transformação de scroll/zoom) ----
    ctx.save();
    ctx.beginPath();
    ctx.rect(headerW, headerH, viewW - headerW, viewH - headerH);
    ctx.clip();
    ctx.translate(headerW, headerH);
    ctx.scale(zoom, zoom);
    ctx.translate(-scrollX, -scrollY);

    _paintGridLines(sheet, layout, rowStart, rowEnd, colStart, colEnd,
        scrollX, scrollY, contentW, contentH);
    _paintFills(sheet, layout, rowStart, rowEnd, colStart, colEnd,
        visibleMerges);
    _paintTexts(sheet, layout, rowStart, rowEnd, colStart, colEnd,
        visibleMerges);
    _paintBorders(sheet, layout, rowStart, rowEnd, colStart, colEnd,
        visibleMerges);
    _paintImages(sheet, layout);
    _paintSelection(layout, selection, active);
    ctx.restore();

    _paintHeaders(layout, rowStart, rowEnd, colStart, colEnd, scrollX,
        scrollY, viewW, viewH, zoom, selection);
  }

  void _paintGridLines(
      Worksheet sheet,
      SheetLayout layout,
      int rowStart,
      int rowEnd,
      int colStart,
      int colEnd,
      double scrollX,
      double scrollY,
      double contentW,
      double contentH) {
    if (!sheet.showGridLines) return;
    ctx.strokeStyle = '#D8D8D8'.toJS;
    ctx.lineWidth = 1;
    ctx.beginPath();
    final xMax = scrollX + contentW;
    final yMax = scrollY + contentH;
    for (var r = rowStart; r <= rowEnd + 1; r++) {
      final y = layout.rows.posOf(r) + 0.5;
      ctx.moveTo(scrollX, y);
      ctx.lineTo(xMax, y);
    }
    for (var c = colStart; c <= colEnd + 1; c++) {
      final x = layout.cols.posOf(c) + 0.5;
      ctx.moveTo(x, scrollY);
      ctx.lineTo(x, yMax);
    }
    ctx.stroke();
  }

  void _paintFills(Worksheet sheet, SheetLayout layout, int rowStart,
      int rowEnd, int colStart, int colEnd, List<CellRange> visibleMerges) {
    for (var r = rowStart; r <= rowEnd; r++) {
      final y = layout.rows.posOf(r);
      final h = layout.rows.sizeOf(r);
      if (h <= 0) continue;
      for (var c = colStart; c <= colEnd; c++) {
        if (sheet.mergeAt(r, c) != null) continue; // merges à parte
        final style = resolveStyle(sheet.effectiveStyleIndex(r, c));
        final fill = style.fillColor;
        if (fill == null) continue;
        final x = layout.cols.posOf(c);
        final w = layout.cols.sizeOf(c);
        if (w <= 0) continue;
        ctx.fillStyle = fill.toJS;
        ctx.fillRect(x, y, w, h);
      }
    }
    for (final m in visibleMerges) {
      final style =
          resolveStyle(sheet.effectiveStyleIndex(m.r1, m.c1));
      final fill = style.fillColor;
      final rect = layout.cellRect(m.r1, m.c1);
      ctx.fillStyle = (fill ?? '#FFFFFF').toJS;
      ctx.fillRect(rect.x, rect.y, rect.w, rect.h);
    }
  }

  void _paintTexts(Worksheet sheet, SheetLayout layout, int rowStart,
      int rowEnd, int colStart, int colEnd, List<CellRange> visibleMerges) {
    for (var r = rowStart; r <= rowEnd; r++) {
      final h = layout.rows.sizeOf(r);
      if (h <= 0) continue;
      for (var c = colStart; c <= colEnd; c++) {
        if (sheet.mergeAt(r, c) != null) continue;
        final cell = sheet.cellAt(r, c);
        if (cell == null || cell.value == null) continue;
        final rect = (
          x: layout.cols.posOf(c),
          y: layout.rows.posOf(r),
          w: layout.cols.sizeOf(c),
          h: h
        );
        _paintCellText(sheet, layout, r, c, cell, rect, allowSpill: true);
      }
    }
    for (final m in visibleMerges) {
      final cell = sheet.cellAt(m.r1, m.c1);
      if (cell == null || cell.value == null) continue;
      final rect = layout.cellRect(m.r1, m.c1);
      _paintCellText(sheet, layout, m.r1, m.c1, cell, rect,
          allowSpill: false);
    }
  }

  void _paintCellText(
      Worksheet sheet,
      SheetLayout layout,
      int r,
      int c,
      Cell cell,
      ({double x, double y, double w, double h}) rect,
      {required bool allowSpill}) {
    final style = resolveStyle(sheet.effectiveStyleIndex(r, c));
    final (text, fmtColor) = formattedText(cell, style);
    if (text.isEmpty) return;

    final align = style.alignment;
    var horizontal = align.horizontal;
    if (horizontal == 'general') {
      horizontal = switch (cell.value) {
        NumberValue() => 'right',
        BoolValue() || ErrorValue() => 'center',
        _ => 'left',
      };
    }

    const padX = 3.0;
    final indentPx = align.indent * 8.0;
    ctx.font = style.fontCss;
    ctx.fillStyle = (fmtColor ?? style.fontColor).toJS;

    // Linhas (wrap por palavra ou quebras explícitas).
    final innerW = rect.w - padX * 2 - indentPx;
    List<String> lines;
    if (align.wrapText) {
      lines = _wrapText(text, style.fontCss, innerW);
    } else {
      lines = text.contains('\n') ? text.split('\n') : [text];
    }
    final lineH = style.fontSizePx * 1.25;
    final blockH = lineH * lines.length;

    double clipX = rect.x, clipW = rect.w;
    if (allowSpill && !align.wrapText && lines.length == 1) {
      final textW = measure(style.fontCss, text) + padX * 2 + indentPx;
      if (textW > rect.w) {
        // Deixa vazar sobre vizinhos vazios (esq/dir conforme alinhamento).
        if (horizontal == 'left' || horizontal == 'center') {
          var cEnd = c;
          var limit = rect.x + rect.w;
          while (limit < rect.x + textW && cEnd + 1 < layout.colCount) {
            final next = cEnd + 1;
            final neighbor = sheet.cellAt(r, next);
            if ((neighbor != null && neighbor.value != null) ||
                sheet.mergeAt(r, next) != null) {
              break;
            }
            cEnd = next;
            limit += layout.cols.sizeOf(next);
          }
          clipW = limit - rect.x;
        }
        if (horizontal == 'right' || horizontal == 'center') {
          var cBegin = c;
          var begin = rect.x;
          final needed = horizontal == 'center'
              ? rect.x - (textW - rect.w) / 2
              : rect.x + rect.w - textW;
          while (begin > needed && cBegin - 1 >= 0) {
            final prev = cBegin - 1;
            final neighbor = sheet.cellAt(r, prev);
            if ((neighbor != null && neighbor.value != null) ||
                sheet.mergeAt(r, prev) != null) {
              break;
            }
            cBegin = prev;
            begin -= layout.cols.sizeOf(prev);
          }
          clipW += clipX - begin;
          clipX = begin;
        }
      }
    }

    ctx.save();
    ctx.beginPath();
    ctx.rect(clipX, rect.y, clipW, rect.h);
    ctx.clip();

    // Posição vertical do bloco de linhas.
    final vAlign = align.vertical;
    double yTop;
    if (vAlign == 'top') {
      yTop = rect.y + 2;
    } else if (vAlign == 'center' || vAlign == 'justify') {
      yTop = rect.y + (rect.h - blockH) / 2;
    } else {
      yTop = rect.y + rect.h - blockH - 2;
    }

    ctx.textBaseline = 'alphabetic';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineW = measure(style.fontCss, line);
      double x;
      if (horizontal == 'right') {
        x = rect.x + rect.w - padX - indentPx - lineW;
      } else if (horizontal == 'center' || horizontal == 'centerContinuous') {
        x = rect.x + (rect.w - lineW) / 2;
      } else {
        x = rect.x + padX + indentPx;
      }
      final baseline = yTop + lineH * i + style.fontSizePx;
      ctx.fillText(line, x, baseline);
      if (style.underline) {
        ctx.strokeStyle = (fmtColor ?? style.fontColor).toJS;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x, baseline + 2);
        ctx.lineTo(x + lineW, baseline + 2);
        ctx.stroke();
      }
      if (style.strike) {
        ctx.strokeStyle = (fmtColor ?? style.fontColor).toJS;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x, baseline - style.fontSizePx * 0.3);
        ctx.lineTo(x + lineW, baseline - style.fontSizePx * 0.3);
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  List<String> _wrapText(String text, String font, double maxW) {
    final result = <String>[];
    for (final paragraph in text.split('\n')) {
      if (measure(font, paragraph) <= maxW || maxW <= 0) {
        result.add(paragraph);
        continue;
      }
      final words = paragraph.split(' ');
      var line = StringBuffer();
      for (final word in words) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (measure(font, candidate) <= maxW || line.isEmpty) {
          line = StringBuffer(candidate);
        } else {
          result.add(line.toString());
          line = StringBuffer(word);
        }
      }
      if (line.isNotEmpty) result.add(line.toString());
    }
    return result;
  }

  void _strokeSide(double x1, double y1, double x2, double y2,
      BorderSide side) {
    if (!side.isVisible) return;
    final color = side.color.css(workbook.theme);
    double width;
    JSArray<JSNumber>? dash;
    switch (side.style) {
      case 'medium':
        width = 2;
      case 'thick':
        width = 3;
      case 'double':
        width = 1; // aproximação: linha simples
      case 'dotted':
        width = 1;
        dash = [1.toJS, 1.toJS].toJS;
      case 'dashed':
      case 'mediumDashed':
        width = side.style == 'mediumDashed' ? 2 : 1;
        dash = [3.toJS, 2.toJS].toJS;
      case 'hair':
        width = 1;
      default:
        width = 1;
    }
    ctx.strokeStyle = color.toJS;
    ctx.lineWidth = width;
    if (dash != null) ctx.setLineDash(dash);
    ctx.beginPath();
    final off = width == 1 ? 0.5 : 0.0;
    if (y1 == y2) {
      ctx.moveTo(x1, y1 + off);
      ctx.lineTo(x2, y2 + off);
    } else {
      ctx.moveTo(x1 + off, y1);
      ctx.lineTo(x2 + off, y2);
    }
    ctx.stroke();
    if (dash != null) ctx.setLineDash(<JSNumber>[].toJS);
    if (side.style == 'double') {
      // Segunda linha para 'double'.
      ctx.beginPath();
      if (y1 == y2) {
        ctx.moveTo(x1, y1 + 2.5);
        ctx.lineTo(x2, y2 + 2.5);
      } else {
        ctx.moveTo(x1 + 2.5, y1);
        ctx.lineTo(x2 + 2.5, y2);
      }
      ctx.stroke();
    }
  }

  void _paintBorders(Worksheet sheet, SheetLayout layout, int rowStart,
      int rowEnd, int colStart, int colEnd, List<CellRange> visibleMerges) {
    void paintCellBorder(int r, int c,
        ({double x, double y, double w, double h}) rect) {
      final style = resolveStyle(sheet.effectiveStyleIndex(r, c));
      final b = style.border;
      _strokeSide(rect.x, rect.y, rect.x + rect.w, rect.y, b.top);
      _strokeSide(rect.x, rect.y + rect.h, rect.x + rect.w, rect.y + rect.h,
          b.bottom);
      _strokeSide(rect.x, rect.y, rect.x, rect.y + rect.h, b.left);
      _strokeSide(rect.x + rect.w, rect.y, rect.x + rect.w, rect.y + rect.h,
          b.right);
    }

    for (var r = rowStart; r <= rowEnd; r++) {
      final h = layout.rows.sizeOf(r);
      if (h <= 0) continue;
      for (var c = colStart; c <= colEnd; c++) {
        if (sheet.mergeAt(r, c) != null) continue;
        paintCellBorder(
            r,
            c,
            (
              x: layout.cols.posOf(c),
              y: layout.rows.posOf(r),
              w: layout.cols.sizeOf(c),
              h: h
            ));
      }
    }
    for (final m in visibleMerges) {
      paintCellBorder(m.r1, m.c1, layout.cellRect(m.r1, m.c1));
    }
  }

  void _paintImages(Worksheet sheet, SheetLayout layout) {
    final imagesOfSheet = workbook.imagesBySheet[sheet.name];
    if (imagesOfSheet == null) return;
    for (final si in imagesOfSheet) {
      final img = images.imageFor(si.mediaPath, () => mediaBytes(si.mediaPath));
      if (img == null) continue;
      final x = layout.cols.posOf(si.fromCol) + si.fromColOff / kEmuPerPx;
      final y = layout.rows.posOf(si.fromRow) + si.fromRowOff / kEmuPerPx;
      final x2 = layout.cols.posOf(si.toCol) + si.toColOff / kEmuPerPx;
      final y2 = layout.rows.posOf(si.toRow) + si.toRowOff / kEmuPerPx;
      if (x2 > x && y2 > y) {
        ctx.drawImage(img, x, y, x2 - x, y2 - y);
      }
    }
  }

  void _paintSelection(SheetLayout layout, CellRange selection, CellRef active) {
    final x = layout.cols.posOf(selection.c1);
    final y = layout.rows.posOf(selection.r1);
    final w = layout.cols.posOf(selection.c2 + 1) - x;
    final h = layout.rows.posOf(selection.r2 + 1) - y;

    // Preenchimento translúcido, exceto sobre a célula ativa (4 retângulos
    // ao redor dela).
    final a = layout.cellRect(active.row, active.col);
    ctx.fillStyle = 'rgba(16,124,65,0.10)'.toJS;
    final topH = (a.y - y).clamp(0.0, h);
    final bottomY = a.y + a.h;
    final leftW = (a.x - x).clamp(0.0, w);
    final rightX = a.x + a.w;
    if (topH > 0) ctx.fillRect(x, y, w, topH);
    if (bottomY < y + h) ctx.fillRect(x, bottomY, w, y + h - bottomY);
    final midY = y + topH;
    final midH = (bottomY < y + h ? bottomY : y + h) - midY;
    if (midH > 0) {
      if (leftW > 0) ctx.fillRect(x, midY, leftW, midH);
      if (rightX < x + w) ctx.fillRect(rightX, midY, x + w - rightX, midH);
    }

    ctx.strokeStyle = '#107C41'.toJS;
    ctx.lineWidth = 2;
    ctx.strokeRect(x + 1, y + 1, w - 2, h - 2);

    // Alça de preenchimento.
    ctx.fillStyle = '#107C41'.toJS;
    ctx.fillRect(x + w - 3.5, y + h - 3.5, 6, 6);
    ctx.strokeStyle = '#FFFFFF'.toJS;
    ctx.lineWidth = 1;
    ctx.strokeRect(x + w - 3.5, y + h - 3.5, 6, 6);
  }

  void _paintHeaders(
      SheetLayout layout,
      int rowStart,
      int rowEnd,
      int colStart,
      int colEnd,
      double scrollX,
      double scrollY,
      double viewW,
      double viewH,
      double zoom,
      CellRange selection) {
    final headerW = kHeaderW * zoom;
    final headerH = kHeaderH * zoom;
    final fontPx = 11 * zoom;

    // Fundo dos headers.
    ctx.fillStyle = '#F5F5F5'.toJS;
    ctx.fillRect(0, 0, viewW, headerH);
    ctx.fillRect(0, 0, headerW, viewH);

    ctx.font = '${fontPx.toStringAsFixed(1)}px "Segoe UI", sans-serif';
    ctx.textBaseline = 'middle';

    // Colunas.
    ctx.save();
    ctx.beginPath();
    ctx.rect(headerW, 0, viewW - headerW, headerH);
    ctx.clip();
    for (var c = colStart; c <= colEnd; c++) {
      final w = layout.cols.sizeOf(c) * zoom;
      if (w <= 0) continue;
      final x = headerW + (layout.cols.posOf(c) - scrollX) * zoom;
      final selected = c >= selection.c1 && c <= selection.c2;
      if (selected) {
        ctx.fillStyle = '#CAEAD8'.toJS;
        ctx.fillRect(x, 0, w, headerH);
      }
      ctx.strokeStyle = '#C6C6C6'.toJS;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x + w + 0.5, 0);
      ctx.lineTo(x + w + 0.5, headerH);
      ctx.stroke();
      ctx.fillStyle = (selected ? '#0E6B39' : '#444444').toJS;
      final label = colName(c);
      final tw = measure(ctx.font, label);
      ctx.fillText(label, x + (w - tw) / 2, headerH / 2 + 1);
    }
    ctx.restore();

    // Linhas.
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, headerH, headerW, viewH - headerH);
    ctx.clip();
    for (var r = rowStart; r <= rowEnd; r++) {
      final h = layout.rows.sizeOf(r) * zoom;
      if (h <= 0) continue;
      final y = headerH + (layout.rows.posOf(r) - scrollY) * zoom;
      final selected = r >= selection.r1 && r <= selection.r2;
      if (selected) {
        ctx.fillStyle = '#CAEAD8'.toJS;
        ctx.fillRect(0, y, headerW, h);
      }
      ctx.strokeStyle = '#C6C6C6'.toJS;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, y + h + 0.5);
      ctx.lineTo(headerW, y + h + 0.5);
      ctx.stroke();
      ctx.fillStyle = (selected ? '#0E6B39' : '#444444').toJS;
      final label = '${r + 1}';
      final tw = measure(ctx.font, label);
      ctx.fillText(label, (headerW - tw) / 2, y + h / 2 + 1);
    }
    ctx.restore();

    // Bordas externas + canto.
    ctx.strokeStyle = '#B5B5B5'.toJS;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, headerH + 0.5);
    ctx.lineTo(viewW, headerH + 0.5);
    ctx.moveTo(headerW + 0.5, 0);
    ctx.lineTo(headerW + 0.5, viewH);
    ctx.stroke();
    ctx.textBaseline = 'alphabetic';
  }
}
