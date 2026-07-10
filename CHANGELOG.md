# Changelog

Todas as alterações relevantes deste projeto serão documentadas neste arquivo.

## 1.0.0 — 2026-07-10

Alterações introduzidas pelo commit `a97f3e0`.

### Editor embutível

- Adicionada a fachada pública `XlsxEditorWidget`, que recebe um
  `HTMLElement` host e pode ser usada em Dart Web puro e AngularDart/ngdart 8.
- Adicionado `XlsxEditorConfig` para configurar altura, aparência, modo,
  barras visíveis, título, planilha inicial, tema e callbacks.
- Adicionados os modos `editor` e `viewer`, com alternância em tempo de
  execução por `setMode()` e bloqueio efetivo das operações de escrita no
  visualizador.
- Adicionadas as aparências `excel` e `compact`, incluindo toolbar específica
  para cada apresentação.
- Adicionadas as APIs públicas `loadXlsx()`, `saveXlsx()`, `destroy()`, abrir,
  baixar, desfazer, refazer e aplicar formatação à seleção.
- Implementada limpeza do ciclo de vida, removendo listeners globais,
  observadores, componentes e elementos DOM ao destruir o widget.
- Restringida a captura de clipboard à grade focada, evitando interferência
  com outros componentes da aplicação host.

### Interface e identidade visual

- Criada uma folha de estilos isolada pelo namespace `.xe-*`, adequada para
  múltiplas instâncias na mesma página.
- Aplicada a identidade verde do Excel (`#107C41`) à aparência Excel,
  incluindo titlebar, seleção, cabeçalhos, abas e estados ativos.
- Mantida uma paleta azul alternativa para a aparência compacta.
- Adicionadas titlebar, barra de fórmulas, caixa de referência, status,
  abas de planilha e seletor de zoom configuráveis.
- Adicionados controles de fonte, tamanho, cores, formato numérico, negrito,
  itálico, sublinhado, alinhamento, quebra de texto, mesclagem e bordas.
- Integrado o conjunto de ícones Tabler, com fontes e licença distribuídas
  como assets do pacote.
- Implementada injeção idempotente dos estilos do editor e dos ícones.

### Renderização e funcionamento

- Criado `GridTheme` para personalizar gridlines, seleção e cabeçalhos do
  canvas, com os temas `excelGreen` e `blue`.
- Corrigido o canvas em branco após carregamento assíncrono do CSS por meio de
  `ResizeObserver`, incluindo suporte a modais e containers redimensionáveis.
- A shell interna `SpreadsheetApp` passou a aceitar opções de visualização,
  somente leitura, tema, confirmação de saída e callbacks.
- Expostas operações de edição e formatação antes internas para uso pela
  fachada embutível.
- Adicionados callbacks de mudança, seleção, erro e abertura de arquivo.
- Adicionada geração de um XLSX vazio válido quando nenhum arquivo inicial é
  informado.

### Demo e API pública

- Atualizado `lib/xlsx_editor.dart` para exportar a fachada, componentes de UI
  e o gerador de planilha vazia.
- Reformulada a demo web para montar o editor em um container dedicado.
- Adicionados seletores na demo para alternar entre as aparências Excel e
  compacta e entre os modos de edição e visualização.
- Documentado o padrão de montagem e destruição para AngularDart.

### Testes

- Adicionados testes unitários para criação, leitura, edição e round-trip de
  uma planilha XLSX vazia.
- Adicionada uma suíte E2E com `puppeteer: ^3.19.0` que compila a aplicação,
  inicia um servidor em porta livre e executa o Chrome em modo headless.
- Os testes E2E verificam dimensões e pintura do canvas, tema verde, abas,
  navegação e edição de célula, bloqueio no modo visualizador e alternância
  para a aparência compacta.
- Documentados no README os comandos para executar testes unitários e E2E.

### Validação

- `dart analyze` sem problemas.
- 106 testes unitários aprovados.
- 4 testes E2E aprovados no Chrome headless.
