Veredito prático

Para renderizar e editar a sua planilha XLSX específica no navegador, as melhores opções open-source prontas são Collabora Online/CODE e ONLYOFFICE Docs Community, mas ambas são suítes grandes, normalmente com servidor, não bibliotecas Dart puras. Para uma referência moderna de editor canvas client-side, Univer é o projeto mais interessante, porém o fluxo robusto de importação/exportação XLSX aparece ligado ao servidor/Pro. Para implementar em Dart puro Web com apenas:

environment:
  sdk: ^3.6.0

dependencies:
  web: ^1.1.1

o caminho viável é criar um editor XLSX especializado, começando pelo subset real exigido pela sua planilha. O pacote web é adequado para acessar APIs do navegador com bindings leves e é pensado como substituto moderno de dart:html em compilação para JS ou WebAssembly.

O que a sua planilha realmente exige

Inspecionei o arquivo enviado PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx. Ele tem 2 abas:

Aba	Uso real observado	Complexidade
MÉDIA	Conteúdo principal de A1:R288, embora a dimensão formal no XML vá até AMJ288	Alta, por causa de muitas fórmulas, estilos e mesclagens
Composições	Conteúdo principal A1:F99	Média, com imagens, mesclagens e poucas fórmulas

Recursos presentes que o seu editor precisa suportar no MVP:

Recurso XLSX	Encontrado no arquivo	Impacto na implementação
Abas múltiplas	Sim, 2 abas	Navegação por abas
Shared strings	Sim, 113 strings únicas	Parser de sharedStrings.xml
Estilos	Sim, 155 estilos de célula	Parser de fontes, preenchimentos, bordas, alinhamento e formatos numéricos
Mesclagens	Sim, 116 na aba MÉDIA, 29 na aba Composições	Layout e hit-test precisam entender ranges mesclados
Fórmulas	Sim, cerca de 1.355 no total	Engine mínima de fórmulas
Fórmulas compartilhadas	Sim	Precisa expandir ou preservar fórmulas shared
Fórmulas array	Sim, 26	Principalmente para expressões tipo MEDIAN(IF(...))
Imagens	Sim, 4 mídias no pacote; 2 imagens visíveis em Composições	Parser de drawings e renderização com drawImage
Macros	Não	Não precisa VBA
Tabelas estruturadas	Não	Pode ficar fora do MVP
Gráficos	Não	Pode ficar fora do MVP
Pivot tables	Não	Pode ficar fora do MVP
Conditional formatting	Não	Pode ficar fora do MVP
Data validation	Não	Pode ficar fora do MVP
Hyperlinks	Não	Pode ficar fora do MVP
Proteção de planilha	Sim, na aba MÉDIA	Pode implementar como aviso/bloqueio opcional no início

As funções que aparecem no arquivo são um conjunto pequeno: IF, AVERAGE, AVERAGEIF, MEDIAN, MIN e SUM. Isso é ótimo para um MVP, porque você não precisa implementar centenas de funções do Excel logo no começo.

Soluções open-source pesquisadas
1. Collabora Online / CODE

Adequação: melhor opção open-source pronta para renderizar/editar XLSX com alta fidelidade, mas não serve como base “Dart puro sem dependências”.

Collabora Online é uma suíte colaborativa open-source e self-hosted. Um ponto muito relevante para a sua pergunta é que a Collabora informou que passou a usar HTML5 canvas para todos os aplicativos, incluindo Writer, Calc, Impress e Draw, depois de já ter iniciado esse caminho para planilhas no desktop.

Conclusão: é uma referência forte de arquitetura: servidor processa documentos complexos, front-end renderiza em canvas/tiles. Para seu projeto Dart puro, ela mostra que canvas é uma escolha realista para planilhas complexas, mas o produto inteiro é grande demais para ser incorporado como biblioteca simples.

2. ONLYOFFICE Docs Community / DocumentServer

Adequação: excelente como editor open-source pronto de XLSX/OOXML, mas também é uma suíte grande, com servidor e código JS próprio.

ONLYOFFICE DocumentServer oferece editores/viewers para documentos, planilhas e apresentações, com compatibilidade OOXML, incluindo .xlsx. A edição Community é distribuída sob AGPL v3, com código-fonte no GitHub. Há também documentação/descrições da arquitetura indicando uso de HTML5 Canvas e OOXML como formato central.

Conclusão: se o objetivo fosse “ter um editor XLSX open-source funcionando agora”, ONLYOFFICE e Collabora seriam os candidatos. Se o objetivo é “implementar em Dart puro”, eles servem como referência de produto, não como dependência.

3. Univer

Adequação: melhor referência moderna para arquitetura canvas client-side, mas não resolve import/export XLSX open-source puro.

Univer é um SDK office full-stack/isomorphic para planilhas, documentos e apresentações, com licença Apache-2.0, arquitetura de plugins, renderização baseada em canvas e engine de fórmulas. Porém a própria documentação indica que importação/exportação XLSX depende do servidor Univer e aparece ligada ao Univer Pro; também sugere que, para uso só no front-end, é possível usar bibliotecas open-source de parsing e converter para o modelo interno.

Conclusão: para o seu plano Dart, Univer é provavelmente a melhor referência de design: modelo de dados separado do renderer, renderer canvas, plugins, engine de fórmulas e virtualização. Mas não é uma solução direta em Dart puro.

4. Luckysheet + Luckyexcel

Adequação: útil como referência histórica, arriscado para produção nova.

Luckysheet é um editor de planilhas web open-source com licença MIT e recursos parecidos com Excel, mas o próprio repositório informa que o projeto não está mais mantido e recomenda usar Univer. O Luckyexcel é uma biblioteca MIT para importar/exportar arquivos para o modelo do Luckysheet, com suporte a .xlsx, estilos, bordas, formatos e fórmulas.

Conclusão: pode ser estudado para entender conversão XLSX → modelo de planilha web, mas não deveria ser a base principal de um projeto novo.

5. x-spreadsheet + SheetJS CE

Adequação: bom exemplo de grid canvas simples; insuficiente para fidelidade alta do seu XLSX.

x-spreadsheet é um componente web MIT, com recursos como undo/redo, células mescladas, freeze, funções, múltiplas abas, impressão e validações. O ecossistema costuma usar SheetJS para import/export XLSX. Porém o projeto é antigo/migrado e não é um renderizador XLSX fiel completo. SheetJS CE, por sua vez, é uma biblioteca open-source Apache-2.0 para extrair dados de planilhas e gerar arquivos, mas não é um editor/renderizador visual.

Conclusão: serve como inspiração para interação de grade, não como solução para renderizar a sua planilha com fidelidade visual.

6. Jspreadsheet CE, AG Grid, Handsontable

Adequação: são mais “data grids” do que renderizadores XLSX fiéis.

Jspreadsheet CE é um framework para controles tipo planilha; AG Grid tem exportação Excel em versão Enterprise e exemplos de importação com bibliotecas externas; Handsontable tem um modelo de licença que não é simplesmente “open-source livre para produção comercial”. Essas opções são boas para editar tabelas, mas não são o melhor caminho para abrir, renderizar e salvar uma pasta XLSX complexa com estilos, mesclagens, fórmulas, imagens e layout Excel-like.

7. Pacotes Dart existentes

Existem pacotes Dart como excel e excel_community para ler, criar e editar XLSX, mas eles são bibliotecas de arquivo/modelo, não editores visuais. Além disso, usam dependências como archive, xml, collection, equatable e outras, o que conflita com a restrição de usar apenas web.

Conclusão: para o seu requisito estrito, você teria que reimplementar parser ZIP, parser XML, parser OOXML, renderer e writer em Dart.

Google Sheets renderiza em canvas?

A resposta mais honesta é: há evidências públicas fortes de que o Google Sheets usa uma abordagem híbrida com canvas para a grade, mas não encontrei uma confirmação oficial recente do Google dizendo explicitamente “o grid do Google Sheets é renderizado em canvas”.

O Google confirmou oficialmente esse tipo de mudança para o Google Docs, dizendo que o Docs migrou de renderização baseada em HTML para renderização baseada em canvas para melhorar desempenho e consistência.

Já a documentação oficial atual sobre “Canvas” no Google Sheets se refere a um recurso do Gemini que cria interfaces visuais/interativas sobre dados da planilha; isso não é documentação da implementação interna do grid.

Como evidência secundária, há discussões públicas de engenharia/inspeção afirmando que o Sheets usa um modelo híbrido: corpo da grade em canvas, cabeçalhos/seleção/editor em DOM. Eu trataria isso como evidência técnica útil, mas não como contrato oficial do Google.

Decisão arquitetural para o seu editor: copie o modelo híbrido:

Canvas:
  - células visíveis
  - preenchimentos
  - bordas
  - texto
  - imagens
  - gridlines
  - highlights visuais

DOM:
  - barra de fórmulas
  - input/textarea de edição da célula ativa
  - menus/context menus
  - abas
  - acessibilidade
  - seleção de arquivo

Essa é a arquitetura mais sensata. Editar texto diretamente em canvas é desnecessariamente difícil e ruim para IME, seleção de texto, colar/copiar, leitores de tela e acessibilidade.

Plano extremamente detalhado para implementar em Dart puro Web
0. Escopo correto do projeto

Não implemente “um Excel completo” no início. Implemente primeiro:

Um editor XLSX compatível com a planilha PGCTIC1, capaz de abrir, renderizar, editar valores/fórmulas simples, recalcular o subset necessário e salvar um XLSX que abre corretamente no Excel, LibreOffice, Collabora e ONLYOFFICE.

Critérios de aceite do MVP:

Abrir o arquivo .xlsx pelo navegador.
Listar as abas MÉDIA e Composições.
Renderizar visualmente células, estilos, larguras, alturas, mesclagens, bordas, textos, números e imagens.
Exibir os valores calculados existentes mesmo antes de implementar toda a engine de fórmulas.
Permitir edição de valores em células desbloqueadas ou, no primeiro MVP, permitir edição com aviso quando a aba estiver protegida.
Recalcular as funções usadas pelo arquivo: SUM, MIN, AVERAGE, AVERAGEIF, MEDIAN, IF.
Preservar partes desconhecidas do XLSX no round-trip.
Salvar um novo .xlsx.
Abrir o arquivo salvo em Excel/LibreOffice/ONLYOFFICE sem corromper estilos, imagens ou abas.
1. Estrutura do projeto

Sugestão de diretórios:

xlsx_editor/
  pubspec.yaml
  web/
    index.html
    main.dart.js          # gerado no build
  lib/
    main.dart

    src/
      platform/
        browser_file_io.dart
        browser_canvas.dart
        browser_events.dart
        browser_download.dart

      zip/
        zip_reader.dart
        zip_writer.dart
        zip_crc32.dart
        zip_deflate.dart
        zip_models.dart

      xml/
        xml_tokenizer.dart
        xml_parser.dart
        xml_writer.dart
        xml_entities.dart
        xml_namespaces.dart

      ooxml/
        package_reader.dart
        content_types.dart
        relationships.dart
        workbook_reader.dart
        shared_strings_reader.dart
        styles_reader.dart
        theme_reader.dart
        worksheet_reader.dart
        drawing_reader.dart
        media_reader.dart
        workbook_writer.dart
        worksheet_writer.dart
        shared_strings_writer.dart
        styles_writer.dart

      model/
        workbook_model.dart
        sheet_model.dart
        cell_model.dart
        style_model.dart
        drawing_model.dart
        formula_model.dart
        address.dart
        range.dart
        sparse_grid.dart
        edit_transaction.dart

      layout/
        sheet_layout.dart
        column_width.dart
        row_height.dart
        viewport.dart
        merged_cell_layout.dart
        text_measure_cache.dart

      render/
        canvas_renderer.dart
        grid_painter.dart
        cell_painter.dart
        border_painter.dart
        text_painter.dart
        image_painter.dart
        selection_painter.dart
        dirty_region_tracker.dart

      editing/
        selection_controller.dart
        keyboard_controller.dart
        mouse_controller.dart
        cell_editor_overlay.dart
        clipboard_controller.dart
        undo_redo_stack.dart
        resize_controller.dart

      formula/
        formula_tokenizer.dart
        formula_parser.dart
        formula_ast.dart
        formula_eval.dart
        formula_functions.dart
        dependency_graph.dart
        recalc_engine.dart
        reference_resolver.dart

      formatting/
        number_format_parser.dart
        number_formatter.dart
        date_serial.dart
        text_wrap.dart
        color_resolver.dart

      app/
        app_controller.dart
        sheet_tabs.dart
        toolbar.dart
        formula_bar.dart
        status_bar.dart
2. Modelo mental do XLSX

Um .xlsx é um pacote ZIP contendo partes XML. No SpreadsheetML, o workbook referencia planilhas; cada planilha é um XML separado. Além disso, strings repetidas podem ser armazenadas em uma tabela global de shared strings.

Pipeline de abertura:

Arquivo .xlsx
  ↓
ArrayBuffer do navegador
  ↓
ZIP reader
  ↓
[Content_Types].xml
  ↓
_rels/.rels
  ↓
xl/workbook.xml
  ↓
xl/_rels/workbook.xml.rels
  ↓
xl/worksheets/sheet1.xml
  ↓
xl/sharedStrings.xml
  ↓
xl/styles.xml
  ↓
xl/theme/theme1.xml
  ↓
xl/drawings/*.xml
  ↓
WorkbookModel em memória
  ↓
Layout engine
  ↓
Canvas renderer
3. Entrada de arquivo no navegador

Com package:web, use APIs nativas do navegador:

<input type="file" accept=".xlsx">

Fluxo:

Usuário seleciona arquivo.
Ler File como ArrayBuffer.
Converter para Uint8List.
Passar para ZipReader.
Criar WorkbookModel.
Renderizar a primeira aba.

Classes sugeridas:

class BrowserFileLoader {
  Future<Uint8List> pickXlsx();
}

class BrowserDownloader {
  void downloadBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });
}

MIME type de saída:

application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
4. ZIP reader e writer sem dependências

Como você não quer usar archive, será necessário implementar o mínimo do ZIP.

4.1 Reader

Suportar inicialmente:

Recurso ZIP	MVP
End of Central Directory	Sim
Central Directory	Sim
Local File Header	Sim
Método 0, stored	Sim
Método 8, deflate	Sim
ZIP64	Rejeitar no MVP
Encriptação ZIP	Rejeitar
Data descriptor	Suportar ou rejeitar com erro claro
CRC32	Validar

Fluxo:

1. Procurar EOCD de trás para frente.
2. Ler quantidade de entradas.
3. Ler offset do Central Directory.
4. Para cada entrada:
   - nome
   - método de compressão
   - tamanho comprimido
   - tamanho descomprimido
   - CRC32
   - offset do local header
5. Ler bytes do arquivo.
6. Descomprimir se necessário.
4.2 Deflate no navegador

A API Compression Streams suporta gzip, deflate e deflate-raw, e deflate-raw é especialmente relevante para ZIP. Ela também é exposta em workers em navegadores modernos.

Plano pragmático:

Fase 1:
  - Ler ZIP com método 0.
  - Para método 8, tentar DecompressionStream('deflate-raw').

Fase 2:
  - Implementar inflate puro em Dart como fallback.

Fase 3:
  - Writer inicialmente pode gravar entradas como stored/método 0.
  - Depois adicionar CompressionStream('deflate-raw') para reduzir tamanho.

Gravar como método 0 gera arquivos maiores, mas é muito mais simples e ainda compatível com XLSX, desde que o pacote ZIP esteja correto.

5. XML parser sem dependências

Como você não quer usar xml, implemente um parser XML suficiente para OOXML.

5.1 Tokenizer

Tokens mínimos:

sealed class XmlToken {}

class XmlStartElement extends XmlToken {
  final String name;
  final Map<String, String> attributes;
  final bool selfClosing;
}

class XmlEndElement extends XmlToken {
  final String name;
}

class XmlText extends XmlToken {
  final String text;
}

class XmlCData extends XmlToken {
  final String text;
}

class XmlComment extends XmlToken {}

class XmlProcessingInstruction extends XmlToken {}
5.2 Regras importantes

Suportar:

<element attr="value">
<element attr='value'>
<element/>
<r><t xml:space="preserve"> texto </t></r>
&amp; &lt; &gt; &quot; &apos;
<![CDATA[...]]>

Rejeitar ou ignorar com segurança:

DOCTYPE
entidades externas
DTD

Isso evita XXE e simplifica bastante.

5.3 Parser pull-based

Use um parser de streaming/pull, não um DOM gigante para tudo.

class XmlPullParser {
  XmlToken? next();
}

Mas para arquivos pequenos como workbook.xml, styles.xml, sharedStrings.xml, pode criar objetos intermediários.

6. Parser OOXML
6.1 Ordem de leitura
1. [Content_Types].xml
2. _rels/.rels
3. xl/workbook.xml
4. xl/_rels/workbook.xml.rels
5. xl/sharedStrings.xml
6. xl/styles.xml
7. xl/theme/theme1.xml
8. xl/worksheets/*.xml
9. xl/worksheets/_rels/sheet*.xml.rels
10. xl/drawings/*.xml
11. xl/drawings/_rels/drawing*.xml.rels
12. xl/media/*
6.2 Workbook

Modelo:

class WorkbookModel {
  final List<SheetModel> sheets;
  final SharedStringTable sharedStrings;
  final StyleTable styles;
  final Map<String, Uint8List> originalPackageParts;
  final PackageRelationshipMap relationships;
}
6.3 Sheets
class SheetModel {
  final String name;
  final String sheetId;
  final String relationshipId;
  final SparseGrid<CellData> cells;
  final List<MergedRange> merges;
  final List<ColumnInfo> columns;
  final Map<int, RowInfo> rows;
  final List<DrawingObject> drawings;
  final SheetProtection? protection;
  final SheetPageSetup? pageSetup;
  final SheetViewInfo viewInfo;
  final UsedRange usedRange;
}
6.4 Células
class CellData {
  final int row;
  final int col;
  final CellType type;
  final Object? value;
  final String? formula;
  final int? styleIndex;
  final String? sharedFormulaId;
  final String? arrayFormulaRange;
  final bool hasCachedValue;
}

Tipos:

enum CellType {
  blank,
  number,
  sharedString,
  inlineString,
  boolean,
  error,
  formula,
  dateLikeNumber,
}
7. Armazenamento esparso da grade

Não use matriz densa. A aba MÉDIA tem dimensão XML formal até AMJ288, mas o conteúdo útil é muito menor. Uma matriz densa desperdiçaria memória e causaria renderização errada.

Use chunks:

class SparseGrid<T> {
  static const int chunkRows = 64;
  static const int chunkCols = 32;

  final Map<int, GridChunk<T>> chunks;

  T? get(int row, int col);
  void set(int row, int col, T? value);
}

Chave do chunk:

chunkRow = row ~/ 64
chunkCol = col ~/ 32
chunkKey = chunkRow << 20 | chunkCol

Também mantenha índices auxiliares:

nonEmptyRows
nonEmptyCols
formulaCells
styleOnlyCells
mergedRangeIndex
8. Estilos

A sua planilha depende muito de estilo. O renderer precisa suportar:

Estilo	MVP
Fonte	nome, tamanho, negrito, itálico, sublinhado, cor
Preenchimento	cor sólida
Bordas	esquerda, direita, topo, baixo; estilo fino/médio/grosso
Alinhamento	horizontal, vertical
Quebra de linha	sim
Mesclagem	sim
Formatos numéricos	sim
Rotação de texto	pode ficar para depois
Rich text parcial	ler como texto simples no MVP

Modelo:

class ResolvedCellStyle {
  final FontStyleInfo font;
  final FillStyleInfo fill;
  final BorderStyleInfo border;
  final AlignmentInfo alignment;
  final NumberFormatInfo numberFormat;
}

Importante: estilos podem vir de célula, coluna, linha e estilo padrão. A ordem de resolução deve ser:

default style
  ↓
column style
  ↓
row style
  ↓
cell style
9. Formatos numéricos

Sem intl, você precisará de um formatador próprio.

Para a sua planilha, implemente primeiro:

0
0.00
#,##0
#,##0.00
R$ #,##0.00
R$ #,##0.00;[Red]-R$ #,##0.00
0%
0.00%
dd/mm/yyyy
mm/yyyy

Pipeline:

valor bruto numérico
  ↓
detectar formato pelo styleIndex
  ↓
NumberFormatParser
  ↓
NumberFormatter
  ↓
string final para canvas

Para moeda brasileira:

1234.5 -> R$ 1.234,50

Não dependa do locale do navegador no MVP, porque o arquivo precisa ser reproduzível.

10. Layout de linhas e colunas
10.1 Conversão de largura de coluna

O Excel armazena largura em uma unidade própria baseada na largura de caracteres. Para MVP, use aproximação estável:

pixelWidth ≈ floor(width * 7 + 5)

Depois refine com medição real da fonte padrão.

10.2 Altura de linha

Altura de linha normalmente vem em pontos:

px = points * devicePixelRatioIndependentScale
px = points * 96 / 72
10.3 Prefix sums

Para scroll rápido:

class AxisMetrics {
  double offsetOfIndex(int index);
  int indexAtOffset(double offset);
  void setSize(int index, double px);
}

Implemente com:

Fase 1: array + busca binária para poucas linhas/colunas.
Fase 2: Fenwick tree para muitos updates de resize.
11. Renderização via canvas

A API CanvasRenderingContext2D permite desenhar formas, texto, imagens e outros objetos em <canvas>. Métodos como measureText, fillText e drawImage são justamente os blocos básicos para medir texto, escrever células e desenhar imagens. OffscreenCanvas pode ser usado depois para mover renderização pesada para fora do DOM/thread principal.

11.1 Camadas

Use múltiplos canvases sobrepostos:

<div id="sheet-host">
  <canvas id="grid-canvas"></canvas>
  <canvas id="overlay-canvas"></canvas>
  <textarea id="cell-editor"></textarea>
</div>

Camadas:

Camada	Conteúdo
grid-canvas	preenchimentos, bordas, textos, imagens
overlay-canvas	seleção, autofill handle, hover, indicadores
DOM editor	input/textarea ativo
DOM UI	toolbar, barra de fórmulas, abas
11.2 High DPI

Sempre renderize considerando devicePixelRatio:

canvas.width = cssWidth * dpr
canvas.height = cssHeight * dpr
context.scale(dpr, dpr)
11.3 Viewport virtualizada

Não desenhe a planilha inteira.

scrollLeft, scrollTop
  ↓
calcular colunas visíveis
  ↓
calcular linhas visíveis
  ↓
expandir por margem de overscan
  ↓
desenhar só células visíveis

Overscan recomendado:

10 linhas acima/abaixo
5 colunas antes/depois
11.4 Ordem de pintura de células

Para cada célula visível:

1. Resolver mesclagem.
2. Se for célula secundária de merge, pular.
3. Calcular retângulo visual.
4. Pintar background.
5. Pintar imagem se houver objeto ancorado.
6. Pintar texto.
7. Pintar bordas.
11.5 Texto

Suportar:

alinhamento horizontal: left, center, right
alinhamento vertical: top, middle, bottom
wrapText
clipping
overflow horizontal para células vazias vizinhas

No MVP, para células mescladas e com quebra de linha:

medir palavras
quebrar por largura disponível
limitar por altura
desenhar linhas com lineHeight
12. Imagens e drawings

Sua planilha contém imagens e arquivos de drawing. O parser precisa ler:

xl/worksheets/sheet*.xml
  → <drawing r:id="...">

xl/worksheets/_rels/sheet*.xml.rels
  → target ../drawings/drawing*.xml

xl/drawings/drawing*.xml
  → anchors

xl/drawings/_rels/drawing*.xml.rels
  → target ../media/image*.png/jpeg

Tipos a suportar primeiro:

twoCellAnchor
oneCellAnchor
pic

Modelo:

class DrawingObject {
  final DrawingType type;
  final String mediaPath;
  final CellAnchor from;
  final CellAnchor to;
  final double offsetXPx;
  final double offsetYPx;
}

Renderização:

1. Converter anchor de linha/coluna para pixels.
2. Carregar bytes da imagem.
3. Criar Blob ou data URL.
4. Decodificar com HTMLImageElement/ImageBitmap.
5. Desenhar com drawImage.

Na gravação, preserve os drawings originais se o usuário não editar imagens.

13. Seleção, mouse e teclado
13.1 Hit test

Converter coordenada do mouse:

clientX/clientY
  ↓
coordenada relativa ao canvas
  ↓
somar scrollLeft/scrollTop
  ↓
axisMetrics.indexAtOffset()
  ↓
row/col
  ↓
verificar mergedRangeIndex
13.2 Seleção

Estados:

class SelectionState {
  final CellAddress activeCell;
  final CellRange selectedRange;
  final bool isEditing;
}

Ações:

clique simples: selecionar célula
duplo clique: editar
shift + clique: expandir seleção
arrastar: selecionar range
ctrl/cmd + c: copiar TSV
ctrl/cmd + v: colar TSV
delete/backspace: limpar valores
enter: editar/confirmar
escape: cancelar
tab: próxima célula
setas: mover seleção
13.3 Editor overlay

Use um <textarea> posicionado sobre a célula ativa.

posição = cellRect no viewport
largura = cellRect.width
altura = max(cellRect.height, altura mínima)
font = estilo resolvido da célula
text-align = alinhamento da célula

Ao confirmar:

se começa com "=":
  salvar como fórmula
senão:
  inferir tipo:
    número
    moeda
    porcentagem
    texto
14. Barra de fórmulas

Componentes:

name box: A1, B5, C10:D12
formula input: conteúdo bruto da célula
status: pronto/editando/recalculando

Comportamento:

seleção muda → atualizar formula bar
usuário edita formula bar → atualizar célula
enter → confirmar
escape → cancelar

Para fórmulas, mostre o texto com =:

=AVERAGE(E10:E20)
15. Engine de fórmulas

A sua planilha permite um MVP relativamente focado.

15.1 Fase 1: usar valores em cache

No XLSX, fórmulas geralmente têm valor calculado em <v>. Primeiro:

- Ler fórmula.
- Ler valor em cache.
- Exibir valor em cache.
- Não recalcular ainda.

Isso permite renderização correta antes da engine completa.

15.2 Fase 2: parser de fórmulas

Tokenizer:

números: 123, 123.45
strings: "texto"
operadores: + - * / ^ &
comparadores: = <> < <= > >=
parênteses: ( )
separadores: , ;
ranges: A1, A1:B10, 'Nome Aba'!A1:B10
porcentagem: 10%
funções: SUM(...)

AST:

sealed class FormulaExpr {}

class NumberExpr extends FormulaExpr {}
class StringExpr extends FormulaExpr {}
class BooleanExpr extends FormulaExpr {}
class CellRefExpr extends FormulaExpr {}
class RangeRefExpr extends FormulaExpr {}
class BinaryExpr extends FormulaExpr {}
class UnaryExpr extends FormulaExpr {}
class FunctionCallExpr extends FormulaExpr {}
15.3 Funções exigidas pelo arquivo

Implementar:

SUM(range...)
MIN(range...)
AVERAGE(range...)
MEDIAN(range...)
IF(condition, trueValue, falseValue)
AVERAGEIF(range, criteria, averageRange?)
15.4 Fórmulas array

Seu arquivo tem fórmulas array. O caso mais provável é algo como:

MEDIAN(IF(condição, intervalo))

Estratégia:

1. Avaliador normal retorna ScalarValue.
2. Avaliador array retorna List<Value>.
3. IF com condição array retorna array filtrado.
4. MEDIAN aceita array.

Modelo de valor:

sealed class EvalValue {}

class NumberValue extends EvalValue {}
class StringValue extends EvalValue {}
class BooleanValue extends EvalValue {}
class ErrorValue extends EvalValue {}
class BlankValue extends EvalValue {}
class ArrayValue extends EvalValue {}
15.5 Grafo de dependências

Ao abrir:

para cada célula com fórmula:
  parse AST
  extrair referências
  registrar dependências

Ao editar uma célula:

1. Marcar célula alterada.
2. Encontrar dependentes diretos.
3. Propagar dependentes.
4. Ordenar topologicamente.
5. Recalcular.
6. Atualizar viewport.
15.6 Referências relativas e shared formulas

Fórmulas compartilhadas no OOXML são armazenadas uma vez e reutilizadas por células relacionadas. Para simplificar:

na leitura:
  expandir shared formulas para fórmulas individuais

na gravação:
  gravar fórmulas individuais

Isso aumenta o XML, mas simplifica muito. Depois você pode otimizar e regenerar shared formulas.

16. Edição de valores

Tipos de edição:

Entrada do usuário	Armazenamento
abc	string
123	número
123,45	número, se locale BR
R$ 1.234,56	número com estilo moeda preservado
10%	número 0.1 com formato percentual
=SUM(A1:A3)	fórmula
vazio	célula limpa

Ao editar:

1. Criar EditTransaction.
2. Alterar CellData.
3. Atualizar sharedStrings se necessário.
4. Atualizar dependências.
5. Recalcular fórmulas afetadas.
6. Invalidar regiões visuais.
7. Empilhar undo.
17. Undo/redo

Modelo:

class EditTransaction {
  final List<CellChange> changes;
  final SelectionState beforeSelection;
  final SelectionState afterSelection;
}

Operações:

setCellValue
setCellFormula
clearRange
pasteRange
resizeColumn
resizeRow
formatRange

No MVP, implemente undo/redo para:

- edição de célula
- colagem
- limpeza
- resize de linha/coluna
18. Clipboard
18.1 Copiar

Gerar TSV:

células na seleção
  ↓
linhas separadas por \n
colunas separadas por \t

Também gere HTML simples:

<table>
  <tr><td>...</td></tr>
</table>
18.2 Colar

Aceitar:

text/plain
text/html

Prioridade:

1. text/html, se vier de Excel/Sheets e for parseável
2. text/plain TSV

No MVP, TSV resolve a maioria dos casos.

19. Redimensionamento de linhas e colunas

Interação:

mouse perto da borda do cabeçalho de coluna
  ↓
cursor resize
  ↓
drag
  ↓
atualizar ColumnInfo.widthPx
  ↓
invalidar viewport

Persistência:

<cols>
  <col min="1" max="1" width="..." customWidth="1"/>
</cols>

Para linhas:

<row r="10" ht="24" customHeight="1">
20. Proteção de planilha

A aba MÉDIA tem proteção no XML. Para o MVP:

Fase 1:
  - Mostrar indicador "aba protegida".
  - Permitir edição apenas em modo desenvolvimento.

Fase 2:
  - Respeitar locked/unlocked dos estilos.
  - Bloquear edição de células locked.
  - Permitir seleção conforme flags de proteção.

Fase 3:
  - Suportar senha hash OOXML, se necessário.
21. Escrita do XLSX

A estratégia mais segura é preservar tudo o que você não entende.

21.1 Preserve-by-default

Ao abrir o ZIP:

originalPackageParts[path] = bytes

Ao salvar:

para cada parte original:
  se não foi alterada:
    copiar bytes originais
  se foi alterada:
    gerar novo XML

Partes que você provavelmente alterará:

xl/worksheets/sheet1.xml
xl/worksheets/sheet2.xml
xl/sharedStrings.xml
xl/calcChain.xml
xl/workbook.xml, se renomear abas
xl/styles.xml, se alterar estilos

Partes que deve preservar:

xl/theme/theme1.xml
xl/drawings/*
xl/media/*
xl/printerSettings/*
docProps/*
_rels/*
xl/_rels/*
21.2 Shared strings

Duas estratégias:

Estratégia simples
- Recriar sharedStrings.xml inteiro.
- Todas as strings das células viram shared strings.
- Atualizar índices das células.

Vantagem: simples.

Desvantagem: muda mais o arquivo.

Estratégia preservadora
- Manter tabela original.
- Adicionar novas strings no final.
- Reutilizar índice se string já existe.

Vantagem: diff menor.

Desvantagem: precisa índice string → sharedStringId.

Eu começaria pela estratégia preservadora.

21.3 Fórmulas e valores em cache

Ao salvar uma célula com fórmula:

<c r="A1" s="5">
  <f>SUM(A2:A10)</f>
  <v>123</v>
</c>

Se a fórmula não foi recalculada:

- preservar valor em cache antigo, se célula não foi afetada
- marcar workbook para recálculo, se possível

Para calcChain.xml:

MVP:
  - remover ou regenerar com testes de compatibilidade.
  - validar no Excel/LibreOffice/ONLYOFFICE.

Versão robusta:
  - gerar calcChain atualizado.
21.4 Gravação das planilhas

Ordem recomendada no XML:

worksheet
  sheetPr
  dimension
  sheetViews
  sheetFormatPr
  cols
  sheetData
  mergeCells
  phoneticPr
  pageMargins
  pageSetup
  headerFooter
  drawing
  legacyDrawing
  picture

Preserve elementos desconhecidos na ordem original sempre que possível.

22. Renderer: detalhes finos para ficar parecido com Excel
22.1 Bordas

Pinte bordas depois dos backgrounds e textos.

Prioridade quando duas células compartilham borda:

1. borda mais grossa vence
2. borda colorida vence borda automática
3. borda da célula atual pode vencer, desde que consistente

No MVP, pinte bordas de cada célula e aceite pequenos overlaps.

22.2 Mesclagens

Para range mesclado:

A1:C3

Apenas a célula superior esquerda contém valor renderizável. As outras células existem para layout/hit-test.

Ao selecionar célula dentro de merge:

activeCell = topLeft
selectedRange = mergedRange
22.3 Overflow de texto

Excel permite texto invadir células vazias à direita. MVP:

se célula não tem wrap e alinhamento left:
  expandir clip até encontrar célula ocupada ou borda de viewport

Para células mescladas, clip no retângulo mesclado.

22.4 Cores de tema

OOXML pode usar cores de tema:

<color theme="1" tint="-0.249977111117893"/>

Implementar:

theme index → RGB base
aplicar tint

Sem isso, algumas cores podem sair erradas.

23. Performance
23.1 Metas

Para a sua planilha:

abrir arquivo: < 1s a 3s em máquina comum
trocar aba: instantâneo após parse
scroll: 60 fps na maior parte do tempo
edição: feedback imediato
salvar: aceitável mesmo se levar alguns segundos
23.2 Técnicas
- parse ZIP/XML fora do frame de renderização
- requestAnimationFrame para pintura
- dirty rectangles
- caches de texto medido
- cache de estilos resolvidos
- cache de número formatado
- viewport virtualizada
- parsing lazy de desenhos/imagens
- não recalcular fórmulas não afetadas
23.3 OffscreenCanvas depois

Após o MVP, mover renderização pesada para worker com OffscreenCanvas, se o browser alvo suportar. Isso pode deixar scroll e recálculo mais estáveis.

24. Segurança

Como o usuário abrirá arquivos locais, implemente proteções:

limite de tamanho do XLSX
limite de quantidade de entradas ZIP
limite de tamanho descomprimido total
detecção de zip bomb
rejeitar ZIP encriptado
rejeitar XML com DOCTYPE/entidades externas
limite de profundidade XML
limite de tamanho de string
limite de quantidade de células
limite de quantidade de fórmulas

Também trate fórmulas como dados, não como código.

25. Testes
25.1 Testes unitários
zip_reader_test.dart
xml_tokenizer_test.dart
address_test.dart
range_test.dart
shared_strings_test.dart
styles_test.dart
worksheet_reader_test.dart
number_formatter_test.dart
formula_parser_test.dart
formula_eval_test.dart
25.2 Testes com sua planilha

Casos obrigatórios:

abre workbook
detecta 2 abas
MÉDIA renderiza A1:R288
Composições renderiza A1:F99
lê 116 merges em MÉDIA
lê 29 merges em Composições
lê imagens
lê estilos
lê fórmulas
recalcula SUM
recalcula AVERAGE
recalcula AVERAGEIF
recalcula MEDIAN(IF(...))
salva XLSX
reabre XLSX salvo
compara valores principais
25.3 Golden visual tests

Gere screenshots de referência em:

Excel
LibreOffice
ONLYOFFICE
Collabora
seu renderer

Compare:

posição de textos
larguras de colunas
alturas de linhas
cores
bordas
mesclagens
imagens
valores formatados
26. Roadmap recomendado
Marco 1 — Abrir XLSX e listar abas

Entregas:

- file picker
- zip reader
- content types
- relationships
- workbook parser
- lista de abas

Critério de aceite:

mostrar:
  MÉDIA
  Composições
Marco 2 — Ler células e shared strings

Entregas:

- sharedStrings parser
- worksheet parser básico
- CellData
- SparseGrid
- endereço A1

Critério de aceite:

mostrar valores brutos das células em uma tabela debug
Marco 3 — Renderização canvas read-only simples

Entregas:

- canvas full screen
- scroll
- viewport virtualizada
- gridlines
- textos simples
- números simples

Critério de aceite:

ver a aba MÉDIA navegável no canvas
Marco 4 — Estilos, mesclagens e dimensões

Entregas:

- styles.xml
- larguras de colunas
- alturas de linhas
- merges
- backgrounds
- fontes
- bordas
- alinhamento
- wrap

Critério de aceite:

MÉDIA fica visualmente próxima do Excel/LibreOffice
Marco 5 — Formatos numéricos

Entregas:

- parser de formatos
- moeda BRL
- porcentagem
- decimais
- datas básicas

Critério de aceite:

valores monetários e médias aparecem como na planilha original
Marco 6 — Imagens e drawings

Entregas:

- drawing parser
- image relationships
- anchors
- image decoding
- drawImage no canvas

Critério de aceite:

aba Composições mostra as imagens no local correto
Marco 7 — Seleção e edição

Entregas:

- hit-test
- seleção
- teclado
- editor overlay
- formula bar
- edição de valores
- undo/redo básico

Critério de aceite:

editar uma célula, confirmar, desfazer e refazer
Marco 8 — Fórmulas mínimas

Entregas:

- tokenizer
- parser
- AST
- evaluator
- dependency graph
- funções: SUM, MIN, AVERAGE, AVERAGEIF, MEDIAN, IF

Critério de aceite:

alterar um valor de cotação e atualizar médias/avaliações dependentes
Marco 9 — Salvar XLSX

Entregas:

- worksheet writer
- sharedStrings writer
- zip writer
- download
- preservação de partes desconhecidas

Critério de aceite:

arquivo salvo abre novamente no Excel/LibreOffice/ONLYOFFICE
Marco 10 — Robustez e compatibilidade

Entregas:

- validação contra zip bombs
- fallback de inflate puro
- testes visuais
- testes round-trip
- tratamento de erros amigável

Critério de aceite:

usuário consegue abrir, editar e salvar a planilha sem corromper o arquivo
27. Decisões técnicas que eu tomaria
Decisão 1: canvas para grid, DOM para edição

Use canvas para performance visual e DOM para edição. É o mesmo padrão que aparece em editores modernos e é mais realista do que tentar fazer todo input textual dentro do canvas.

Decisão 2: preservar o XLSX original

Não tente reescrever o pacote inteiro no começo. Preserve todas as partes desconhecidas e só regenere XMLs alterados.

Decisão 3: renderizar primeiro, editar depois

Ordem correta:

abrir → renderizar fielmente → editar valores → recalcular fórmulas → salvar

Se começar pelo writer, você corre o risco de corromper arquivos antes de ter uma visualização confiável.

Decisão 4: engine de fórmulas orientada pelo arquivo

Implemente primeiro exatamente as funções que existem na sua planilha:

IF
AVERAGE
AVERAGEIF
MEDIAN
MIN
SUM

Depois expanda.

Decisão 5: não confiar no dimension

A aba MÉDIA declara uma dimensão XML muito maior do que o conteúdo útil. Use o dimension como sugestão, mas calcule o used range real a partir de:

células com valor
células com fórmula
mesclagens
desenhos
larguras customizadas
linhas customizadas
28. Resultado final esperado da arquitetura

O produto final ficaria assim:

Browser
  ├── File picker
  ├── Dart package:web
  ├── XLSX ZipReader puro Dart
  ├── XML parser puro Dart
  ├── OOXML parser puro Dart
  ├── WorkbookModel
  ├── FormulaEngine
  ├── LayoutEngine
  ├── CanvasRenderer
  ├── DOM CellEditor
  ├── XLSX Writer puro Dart
  └── Download .xlsx

Sem Flutter, sem SheetJS, sem JS externo, sem archive, sem xml, sem excel, sem dart:html.

Conclusão

Sim, existem editores/renderizadores open-source que conseguem lidar com XLSX e usam canvas ou arquitetura parecida, principalmente Collabora Online, ONLYOFFICE e Univer. Mas nenhum deles resolve diretamente o seu requisito de Dart puro Web com apenas package:web.

Para a sua planilha específica, a implementação é viável porque o arquivo não usa macros, pivôs, gráficos, tabelas estruturadas, validações ou formatação condicional. O núcleo difícil será outro: ZIP + XML + OOXML + estilos + canvas + fórmulas + gravação round-trip.

A abordagem mais segura é construir um editor especializado, canvas-based, híbrido com DOM, preservando o pacote XLSX original e implementando primeiro o subset real usado por PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx.