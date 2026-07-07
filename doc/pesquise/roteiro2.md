1. Pesquisa de Mercado: Editores Open Source e Renderização via Canvas
Soluções Open Source Existentes:

https://github.com/TonyGermaneri/canvas-datagrid
https://github.com/unisys12/canvasGrid

https://github.com/meandavejustice/canvas-grid

C:\MyDartProjects\xlsx_editor\referencias

esta é a melhor referencia C:\MyDartProjects\xlsx_editor\referencias\grid-master


Existem excelentes bibliotecas de código aberto que renderizam planilhas complexas (como a sua PGCTIC1) via Canvas para garantir alta performance:
Univer (Sucessor do Luckysheet): É atualmente o padrão-ouro open-source para planilhas web. Ele utiliza uma arquitetura baseada em Canvas e suporta formatação complexa, mesclagem de células e fórmulas [[3], [6]].
x-spreadsheet / Fortune-sheet: Bibliotecas JS focadas em renderização via Canvas API, otimizadas para lidar com milhares de linhas sem travar o DOM [[4], [5]].
Excel-canvas / Glide Data Grid: Focam em virtualização extrema, desenhando apenas o que está visível na tela 
www.npmjs.com
.
O Google Sheets usa Canvas?
Sim. Historicamente, o Google Sheets utilizava um modelo híbrido onde a grade principal (o corpo da planilha) era renderizada via Canvas para garantir performance, enquanto a interface (menus) ficava no DOM [[10], [19]]. Recentemente (a partir de 2021), o Google Docs e o Google Sheets aprofundaram essa migração, abandonando o DOM (HTML) para a renderização de texto e grade, passando a usar Canvas-based rendering de forma massiva para ter controle total sobre a latência de renderização e pixel-perfect cross-browser [[12], [13], [16], [18]].
2. A Arquitetura Híbrida (O "Segredo" da Performance)
Para implementar um editor capaz de abrir sua planilha de economicidade (que possui células mescladas, formatação condicional, moeda e fórmulas) em Dart Puro, você não deve usar tabelas HTML (<table>). O DOM não suporta 1 milhão de nós sem travar.
A Arquitetura Vencedora:
Camada de Renderização (Canvas): Um único elemento <canvas> desenha as linhas, fundos, bordas e textos.
Camada de Interação (Overlay DOM): Um textarea ou input invisível posicionado absolutamente sobre a célula ativa. O Canvas não sabe lidar com cursor de texto, IME (acentuação) ou seleção de texto nativa do navegador. O Google Sheets e o Excel Web fazem exatamente isso: o Canvas desenha o texto, mas quando você dá duplo clique, um input DOM aparece por cima para capturar a digitação.
3. Plano de Implementação Detalhado (Dart 3.6.0 + web: ^1.1.1)
O pacote web substitui o dart:html usando interop via dart:js_interop. Abaixo está o roteiro técnico para construir o motor.
Fase 1: Setup e Inicialização do Canvas (Retina Display)
O primeiro desafio é garantir que o canvas não fique "borrado" em telas de alta densidade (Retina).
dart
1234567891011121314151617181920212223
Fase 2: Parser XLSX e Modelo de Dados
Sua planilha possui células mescladas (ex: LOTE 1 - PMRO ocupando 16 colunas) e formatação condicional ("VÁLIDO", "EXCESSIVAMENTE ELEVADO").
Dependências: Use o pacote archive para descompactar o .xlsx (que é um ZIP) e o pacote xml para ler sheet1.xml, styles.xml e sharedStrings.xml.
Estrutura de Dados (Sparse Matrix): Não crie listas de listas gigantes. Use um Map<int, Map<int, Cell>> onde a chave é o índice da linha/coluna.
Merge Cells: O XML contém <mergeCells><mergeCell ref="A1:P1"/></mergeCells>. Você deve armazenar isso em uma estrutura de "Bounding Boxes". Na hora de renderizar, se a célula atual for a "cabeça" do merge, você desenha o texto e o fundo abrangendo a largura total das 16 colunas. Se for uma célula "escrava" (dentro do merge), você ignora a renderização de texto e bordas internas.
Fase 3: Motor de Renderização (Virtualização)
Você só deve desenhar o que o usuário está vendo (Viewport).
dart
123456789101112131415161718192021222324252627
Otimização: Use requestAnimationFrame do pacote web para sincronizar a renderização com a taxa de atualização do monitor (60fps).
dart
1234
Fase 4: Hit-Testing (Mapeamento de Clique)
Como saber em qual célula o usuário clicou se tudo é apenas pixels no Canvas?
Pré-computação: Mantenha dois arrays: cumulativeColWidths e cumulativeRowHeights.
Busca Binária: Quando o evento mousedown disparar, pegue as coordenadas offsetX e offsetY. Faça uma busca binária nesses arrays para descobrir o índice da coluna e da linha em tempo 
O
(
log
⁡
N
)
O(logN).
dart
123456
Fase 5: O Editor de Células (O "Input Fantasma")
Para editar a célula R$ 303,096.17, você não pode digitar no Canvas.
Crie um HTMLTextAreaElement invisível ou opaco (opacity: 0) e posicione-o com position: absolute exatamente sobre as coordenadas da célula ativa.
Quando o usuário pressiona uma tecla (capturada via keydown no documento), o foco vai para esse textarea.
Quando o usuário clica na "Formula Bar" (que é um input DOM normal), o textarea fantasma é escondido e a barra de fórmulas assume.
Formatação: Ao perder o foco (blur), o motor de fórmulas avalia o conteúdo. Se for um número, o formatador aplica a máscara R$ ##0,00 (baseado no numFmtId do XML do Excel) e o Canvas redesenha o texto formatado.
Fase 6: Motor de Fórmulas (AST e Grafo de Dependência)
Sua planilha usa médias e percentis (MÉDIA DOS DEMAIS VALORES, 25%).
Lexer/Parser: Implemente um algoritmo Shunting-yard para converter strings como =A1+B2*0.25 em uma Árvore Sintática Abstrata (AST).
Grafo de Dependência: Crie um mapa Map<String, Set<String>> onde a chave é a célula e o valor são as células que dependem dela.
Recálculo Sujo (Dirty Flag): Quando o usuário altera a célula B2, você marca B2 e todos os seus dependentes no grafo como "sujos" (dirty). No próximo frame de renderização, apenas as células sujas são reavaliadas.
4. Resumo das Dependências (pubspec.yaml)
Para este projeto, evite pacotes que tentam "adivinhar" o HTML. Use a stack moderna do Dart 3.6:
yaml
123456789
5. Desafios Específicos da sua Planilha (PGCTIC1)
Cabeçalhos Repetitivos: Sua planilha tem cabeçalhos que se repetem em cada linha (ex: Migração / Implantação...). O parser deve ler isso corretamente do sharedStrings.xml para não estourar a memória.
Cores Condicionais: Palavras como "VÁLIDO" (verde) e "EXCESSIVAMENTE ELEVADO" (vermelho) provavelmente usam Conditional Formatting Rules no XML ou estilos diretos. Seu motor de renderização Canvas deve suportar ctx.fillStyle = cor antes de chamar ctx.fillText().
Agrupamento de Lotes: A planilha possui "LOTE 1", "LOTE 2". Isso sugere que você precisará implementar suporte a Múltiplas Abas (Worksheets), onde cada aba é uma instância separada do seu SheetEngine e DataModel, alternando via abas DOM na parte inferior da tela.
Este plano fornece a base para um clone do Excel/Google Sheets nativo em Dart, com performance de nível de produção e fidelidade visual ao seu arquivo original.