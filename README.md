# xlsx_editor

## Testes

```bash
dart test
dart test e2e_test/editor_e2e_test.dart
```

O segundo comando usa `puppeteer: ^3.19.0`, compila a aplicação web, inicia
um servidor local em uma porta livre e executa os testes no Chrome headless.

Editor de planilhas `.xlsx` estilo Excel/Google Sheets, **100% Dart** (sem
dependências externas além de `package:web`), renderizado em HTML5 Canvas.

Plano/arquitetura: [doc/PLANO.md](doc/PLANO.md).

## Rodar

```bash
dart pub get

# desenvolvimento (com hot reload da toolchain web)
dart run build_runner serve web:8080

# ou build de produção
dart run build_runner build --release -o build
dart run scripts/serve.dart build/web 8088
```

Abre `http://localhost:8080` — a planilha-alvo (`web/planilha.xlsx`) é
carregada automaticamente. Use 📂 na toolbar para abrir outro arquivo e 💾
(ou Ctrl+S) para baixar o `.xlsx` editado.

## Testes

```bash
dart test                      # VM: zip/xml/reader/writer/numfmt/fórmulas
dart run scripts/smoke_zip_xml.dart
dart run scripts/ui_screenshot.dart   # screenshots headless do app compilado
```

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `lib/src/zip`, `lib/src/xml` | ZIP (inflate/deflate/CRC32) e XML (SAX+DOM) em Dart puro, vendorados de `canvas-editor-port` |
| `lib/src/model` | Workbook, worksheets (grade esparsa), estilos OOXML, tema |
| `lib/src/xlsx` | Leitor e gravador round-trip preservador |
| `lib/src/numfmt` | Motor de formatos numéricos ECMA-376 (R$, seções, [Red], datas) |
| `lib/src/formula` | Tokenizer, parser Pratt, avaliador, grafo de dependências, pt-BR ↔ en-US |
| `lib/src/layout` | Prefix sums, hit-test O(log n), retângulos de merges |
| `lib/src/render` | Renderizador canvas virtualizado (fundos, gridlines, texto, bordas, imagens, seleção, headers) |
| `lib/src/ui` | Shell like-Excel: toolbar, barra de fórmulas, abas, editor de célula, clipboard, undo/redo |

## Atalhos

Setas/Tab/Enter (navegar), F2 ou duplo clique (editar), Delete (limpar),
Ctrl+Z/Y (desfazer/refazer), Ctrl+B/I/U (fonte), Ctrl+C/X/V (clipboard TSV),
Ctrl+S (salvar). Fórmulas em pt-BR: `=SOMA(A1;B2)`, `=MÉDIASE(...)`.
