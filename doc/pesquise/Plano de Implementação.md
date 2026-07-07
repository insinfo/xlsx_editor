Plano de Implementação — Editor de Planilhas XLSX em Dart Puro (package:web + Canvas)

Projeto: xlsx_editor
Alvo: Dart Web puro (dart2js / dart compile js), sem Flutter, sem dart:html (deprecated no Dart 3.7+), usando exclusivamente package:web ^1.1.1 + dart:js_interop.
SDK: ^3.6.0
Caso de uso de referência: PGCTIC1 - PE - Planilha de Economicidade - Gestão Pública.xlsx (planilha de economicidade de pregão eletrônico — células mescladas, moeda R$, fórmulas, bordas, cabeçalhos coloridos).


0. Fundamentação da pesquisa (estado da arte)

ProjetoLicençaRenderizaçãoXLSXStatusLição para nósUniver (dream-num)Apache 2.0 (core)Canvas (engine própria) + fórmulas em Web WorkerImport/export XLSX é recurso pago/proAtivo, referência atualArquitetura em camadas: engine-render, engine-formula, sheets, sheets-ui como módulos separados. Command system + mutations para undo/redo e colaboração.LuckysheetMITDOM (tabelas HTML)Import/export via LuckyExcelArquivado (migrado p/ Univer)DOM não escala: milhares de células = milhares de nós. Confirma a escolha por canvas.x-spreadsheet / wolf-tableMITCanvas puro, código pequenoParcialMigrado p/ wolf-tableMelhor código-fonte para estudar: grid virtual, scroll próprio, seleção, tudo em ~poucos KLOC.canvas-datagridMITCanvas único, immediate modeNão (é grid, não workbook)Estável"Data size does not impact performance" — desenho apenas do viewport.ONLYOFFICE DocsAGPL v3CanvasFidelidade OOXML totalAtivoProva que canvas dá conta de 100% do OOXML, mas AGPL contamina e o código é gigantesco.Jspreadsheet CE / HandsontableMIT / comercialDOMParcialAtivosAlternativas DOM; boas para grids pequenos, não para fidelidade Excel.Google Sheets / Google DocsproprietárioCanvas (Sheets sempre foi; Docs migrou de DOM→Canvas em 2021)——Padrão validado: canvas para pintura + DOM paralelo para acessibilidade e editor de célula (textarea/input sobreposto).

Decisões que a pesquisa impõe:


Renderização: canvas 2D em modo imediato, desenhando somente o viewport (virtualização). É o modelo do Google Sheets, Univer, x-spreadsheet e canvas-datagrid.
DOM auxiliar mínimo: um <input>/<textarea> invisível/flutuante para edição de célula e captura de IME/teclado, scrollbars sintéticas ou nativas via container, e uma camada de acessibilidade opcional (padrão "side DOM" do Google).
I/O XLSX: como o import/export fiel do Univer é pago e nada existe pronto em Dart com renderização, o diferencial do projeto é justamente unir um leitor/escritor XLSX Dart (baseado em archive + xml, com estratégia de preservação byte-a-byte das partes não modeladas, como faz o excel_plus) ao renderer canvas.
Arquitetura em camadas independentes (modelo ⟂ fórmulas ⟂ render ⟂ UI), como o Univer, para permitir testes em VM pura (sem browser) de tudo que não é pintura.



1. Visão geral da arquitetura

┌──────────────────────────────────────────────────────────────┐
│                        APP (main.dart)                       │
│  bootstrap, toolbar, formula bar, abas de sheets, file open  │
├──────────────────────────────────────────────────────────────┤
│  UI / INTERAÇÃO (package:web + dart:js_interop)              │
│  SpreadsheetView, InputController (mouse/teclado/wheel/IME), │
│  CellEditorOverlay (input DOM), ClipboardBridge,             │
│  ScrollController, ContextMenu, ResizeHandles                │
├──────────────────────────────────────────────────────────────┤
│  RENDER ENGINE (canvas 2D)                                   │
│  GridRenderer, CellRenderer, SelectionRenderer,              │
│  HeaderRenderer, FreezePaneCompositor, TextMeasurer(cache),  │
│  DirtyRegionScheduler (requestAnimationFrame)                │
├──────────────────────────────────────────────────────────────┤
│  VIEWMODEL / LAYOUT (Dart puro, testável em VM)              │
│  ViewportState, RowColLayout (posições acumuladas),          │
│  MergeResolver, RenderCell (célula já resolvida p/ pintura)  │
├──────────────────────────────────────────────────────────────┤
│  CORE MODEL (Dart puro)                                      │
│  Workbook, Worksheet, Cell (sparse), StyleTable,             │
│  NumberFormatter (ECMA-376 numFmt), CommandStack (undo/redo) │
├──────────────────────────────────────────────────────────────┤
│  FORMULA ENGINE (Dart puro, opcional/fase tardia)            │
│  Tokenizer, Parser (AST), DependencyGraph, Evaluator         │
├──────────────────────────────────────────────────────────────┤
│  XLSX I/O (Dart puro)                                        │
│  XlsxReader / XlsxWriter (archive + xml),                    │
│  PreservationStore (partes OPC não modeladas, round-trip)    │
└──────────────────────────────────────────────────────────────┘

Regra de ouro: tudo abaixo de "RENDER ENGINE" não importa package:web — roda e é testado na Dart VM (dart test), no seu estilo de testes de integração reais do backend SALI. Só a camada de render/UI toca browser API.

1.1 pubspec.yaml

yamlname: xlsx_editor
description: Editor de planilhas XLSX renderizado em canvas, Dart web puro.
environment:
  sdk: ^3.6.0

dependencies:
  web: ^1.1.1          # bindings browser modernos (substitui dart:html)
  archive: ^3.6.1      # ZIP (container OPC do xlsx)
  xml: ^6.5.0          # parser/serializer XML (com suporte a eventos/SAX)
  intl: ^0.19.0        # locale pt_BR p/ números e datas (apoio ao numFmt)
  collection: ^1.18.0

dev_dependencies:
  build_runner: ^2.4.13
  build_web_compilers: ^4.0.11   # atenção: fixar versão compatível com SDK 3.6.x
  test: ^1.25.0
  lints: ^5.0.0


Nota (seu contexto): você já topou com os bugs de dart2js/AngularDart com build_web_compilers no SDK 3.6.2 por causa da deprecação do dart:html. Este projeto evita o problema na raiz: zero dart:html, só package:web + dart:js_interop, que é o caminho suportado no 3.6 e obrigatório do 3.7 em diante (e compatível com futura compilação WASM).



1.2 Estrutura de diretórios

xlsx_editor/
├── pubspec.yaml
├── web/
│   ├── index.html
│   ├── main.dart
│   └── styles.css
├── lib/
│   ├── src/
│   │   ├── core/
│   │   │   ├── workbook.dart
│   │   │   ├── worksheet.dart
│   │   │   ├── cell.dart              # CellValue sealed class
│   │   │   ├── cell_address.dart      # A1 <-> (row,col), ranges
│   │   │   ├── style/
│   │   │   │   ├── style_table.dart   # xf indexado (como styles.xml)
│   │   │   │   ├── font.dart
│   │   │   │   ├── fill.dart
│   │   │   │   ├── border.dart
│   │   │   │   ├── alignment.dart
│   │   │   │   └── number_format.dart # motor de numFmt ECMA-376
│   │   │   ├── merge.dart
│   │   │   └── commands/
│   │   │       ├── command.dart       # Command/undo/redo
│   │   │       ├── set_cell_value.dart
│   │   │       ├── set_style.dart
│   │   │       ├── row_col_ops.dart
│   │   │       └── command_stack.dart
│   │   ├── formula/
│   │   │   ├── tokenizer.dart
│   │   │   ├── parser.dart            # AST
│   │   │   ├── evaluator.dart
│   │   │   ├── dependency_graph.dart
│   │   │   └── functions/             # SUM, IF, VLOOKUP, ...
│   │   ├── xlsx/
│   │   │   ├── xlsx_reader.dart
│   │   │   ├── xlsx_writer.dart
│   │   │   ├── opc_package.dart       # ZIP + [Content_Types] + rels
│   │   │   ├── shared_strings.dart
│   │   │   ├── styles_reader.dart
│   │   │   ├── styles_writer.dart
│   │   │   ├── sheet_reader.dart      # SAX streaming
│   │   │   ├── sheet_writer.dart
│   │   │   ├── theme_reader.dart      # theme1.xml (cores indexadas/tint)
│   │   │   └── preservation_store.dart
│   │   ├── layout/
│   │   │   ├── row_col_layout.dart    # offsets acumulados + busca binária
│   │   │   ├── viewport.dart
│   │   │   └── merge_resolver.dart
│   │   ├── render/
│   │   │   ├── canvas_context.dart    # wrapper fino sobre CanvasRenderingContext2D
│   │   │   ├── grid_renderer.dart
│   │   │   ├── cell_renderer.dart
│   │   │   ├── header_renderer.dart
│   │   │   ├── selection_renderer.dart
│   │   │   ├── freeze_compositor.dart
│   │   │   ├── text_measurer.dart     # cache de measureText
│   │   │   └── render_scheduler.dart  # rAF + dirty flags
│   │   └── ui/
│   │       ├── spreadsheet_view.dart  # componente raiz
│   │       ├── input_controller.dart
│   │       ├── cell_editor_overlay.dart
│   │       ├── scroll_controller.dart
│   │       ├── clipboard_bridge.dart
│   │       ├── formula_bar.dart
│   │       ├── sheet_tabs.dart
│   │       └── context_menu.dart
│   └── xlsx_editor.dart               # exports públicos
└── test/
    ├── core/ ...                      # roda na VM
    ├── formula/ ...
    ├── xlsx/
    │   ├── roundtrip_test.dart        # abre→salva→reabre→compara
    │   └── resources/
    │       └── PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx
    └── layout/ ...


2. Fase 0 — Inspeção da planilha alvo (1 dia)

Antes de escrever qualquer código de produção, inventariar exatamente o que a planilha de economicidade usa. Um .xlsx é um ZIP; abrir e listar:

bashcd resources
unzip -l "PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx"
# extrair e examinar:
# xl/workbook.xml        -> sheets, definedNames
# xl/worksheets/sheet1.xml -> mergeCells, cols (larguras), rows (alturas),
#                             tipos de célula (t="s|n|str|b|inlineStr"), fórmulas <f>
# xl/styles.xml          -> numFmts custom (R$!), fonts, fills, borders, cellXfs
# xl/sharedStrings.xml   -> strings (com ou sem rich text <r>)
# xl/theme/theme1.xml    -> paleta de cores do tema
# xl/printerSettings, drawings, etc. -> partes a PRESERVAR, não modelar

Checklist a produzir (vira o "contrato de escopo" do renderer):


 Quantas sheets? Alguma oculta?
 mergeCells — quantidade e padrões (títulos mesclados em várias colunas é típico).
 numFmts customizados — planilhas de economicidade quase sempre têm "R$"\ #,##0.00 e percentuais.
 Fórmulas usadas — inventariar funções (SUM, IF, ROUND, VLOOKUP?) para priorizar o formula engine.
 Bordas/fills/cores de tema (cor via theme + tint exige theme1.xml).
 Larguras de coluna (<col customWidth>) e alturas de linha customizadas.
 Congelamento de painéis (<pane> em sheetView)?
 Validação de dados, comentários, imagens, drawing? (→ PreservationStore, não renderizar na v1).


Ferramenta interna: escrever tool/inspect_xlsx.dart (CLI, Dart VM) que imprime esse relatório — reutilizável para qualquer planilha da prefeitura.


3. Fase 1 — Core Model (semana 1)

3.1 Endereçamento

dart/// Imutável, barato, usado como chave.
extension type const CellRef._(int _packed) {
  const CellRef(int row, int col) : _packed = (row << 20) | col; // até ~1M linhas
  int get row => _packed >> 20;
  int get col => _packed & 0xFFFFF;

  static CellRef parseA1(String a1) { /* "B7" -> CellRef(6,1) */ ... }
  String toA1() { ... }
}

class CellRange {
  final CellRef start, end; // normalizado (start <= end)
  bool contains(CellRef ref) { ... }
  Iterable<CellRef> get cells sync* { ... }
}

Usar extension type (Dart 3.3+) para CellRef dá custo zero de alocação — importante porque o render loop cria milhares por frame.

3.2 Valor de célula (sealed class, padrão do próprio pacote excel v4)

dartsealed class CellValue { const CellValue(); }
final class TextValue extends CellValue { final String text; ... }        // pode ter rich text depois
final class NumberValue extends CellValue { final double value; ... }
final class BoolValue extends CellValue { final bool value; ... }
final class DateTimeValue extends CellValue { final DateTime value; ... } // serial date Excel
final class FormulaValue extends CellValue {
  final String formula;        // sem o '='
  CellValue? cached;           // último resultado (do arquivo ou do evaluator)
  final String? sharedIndex;   // shared formulas <f t="shared" si="n">
}
final class ErrorValue extends CellValue { final String code; ... }       // #DIV/0! etc.

3.3 Armazenamento esparso

Planilhas reais são esparsas. Não usar matriz densa:

dartclass Worksheet {
  final String name;
  // linha -> (coluna -> célula). SplayTreeMap mantém ordem p/ serialização.
  final SplayTreeMap<int, SplayTreeMap<int, Cell>> _rows = SplayTreeMap();

  final Map<int, double> customRowHeights = {};   // em pontos
  final Map<int, double> customColWidths = {};    // em "chars" (unidade OOXML)
  final Set<int> hiddenRows = {}, hiddenCols = {};
  final List<CellRange> merges = [];
  FreezePane? freeze;                              // xSplit/ySplit
  int maxRow = 0, maxCol = 0;                      // bounding box usado
}

class Cell {
  CellValue? value;
  int styleIndex;   // índice no StyleTable (espelha cellXfs do styles.xml)
}

3.4 StyleTable — espelhar o modelo do styles.xml

Não "achatar" estilos por célula. O OOXML já é normalizado (fonts[], fills[], borders[], numFmts[], cellXfs[] que referenciam por índice). Manter essa estrutura:


round-trip do arquivo fica trivial (índices preservados);
render usa styleIndex como chave de cache (ex.: fonte CSS string pré-computada por xf).


dartclass StyleTable {
  final List<NumFmt> numFmts;     // builtin 0..49 + custom >=164
  final List<FontStyle> fonts;
  final List<Fill> fills;
  final List<Border> borders;
  final List<CellXf> cellXfs;     // {numFmtId, fontId, fillId, borderId, alignment, aplicações}
  final ThemePalette theme;       // resolve <color theme="4" tint="0.4"/>
  ResolvedStyle resolve(int xfIndex) { ... } // com cache
}

3.5 NumberFormatter (ECMA-376 numFmt) — crítico para a sua planilha

O formato "R$ "#,##0.00 e datas dd/mm/yyyy são o coração visual de uma planilha de economicidade. Implementar um subconjunto pragmático do minilinguagem numFmt:


Split em até 4 seções por ; (positivo;negativo;zero;texto).
Tokens: 0 # ? . , % E+ "literal" \x @ [Red] [$-pt-BR] d m y h s AM/PM.
Detecção de formato de data (presença de d/m/y/h/s fora de literais) → converter serial date (base 1899-12-30, cuidado com o bug do ano 1900 do Excel).
Agrupamento de milhar e decimal conforme pt_BR quando aplicável (o Excel grava o formato "neutro" e a exibição depende do locale — decidir e documentar: fixar pt_BR).


Testes de unidade exaustivos aqui (é onde bugs visuais nascem): 1234.5 + #,##0.00 → 1.234,50; -10 + "R$" #,##0.00;[Red]("R$" #,##0.00) → vermelho e parênteses; serial 45000 + dd/mm/yyyy → data correta.

3.6 Command stack (undo/redo desde o dia 1)

Padrão Command com inverso explícito (mesma filosofia de mutations do Univer):

dartabstract interface class SheetCommand {
  void apply(Workbook wb);
  SheetCommand invert(Workbook wb); // capturado ANTES do apply
  String get label;                  // "Editar B7", p/ UI de undo
}

CommandStack com limite (ex. 200), agrupamento (digitação contínua = 1 undo) e notificação de dirty ranges para o renderer.


4. Fase 2 — XLSX I/O com preservação (semanas 2–3)

4.1 Leitura (XlsxReader)

Pipeline (tudo Dart VM-testável):


archive.decodeBytes(bytes) → arquivos do pacote OPC.
[Content_Types].xml + _rels/.rels + xl/_rels/workbook.xml.rels → mapear partes.
xl/sharedStrings.xml → List<String> (concatenar runs <r> na v1; guardar rich text bruto para preservação).
xl/styles.xml → StyleTable (inclusive numFmts custom).
xl/theme/theme1.xml → paleta (10 cores + tint math: aplicar tint sobre HSL/luminância conforme spec).
Para cada sheet: parser de eventos (SAX) do package:xml (XmlEventDecoder) em vez de DOM — a lição de performance do excel_plus. Ler <cols>, <row r= ht= hidden=>, <c r= s= t=><v/><f/></c>, <mergeCells>, <sheetView><pane/>.
PreservationStore: todo arquivo do ZIP que não foi modelado (drawings, printerSettings, calcChain — este pode ser descartado —, vmlDrawing, comentários, pivots) é guardado byte a byte e re-emitido no save. É isso que garante que a planilha da prefeitura volte íntegra mesmo com recursos que o editor não entende.


4.2 Escrita (XlsxWriter)


Reescrever somente: sheets tocadas, sharedStrings (append-only quando possível), styles (se houve estilo novo), workbook.xml se estrutura mudou.
Partes não tocadas: copiar do PreservationStore.
Remover xl/calcChain.xml se qualquer fórmula mudou (Excel regenera) e ajustar [Content_Types].xml/rels de acordo.
Gravar <v> cacheado das fórmulas quando o evaluator tiver resultado; caso contrário, omitir <v> (Excel recalcula ao abrir).


4.3 Teste de round-trip com a planilha real

roundtrip_test.dart: abrir a PGCTIC1 → salvar sem edições → reabrir → comparar modelo a modelo (valores, estilos resolvidos, merges, larguras). Segundo teste: abrir no LibreOffice/Excel manualmente e validar visual. Este teste é o gate da fase.


Decisão make vs. buy: avaliar seriamente usar excel_plus (ou excel_community) como camada I/O pronta na v1 e só escrever o reader próprio se faltar fidelidade (rich text, panes, cores de tema). O plano acima descreve o reader próprio para o caso de você querer controle total — que combina com seu histórico —, mas começar com excel_plus corta ~2 semanas.




5. Fase 3 — Layout & Viewport (semana 3)

5.1 Conversão de unidades (fonte clássica de bugs)


Largura de coluna OOXML é em "caracteres da fonte padrão": px ≈ trunca((chars * 7 + 5)) para Calibri 11 (usar a fórmula da spec com MDW=7). Pré-computar colWidthPx[i].
Altura de linha é em pontos: px = pt * 96 / 72 (depois multiplicado por devicePixelRatio só na pintura).


5.2 RowColLayout — offsets acumulados + busca binária

dartclass AxisLayout {
  // offsets[i] = posição inicial (px lógicos) da linha/coluna i
  // reconstruído lazy quando alturas/larguras mudam (dirty a partir do índice i)
  final List<double> _offsets;
  double offsetOf(int index) { ... }
  double sizeOf(int index) { ... }
  int indexAt(double px) { /* busca binária */ }
  (int first, int last) visibleRange(double scrollPx, double viewportPx) { ... }
}

Com isso o cálculo "quais células estão visíveis" é O(log n) e o render é O(células visíveis), independente do tamanho da planilha — o princípio do canvas-datagrid.

5.3 MergeResolver

Pré-indexar merges num mapa anchorRef -> range + coveredRef -> anchorRef. No render: célula coberta não desenha conteúdo nem bordas internas; a âncora desenha com width = soma das colunas do range, com clipping. Seleção e navegação por teclado tratam o merge como uma célula única (pular células cobertas em Tab/Enter/setas).


6. Fase 4 — Render Engine em Canvas (semanas 4–5)

6.1 Setup com package:web (sem dart:html)

dartimport 'dart:js_interop';
import 'package:web/web.dart';

class CanvasSurface {
  final HTMLCanvasElement canvas;
  final CanvasRenderingContext2D ctx;
  double dpr = 1;

  CanvasSurface(this.canvas)
      : ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

  void resize(double cssWidth, double cssHeight) {
    dpr = window.devicePixelRatio;
    canvas.width = (cssWidth * dpr).round();
    canvas.height = (cssHeight * dpr).round();
    canvas.style.width = '${cssWidth}px';
    canvas.style.height = '${cssHeight}px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); // desenhar em px lógicos
  }
}

Pontos de atenção package:web/js_interop:


Callbacks: void Function(Event) → .toJS (ex.: canvas.addEventListener('pointerdown', _onDown.toJS)).
requestAnimationFrame(_frame.toJS).
ResizeObserver para o container (disponível no package:web; senão, window.onresize + fallback).
Alinhamento de linhas de grade: desenhar em y + 0.5 (coordenada de meio-pixel) com lineWidth 1 para grade nítida; ou arredondar para device pixels ((y*dpr).round()/dpr).


6.2 Pipeline de um frame

frame(t):
  if (!dirty) return;
  clipRegions = FreezeCompositor.regions(viewport, freeze)
  // 4 regiões no pior caso: congelada-topo-esq, topo, esquerda, corpo
  for region in clipRegions:
    ctx.save(); ctx.beginPath(); ctx.rect(region); ctx.clip();
    ctx.translate(-scrollX*region.scrollFactorX, -scrollY*region.scrollFactorY);
    1. fundo branco / fills de célula (por RUN de células contíguas c/ mesmo fill)
    2. linhas de grade (2 loops: verticais, horizontais — 2 paths batched)
    3. conteúdo das células:
         para cada (row, col) em visibleRange:
           cell = sheet.cellAt(row,col); if coberta por merge -> skip
           style = styleTable.resolve(cell.styleIndex)
           text = numberFormatter.format(cell.value, style.numFmt)
           cellRenderer.draw(ctx, rect, text, style)   // align, wrap, overflow
    4. bordas (por cima da grade: bordas OOXML têm precedência)
    5. merges (redesenho da âncora sobre a área mesclada)
    ctx.restore();
  6. headers (A,B,C / 1,2,3) + canto
  7. seleção (borda 2px accent + fill translúcido + fill handle)
  8. cursor de célula ativa
  dirty = false

Otimizações na ordem em que valem a pena:


Batch de estado do ctx: agrupar células por font string e por fillStyle (mudar ctx.font é caro).
TextMeasurer com cache: Map<(font, text), double> para measureText().width; invalidar nunca (imutável). Overflow de texto (célula vizinha vazia → texto vaza, senão → clip) exige saber a largura.
Dirty flags grossas primeiro (frame inteiro), dirty-rect por região só se necessário — para uma planilha de economicidade (algumas centenas de linhas), repintar o viewport inteiro a 60fps é tranquilo (~2k células visíveis).
Camada separada (2º canvas absoluto por cima) apenas para seleção/cursor, para piscar cursor e arrastar seleção sem repintar conteúdo.


6.3 CellRenderer — detalhes de fidelidade Excel


Alinhamento default por tipo: texto→esquerda, número/data→direita, bool/erro→centro (quando xf não especifica).
wrapText: quebra por palavras usando TextMeasurer; a altura da linha NÃO cresce automaticamente na v1 (respeitar ht do arquivo, como o Excel salvo).
indent, shrinkToFit (reduzir fonte até caber — iterativo com cache), rotação de texto (fase posterior; usar ctx.rotate).
Número que não cabe → #### como no Excel (opcional; ou clip simples na v1).
Fonte: mapear Calibri → stack CSS 'Calibri, "Segoe UI", Arial, sans-serif'; carregar métricas após document.fonts.ready para não medir com fonte fallback.



7. Fase 5 — Interação e edição (semanas 6–7)

7.1 Scroll

Modelo Google Sheets: o canvas ocupa 100% do container; scroll é sintético:


wheel (com preventDefault) → acumula deltas → clamp em [0, contentSize - viewport] → marca dirty. Suporte a deltaMode (linhas vs px) e inércia natural do trackpad.
Scrollbars: v1 usa scrollbars desenhadas no canvas (thumb proporcional, drag); alternativa mais rápida de implementar: um div "espaçador" com overflow nativo sincronizado (técnica comum, mas limita a ~15M px de altura por limites do browser — suficiente aqui).
Scroll alinhado a linhas (como Excel) ou por pixel (como Sheets) — decidir; por pixel é mais simples e agradável.


7.2 Mouse/ponteiro


pointerdown no corpo → hit test (AxisLayout.indexAt) → seleciona célula/inicia arrasto de range; setPointerCapture para arrasto sair do canvas.
Headers: clique seleciona linha/coluna inteira; bordas do header com cursor col-resize/row-resize → arrasto redimensiona (Command → undo).
Duplo clique na borda do header → autofit (usar TextMeasurer na coluna visível).
Duplo clique em célula → editar. Clique com Shift → estende seleção. Ctrl → multi-range (fase posterior).


7.3 Teclado + IME — o "side DOM"

Um <input type="text"> posicionado fora da tela (ou 0×0 sobre a célula ativa) mantém foco sempre:


Setas/Tab/Enter/PageUp/Home → navegação (interceptar keydown, preventDefault).
Digitar caractere imprimível → entra em modo edição ("replace"), F2 → modo edição "append" (distinção clássica Excel de navegação por setas dentro/fora da edição).
IME/acentos (pt-BR: ~, ´, ç) funcionam de graça porque a digitação real acontece no input DOM — este é exatamente o motivo do padrão side-DOM do Google Docs/Sheets.


7.4 CellEditorOverlay

Ao editar: posicionar um <div contenteditable>/<input> absoluto exatamente sobre o rect da célula (mesma fonte, mesmo alinhamento, borda accent), crescendo para a direita como no Excel. Commit em Enter/Tab/clicar fora (→ SetCellValueCommand, com parsing: =...→fórmula, número pt-BR 1.234,56, data dd/mm/aaaa, senão texto). Esc cancela. Sincronizado com a formula bar.

7.5 Clipboard


copy/cut/paste via eventos de clipboard no input focado (ClipboardEvent.clipboardData): escrever/ler text/plain (TSV) e text/html (<table> com estilos inline) — é assim que Excel web e Google Sheets interoperam com o Excel desktop.
Paste: parsear TSV → range; se HTML <table> presente, extrair estilos básicos (bold, bg-color). Colar de/para o Excel real é critério de aceite.



8. Fase 6 — Formula Engine (semanas 8–9, incremental)

A v1 pode exibir valores cacheados (<v>) sem calcular nada — o arquivo já traz os resultados. O engine entra para edição:


Tokenizer: números, strings, refs (A1, $A$1, Sheet2!A1, ranges A1:B9), operadores, funções, separador de argumentos (atenção: arquivo grava ,; UI pt-BR usa ; — traduzir na borda da UI).
Parser → AST (precedência: : espaço , % ^ * / + - & = < > conforme spec).
DependencyGraph: cell → precedentes/dependentes; recálculo topológico incremental; detecção de ciclo → #REF!/aviso circular.
Evaluator + funções: implementar primeiro o conjunto que a Fase 0 encontrou na PGCTIC1 (aposta: SUM, ROUND, IF, aritmética, AVERAGE, talvez VLOOKUP). Coerções Excel (texto-número, boolean), propagação de erros.
Ajuste de referências ao inserir/deletar linhas/colunas (rewrite do AST → re-serializar fórmula).


Cada peça é 100% testável na VM com casos extraídos da própria planilha (comparar com os <v> cacheados do arquivo — um dataset de teste gratuito e perfeito).


9. Fase 7 — Shell da aplicação (semana 10)


index.html mínimo + main.dart: toolbar (bold/italic, cor, formato de número R$/%, merge, bordas), formula bar (Name Box + fx), abas de sheets, status bar (soma/média da seleção — feature querida de quem confere economicidade).
Abrir arquivo: <input type=file> → File.arrayBuffer() (JSPromise → .toDart) → Uint8List → XlsxReader. Drag & drop no canvas.
Salvar: XlsxWriter → Blob → URL.createObjectURL → <a download>. (Depois: File System Access API onde disponível.)
Atalhos: Ctrl+Z/Y, Ctrl+C/X/V, Ctrl+B/I, Ctrl+S (salvar), Ctrl+Home/End, Ctrl+setas (salto para borda de dados).



10. Fase 8 — Qualidade, performance e entrega (semanas 11–12)


Golden tests de render: headless via dart test -p chrome desenhando em OffscreenCanvas/canvas e comparando toDataURL com imagens de referência (diffs de imagem — como a comunidade observa, testar canvas por image-diff é até mais direto que testar DOM).
Benchmarks: abrir planilha 100k células < 1s; scroll a 60fps; digitação sem latência perceptível (<16ms por commit+repaint).
dart compile js -O2 + análise de tamanho do bundle; lazy-init do formula engine.
Acessibilidade mínima: role="grid" no container, aria-live anunciando célula ativa/valor (o side DOM já existe para o input — anexar aria nele), navegação 100% por teclado.
Documentação: README com arquitetura, guia de extensão de funções de fórmula, limitações conhecidas (sem gráficos/pivots — preservados no round-trip mas não renderizados).



11. Riscos e mitigação

RiscoImpactoMitigaçãoFidelidade numFmt/locale pt-BRValores de R$ errados = inaceitável no domínioSuite de testes dirigida pelos formatos reais extraídos da PGCTIC1 (Fase 0)Métricas de fonte divergem do ExcelLarguras/quebras diferentesAceitar aproximação (todos os web spreadsheets divergem); autofit própriobuild_web_compilers × SDK 3.6.xJá te mordeu no AngularDartZero dart:html; pinar versões; smoke test de build no CI desde a semana 1Scroll/wheel inconsistente entre browsersUX ruim (vide reclamações históricas do Luckysheet)Normalizar deltaMode, testar Chrome/Firefox/Edge, nunca scrolljack fora do canvasEscopo de fórmulas explodirAtrasoEngine só cobre o inventário da Fase 0; resto exibe valor cacheado + badge "não recalculado"Partes OOXML desconhecidas corrompidas no savePerda de dadosPreservationStore byte-a-byte + teste de round-trip com o arquivo real como gate

12. Cronograma resumido

FaseEntregaDuração0Inventário da PGCTIC1 + tool/inspect_xlsx.dart1 dia1Core model + NumberFormatter + Commands (VM tests verdes)1 semana2XLSX reader/writer com round-trip da planilha real2 semanas3Layout/viewport/merges1 semana4Render canvas (visualizador fiel, read-only) — primeiro marco demonstrável2 semanas5Seleção, edição, clipboard, undo/redo2 semanas6Formula engine (funções do inventário)2 semanas7Shell (toolbar, abas, abrir/salvar)1 semana8Golden tests, perf, a11y, docs2 semanas

Total: ~12 semanas para um editor funcional com fidelidade suficiente para as planilhas de economicidade da PMRO. O marco da Fase 4 (visualizador read-only fiel em canvas) já é útil sozinho — por exemplo, para visualizar anexos .xlsx de processos dentro do SALI, no mesmo espírito do seu viewer PDF.js.