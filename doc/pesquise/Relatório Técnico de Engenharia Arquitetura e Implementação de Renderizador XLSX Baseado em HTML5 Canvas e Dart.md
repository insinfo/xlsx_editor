Relatório Técnico de Engenharia: Arquitetura e Implementação de Renderizador XLSX Baseado em HTML5 Canvas e Dart (WebAssembly)
1. Introdução e Contextualização Tecnológica
A engenharia de interfaces web tem testemunhado uma mudança tectônica na forma como aplicações densas em dados, particularmente planilhas eletrônicas, são renderizadas pelo navegador. O modelo arquitetural convencional, que depende da manipulação do Document Object Model (DOM) através da injeção de elementos estruturais como tabelas e divisões em cascata, demonstra falhas catastróficas de escalabilidade quando submetido a dezenas de milhares de nós ativos simultaneamente. A resposta da indústria de software a este gargalo de processamento tem sido a migração massiva para a renderização direta via HTML5 Canvas. Esta técnica permite que a aplicação assuma o controle imperativo do motor gráfico do navegador, ignorando completamente os dispendiosos ciclos de recálculo de layout e repintura do DOM, desenhando a interface como um bitmap unificado.

O presente documento consubstancia uma pesquisa arquitetural exaustiva e fornece um plano de engenharia de software rigorosamente detalhado para a implementação de um editor e renderizador de planilhas Office Open XML (XLSX). A concepção deste sistema baseia-se em requisitos tecnológicos contemporâneos e estritos: a utilização exclusiva da linguagem Dart, alinhada com as especificações do SDK na versão 3.6.0 ou superior, e a adoção peremptória do pacote web (versão 1.1.1 ou superior) para interoperabilidade com o navegador, em total substituição à biblioteca legada dart:html. Esta modernização do ecossistema Dart é motivada pela compatibilidade com a compilação para WebAssembly com Garbage Collection (WasmGC), estabelecendo um novo limiar de desempenho para aplicações web compiladas.   

O objeto empírico que baliza o dimensionamento desta arquitetura é o documento fornecido sob a nomenclatura "Planilha de Economicidade - Gestão Pública". A análise da topologia de dados deste arquivo orienta as decisões de projeto em relação ao mapeamento de memória, ao algoritmo de corte visual (viewport clipping) no Canvas e ao mecanismo de grafo de dependência para avaliação de fórmulas. Através da dissecação de soluções líderes de mercado, notadamente a arquitetura do Google Sheets e projetos de código aberto baseados em Canvas, o relatório estabelece um arcabouço metodológico para construir um componente de edição de alto desempenho de forma puramente isomórfica em Dart.   

2. Análise Estrutural e Topológica do Artefato de Referência
Para que o motor de renderização seja projetado com precisão heurística, é indispensável executar uma taxonomia profunda sobre os dados contidos na planilha alvo. O arquivo "PGCTIC1_-PE-Planilha_de_Economicidade-_Gestão_Pública.xlsx" representa um instrumento complexo de modelagem de custos corporativos e governamentais, cujo arranjo espacial impõe desafios diretos ao ciclo de pintura gráfica e à persistência em memória.   

A topologia da planilha não é uma matriz de dados uniforme, mas sim uma coleção esparsa de blocos de dados sumarizados, intercalados por cabeçalhos mesclados e espaços vazios. Observa-se a divisão lógica em "Lotes", como "LOTE 1 - PMRO", "LOTE 2 - FUNDAÇÃO DE CULTURA", "LOTE 3 - SAAE" e "LOTE 4 - OSTRASPREV". Cada lote contém uma estrutura de cabeçalho que subordina múltiplos itens orçamentários, descrevendo serviços de migração, implantação, locação de licenças de uso por meses e suporte técnico.   

A complexidade arquitetural que o renderizador precisará absorver inclui o gerenciamento de células fundidas, a heterogeneidade tipológica e as equações inter-planilhas. O arquivo é composto por uma folha principal e uma folha acessória de "Composições". Na aba principal, a disposição dos dados exige um sistema de coordenadas capaz de abrigar textos densos e cálculos de valores em pontos flutuantes, como o registro de "VALOR UNITÁRIO ESTIMADO (MÉDIA)" e a quantificação algorítmica da "MÉDIA DOS DEMAIS VALORES".   

A tabela a seguir sistematiza as características morfológicas encontradas na planilha e a consequente exigência de engenharia para o renderizador Dart:

Característica da Planilha OOXML	Exemplo Encontrado no Artefato Alvo	Implicação Arquitetural para o Renderizador Canvas
Mesclagem de Células Espaciais	"LOTE 1 - PMRO" ou "COMPARATIVO DOS VALORES GLOBAIS"	
Necessidade de desativar a grade (gridlines) interna; cálculo do bounding box englobando colunas adjacentes.

Variação de Formatação Tipográfica	Alinhamento descritivo vs alinhamento numérico de cotações	
O ciclo de renderização deve alternar estados de CanvasRenderingContext2D.textAlign antes do fillText.

Precisão Numérica e Condicionais	Valores como 303096.16666666669 e a flag texto "VÁLIDO"	
O renderizador deve separar o valor primitivo (double) da máscara de exibição (String monetária) formatada para a tela.

Dispersão de Dados Esparsos	Linhas de divisão e blocos estruturais não adjacentes	
Inviabilidade de uso de arrays 2D densos; exigência de instanciar Mapas (HashMaps) de coordenadas matriciais.

Relacionamentos Cross-Sheet	Cálculos de itens buscando bases em "Composições"	
Implementação de um Grafo Acíclico Dirigido (DAG) que suporte resolução de dependência topológica em múltiplas abas.

  
Uma das maiores vicissitudes na construção do modelo de dados é a representação das mesclagens. O formato Office Open XML (OOXML) organiza as células mescladas na tag <mergeCells>, que aponta para um intervalo específico. Durante a leitura do artefato com o parser em Dart, o modelo de memória precisará catalogar estas regiões para que o motor de Canvas saiba que, ao iterar sobre uma célula pertencente a um bloco mesclado, a operação de preenchimento de fundo e contorno deve ser abortada caso a célula não seja a âncora (canto superior esquerdo) da fusão. Ademais, a detecção de valores excessivamente elevados e inexecutáveis, marcados textualmente no documento, sinaliza a presença potencial de formatação condicional que o motor deverá interpretar traduzindo as regras lógicas para cores hexadecimais no momento da pintura.   

3. Análise Sistêmica do Estado da Arte em Renderização de Planilhas Web
Para fundamentar as escolhas arquiteturais da implementação em Dart, uma revisão exaustiva das práticas de mercado e soluções de código aberto demonstra a inevitabilidade matemática do uso do Canvas. As abordagens tradicionais falharam em fornecer a fluidez exigida por usuários corporativos.

3.1. O Caso Paradigmático do Google Sheets e a Mudança Arquitetural
Uma investigação sobre as tecnologias empregadas por aplicações corporativas de escala massiva confirma de maneira resoluta que o Google Sheets é inteiramente renderizado através do HTML5 Canvas. A transição do Google, consolidada em meados de 2021, representou o abandono da arquitetura orientada ao DOM (Document Object Model) em favor de uma superfície de desenho vetorial imperativa.   

O raciocínio subjacente a esta migração ilustra os limites físicos dos motores de navegação web. Em uma representação baseada no DOM, uma visualização moderada de 1.000 linhas por 50 colunas exige a manutenção de pelo menos 50.000 nós no navegador. Cada vez que o usuário executa uma operação de rolagem de tela (scroll), a árvore do DOM é forçada a invalidar e recalcular o layout de todos os nós visíveis e parcialmente visíveis, ocasionando o fenômeno conhecido como Layout Thrashing. Ao encapsular a renderização dentro do elemento Canvas, o Google Sheets efetivamente reduziu o número de nós de interface pesados para um único elemento HTML genérico. Toda a grade de células, textos, cores de fundo e bordas tornou-se um mero arranjo matemático de invocações de pintura (fillRect, fillText, lineTo) submetidas diretamente à aceleração por hardware da unidade de processamento gráfico (GPU).   

Contudo, a engenharia reversa do Google Sheets revela um pragmatismo essencial que deve ser copiado no projeto em Dart: trata-se de um modelo híbrido. Enquanto a grade visual pesada reside no Canvas, o sistema delega as funções de edição direta de texto, manipulação do cursor, detecção de áreas sensíveis para deficientes visuais e menus contextuais flutuantes para elementos nativos do DOM, que são dinamicamente sobrepostos à camada do Canvas quando solicitados pelo usuário. Desenhar algoritmos de seleção de texto complexos, lidar com a área de transferência do sistema operacional e piscar o cursor programaticamente no Canvas provou-se uma empreitada desnecessariamente suscetível a erros, ditando que a simbiose entre o controle do Canvas e os editores efêmeros do DOM é a solução ótima.   

3.2. Ecossistema de Código Aberto e Soluções Canvas
A avaliação do mercado de código aberto reforça a viabilidade e a superioridade da arquitetura Canvas. Diferentes projetos implementaram esta mecânica, demonstrando abordagens valiosas para o plano estrutural em Dart.

O projeto x-spreadsheet manifesta-se como uma biblioteca JavaScript extremamente leve e otimizada para o Canvas, priorizando a performance sem inflar o tamanho do artefato distribuído. A arquitetura deste projeto lida com as mutações visuais calculando com precisão cartesiana os limites do que o usuário vê (Viewport) e limitando os comandos de desenho a esse subconjunto estrito de células, utilizando uma lógica híbrida para injetar textareas invisíveis ou sobrepostas que assumem a captura de digitação. Esta abordagem confirma a premissa de que a edição interativa requer assistência do DOM clássico.   

Em contraste, a suíte Univer oferece uma arquitetura corporativa maciça, servindo não apenas planilhas, mas um ecossistema completo de documentos suportado por Canvas. A genialidade do modelo do Univer reside na sua infraestrutura baseada em Injeção de Dependência, isolando serviços através da separação estrita de preocupações lógicas. Essa filosofia isomórfica possibilita que os algoritmos de renderização e cálculo executem de maneira agnóstica ao ambiente de hospedagem, seja ele o navegador principal, um Web Worker periférico, ou um backend isolado em Node.js. O motor gráfico do Univer é projetado com suporte intrínseco a scroll buffering e composição avançada, o que minimiza a latência perceptual durante interações vigorosas do utilizador.   

Por outro lado, iniciativas menos complexas como o WorksheetJS explicitam os ganhos práticos de quadros por segundo (FPS). Na arquitetura Canvas demonstrada pelo WorksheetJS, o custo da renderização deixou de escalar em função do volume total de dados da planilha, passando a escalar unicamente pela resolução da tela do usuário. O esforço de iteração do motor resume-se a varrer espacialmente entre a startRow e endRow, e startCol e endCol, executando buscas constantes O(1) na matriz de estado, garantindo animações a 60 FPS independentemente do tamanho do arquivo OOXML carregado.   

Outros pacotes de mercado, como o Jspreadsheet, defendem a manutenção do DOM mesclando otimizações avançadas, alegando maior facilidade para modificação e estilização CSS. Entretanto, diante do imperativo técnico e da dimensão estrutural apresentada pelo artefato de economicidade , o sacrifício da capacidade pura de processamento providenciada pelo Canvas em favor de comodidade de estilização DOM é considerado arquiteturalmente inaceitável.   

4. Fundamentos Tecnológicos do Ecossistema Dart e a Mudança para WebAssembly
O requisito basilar deste relatório estabelece a implementação puramente na linguagem Dart, fazendo uso contíguo do pacote web sob a restrição do SDK versão 3.6.0. Esta premissa requer a navegação cuidadosa sobre a atual metamorfose do ecossistema da linguagem em direção ao padrão WebAssembly (Wasm).

4.1. O Ocaso da Biblioteca dart:html e a Emergência do package:web
A trajetória do desenvolvimento web em Dart dependeu historicamente da biblioteca dart:html, que fornecia interfaces abstratas, porém amigáveis, para manipulação de nós do DOM. Contudo, essa biblioteca foi declarada legada e depreciada, tendo sido arquitetada sobre premissas de reflexão e tipagem dinâmica incompatíveis com compiladores restritos modernos. O foco estratégico do Google transferiu-se para compilação via WebAssembly com suporte a Garbage Collection (WasmGC).   

O WebAssembly apresenta um modelo de memória linear seguro que exige a passagem de referências claras e diretas para o lado do JavaScript sempre que se deseja interagir com as APIs do navegador (como o Canvas e o Documento). Bibliotecas nucleares como dart:html, dart:svg, e dart:web_gl careciam do rigor de conversão em tempo de compilação necessário para o WasmGC. O projeto que supre este vácuo tecnológico é o package:web, gerado de modo automático diretamente do Web Interface Definition Language (Web IDL) mantido pela W3C.   

O paradigma imposto pelo package:web força os engenheiros a manipularem os objetos através do tipo JSObject, provido pela biblioteca dart:js_interop. Não existem mais métodos construtores facilitadores no pacote web; a alocação de qualquer elemento HTML precisa invocar as funções globais vinculadas ao contexto documental do navegador, obrigando conversões de tipo estritas (casts) para interfaces correspondentes, como ilustrado nas definições de HTMLCanvasElement e CanvasRenderingContext2D.   

4.2. Complexidades de Interoperabilidade Estrita em Callbacks de Eventos
Uma alteração de paradigma sísmica no modelo do package:web que ditará a arquitetura da camada de interação interativa diz respeito ao gerenciamento e assinatura de funções. No modelo legado, listeners de eventos podiam receber funções anônimas nativas do Dart. Com a imposição da segurança do dart:js_interop, qualquer membro do pacote web que espera receber um callback em JavaScript exige que a função Dart seja empacotada em uma interface JSFunction.   

Isso determina que, ao longo do projeto, qualquer interação para detectar cliques, rolagem de roda do mouse e digitação de teclado passará por uma sintaxe de conversão imperativa. A função utilitária .toJS atua como uma ponte de memória entre o ambiente executivo WasmGC do Dart e o motor V8 do JavaScript do navegador.   

Dessa forma, o rastreamento do mouse sobre o Canvas, crucial para decidir qual célula receberá o cursor de edição, demandará código compatível com a interoperabilidade:

Dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';

void registrarInteracaoGrafica(web.HTMLCanvasElement surface) {
  void eventoDeClique(web.MouseEvent evento) {
    // Cálculo vetorial sobre evento.clientX e evento.clientY
  }
  
  // A conversão.toJS é a garantia criptográfica de tipo para o interop Wasm
  surface.addEventListener('click', eventoDeClique.toJS); // [30]
}
Essas funções de transição exigem cautela arquitetural, visto que aceitam apenas parâmetros que satisfaçam restrições do JSObject ou sejam primitivas reconhecidas nativamente. Uma arquitetura madura modularizará a ponte de interoperabilidade, confinando as chamadas .toJS numa subcamada dedicada a eventos periféricos, impedindo que os vazamentos de tipos JSFunction poluam as regras de negócio puras do processador da planilha.

5. Arquitetura Detalhada: A Camada de Processamento de Dados (Parsing e Memória)
Para transformar um repositório inerte de binários em um ambiente de renderização manipulável, a arquitetura preconiza um modelo de divisão tripartida, inspirada por filosofias isomórficas de separação de responsabilidades (MVC desacoplado). A fundação do sistema é a Camada de Dados, incumbida de dissecar o pacote Office Open XML.

5.1. A Semântica do Formato OOXML e Parsers Compatíveis com Wasm
Arquivos com a extensão .xlsx não são representações textuais brutas, mas contêineres ZIP compactados reunindo uma constelação hierárquica de arquivos XML. Os dados são rigorosamente normalizados; por exemplo, o texto não é alocado diretamente na definição da célula no arquivo sheet1.xml (sob a tag <c>), mas os nós armazenam referências inteiras relativas a um repositório lexical universal guardado em sharedStrings.xml. Este arranjo otimiza enormemente o tamanho físico do arquivo caso existam frases corriqueiras (como "MÉDIA DOS DEMAIS VALORES" na planilha de economicidade) repetidas centenas de vezes. Estilos, cores, fontes, espessura das bordas e metadados de impressão encontram-se segmentados de modo análogo no styles.xml.   

Dado o requerimento de compilar o motor puramente em Dart web, o uso de bibliotecas clássicas de manipulação de sistemas de arquivos (dart:io) é absolutamente vedado, inviabilizando diversos pacotes de legado. A solução indicada pelo projeto consiste no uso contíguo da biblioteca excel_plus.   

A escolha do excel_plus como provedor de ingestão de dados reflete um cálculo de engenharia deliberado. Trata-se de um bifurcamento (fork) do ecossistema da biblioteca original excel, totalmente otimizado para lidar com arquivos imensos e portabilidade universal. O excel_plus é amigável com a WebAssembly (pois suporta processamento de arranjos de bytes diretamente na memória) e consome os XMLs subjacentes recorrendo a metodologias eficientes de leitura SAX (Simple API for XML) orientada a fluxos (streams) ao invés do dispendioso carregamento em árvore completa do DOM XML.   

5.2. Construção do Modelo de Memória Virtual e Esparsa
Uma vez que o arquivo binário do lote "PGCTIC1_-PE-Planilha_de_Economicidade-_Gestão_Pública.xlsx" for passado para o método Excel.decodeBytes() , o renderizador não deve simplesmente transcrever as propriedades da folha para os parâmetros internos, mas reconstruir o modelo físico por meio de virtualização.   

O plano arquitetural exige que o estado mutável do renderizador, batizado como GridDataModel, contenha estruturas flexíveis, abandonando coleções multidimensionais estritas em prol de Mapas Hash e árvores especializadas:

Dicionário de Dimensionamento (Metrics Mapping): Estrutura de dados chave-valor (Map<int, double>) para catalogar as linhas e colunas que sofreram adulteração geométrica face ao tamanho padrão. Se a coluna referenciada não estiver catalogada, a interface do usuário presumirá larguras comuns sem incorrer em falha computacional de alocação de memória.

Repositório Matricial Esparso (Sparse Cell Repository): Uma base de índices cujas chaves correspondam à conversão alfanumérica vetorial (ex: "B2", "AA14"). Somente as células declaradas explicitamente com formatação ou valor ocupam espaço vetorial no repositório. Para otimizar o gargalo algorítmico, o repositório possuirá aceleradores geo-espaciais ou paginação por quadrantes de zonas ativas, fundamentais para resolver sobreposições durante rolagem.   

Tabela de Agrupamentos e Mesclagens (Merge Clusters): Baseada nas indicações de tags <mergeCells> colhidas pelo parser, o repositório mantém uma lista referencial estrita de coordenadas fronteiriças no padrão espaciotemporal ``. O motor gráfico iterará sobre essa tabela primariamente antes da pintura e decidirá silenciar traçados das bordas caso o vetor em tela adentre uma zona de bloqueio declarada na mesclagem.   

Matriz de Tradução Estética (Style Normalizer): O excel_plus extrai informações estéticas contidas na aba de estilos (arquivos OOXML) que devem ser adaptadas rapidamente para as propriedades semânticas do Web Canvas. Cores indexadas ou expressas em representações decimais hexadecimais de ARGB precisam se tornar compatíveis com a sintaxe string do CSS aplicada sobre CanvasRenderingContext2D.fillStyle e .strokeStyle.   

A tabela apresentada elucida o mapeamento tecnológico executado pela Camada de Processamento:

Artefato OOXML Original	Funcionalidade Processada no excel_plus	Mapeamento no Renderizador Interno (GridDataModel)
xl/worksheets/sheet1.xml	Carrega sheet.rows sob demanda.	
Iteração transformadora gravando coordenadas (Row/Col) sobre a Matriz Esparsa (Sparse Cell Repository).

xl/sharedStrings.xml	Descompacta os nós <sst> na inicialização.	
O valor primitivo na célula resgata a string via índice, poupando cópias idênticas.

<mergeCells>	Assinala sheet.spannedItems.	
Inclusão dos vetores quadridimensionais na Tabela de Agrupamentos (Merge Clusters).

Formatação Numérica (Format Id)	Extração de strings como #,##0.00.	
Alimenta a lógica que formata os pontos flutuantes convertendo 303096.166666 em notação de capital corrente.

  
6. Arquitetura Detalhada: A Camada de Renderização Gráfica e Clipping
A pedra angular deste ecossistema arquitetônico repousa sobre a manipulação eficiente das classes interop do pacote web. O CanvasRenderingContext2D atua como a via expressa pela qual milhões de avaliações lógicas adquirem concretude ótica.   

6.1. Inicialização Física, Escalonamento Retina (HiDPI) e Estabilidade Visual
A nitidez textual e a pureza da espessura dos traços da planilha dependem crucialmente de como a malha gráfica interage com monitores de densidade superior de pixels, comuns nos equipamentos contemporâneos (telas Retina, configurações de escalonamento em monitores 4K). A renderização ingênua em HTML produz artefatos ruidosos de rasterização ou o chamado "desfoque" perceptível.

Para anular esta falha anatômica, a instanciação geométrica do renderizador via Dart deve realizar o cálculo compensatório multiplicando a resolução intrínseca dos pixels visuais em paridade com a propriedade devicePixelRatio do ambiente em hospedagem.

O processo imperativo define-se com as invocações sob interoperabilidade Dart-Wasm:

Dart
import 'package:web/web.dart' as web;

web.HTMLCanvasElement instanciarMotorGrafico(web.HTMLDivElement rootContainer) {
  // A construção explícita é forçada, refutando construtores implícitos de outrora
  final viewportCanvas = web.document.createElement('canvas') as web.HTMLCanvasElement; // [43]
  final motorGraficoContexto2D = viewportCanvas.getContext('2d') as web.CanvasRenderingContext2D; // 
  
  // Coleta a escala racional de densidade do monitor hospedeiro
  final floatDensidadeHiDPI = web.window.devicePixelRatio;
  final numLarguraFisica = rootContainer.clientWidth;
  final numAlturaFisica = rootContainer.clientHeight;
  
  // Ocupação do Canvas multiplicada para gerar uma reserva física de pixels superior
  viewportCanvas.width = (numLarguraFisica * floatDensidadeHiDPI).toInt();
  viewportCanvas.height = (numAlturaFisica * floatDensidadeHiDPI).toInt();
  
  // Manutenção elástica da grade no mundo CSS do usuário final
  viewportCanvas.style.width = '${numLarguraFisica}px';
  viewportCanvas.style.height = '${numAlturaFisica}px';
  
  // Calibração fundamental do motor gráfico emulando proporções exatas de interface
  motorGraficoContexto2D.scale(floatDensidadeHiDPI, floatDensidadeHiDPI);
  rootContainer.appendChild(viewportCanvas); // [44, 45]
  
  return viewportCanvas;
}
6.2. O Ciclo de Pintura Ortogonal e o Clipping de Viewport (Janela Visual)
Para que a avaliação volumosa de "MÉDIA DOS DEMAIS VALORES" e dados estatísticos contidos na Planilha de Economicidade fluam sob a régua rígida dos 60 Quadros por Segundo (onde cada processamento completo se esgota em menos de 16,6 milissegundos), adota-se um paradigma matemático pautado estritamente por avaliação subtrativa. A tela descarta agressivamente computações fora do raio cartesiano delimitado.   

O loop contínuo de renderização gráfica, atrelado comumente a requisições de quadros do hospedeiro, procede por intermédio das etapas rigorosas da técnica Double Buffering Lógico, que suprime espasmos gráficos por realizar o cálculo imperativo sobre um buffer interno opaco ao espectador para projeta-lo uníssono apenas quando a cadeia de passos atinge sua totalidade.   

Reconhecimento Geométrico (Cálculo O(1)): A partir da posição absoluta de rolagem global (scroll paramétrico do X e do Y em pixels), a Camada Gráfica intercepta o Dicionário de Dimensionamento e fraciona iterativamente a matemática para deduzir qual coluna está fixada sob o limite esquerdo, e sob o cume superior da janela em exibição visual, denotando a intersecção de linhaInicial (startRow) e colunaInicial (startCol).   

Extinção Universal da Grade Anterior (Limpeza Subtrativa): Previamente ao início do ciclo imperativo, o comando clearRect() é despachado contrapondo as dimensões perimétricas estipuladas do vetor para remover resquícios fantasmagóricos do quadro antecedente gerado sob a tela inteira.

Rasterização em Múltiplas Etapas (Layering Sequencial): O laço algorítmico, doravante confinado em operar meramente nas subdivisões entre as marcações iniciais e terminais de colunas, empilha instruções em blocos organizados por complexidade ascendente visando minorar sobrecargas das engrenagens de mudança de estado da aceleração da Placa Mãe Visual (GPU) do dispositivo hospedeiro.

Etapa 0 - Planos de Preenchimento Sólido: Executa a rastreabilidade inicial conferindo as definições colorimétricas injetadas por excel_plus para determinar os quadros condicionados a destaque de CanvasRenderingContext2D.fillStyle injetando polígonos fechados e coloridos, correspondentes a preenchimentos estipulados via PatternFill.   

Etapa 1 - Linhas Estruturais (Gridlines): A rede divisória quadriculada de cor cinza diluída (hexadecimal exato atrelado às normas da Planilha Ostrasprev) é arquitetada varrendo-se horizontalmente e iterando eixos verticais invocando .strokeStyle, e delineando traçados retilíneos por meio do sequenciamento contínuo abstrato de funções beginPath(), moveTo(x,y), e lineTo(x,y) e a deflagração da impressão via .stroke().

Etapa 2 - Enxerto Tipográfico e Poda Perimétrica (Clipping do Contexto Geométrico): Aqui ocorre a alocação densa de bytes de memória tipográfica. Para injetar corretamente formatações longas monetárias dispares à "R$ 303.096,16", o motor adere temporariamente restrições de formatação configurando as atribuições lexicais de .font, .textAlign e .textBaseline para alinhar apropriadamente os números da planilha à direita e as categorizações nominais para a área correspondente na esquerda. Para resguardar cordas literais colossais de vazar esteticamente do seu enclausuramento modular retangular estrito (bleeding de pixels na célula do flanco vizinho), a API Canvas ativa as proteções poligonais delimitadas imperativas: .save() retém as restrições estatais do buffer pretérito, aciona-se os perímetros virtuais via .rect(x,y, w, h), decreta os trincos espaciais com o imperativo .clip(), pinta-se enfim a palavra textual via a diretiva .fillText(string, x, y) e, imediatamente, a proteção espacial perde a vigência com o distensionamento do estado anterior invocado por .restore() reabilitando o desenho periférico total da superfície limítrofe visual subsequente.   

6.3. Solução Estratégica para as Anomalias de Células Integradas
O processo algorítmico precisa incorporar condicionalidades explícitas em todas as etapas mencionadas supracitadas a fim de mitigar fraturas visuais oriundas de células integradas (MergeCells) — característica largamente presente na referida Tabela da Gestão Pública ("LOTE 1 - PMRO").   

A rotina avalia se o vetor bidimensional sobre o qual a cabeça imperativa do cursor percorre em tempo real reside no repositório catalogado "Merge Clusters". A identificação acarreta um reajuste matemático da renderização em que todas as dimensões, contornos virtuais para as amarras matemáticas poligonais (Clipping Region), bem como a formatação central do registro de alinhamento visual convergem-se exclusivamente na amálgama correspondente à dimensão perimétrica espacial unida das colunas subjacentes abrangidas pelo XML original; os quadros remanescentes anexados ao bloco integrado são integralmente descartados da equação e jamais renderizados para fins otimizatórios estéticos da área.   

A tabela infra apresenta as funções nativas da especificação Canvas necessárias para traduzir comandos lógicos em impulsos fotônicos na tela gráfica do usuário:

Operação de Renderização Lógica	API CanvasRenderingContext2D Associada (Dart via package:web)	Função na Construção do Editor
Pintura e Preenchimento Colorido	fillStyle, fillRect(x, y, w, h)	
Gerenciar a paleta de fundo condicional (Background Color de OOXML PatternFill).

Limitação de Transbordamento Textual	save(), rect(), clip(), restore()	
Restringir as cordas longas da Planilha (Média dos Valores) mantendo confinado nos eixos.

Alinhamento Numérico/Textual	textAlign, textBaseline	
Deslocar flutuantes à direita e cabeçalhos ao centro, garantindo similaridade.

Traçado da Rede Gradiente (Grid)	beginPath(), moveTo(), lineTo(), stroke()	O desenho algorítmico contínuo isolado das fronteiras para as partições do vetor sem corrompimento.
Formatação e Peso Tipográfico	font	
Combinação interpolada de espessura de fonte e definição Arial de dimensões dinâmicas (Bold/Itálico).

  
7. Arquitetura Detalhada: O Dilema Interativo e o Modelo Híbrido de Injeção de Input (Camada de Interação)
O HTML5 Canvas é insuperável na reprodução plástica inerte de miríades de quadros numéricos perfeitamente calibrados à GPU. Todavia, sob sua fachada performática esconde-se a incapacidade crônica inata de fornecer e gerir suporte à mecânica fundamental elementar para aplicações e interações de editores e processadores de texto: a ausência de cursores visuais nativos operacionais (Carets), anulações rudimentares das APIs convencionais de Área de Transferência universal (Copiar/Colar) e incompatibilidade avassaladora crônica perante leitores auditivos assistentes na Acessibilidade Global de softwares universais.

Reproduzir os comportamentos fundamentais atrelados a blocos de digitação (borda flutuante piscante com suporte a seleções fragmentárias, sublinhados sintáticos por ferramentas gramaticais locais e seletores flutuantes periféricos universais com o rato físico) constitui-se uma perigosa utopia de sub-renderização artificial em cima do Canvas, incorrendo em imensa lentidão, falhas constantes e imaturidade mecânica fatal perante peculiaridades da formatação e dos navegadores.

Para solucionar essa debilidade arquitetural em Dart, a estrutura adota o rigor empregado pelo Google Sheets e pelas matrizes independentes de projetos de capital aberto (x-spreadsheet), utilizando a sistemática denominada Técnica de DOM Overlay e Intervenção Dinâmica Híbrida.   

7.1. Detecção Tátil e Transcrição Geométrica (Hit-Testing Espacial)
Para possibilitar interação seletiva entre homem e máquina, a arquitetura injetada no ecossistema subjacente amarra-se intrinsicamente a receptores globais dos impulsos elétricos disparados periféricos (rato e teclas alfanuméricas). Utilizando novamente a ponte obrigatória de interoperabilidade WasmGC por vias de cast do tipo primitivo (conversão .toJS), intercepta-se a emissão orgânica de disparos da sub-estrutura do DOM atrelada perimetralmente na camada base Canvas.

O evento base de captação reativa web.MouseEvent dispara sob cada deslize tangível efetuado com o componente físico. Contudo, eventos disparam baseados na métrica vetorial associada restritamente e exclusivamente às marcações relativas à página (offsetX e offsetY). A responsabilidade primária do componente iterador na interface emulação baseia-se primordialmente na formulação retroativa matemática que englobe também o diferencial escalar global das variáveis e medidas rolantes somadas aos deslocamentos globais verticais ou transversais (scrollX e scrollY), varrendo retroativamente a subcamada de chaves estruturantes Dicionário de Dimensionamento a fim de reverter as equações matemáticas complexas e decodificar perfeitamente sob qual célula tabular hipotética exata a interrupção temporal foi requisitada.   

7.2. A Orquestração de Overlay e a Simbiose da Janela Mutável Absoluta
A confirmação assertiva e reativa a um toque agressivo pontual (dblclick) sobre uma métrica decodificada como válida instrui o sistema algorítmico do Controlador em Dart a suprimir os traços estéticos impressos temporariamente relativos a célula correspondente submetendo as demais à persistência estática comum. O Canvas 2D cessa o desenho da string específica durante as requisições ativas vindas do vetor interativo.

Imediatamente após a invalidação transitória passiva gráfica e efêmera do quadro delimitado, a classe construtora instancializa programaticamente através das prerrogativas abstratas do package:web, operando os elementos do DOM isolados com requisições globais do nível estruturante nativo instanciando, de modo transitório imperativo, uma arquitetura web.HTMLTextAreaElement ou sua derivada de texto simples flutuante (Input).   

Essa divisão nativa recém germinada e orquestrada de injetar propriedades intrínsecas ao invólucro do DOM não pertence ao fluxo cartesiano das demais disposições em grade da folha de estilos CSS da subcamada; seu comportamento visual encontra-se estritamente delimitado e enjaulado à formulação estética absoluta espacial de formatação. O bloco de estilo injetado (CSSStyleDeclaration) aciona prerrogativas diretas estritas perimetrais calculadas ao micrômetro no Canvas :   

position = 'absolute' garante que a janela tátil do motor evada restrições espaciais,

top e left recebem perfeitamente em pixels a projeção correspondente atrelada ao limite geométrico vetorial retornado da fase hit-testing da arquitetura global,

width e height encerram o perímetro da injeção nativa imitando emulando as restrições arquiteturais limítrofes exatas em simetria das marcações em grade estipuladas.

A instrução derradeira força organicamente e subitamente um roubo artificial das prerrogativas lógicas espaciais de prioridade ao injetar foco coercitivo (.focus())  sobre essa arquitetura intrusiva transitória efêmera de manipulação híbrida.   

O usuário orgânico usufrui agora da imutável prerrogativa universal elementar do navegador para conduzir seleção contígua nativa e correções da matriz interativa textual amparada pela completude dos periféricos acessíveis. Após a submissão dos cálculos manipulados textuais pela finalização de ciclo temporal por perda espacial interativa (Evento blur) ou validação alfanumérica contígua forçada por gatilho ativo direto (Evento de Disparo das teclas como Enter processadas por meio orgânico de interceptação passiva web.KeyboardEvent) , a subcamada interativa em Dart extrai implacavelmente a submissão textual modificada (input.value) remetendo ao controlador basal primário e procede violentamente por extirpar e implodir fisicamente pelo desmembramento temporal orgânico no repositório de matrizes via remoção da tag .remove() na base principal estrutural da janela, procedendo posteriormente reabilitar a projeção passiva na Camada de Renderização do Canvas e o reinício da formulação visual matemática global de avaliação sequencial da árvore topológica para reconstruir os impulsos retangulares coloridos estáticos, agora impregnados nas variáveis da Matriz de Transformação atualizada.   

8. Arquitetura Detalhada: Lógica Analítica Transversal de Fórmulas (Camada Motriz Numérica e Resolução de Grafos)
Uma Planilha OOXML de gestão e economicidade complexa possui arquitetura lógica atada fundamentalmente aos parâmetros estatísticos descritos explicitamente nas instâncias originais da Tabela Padrão anexada em análise, em que métricas estatísticas essenciais como "MEDIANA", "MENOR PREÇO" e "PREÇO VÁLIDO ESCOLHIDO" reagem sistemicamente a qualquer adulteração intrínseca imposta em blocos colaterais das cotações primárias estipuladas por concorrentes diretos variados ("FORNECEDORES", "Contrato Búzios").   

A simples intersecção mutável em uma aba secundária adjunta (Composições) afeta a matemática de orquestração vetorial na raiz unificada primária global gerando abalos colossais perante inter-referências (Cross-Sheet Referencing). Uma planilha analítica submetida a uma mutação orgânica por entrada visual demanda o emprego rigoroso de recálculos instantâneos estruturados eficientes sob as barreiras computacionais perimetrais da interface gráfica.   

8.1. Parser Analítico Estruturado de Árvore Sintática e Avaliação de Equações
Enquanto o excel_plus ingere organicamente e primitivamente as composições e cordas binárias brutas das representações, a alteração estipulada e injetada no vetor de sub-modificação do modelo de arquitetura efêmera text-area (Overlay Input) das amarras formulatórias das instâncias primitivas ativadoras de somatórias (exemplo representativo genérico: =SOMA(A1:C10) + MEDIA(B4)) exige a adoção imperativa fundamental orgânica e modularidade intrínseca advinda via um avaliador sintático gramatical desmembrador da linguagem e formatação natural computacional.

Na plataforma e ambiente restritivo estático WebAssembly da arquitetura subjacente compilatória de suporte do Dart nativo puro, instâncias bibliotecárias isomórficas restritivas orgânicas fundamentais providas por projetos open-source auxiliares atrelados diretamente a desmembramentos complexos em modelos formais fundamentais, a exemplo modularizado de analisadores léxicos abertos (formula_parser projetado sobre os módulos formais do petitparser), gerenciam e particionam meticulosamente o string contíguo estático do processador textual avaliando cada token relacional ou algébrico isoladamente para construir as Árvores de Sintaxe Abstrata (Abstract Syntax Trees - AST) em tempo linear garantido compatível com restrições gráficas.   

Esta topologia orgânica submete e converte, por derivação léxica hierárquica fundamental matemática perimetral analítica os identificadores nominais em referências vinculantes ao GridDataModel extraindo os valores subjacentes alocados ativando as substituições vetoriais temporais dinâmicas instantâneas em cálculos primitivos diretos na base.   

8.2. Ordenação Topológica de Malhas Computacionais Através do Algoritmo de Grafo de Kahn e Resolução de Dependência
A repintura estrutural total (Total Recalculation Algorithm) na completude vetorial massiva densa e difusa da arquitetura, submissa a qualquer e toda digitação ou mutação escalar vetorial elementar basal trivial do usuário final nas dependências da Planilha Ostrasprev submerge organicamente na ineficiência, inviabilizando brutal e fatalmente o limite cronometrado do frame temporal do navegador (os necessários e estritos limites sub-16ms associados inevitavelmente aos FPS globais na taxa de atualização fluida e ininterrupta do ciclo de Canvas).

Para extirpar a sobrecarga impeditiva imposta transversal e geometricamente ao longo dos processos matemáticos nativos WasmGC da CPU isolada em threads individuais de avaliação das equações orgânicas, impõe-se a premissa teórica arquitetural da inserção sistemática do rastreio de um Grafo de Dependência (Dependency Graph) em Modelo de Direcionamento Sem Ciclos - Acíclico (DAG).   

Arestas Relacionais Formais (Edges): Após a descompactação orgânica inicial basal das arquiteturas XML, ou invariavelmente nas mutações de sobreposição temporal injetadas, toda e cada célula portadora subjacente orgânica formal de uma fórmula injeta a dependência das matrizes e vértices matemáticos listadas internamente sob a árvore. Se uma avaliação orgânica de "MÉDIA" requer as referências colaterais de vetores nas extremidades alheias (Exemplo figurativo referencial restritivo das cordas analíticas, a Célula D4 contendo e estipulando formalmente =SOMA(A1:B1) / MEDIA(C1) cria e instaura de imediato ligações unidirecionais ativas direcionadas primitivas orgânicas perimetrais nas estruturas dos grafos alvos mapeados saindo dos vetores A1, B1, e C1, e encadeados topologicamente apontando formalmente em rota para D4).   

Recalculo Ordenado Direcional Incremental: Mediante a modificação e inserção estrita de novos inputs interativos limitantes em A1 através da camada DOM sobreposta sobre a camada Canvas, a avaliação estruturada algorítmica ativa de forma orgânica passiva apenas o desencadeamento topológico subsequente subordinado e as cascateadas lógicas derivadas subjacentes restritas espaciais afetadas. O arranjo estruturante orgânico metodológico iterativo, baseado invariavelmente e inequivocamente nos axiomas e desmembramentos das prerrogativas restritivas do Algoritmo de Kahn, perpassa topologicamente todos e apenas os rastreios dependentes sucessivos lógicos que as chaves mapeadas engatilharem transversalmente validando recálculos iterativos diretos ao rastreio modificado perimetral sem interrupção e recalculações matemáticas cegas superabundantes no resto da planilha intacta estruturada.   

Prevenção Fatal Lógica de Refrações Mútuas e Ciclos Circulares Naturais Iterativos (Depth-First Search Circular References): O empreendimento matemático orgânico das amarras por Busca Estrita em Profundidade DFS (Depth-First Search) atrelado perfeitamente na sub-resolução de Kahn garante passivamente a detecção subjacente de paradoxos na inserção orgânica. Caso, num momento inoportuno displicente, a arquitetura orgânica de D4 exigir indiretamente a arquitetura espacial temporal associada iterativa de A1 simultaneamente exigindo amparo referencial à subcamada contígua temporal restritiva analítica referencial do próprio D4, o loop temporal será diagnosticado previamente nas varreduras prévias passivas suspendendo, imobilizando organicamente e flagrando a referida operação perigosa e alertando ao manipulador nativo da intersecção a ocorrência da referência circular impossível, evitando falência sistêmica Wasm e o estouro perigoso natural impeditivo limitante sistêmico do call stack de tempo de compilação da submissão algorítmica executável restritiva na memória web principal.   

9. Sumário de Otimizações Restritivas Críticas Baseadas no Wasm e Conclusões Técnicas Superiores
Considerando as dimensões estruturais do relatório estipulado, a concepção e engendramento deste construto visual isomórfico calcado invariavelmente nos domínios rigorosos perimetrais estritos em HTML5 Canvas nativos compilados com Dart Puro perpassa imperativos técnicos muito superiores à construção trivial sistêmica relacional associada em JavaScript.

A incorporação das propriedades otimizantes da nova ponte estrita WasmGC que extinguiu o falível ecossistema dart:html insere dinâmicas passivas rigorosas. O acúmulo despropositado imensurável massivo ininterrupto orgânico passivo transitório de coleções geométricas, cordas tipográficas transitórias das clipagens matemáticas estritas durante o processamento do loop central algorítmico do método iterativo do motor de quadros estipula gargalos drásticos perante coletas de refugo automáticas inadiáveis do Coletor de Lixo Wasm (Wasm Garbage Collection limiters). Exige-se imperativamente a manutenção temporal orgânica contínua reusável isolada e restrita baseada na recusa categórica da formulação efêmera recriada ininterrupta, empregando-se Object Pooling Matemáticos (Cache Vetorial Espacial Conjunto) nas instâncias primitivas descartáveis associadas aos vetores.   

Paralelamente, o sequenciamento iterativo da Matriz Esparsa não pode operar cegamente. As instruções injetadas na GPU via CanvasRenderingContext2D sofrem paralisias sutis invisíveis microscópicas de restrições em virtude contínua massiva passiva orgânica de excesso transversal nas requisições conjuntas submissivas das adulterações das mudanças sistemáticas colorimétricas orgânicas perimetrais (.fillStyle). A orquestração topológica temporal do rastreamento gráfico de renderização das zonas matemáticas precisará iterar sub-grupos aglutinados das coleções limitantes estáticas estipuladas, colorindo todos os fundos associados perimetrais ao azul de uma vez exclusiva estrita contígua, modificando organicamente na subsequente contínua interrupção iterativa para o amarelado, suprimindo saltos transversais sistêmicos custosos no motor perimetral das composições da malha WasmGC associada nativamente da ponte restrita V8 Javascript acoplada orgânica isolada no sistema da W3C.

Em síntese unificada diretiva abrangente uníssona: a implementação deste processador de relatórios econômicos restrito  através do Canvas viabilizará rendimentos fotônicos geométricos inatingíveis nativamente pelas restrições físicas subjacentes da subcamada relacional nativa orientada estruturada vetorial das marcações textuais comuns contíguas isoladas da DOM nativa comum estipulada em aplicações web primitivas normais superadas na premissa iterativa global passiva do ecossistema front-end tradicional obsoleto, replicando orgulhosamente integralmente emulando organicamente no Dart a sofisticação iterativa analítica mecânica orgânica visual associada estrutural universal consolidada com exclusividade pela vanguarda hegemônica isomórfica dominante global nos pólos matriciais orgânicos de pesquisa subjacentes contemporâneos abertos dominantes.   


dart.dev
Migrate to package:web - Dart programming language
Abre em uma nova janela

dart.dev
WebAssembly (Wasm) compilation - Dart programming language
Abre em uma nova janela

docs.flutter.dev
Support for WebAssembly (Wasm) - Flutter documentation
Abre em uma nova janela


PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx

learn.microsoft.com
How to: Merge two adjacent cells in a spreadsheet document | Microsoft Learn
Abre em uma nova janela

pub.dev
web library - Dart API - Pub.dev
Abre em uma nova janela

docs.closedxml.io
Cell styles — ClosedXML 0.102.0 documentation
Abre em uma nova janela

worksheetjs.com
Can a Browser Handle 1 Million Rows? (Spreadsheet Perf)
Abre em uma nova janela

hyperformula.handsontable.com
Dependency graph | HyperFormula (v3.3.0)
Abre em uma nova janela

hellointerview.com
Design Spreadsheet with Formulas - Hello Interview
Abre em uma nova janela

c-rex.net
mergeCells (Merge Cells) - c-rex.net
Abre em uma nova janela

learn.microsoft.com
Working with conditional formatting - Open XML SDK - Microsoft Learn
Abre em uma nova janela

thenewstack.io
Google Docs Switches to Canvas Rendering, Sidelining the DOM - The New Stack
Abre em uma nova janela

news.ycombinator.com
Google sheets uses canvas. The strategy you describe is orthoganal to canvas ver... | Hacker News
Abre em uma nova janela

stackoverflow.com
How to force Google Docs to render HTML instead of Canvas from Chrome Extension?
Abre em uma nova janela

reddit.com
Google Docs will now use canvas based rendering : r/programming - Reddit
Abre em uma nova janela

reddit.com
I created a HTML5 canvas based spreadsheet similar to Google Sheets with full formula support. : r/webdev - Reddit
Abre em uma nova janela

web.reogrid.net
ReoGrid Web vs Luckysheet vs x-spreadsheet — which JS spreadsheet to use
Abre em uma nova janela

opencollective.com
x-spreadsheet - Open Collective
Abre em uma nova janela

sourceforge.net
x-spreadsheet download | SourceForge.net
Abre em uma nova janela

news.ycombinator.com
Show HN: X-spreadsheet – A JavaScript canvas spreadsheet for web | Hacker News
Abre em uma nova janela

docs.univer.ai
Custom Canvas Rendering - Univer
Abre em uma nova janela

github.com
dream-num/univer: Univer is a full-stack framework for creating and editing spreadsheets / word processor / presentation on both web and server. - GitHub
Abre em uma nova janela

docs.univer.ai
Univer Architecture
Abre em uma nova janela

codesandbox.io
univer - Codesandbox
Abre em uma nova janela

reddit.com
A web-based JavaScript (canvas) Spreadsheet, like google sheet - Reddit
Abre em uma nova janela

github.com
sdk/CHANGELOG.md at main · dart-lang/sdk - GitHub
Abre em uma nova janela

pub.dev
spark_web | Dart package - Pub.dev
Abre em uma nova janela

github.com
Deprecate legacy HTML/JS libraries/packages · Issue #59716 · dart-lang/sdk - GitHub
Abre em uma nova janela

dart.dev
Getting started with JavaScript interop - Dart programming language
Abre em uma nova janela

stackoverflow.com
Migrating from dart:html to web — how to listen for events? - Stack Overflow
Abre em uma nova janela

learn.microsoft.com
Structure of a SpreadsheetML document | Microsoft Learn
Abre em uma nova janela

stackoverflow.com
How to properly assemble a valid xlsx file from its internal sub-components?
Abre em uma nova janela

learn.microsoft.com
Working with the shared string table | Microsoft Learn
Abre em uma nova janela

stackoverflow.com
Getting cell-backgroundcolor in Excel with Open XML 2.0 - Stack Overflow
Abre em uma nova janela

pub.dev
excel_plus | Dart package - Pub.dev
Abre em uma nova janela

pub.dev
excel_plus 0.0.5 | Dart package - Pub.dev
Abre em uma nova janela

fluttergems.dev
flutter_excel - Dart and Flutter package in CSV, Excel, ODS & Sheets category
Abre em uma nova janela

pub.dev
excel_community | Dart package - Pub.dev
Abre em uma nova janela

libraries.io
excel_plus 0.0.3 on Pub - Libraries.io - security & maintenance data
Abre em uma nova janela

github.com
about-Office-Open-XML/SpreadsheetML/Merge-cells/xl/workbook.xml at master - GitHub
Abre em uma nova janela

forum.mibuso.com
Change excel cell background color using Open xml - Mibuso Forum
Abre em uma nova janela

doc.qt.io
QWidget Class | Qt Widgets | Qt 6.11.1
Abre em uma nova janela

developer.android.com
Graphics modifiers | Jetpack Compose - Android Developers
Abre em uma nova janela

stackoverflow.com
Best approach to draw clipped UI elements in OpenGL - Stack Overflow
Abre em uma nova janela

w3.org
HTML Canvas 2D Context, Level 2 - W3C
Abre em uma nova janela

pub.dev
createLabel function - bones_ui_test library - Dart API - Pub.dev
Abre em uma nova janela

github.com
alexluigit/emacs-grandview: 原非大观。 - GitHub
Abre em uma nova janela

paulirish.com
What feature would improve the web? - Paul Irish
Abre em uma nova janela

w3.org
User Agent Accessibility Guidelines (UAAG) 2.0 - W3C
Abre em uma nova janela

pub.dev
formula_parser - Dart API docs - Pub.dev
Abre em uma nova janela

reddit.com
Open Source Javascript parser and interpreter in Dart. Ready to be used in your Flutter code
Abre em uma nova janela

handsontable.com
New formula plugin - Handsontable 9.0.0
Abre em uma nova janela

learn.microsoft.com
Working with formulas | Microsoft Learn
Abre em uma nova janela

github.com
API Proposal: Formula Evaluation Feature · Issue #1973 · dotnet/Open-XML-SDK - GitHub
Abre em uma nova janela

arxiv.org
Efficient and Compact Spreadsheet Formula Graphs - arXiv
Abre em uma nova janela
