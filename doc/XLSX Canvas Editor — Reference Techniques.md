XLSX Canvas Editor — Reference Techniques
1. fortune-sheet (React canvas spreadsheet)
Rendering core: referencias/fortune-sheet-master/packages/core/src/canvas.ts (~2700 lines). A single Canvas class holds a reference to one <canvas> element plus a sheetCtx (the sheet context/state). React side wires it up in packages/react/src/components/Sheet/index.tsx: updateContextWithCanvas sizes the canvas, and a redraw useEffect (lines ~102-240) constructs new Canvas(...) and calls drawMain, drawColumnHeader, drawRowHeader on every context change. One canvas draws everything; headers and frozen panes are separate draw calls into the same canvas.

Main draw loop — drawMain({scrollWidth, scrollHeight, drawWidth, drawHeight, offsetLeft, offsetTop, ...}) (canvas.ts:511):

renderCtx.save(); renderCtx.scale(devicePixelRatio, devicePixelRatio) then optional clearRect (lines 583-595) — DPR handled by scaling the context, backing store sized ×DPR.
Visible range via binary search on cumulative pixel-offset arrays: _.sortedIndex(sheetCtx.visibledatarow, scrollHeight) → rowStart, and visibledatacolumn for cols (lines 603-629). visibledatarow/column are prefix-sum arrays of row heights / col widths — this is the virtualization: only rowStart..rowEnd × colStart..colEnd are iterated.
Per cell: resolve style via getStyleByCell, fill background, then renderCtx.fillText(...) (e.g. line 1096). Text measurement is cached (getMeasureText, measureTextCacheTimeOut at 537/1430) to avoid repeated measureText.
Merged cells: stored in sheetCtx.config.merge keyed "r_c" → {r,c,rs,cs} (row/col span). During border/cell draw the end pixel of the merge is looked up in a borderOffset["endRow_endCol"] map to get mergeCellEndX/Y (canvas.ts:1323-1341). API in core/src/modules/merge.ts and api/merge.ts.

Frozen rows/cols: core/src/modules/freeze.ts. frozenTofreezen() converts frozen:{type:"row"|"column"|"both", range:{row_focus,column_focus}} into a freezen cache with horizontal/vertical split data built by slicing visibledatarow/column at the focus index (cutVolumn). The Sheet redraw effect then issues four drawMain calls for the four quadrants with different scrollWidth/scrollHeight offsets (Sheet/index.tsx:120-240) — top-left frozen quadrant uses raw scrollLeft/scrollTop, others add the pane offset.

Selection: drawn on separate DOM overlay layers, not the main canvas — packages/react/src/components/SheetOverlay/ (index.tsx, ColumnHeader.tsx, RowHeader.tsx). Selection state in core/src/modules/selection.ts.

In-cell editor IS a DOM overlay (not canvas): packages/react/src/components/SheetOverlay/InputBox.tsx — an absolutely-positioned <div class="luckysheet-input-box"> whose left/top/minWidth/minHeight come from the selected cell rect (firstSelection.left/top/width/height), containing a contentEditable (ContentEditable.tsx, id luckysheet-rich-text-editor). Cell style is copied onto the box via getStyleByCell and it is scaled with transform: scale(zoomRatio). Scrollbars are also DOM overlays: SheetOverlay/ScrollBar/index.tsx.

2. FortuneExcel / SheetJS — XLSX parsing
(Note: referencias/sheetjs-github contains only demos, no bundled xlsx.js. The real parser is FortuneExcel.)

Parser: referencias/FortuneExcel-main/src/ToFortuneSheet/. ReadXml.ts is a regex-based XML reader (no DOM): getElementsByOneTag builds a regex per tag, Element parses attributes with /[a-zA-Z0-9_:]*?=".*?"/g. FortuneFile.ts orchestrates which parts are read (lines 50-98):

sharedStrings.xml → sharedStrings (sharedStringsFile)
styles.xml → cellXfs/xf, cellStyleXfs/xf, cellStyles, fonts/font, fills/fill, borders/border, numFmts/numFmt
theme1.xml → clrScheme via tag list a:dk1|a:lt1|a:dk2|a:lt2|a:accent1..6|a:hlink|a:folHlink, plus colors/indexedColors/rgbColor and mruColors
workbook.xml.rels (workbookRelList) matched against /worksheets\/[^/]*?.xml/ to map sheet r:id → file; sheet list from workbook.xml.
Style resolution (FortuneCell.ts:64-260): cell attribute s indexes into cellXfs[s]; from that xf read numFmtId, fontId, fillId, borderId gated by applyNumberFormat/applyFont/applyFill/applyBorder flags. Then dereference fonts[fontId], fills[fillId] (patternFill/fgColor), borders[borderId], and numfmts[numFmtId] for the format code.

Color theme/indexed mapping — ReadXml.ts getColor() (line 259): priority indexed → rgb → theme. Indexed colors merged from theme's indexedColors over the built-in indexedColors table in common/constant.ts (combineIndexedColor). Theme index remapping (lines 287-297): Excel swaps the first four theme slots — 0↔1 (dk1/lt1) and 2↔3 (dk2/lt2) — before indexing clrScheme; sysClr uses lastClr else val. tint applied via LightenDarkenColor(bg, tint) (common/method.ts). rgb/indexed take the last 6 hex chars (strips alpha), prefixed #.

Merged cells: FortuneSheet.ts:97-287 reads mergeCells/mergeCell ref="A1:B2", converts via getcellrange to {r,c,rs,cs} keyed "r_c" in config.merge — same shape fortune-sheet renders.

Column widths / defaults: FortuneSheet.ts:153-503 — defaultColWidth (9.21) / defaultRowHeight (19) from <sheetFormatPr>; per-col <col> width+customWidth converted by getColumnWidthPixel(charWidth) into config.columnlen[i] and config.customWidth. Char-width→pixel conversion lives in common/method.ts.

3. grid-master & GridPaper — virtualization / scrolling
grid-master (referencias/grid-master/packages/grid/src/Grid.tsx, react-konva Stage/Layer):

Fake DOM scrollbars over the canvas (JSX at 2622-2669): two absolutely-positioned overflow:scroll divs (.rowsncolumns-grid-scrollbar-y/-x, willChange:transform) each containing a 1px spacer sized to estimatedTotalHeight / estimatedTotalWidth. Their native onScroll (handleScroll/handleScrollLeft) drives React scrollTop/scrollLeft state — the canvas itself never scrolls.
Wheel handling: a wheel listener (added {passive} at 687) updates the scroll refs directly (verticalScrollRef.current.scrollTop += ...), decoupled from React for smoothness (wheelingRef rAF throttle).
Virtualization: getRowStartIndexForOffset / binary search over offsets → visibleRowStartIndex..StopIndex; only visible cells rendered as Konva nodes. estimatedRowHeight for unmeasured rows.
Frozen rows/cols: frozenRows/frozenColumns props render extra Konva groups at fixed offset with optional shadow; hit-testing (isWithinFrozenRowBoundary) keeps frozen cells at screen origin (lines 1092-1094).
Snap scrolling (snap) aligns to whole rows/cols on wheel via scrollSnapRefs.
Editable overlay is a DOM textarea: src/hooks/useEditable.tsx + CellOverlay.tsx (same DOM-overlay-editor pattern as fortune-sheet).
GridPaper (referencias/GridPaper-master/src/GridPaper.ts, paper.js): infinite-canvas model — a displayRect (world coords) vs bound; display() sets the paper view matrix (scale = w/(maxX-minX)) instead of moving pixels. DPR: reads paperProject.view.pixelRatio and divides canvas.width/height by it (lines 59-60). Grid lines are recomputed for the visible rect only (updateGridLines, choosing a grid series whose spacing exceeds a density threshold — major/minor lines, stroke width scaled by zoomFactor). UiController.ts renders the custom scrollbars/overlay.

Concrete techniques to adopt
Prefix-sum offset arrays + binary search (sortedIndex) for O(log n) visible-range → virtualization (fortune-sheet canvas.ts:603-629; grid-master getRowStartIndexForOffset).
ctx.scale(dpr,dpr) with backing store ×DPR; wrap draws in save/restore (canvas.ts:583).
Merge model {r,c,rs,cs} keyed "r_c", resolve merge end-pixel from an offset map (canvas.ts:1323).
Four-quadrant redraw with per-pane scroll offsets for frozen rows/cols (Sheet/index.tsx:120-240; freeze.ts).
In-cell editor as an absolutely-positioned contentEditable/textarea overlay mirroring cell rect+style, transform:scale(zoom) (InputBox.tsx).
Fake scrollbars: overflow:scroll div + oversized spacer, drive state from onScroll; canvas stays put (grid-master 2622-2669).
XLSX color resolution order indexed→rgb→theme, with Excel's 0↔1 / 2↔3 theme-slot swap and tint lighten/darken (ReadXml.ts:259).
Style deref chain: cell s → cellXfs[s] → font/fill/border/numFmt tables, gated by apply* flags (FortuneCell.ts).
(docxjs-master was listed but has no XLSX-relevant questions; not explored.)

Update Todos

Reconhecimento: pesquisas, referências, bibliotecas e XLSX alvo

Escrever plano/roteiro consolidado (doc/PLANO.md)

Núcleo de I/O: ZIP (inflate) + parser XML puro Dart

Modelo de dados: workbook, sheet, célula, estilos, tema

Parser XLSX: sharedStrings, styles, sheets, mesclagens, colunas

Motor de formato numérico (R$, #,##0.00, [Red], seções)

Motor de fórmulas: tokenizer, parser, avaliador, recálculo

Renderizador canvas: virtualização, grade, texto, bordas, mesclas

UI like-Excel: toolbar, barra de fórmulas, abas, editor de célula

Escrita XLSX (salvar) e carga do arquivo alvo

Compilar, testar no navegador com a planilha alvo
I have a comprehensive picture. Here is my report.

Pure-Dart reuse for an XLSX editor — findings by project
TOP PICK: canvas-editor-port/packages/* — purpose-built pure Dart, zero pub deps
These sibling packages (declared "G7: zero pub dependencies, only dart:core") are adapted from docx_dart and are the cleanest reuse targets. XLSX and DOCX share the same ZIP+OPC+XML container, so items 1–3 are directly reusable.

ZIP (item 1) — reusable as-is. packages/ce_zip/lib/
src/zip_archive.dart — ZipArchive/ZipEntry, reads End-Of-Central-Directory + central dir + local headers, and encode() writes them back (lines ~255–330). CRC32, local/central signatures present. ZIP64 explicitly unsupported (fine for typical xlsx).
src/codecs/zlib/deflate.dart, inflate.dart, _huffman_table.dart — raw DEFLATE/INFLATE, pure Dart.
src/util/{crc32,input_memory_stream,output_memory_stream,byte_order,input_stream,output_stream}.dart.
XML (item 2) — reusable as-is. packages/ce_xml/lib/ — depends only on dart:convert/dart:typed_data (NOT package:xml). src/sax.dart (XmlSaxParser, streaming for large parts like sheetN.xml), src/dom.dart (lightweight DOM), src/serializer.dart, namespace-aware.
OPC (item 3) — reusable as-is. packages/ce_opc/lib/ — src/content_types.dart ([Content_Types].xml), src/relationships.dart (_rels), src/opc_package.dart (part resolution over ce_zip+ce_xml). Container logic is format-agnostic; works for xlsx unchanged.
DOCX model (item 3) — adaptable (reference). packages/ce_docx/lib/src/ — reader.dart, writer.dart, styles.dart, numbering.dart, effective.dart (style-inheritance resolution), units.dart, model.dart. WordprocessingML-specific, but the reader/writer/styles-resolution pattern is a strong template for a parallel ce_xlsx (worksheets, styles.xml, sharedStrings, theme).
packages/ce_fonts/lib/ce_fonts.dart — single file; check for font metrics if needed.
canvas_text_editor — canvas rendering/measurement (item 4). Adaptable, depends only on package:web
Web-target canvas text layout + measurement, with a clean interop abstraction (swappable/testable).

lib/util/dom_api_web.dart — package:web + dart:js_interop wrapper; _DefaultCanvasRenderingContext2DApi wraps web.CanvasRenderingContext2D, measureTextWidth(t) => _ctx.measureText(t).width (line 191), getContext('2d') (line 210). lib/util/dom_api.dart = the interface, dom_api_stub.dart = non-web stub.
lib/render/text_measurer.dart — text width measurement via ctx; render/measure_cache.dart, metrics.dart, raster_cache.dart.
lib/render/canvas_page_painter.dart — ctx.font, ctx.fillText, cursor/background painting.
lib/layout/ — paragraph_layouter.dart, table_layouter.dart + table_row_layout.dart/table_layout_result.dart, paginator.dart, page_layout.dart, font_metrics.dart. The table layouter/renderer is the closest thing to a grid and is the best starting point to adapt into an XLSX cell-grid renderer.
Note import package name is dart_text_editor (pubspec name: is canvas_text_editor) — a rename/path fixup is needed when reusing.
docx_rendering — OOXML parsing + web rendering reference. Adaptable, only depends on package:web
Own pure ZIP copy: lib/src/zip/zip_archive.dart (+ codecs/zlib/, util/) — imports its local deflate/inflate, no archive/xml pkg.
lib/src/parser/ — document_parser_styles.dart, document_parser_runs.dart, document_parser_tables.dart, xml_parser.dart (own XML parser).
OOXML infra reusable for xlsx: lib/src/common/{content_types,open_xml_package,part,relationship}.dart, lib/src/styles/styles_part.dart, lib/src/theme/{theme,theme_part}.dart (theme handling — directly relevant to xlsx theme1.xml).
docx_dart — original superset. Adaptable, but NOT pure (needs package:xml)
pubspec deps: xml, image, crypto, collection, path. Its lib/src/internal/archive/ (codecs/zlib + util) IS self-contained pure ZIP (the source ce_zip was copied from). Rich OPC (lib/src/opc/*: package, pkgreader, pkgwriter, rel, content-types) and OOXML (lib/src/oxml/*, lib/src/styles/*). Prefer the already-de-dependency'd ce_* packages over this.

Lower-value for an XLSX-editor core
jsPDF — pure Dart (no runtime deps, web commented out); adaptable for PDF export only, not xlsx core.
dart_graphics — 2D graphics but not useful as-is: depends on image, xml, csslib, archive, ffi, vector_math (native/raster oriented).
aggr (AGG port) — not useful: depends on ffi, native_synchronization, image, excel; native raster, not web canvas.
itext / pdfbox_dart — PDF libs depending on archive+xml; not useful for xlsx.
dart_quill — AngularDart rich-text editor (ngdart, ngforms); not useful for a canvas grid.
Recommendation
Build the XLSX editor on the four canvas-editor-port/packages/ce_zip|ce_xml|ce_opc (reuse as-is for container/XML/OPC) + model a new ce_xlsx after ce_docx's reader/writer/styles pattern, and reuse canvas_text_editor's dom_api_web.dart + text_measurer.dart + table_layouter.dart for the canvas grid rendering/measurement layer. All are pure Dart or package:web-only — no archive/xml pub packages required.

