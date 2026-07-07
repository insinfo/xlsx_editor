# Plano Consolidado — Editor XLSX em Dart Puro (Web/Canvas)

> Consolidação executável das pesquisas em `doc/pesquise/` (autoridade: `roteiro3.md` +
> `Plano de Implementação.md` + `deep-research-report.md`), das referências open-source em
> `referencias/` (fortune-sheet, FortuneExcel, grid, GridPaper) e do inventário real do
> arquivo-alvo `resources/PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx`.

## 1. Objetivo

Editor de planilhas `.xlsx` estilo Excel/Google Sheets, **100% Dart** (SDK ^3.6), rodando
no navegador via `dart compile js`, ou webdev build ou webdev serve **sem dependências externas** além de `package:web`
(binding da plataforma). Deve renderizar e editar fielmente a planilha-alvo.

## 2. Inventário do arquivo-alvo (medido, não especulado)

| Recurso | Valor | Implicação |
|---|---|---|
| Abas | `MÉDIA` (A1:P288), `Composições` | multi-sheet + abas |
| Merges | 116 + 29 | índice âncora→range e coberta→âncora |
| Estilos | 155 cellXfs, 28 fonts, 10 fills, 15 borders | tabela de estilos OOXML espelhada |
| numFmts | `R$ #,##0.00` com seções e `[Red]`, `_-* #,##0.00...` | motor de formato numérico próprio |
| Fórmulas | 525 `<f>`: normais, 798 shared (`si`/`ref`), 26 array | expansão de shared; array p/ MEDIAN(IF(...)) |
| Funções | **apenas** IF, AVERAGE, AVERAGEIF, SUM, MEDIAN (+MIN) | motor enxuto orientado pelo arquivo |
| Valores em cache | `<v>` presente em todas | render inicial NÃO depende do motor de fórmulas |
| Imagens | logo via `drawing` (twoCellAnchor) | render de imagem ancorada |
| Tema | theme1.xml (cores + tint) | resolução indexed→rgb→theme com swap 0↔1, 2↔3 |
| Freeze panes / cond. formatting / validação / macros | **ausentes** | fora do escopo v1 |

## 3. Decisões de arquitetura

1. **Canvas + DOM auxiliar** (consenso das pesquisas e do fortune-sheet):
   grade/células/texto/bordas/seleção no canvas; editor de célula é `<textarea>`
   DOM absoluto sobre a célula ativa (IME/acentos PT-BR); barra de fórmulas, toolbar
   e abas em DOM comum.
2. **Virtualização por prefix-sums + busca binária**: arrays acumulados de larguras/alturas;
   só o viewport é pintado (técnica fortune-sheet `visibledatarow` / grid-master).
3. **HiDPI**: backing store × `devicePixelRatio`, `ctx.setTransform(dpr,0,0,dpr,0,0)`;
   gridlines em coordenadas `+0.5` para nitidez.
4. **Scroll**: div `overflow:auto` com spacer do tamanho total sobre o canvas
   (scrollbars nativas, técnica grid-master); canvas fixo repinta no evento `scroll`.
5. **ZIP/XML próprios**: vendorados de `canvas-editor-port/packages/ce_zip` e `ce_xml`
   (Dart puro, zero deps, já testados nos projetos DOCX) → `lib/src/zip`, `lib/src/xml`.
6. **Round-trip preservador**: entradas ZIP não modeladas são reescritas byte-a-byte;
   só `worksheets/sheetN.xml` + `sharedStrings.xml` (+`styles.xml` se editado) são
   re-serializados; `calcChain.xml` é removido e `calcPr fullCalcOnLoad="1"` é gravado.
7. **Fórmulas**: valores `<v>` cacheados para o primeiro paint; motor próprio
   (tokenizer → Pratt parser → AST → grafo de dependências → recálculo incremental)
   entra ao editar. Separador `;` na UI PT-BR, `,` no formato interno.
8. **Formato numérico**: subconjunto ECMA-376 (seções `;`, `0 # ? . ,`, `%`, literais,
   `[Red]`, `[$R$-416]`, `_x`, `*x`, `@`, datas seriais), locale fixo pt-BR.

## 4. Estrutura de módulos

```
lib/src/
  zip/        ZIP reader/writer + inflate/deflate + CRC32   (vendorado ce_zip)
  xml/        SAX + DOM leve + serializer                    (vendorado ce_xml)
  util/       cell_ref.dart (A1 ↔ row/col, CellRange)
  model/      workbook, worksheet (grade esparsa), cell, styles (tabelas OOXML),
              theme, merges
  xlsx/       xlsx_reader.dart (workbook/sheets/sharedStrings/styles/theme/drawings),
              xlsx_writer.dart (round-trip preservador)
  numfmt/     number_format.dart (motor de formatCode, cache compilado)
  formula/    tokenizer, parser (Pratt), ast, evaluator (IF/SUM/AVERAGE/AVERAGEIF/
              MEDIAN/MIN/MAX/COUNT...), engine (grafo de deps, recálculo, ciclos)
  layout/     axis_layout.dart (prefix sums, hit-test, visibleRange, merges em px)
  render/     grid_renderer.dart (fundos → gridlines → texto → bordas → merges →
              headers → seleção), image cache p/ drawings
  ui/         app.dart (shell), toolbar, formula_bar, sheet_tabs, cell_editor
              (textarea overlay), interações (mouse/teclado/clipboard), commands
              (undo/redo)
web/          index.html + main.dart (bootstrap, abre o arquivo-alvo)
```

## 5. Fases (com critérios de aceite)

| # | Fase | Critério de aceite |
|---|---|---|
| 0 | Reconhecimento + vendor zip/xml | ZIP do alvo abre; partes listadas ✔ |
| 1 | Modelo + parser XLSX | células/estilos/merges/colunas do alvo no modelo |
| 2 | Formato numérico | `R$ 1.234,50`, `[Red]` negativo, datas |
| 3 | Layout (prefix sums, merges px) | hit-test e visibleRange O(log n) |
| 4 | **Render read-only fiel** (1º marco demonstrável) | planilha-alvo idêntica ao Excel no navegador |
| 5 | Seleção/navegação/edição | textarea overlay, Enter/Tab/setas, formula bar |
| 6 | Motor de fórmulas + recálculo | editar cotação recalcula médias/medianas |
| 7 | Undo/redo, clipboard, resize linha/col | Ctrl+Z/C/V, arrastar headers |
| 8 | Salvar XLSX round-trip | arquivo reabre no Excel sem reparo |
| 9 | UI like-Excel (toolbar formatação, abas, imagens) | logo renderizada, toolbar aplica estilo |
| 10 | Performance + testes | 60fps scroll; testes VM p/ zip/xml/numfmt/fórmulas |

## 6. Riscos e mitigações

- **Fidelidade de fonte/medida de texto**: cache de `measureText` por (font,text);
  `document.fonts.ready` antes do primeiro paint; larguras de coluna OOXML→px via
  `floor(width*7+5)` (MDW=7, Calibri 11).
- **Zip bomb/XXE**: limites de tamanho, sem DOCTYPE/entidades externas no parser.
- **calcChain**: nunca reescrever; remover + fullCalcOnLoad.
- **Array formulas**: avaliador com contexto array só para o padrão `MEDIAN(IF(range=x,range))`
  presente no arquivo; genérico fica para v2.


Melhorias aplicadas — recarregue localhost:8088 (Ctrl+F5)
Comparando seus screenshots lado a lado, ataquei as quatro diferenças mais visíveis em relação ao Excel:

1. Formato contábil com preenchimento * (a maior diferença visual). No Excel, _("R$ "* #,##0.00_) ancora o R$ na borda esquerda da célula e o número na direita — era por isso que as colunas cinza (L, M, N, P) ficavam diferentes. Implementei o token de fill no motor de formato (number_format.dart agora retorna splitIndex no FormattedResult) e o renderer desenha as duas partes ancoradas em lados opostos. No screenshot novo, R$      303.096,17 fica idêntico ao Excel.

2. "EXCESSIVAMENTE ELEVADO" cortado. Meu wrap só quebrava em espaços; quando a palavra é maior que a coluna, o Excel quebra por caractere. Agora o _wrapText faz o mesmo: renderiza "EXCESSIVAM / ENTE / ELEVADO" em 3 linhas, sem comer o "E" inicial.

3. Headers estilo Excel. Números de linha agora alinhados à direita (não centralizados), fonte menor (10px), e a seleção ganha o filete verde de 2px na borda interna do header de linha/coluna — o mesmo detalhe do Excel moderno.

4. Interação. A toolbar agora reflete a fonte e o tamanho da célula ativa ao navegar (como o Excel), e Ctrl+roda do mouse faz zoom pelos degraus 50–200%.

Validação: analyzer limpo, 105 testes VM passando (os 59 do numfmt continuam verdes com o novo splitIndex), e o teste de edição headless confirma que o recálculo continua funcionando (D12 → 100000 recalculou L8 para R$ 282.129,75).

Uma observação sobre o que não mudei: o formato "R$" #,##0.00 simples (colunas D, E, F, O) sai compacto e alinhado à direita — no seu screenshot do Excel ele também é compacto, então já estava fiel.

continuar aproximando do Excel, os próximos candidatos naturais seriam: alça de preenchimento funcional (arrastar para copiar/série), autofit de coluna por duplo clique na borda do header, e menu de contexto (inserir/excluir linhas com deslocamento de fórmulas).