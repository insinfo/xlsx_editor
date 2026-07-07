Pesquisa de Soluções Open‑Source e Renderização via Canvas
Editores e Renderizadores de Planilhas XLSX em Código Aberto
Luckysheet

Repositório: dream-num/Luckysheet

Linguagem: JavaScript

Renderização: usa canvas para a grade principal e sobreposições HTML para edição.

Funcionalidades: suporte a XLSX (leitura/escrita via SheetJS), fórmulas, mesclagem de células, gráficos, formatação condicional.

Licença: MIT.

Handsontable

Repositório: handsontable/handsontable

Linguagem: JavaScript

Renderização: puramente baseada no DOM (tabelas, divs). Não utiliza canvas.

Licença: comercial / código aberto para usos não comerciais.

SheetJS (xlsx)

Repositório: SheetJS/sheetjs

Função: biblioteca de leitura/escrita de XLSX, não é um editor visual.

É a base de parsing para muitos editores, incluindo Luckysheet.

OpenSpout (antigo box/spout)

Linguagem: PHP

Finalidade: leitura/escrita de XLSX em servidor, sem renderização.

Canvas‑Datagrid

Um grid leve com renderização em canvas, mas não lida com XLSX nativamente.

Conclusão: Existe apenas um editor open-source que renderiza via canvas e oferece suporte XLSX pronto – o Luckysheet. Os demais ou são DOM‑based ou são apenas parsers.

O Google Sheets é Renderizado em Canvas?
Sim. Diversas análises técnicas e inspeções do DOM comprovam que a grade principal do Google Sheets é desenhada em um elemento <canvas>.

A equipe do Google utilizou canvas desde a versão reescrita por volta de 2013, para obter performance fluida com rolagem, zoom e formatação condicional complexa.

As interações de edição (célula ativa, fórmula bar) são feitas com sobreposições HTML posicionadas via JavaScript.

Referência: artigos de engenharia como “The Making of the new Google Sheets” e análises em blogs (ex.: “Google Sheets UI – the Canvas Grid”).

Esse modelo híbrido (canvas para o grid + HTML para edição) é o padrão de referência para planilhas web de alto desempenho.

Plano Extremamente Detalhado para Implementar um Editor de Planilhas XLSX Puramente em Dart (Web) com Renderização em Canvas
1. Contexto e Restrições
Linguagem: Dart puro (sem Flutter) com SDK ^3.6.0.

Dependência única: web: ^1.1.1 (acesso às APIs do navegador).

Sem pacotes externos para XLSX, ZIP ou XML. Tudo deve ser implementado usando as APIs nativas do navegador via interop (CompressionStream, DOMParser, etc.).

Objetivo: carregar, visualizar e editar o arquivo PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx com fidelidade razoável, utilizando canvas para renderização.

2. Arquitetura Geral
text
[Arquivo XLSX] 
    → Leitura (FileReader + CompressionStream) 
    → Parsing XML (DOMParser)
    → Modelo de Dados (Dart classes)
    → Renderizador Canvas (grid, células, estilos)
    → Camada de Interação (mouse/teclado, sobreposição HTML para edição)
    → (Opcional) Motor de Fórmulas
    → Geração/Salvamento XLSX (CompressionStream para ZIP)
Toda a lógica estará em Dart, exceto a chamada às APIs do browser via web package.

3. Etapas de Implementação (Fase 1: Leitura e Visualização)
3.1. Carregar o Arquivo
Criar um <input type="file"> via document.createElement.

Escutar evento change, obter o arquivo: File file = input.files.first.

Ler como ArrayBuffer: await file.arrayBuffer() (via JS interop).

Converter ArrayBuffer para Uint8List do Dart.

3.2. Descompactar o ZIP (XLSX é um ZIP)
Usar CompressionStream (formato 'deflate-raw') e DecompressionStream.

Como um ZIP contém múltiplas entradas, é necessário implementar um parser de estrutura ZIP manualmente (local file headers, central directory) para extrair os arquivos XML (ex.: xl/sharedStrings.xml, xl/styles.xml, xl/worksheets/sheet1.xml).

Alternativa: criar um ReadableStream a partir do ArrayBuffer e processar os chunks.

3.3. Parsing dos XML do XLSX
Para cada arquivo XML extraído, converter o Uint8List em string (UTF‑8) e usar DOMParser para analisar.

Estruturas a processar:

Shared Strings (xl/sharedStrings.xml): tabela de strings únicas referenciadas por índices nas células.

Styles (xl/styles.xml): fontes, preenchimentos, bordas, formatos numéricos.

Sheet data (xl/worksheets/sheet1.xml): linhas, células com referência (r), tipo (s=string, n=número, etc.) e estilo.

Workbook (xl/workbook.xml): nomes das planilhas, relações.

Mapear cada elemento XML para objetos Dart simples (ex.: CellData com valor, tipo, styleId).

3.4. Modelo de Dados
Criar classes imutáveis ou mutáveis:

dart
class Spreadsheet {
  List<Sheet> sheets;
  SharedStrings sharedStrings;
  Styles styles;
}
class Sheet {
  String name;
  Map<String, Cell> cells; // key = "A1", "B2", etc.
}
class Cell {
  dynamic value;
  CellType type; // string, number, boolean, formula
  int styleIndex;
}
class Styles { ... }
Aplicar as strings compartilhadas e mapear os índices de estilo para valores concretos (cor, tamanho fonte, borda, etc.).

4. Renderização Canvas (Fase 2)
4.1. Configurar o Canvas
Criar um HTMLCanvasElement via document.createElement('canvas') e definir seu tamanho para ocupar a área visível.

Obter o CanvasRenderingContext2D com canvas.getContext('2d').

4.2. Medidas e Layout
Definir dimensões padrão: coluna largura ~100px, linha altura ~25px (ou ler do XLSX se houver definições de tamanho customizado).

Calcular larguras e alturas acumuladas para transformar coordenadas de célula (col, row) em pixels.

4.3. Desenho do Grid
Implementar um renderizador que:

Limpa o canvas.
Desenha o fundo branco.
Desenha linhas de grade (traços finos cinza).
Itera sobre as células visíveis na viewport (com base no scroll atual).
Para cada célula visível:
Preenche o fundo com a cor de preenchimento (do estilo).
Aplica alinhamento horizontal/vertical.
Desenha o texto (com fillText) usando a fonte definida no estilo (tamanho, negrito, cor).
Desenha bordas (top, left, right, bottom) conforme estilo.
Para performance, não desenhar células vazias, a menos que tenham estilo que afete visualmente (ex.: cor de fundo).

4.4. Rolagem e Viewport
Escutar eventos de wheel para rolagem vertical/horizontal, ou adicionar barras de rolagem HTML sincronizadas com o canvas.

Manter scrollLeft e scrollTop e apenas desenhar as células entre startRow = scrollTop / rowHeight e endRow = (scrollTop + canvasHeight) / rowHeight.

A cada mudança de scroll, redesenhar o canvas inteiro (usar requestAnimationFrame para suavidade).

4.5. Seleção de Células
Desenhar um retângulo azul translúcido sobre a célula selecionada.

Detectar clique no canvas (canvas.onClick): calcular col/row a partir das coordenadas do mouse e das larguras acumuladas.

5. Edição (Fase 3)
5.1. Entrada de Dados
Ao dar duplo clique em uma célula, exibir um <input> HTML posicionado absolutamente sobre a célula (calculando as coordenadas screen do canvas).

O input deve ter a mesma fonte e alinhamento da célula.

Ao perder o foco (blur) ou pressionar Enter, capturar o valor, atualizar o modelo e redesenhar o canvas.

5.2. Fórmulas
Para suporte inicial, armazenar a fórmula como texto (string iniciada com =) e exibi‑la na célula.

Para avaliação real, construir um parser simples de expressões e um avaliador que suporte funções básicas (SUM, AVERAGE, IF, referências de célula).

O avaliador pode ser acionado quando uma célula dependente é alterada (requer grafo de dependências).

Essa parte é opcional, mas o arquivo de exemplo provavelmente contém fórmulas que precisam ser preservadas.

6. Salvamento (Fase 4)
Gerar a estrutura XML do XLSX (workbook, shared strings, styles, sheet data) a partir do modelo editado.

Construir um arquivo ZIP em memória, novamente usando APIs do navegador: empacotar cada XML como entrada e comprimir com CompressionStream se desejado (ZIP store = sem compressão é mais simples para início).

Criar um Blob a partir do Uint8List final e acionar download via URL.createObjectURL.

7. Otimizações e Desafios Técnicos
Medição de texto: usar context.measureText() para calcular largura e truncar com "..." se necessário.

Cache de estilos: evitar recriar strings de fonte a cada frame; pré‑calcular os estilos.

Offscreen Canvas: para grids muito grandes, pré‑renderizar regiões em offscreen canvas e copiá‑las para o canvas visível (técnica de tiles).

Manipulação de ZIP puro: o parser do formato ZIP é complexo, mas factível. Aproveitar a CompressionStream do navegador simplifica a descompressão, mas ainda é necessário ler os cabeçalhos manualmente.

Performance de rolagem: manter um buffer de células visíveis e atualizar apenas quando o scroll mudar. Evitar redesenhar tudo se apenas a seleção mudar (usar camadas: fundo + grid + seleção).

8. Cronograma Sugerido
Fase	Descrição	Semanas
1	Leitura do arquivo XLSX, descompactação ZIP e parsing XML básico (shared strings, sheet data)	2
2	Modelo de dados, parser completo de estilos	1
3	Canvas: desenho do grid, rolagem, seleção de células	2
4	Edição via sobreposição HTML, atualização do modelo	1
5	Suporte a fórmulas (parser e avaliador básico)	2
6	Geração do XLSX e download	1
7	Testes com o arquivo real, ajustes de estilos e correções	1
Considerações Finais
Este plano adota uma abordagem híbrida canvas + HTML, comprovada pelo Google Sheets e pelo Luckysheet. A implementação totalmente em Dart, sem pacotes externos, exige investimento na construção manual do parser ZIP e do motor de XLSX, mas é viável graças às APIs modernas dos navegadores acessíveis via package:web. O resultado será um editor leve, de alto desempenho, e que pode ser estendido conforme necessário.

