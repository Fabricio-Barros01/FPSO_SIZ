# SPRINTS — índice de execução do FPSO_Siz

Estado de cada sprint: o que já foi entregue, o que o próximo exige. Feito para ser
lido inteiro sem abrir mais nada.

**Manutenção:** ao fechar um sprint, atualize o bloco dele (status → ✅, linha
`Entregue:` com o hash do commit) e marque o próximo como `← ATUAL`.

---

## Estado atual

**SPRINT ATUAL: 5 — Segundo equipamento no registro**

**2291 testes passando** (611 no core, 1680 na interface).

O software dimensiona um separador trifásico horizontal pelo modelo semiempírico de
Stewart & Arnold (2008), com um motor de envelope multi-caso que entrega **um** vaso
atendendo a N correntes e diz qual caso governa cada restrição.

Caso de referência (`config/cases/exemplo_alves_komesu.toml`, 4 casos → 10 cantos):
**d = 6300 mm · Leff = 18,59 m · Lss = 24,78 m · SR = 3,93**, governado pela capacidade
de líquido no caso "Fim de vida", com teto de decantação de 9124 mm.

---

## Sprint 0 — Núcleo headless & motor de envelope ✅

**Objetivo:** a física correta e testada, sem nenhuma dependência de interface.

### Entregue

- `src/interfaces.jl` — `AbstractEquipment`, `AbstractSizingMethod`, `ParameterSpec`,
  `validate`, `defaults`, `with_defaults`. **A interface nunca cita um parâmetro pelo
  nome**: ela itera sobre os descritores que o método declara.
- `src/registry.jl` — `register!`, `equipments`, `methods_for`, registro em `__init__()`.
- `src/units.jl` — conversões e a derivação do coeficiente da Eq. 22. O `4,12×10⁴`
  impresso em Alves & Komesu (2025) é inconsistente com a Tabela 3 do próprio artigo;
  o valor derivado (42152,13) reproduz a tabela com 0,35 % de desvio contra 1,9 %.
- `src/sizing/separator/` — β (Figura 3 resolvida analiticamente, não digitalizada),
  arrasto com convergência amortecida, e os três blocos de Stewart & Arnold.
- `src/engine/envelope.jl` — envelopa a curva `Leff(d)`, não os dados de entrada.
  Correto por construção, sem hipótese de monotonicidade.
- `config/` — constantes e faixas **fora do código**, com proveniência linha a linha.

### Invariantes verificadas por teste

1. **Inviabilidade é estado retornado, nunca exceção** (`test/envelope.jl`, 6 sub-casos).
2. **Caso-ouro**: a varredura reproduz a Tabela 3 do artigo (`test/golden_alves_komesu.jl`),
   com guarda de regressão contra o `4.12e4`.
3. **As constantes vivem no TOML**: um teste procura os dígitos significativos dentro
   dos `.jl` e falha se alguém duplicar (`test/architecture.jl`).
4. **Extensibilidade**: `test/registry.jl` registra um método de fora de `src/` e
   verifica que ele aparece e despacha, sem tocar no core.

---

## Sprint 1 — Interface desktop (Makie) ✅ *(encerrado; substituído no Sprint 2)*

Entregou o dashboard de três colunas, o desenho do vaso em coordenadas reais e os dois
gráficos. Foi aposentado por dois motivos, ambos do GLMakie e nenhum solucionável do
lado do Julia:

- **OpenGL.** O GLMakie usa GLFW, que o Julia baixa como binário JLL pré-compilado que
  procura driver em `/usr/lib/dri`. No NixOS isso exigia ~55 linhas de `LD_LIBRARY_PATH`
  no `flake.nix`; numa máquina sem OpenGL 3.3 o pacote falha **na precompilação**.
- **Empacotamento.** Essa mesma não-relocabilidade impedia um `create_app`: o binário
  levaria o problema para toda máquina de destino.

O layout, o desenho e as decisões de UX sobreviveram — foram portados no Sprint 2.

---

## Sprint 2 — Interface web (Genie) & distribuição (PackageCompiler) ✅

**Objetivo:** a mesma tela, servida ao navegador, e um executável plug-and-play para
Linux e Windows.

### Entregue

**Core relocável** — `src/config.jl`. `const PROJECT_ROOT = joinpath(@__DIR__, "..")`
virou `project_root()`, resolvido em runtime: `FPSOSIZ_RAIZ` → `<bundle>/share/fpso_siz`
(via `Sys.BINDIR`) → dois níveis acima de `src/`. Um `const` com `@__DIR__` congela na
precompilação e apontaria para a máquina que fez o build. `dir_saida()` segue a mesma
lógica, com desvio para a pasta pessoal quando a instalação não é gravável.

**Interface** — `app/` virou pacote (`app/src/FPSOSizApp.jl`) com `julia_main()`.

- Genie **só como roteador e servidor de arquivos estáticos**. Nada de `Genie.Assets`,
  de estrutura MVC ou de Stipple: eles resolvem os próprios arquivos com `@__DIR__` e
  `Base.pkgdir(Genie)`, e o `create_app` não copia diretório-fonte de pacote.
- Desenho e gráficos em **SVG gerado em Julia** (`app/src/desenho/`). A geometria é a
  mesma do Makie, com `Point2f` trocado por uma tupla — o arquivo ficou sem dependência.
- `import FPSOSiz`, nunca `using`: o core exporta `label` e `parameters`, o Genie
  exporta `label`. Com `using` nos dois o erro só aparece quando o handler roda.
- Números atravessam a API como **texto**; quem converte é `Formato.parse_num` e quem
  formata é `Formato.num`, do lado do Julia. A regra PT-BR existe uma vez só.
- O servidor injeta o estado inicial no HTML (`pagina_inicial`), então a primeira
  pintura já vem completa.
- 262 dependências (Makie) → **86**.

**Distribuição** — `build/`.

- `build/build.jl` com `deps | teste | app | pacote | tudo`; `bootstrap.sh` e
  `bootstrap.ps1` instalam o Julia se faltar.
- `app/precompile/aquecimento.jl` exercita o ciclo HTTP inteiro no build.
- A etapa `app` **confere que o bundle roda relocado**: executa o binário a partir de
  `/tmp`, com `JULIA_DEPOT_PATH` inexistente, e exige que ele grave as seis saídas.

**`flake.nix`** — saíram `graficoLibs`, os três `export` de OpenGL e o `mesa-demos`.
Ficaram `gcc` e `gnumake`, que o PackageCompiler precisa para linkar o sysimage.

### Decisões tomadas

| Decisão | Razão |
|---|---|
| Genie puro + front-end em `public/` | Único caminho relocável sob o `create_app`. Ver a nota no topo de `app/src/server.jl`. |
| SVG em vez de PNG | Sem CairoMakie não há rasterizador. SVG é string: zero dependência, e a figura da tela é a mesma do arquivo. |
| Um `AppState` sob `ReentrantLock` | É aplicativo de mesa em `127.0.0.1`, não servidor multi-inquilino. Duas abas compartilham o estado. |
| Cores duplicadas em `app.css`, com teste | A folha de estilo não importa Julia. A duplicação é vigiada em vez de proibida. |
| `create_app` em subprocesso | Carregar o PackageCompiler no processo do build traz problema de *world age*. |

### Defeitos corrigidos no fecho

Todos encontrados por leitura, nenhum produzia status ≠ 200 — é por isso que o
`smoke.jl`, que fala HTTP e não abre navegador, não os alcançava. Cada um levou um teste.

| # | Defeito | Correção |
|---|---|---|
| 1 | `aplicar!` herdava valores **por posição** no vetor. A tela cria e remove casos sozinha, então depois de um "Remover" a posição designava casos diferentes nas duas pontas: o valor do caso removido reaparecia dentro do seguinte, entrando no envelope sem aviso. | `CaseUI` ganhou `id`; a herança passou a ser por identidade (`novo_id`, `state.jl`). |
| 2 | O cursor de diâmetro fazia debounce **sem cancelamento**. Debounce espaça os disparos mas não ordena as chegadas: num arrasto lento uma resposta antiga repintava o desenho num diâmetro já abandonado. | `AbortController` no `fetch`, e `pedir()` engolindo `AbortError`. |
| 3 | `/api/desenho` era **GET e escrevia** `st.d_sel` — que é o diâmetro que Exportar grava. Um reenvio (bfcache, prefetch) mudava o arquivo. | Virou `POST`. Um teste exige que o GET antigo não responda 200. |
| 4 | As ~50 caixas geradas não tinham nome acessível; a barra de status não era região viva; campo recusado se distinguia **só pela cor**. | `aria-label` por caixa, `role="status"`/`aria-live` na barra, `aria-invalid` + `aria-describedby` com a mensagem ao lado da caixa. |
| 5 | `grid-template-columns` com faixas `1fr`: o mínimo automático é `min-content`, e a legenda (`nowrap`) impedia a coluna de encolher. | `minmax(0, 1fr)`. |
| 6 | A nota do topo de `server.jl` afirmava que nenhum caminho de pacote era consultado. `serve_static_file` consulta `bundles_path()` — `joinpath(@__DIR__, "..", "files", "static")` — quando o arquivo não existe. | Nota corrigida; teste fixa 404 limpo para arquivo inexistente. |

### Riscos medidos, não presumidos

- **PackageCompiler 2.4.1 no Julia 1.12.6**: verificado antes de escrever o build, com
  um pacote trivial. Funciona; o binário roda fora do projeto e sem depot.
- **Bundle gerado no NixOS não é distribuível** — linka contra a glibc do `/nix/store`.
  O artefato para outras máquinas sai de container ou de CI. Anotado em `build/LEIAME.md`.
- **Memória na etapa `app`** — não era risco presumido, aconteceu: o `create_app` foi
  morto pelo sistema (código 137 = 128 + `SIGKILL`) deixando meio bundle em `build/out/`.
  Com `incremental = false` o PackageCompiler compila em paralelo e cada thread carrega
  sua cópia do estado do compilador ([PackageCompiler #778][pc778]); em 12 núcleos e
  7,6 GiB isso estoura. O build agora roda o `create_app` com `JULIA_NUM_THREADS=1`, e
  `etapa` traduz morte por sinal em vez de despejar backtrace. `incremental = false`
  fica: é ele que garante a relocabilidade que este sprint inteiro existe para ter.

[pc778]: https://github.com/JuliaLang/PackageCompiler.jl/issues/778

---

## Sprint 3 — Memorial de cálculo na tela ✅

`src/types/results.jl:15` dizia que o `CalcTrace` *"alimenta o painel memorial da GUI"* —
o painel não existia; o rastro só saía no `.txt` exportado. Agora existe.

### Entregue

- **Core:** `block_entries` passou a ser exportada (`src/FPSOSiz.jl`). Era o único
  elo faltando: a função existia em `src/types/results.jl:41` mas o `app/` não a
  alcançava.
- **Rota:** `GET /api/memorial` — GET de verdade, porque só lê. Devolve, por caso, as
  entradas agrupadas nos blocos que o método usou, na **ordem do cálculo**
  (`BLOCOS_MEMORIAL`, em `app/src/report.jl`), com as letras A/B/C de Stewart & Arnold.
  Bloco vazio não vira subtítulo órfão — o vaso bifásico do Sprint 5, que usa A e C sem
  o B, já cabe sem mudança.
- **Tela:** `<details>` recolhido abaixo dos gráficos, com seletor de caso marcando o
  governante. Carrega ao abrir, não a cada Dimensionar: o rastro dos dez cantos é
  grande e o painel é consulta, não operação. Invalidado a cada novo resultado.

### A decisão que faz o aceite ser possível

As linhas atravessam a API **já formatadas**, por `linha_memorial` e `fecho_memorial` —
as mesmas funções que escrevem o `.txt`. Não é economia de código: é a única forma de a
tela e o arquivo não divergirem. O `.txt` é o que vai anexo ao relatório; a tela é o que
se confere antes de anexar. Se cada lado formatasse do seu jeito, se afastariam no
primeiro caso de canto e ninguém notaria.

`fecho_memorial` foi extraída de `escrever_memorial` nesta rodada, pelo mesmo motivo que
`linha_memorial` já tinha sido antes.

**Aceite verificado:** o teste compara linha a linha nos dois sentidos — toda linha da
tela existe idêntica no arquivo, e a contagem por caso bate com
`length(trace.entries)`, então nenhuma entrada ficou de fora. Mais a ordem dos blocos.

---

## Sprint 4 — Casos: abrir, salvar, gerenciar ✅

Até aqui `config/cases/*.toml` era só de leitura: o `AppState()` carregava um conjunto
na abertura e tudo o que se editasse na tela morria com o processo. O programa
dimensionava bem e não guardava nada — não dava para voltar a um estudo no dia seguinte.

### Entregue

- **Core:** `save_case_set(cs, caminho; label)` em `src/config.jl`, inversa exata de
  `case_set_from_config` — número para escalar, `[mín, máx]` para `Interval`,
  `enabled = false` só quando desativado. Escrita à mão, e não por `TOML.print`, porque
  este é um arquivo que a pessoa vai abrir no bloco de notas: `TOML.print` ordena tudo
  alfabeticamente e joga `name` para o meio do bloco. Os números saem por `repr`, que é
  a representação curta **de ida e volta exata** de um `Float64` — um `%.6f` degradaria
  o valor a cada gravação sucessiva.
- **Onde os arquivos ficam:** `dir_casos()`, com a mesma lógica de `dir_saida()`
  (`FPSOSIZ_CASOS` → `config/cases/` se gravável → pasta pessoal). Um programa instalado
  em `/opt` ou em `C:\Program Files` não pode escrever ao lado de si mesmo, e "Salvar"
  não pode falhar por permissão. `dirs_casos()` procura nos dois: os exemplos de fábrica
  continuam à vista, e um arquivo do usuário com o mesmo nome **sombreia** o exemplo.
- **Rotas:** `GET /api/casos/arquivos`, `POST /api/casos/abrir`, `POST /api/casos/salvar`.
  Salvar manda o conteúdo da tela junto: grava-se o que está à vista, não o que o
  servidor tinha da última vez que se clicou em Dimensionar.
- **Tela:** seletor de arquivo acima do seletor de caso, com "Abrir", "Salvar" e
  "Salvar como…". O cadeado marca o que veio de fábrica. Editar marca o estado como
  sujo, e "Abrir" pergunta antes de descartar.

### Decisões tomadas

| Decisão | Razão |
|---|---|
| Os ajustes globais **não** entram no arquivo de casos | Grade de diâmetro e banda de SR são decisão de projeto, não dado de corrente. `CaseUI` só guarda as chaves de `st.campos`, então a leitura os descartaria: gravá-los seria um arquivo que aparenta guardar mais do que guarda. |
| Nome de arquivo é validado no core, não na rota | `nome_casos_valido` mora ao lado de quem escreve em disco. A rota é um dos chamadores, não o guardião. |
| Arquivo ilegível entra na listagem com o rótulo do erro | Sumir com ele esconderia exatamente o arquivo que a pessoa acabou de editar à mão e quebrar. |
| Salvar por cima de um exemplo faz uma cópia | O exemplo que acompanha o programa é referência; sobrescrevê-lo apagaria o caso publicado do artigo. A cópia vai para a pasta do usuário e passa a ter precedência. |

### Defeitos corrigidos nesta rodada

| # | Defeito | Correção |
|---|---|---|
| 1 | **Nome de arquivo vindo do navegador virava caminho em disco.** `POST /api/casos/salvar` grava com o nome que o cliente manda: `"../../.bashrc.toml"` sairia de `dir_casos()`. Não é hipótese remota — o servidor escuta em `127.0.0.1`, e qualquer página aberta no mesmo navegador pode postar. | `nome_casos_valido`: nome simples, terminando em `.toml`, sem separador, sem `..`. Testado nas duas pontas (core e rota). |
| 2 | **Rotas que escrevem aceitavam requisição de outra origem.** Um `fetch` com `Content-Type: application/json` seria barrado pelo preflight de CORS, mas um `<form method=post>` para `text/plain` **não** é preflightado — e `corpo_json` lê o corpo cru, sem olhar o tipo. Valia para `/api/exportar` e `/api/parar` desde o Sprint 2. | `mesma_origem()`, conferida em `/api/casos/{abrir,salvar}`, `/api/exportar` e `/api/parar`. Rejeita só quando o `Origin` **está presente e diverge** — ausente é o caso normal de cliente que não é navegador. |
| 3 | **Um "Abrir" que falhava deixava na tela o resultado do conjunto anterior.** O arquivo ilegível trocava os casos por um em branco, mas `st.resultado` continuava de pé: desenho, cartão, grade e memorial mostravam os números de um vaso que a tela já não tinha como explicar, e nada dizia que os dois lados haviam deixado de se corresponder. | `redimensionar_sem_perder_queixa!`: redimensiona nos dois desfechos e preserva na barra a mensagem que interessa — por que o arquivo não abriu. Vale também para `--caso arquivo_inexistente.toml`, cuja queixa era engolida por `estado_atual`. |

### Aceite verificado

Ida e volta nas duas camadas. No core (`test/cases.jl`): carregar → salvar → carregar
produz `CaseSet` idêntico, valor a valor, incluindo `0.1 + 0.2` bit a bit, faixa
degenerada que continua degenerada e nome de caso com aspas, barra invertida e quebra
de linha. Na interface (`app/smoke.jl`): tela → arquivo → tela preserva nome, estado
ativo e os dois extremos de cada campo — e o arquivo gravado **não** contém nenhuma das
`CHAVES_GLOBAIS`.

*Nota de operação:* em desenvolvimento `config/cases/` é gravável, então é para lá que
"Salvar" escreve — um estudo salvo aparece como arquivo novo no `git status`. É o
comportamento pretendido (conjunto de casos é dado do projeto), mas vale saber antes de
commitar.

---

## Sprint 5 — Segundo equipamento no registro ⏳ ← ATUAL

`config/stream.toml:4-5` promete reaproveitamento para *"separador, bomba, tratador,
trocador e vaso flash"*, e `test/registry.jl` já prova que um método registra de fora de
`src/` e aparece com o formulário montado. Falta exercer a costura **de dentro** — e é
este sprint que diz se a arquitetura dos Sprints 0–4 vale o que promete.

Candidato de menor física nova: **vaso flash / knockout drum bifásico** — blocos A e C
de Stewart & Arnold sem o bloco B, porque não há decantação água-óleo a resolver. Os
dois blocos que sobram têm exatamente a mesma forma do trifásico (`d·Leff ≥ X` para o
gás, `d²·Leff ≥ Y` para o líquido), e `BLOCOS_MEMORIAL` (`app/src/report.jl:48`) já foi
escrito prevendo isto: bloco vazio não vira subtítulo órfão.

### O que a leitura do código revelou — e corrige o planejamento anterior

A estimativa antiga ("um `struct`, quatro métodos, um TOML, um `include` e um
`register!`") vale para `size_equipment` de caso único. **Não vale para o motor de
envelope**, que é onde está o trabalho de verdade. Três obstáculos, todos verificados:

**1. `size_envelope` não era genérico — era declarado sobre os tipos concretos.** ✅ *feito*

```julia
# src/engine/envelope.jl:40
function size_envelope(eq::Separator, m::StewartArnold, cases::CaseSet; …)
    k     = constants(_sa_config())          # :43  — o TOML do separador
    conss = SeparatorConstraints[]           # :56  — o struct do separador
    ok, cons, _ = separator_constraints(…)   # :69  — a função do separador
```

Ele recebe equipamento e método por argumento, mas o corpo inteiro fala com o
separador. Um vaso bifásico registrado hoje ganharia formulário e `size_equipment`, e
**perderia o multi-caso** — que é o diferencial do software. Este é o item maior do
sprint, e o planejamento anterior o subestimava.

A generalização é pequena porque a costura já existe: os blocos produzem *três números
que não dependem de `d`*, e essa abstração serve aos dois vasos. O que muda de nome:

| Hoje | Vira | Por quê |
|---|---|---|
| `separator_constraints(m::StewartArnold, …)` | `sizing_constraints(m::AbstractSizingMethod, …)` | ponto de extensão, despachado pelo método |
| `SeparatorConstraints` | `VesselConstraints` | `d_max_mm = Inf` no bifásico (não há teto de decantação); `beta`/`aw_over_a` viram `NaN` |
| `_sa_config()` dentro do motor | `method_config(m)` | cada método aponta o próprio TOML |
| `f_lss` lido de `_sa_config` | `lss_factor(m, k)` | a relação `Lss(Leff)` é do método |

`size_envelope(::AbstractEquipment, ::AbstractSizingMethod, …)` passa a chamar só essas
quatro, e o resto do corpo — grade comum, envelope de `Leff(d)`, teto mais restritivo,
escolha por `|SR − alvo|` — fica **idêntico**, porque nunca dependeu do separador.

**Como ficou.** `src/sizing/constraints.jl` (novo) guarda o contrato: `VesselConstraints`,
`sizing_constraints`, `method_config`, `lss_from`, mais os helpers de geometria que
nunca foram do separador (`diameter_grid`, `sweep_row`, `selection_diagnosis`) e
`size_vessel`, o caso único que a família compartilha — `size_equipment` do separador
virou uma linha delegando a ele, e o do bifásico será outra. `stewart_arnold.jl` caiu de
262 para 172 linhas e ficou só com a física e as três divergências documentadas.
`grep 'Separator\|StewartArnold' src/engine/envelope.jl` volta só as menções na nota
histórica da docstring.

Duas coisas que a generalização trouxe de brinde:

- **`VesselConstraints` admite "não se aplica"** — `d_max_mm = Inf` (sem teto de
  decantação), `mechanism = :none`, `beta`/`aw_over_a` = `NaN`. `NaN` e não `0.0` de
  propósito: zero é um β possível, e usá-lo como "ausente" faria um desenho errado
  passar por desenho válido.
- **Par equipamento/método incoerente é recusado** com mensagem. Com um só equipamento
  o engano era impossível; com dois ele produziria números do método errado sob o
  rótulo do outro.

*Guarda, já escrita:* `test/envelope.jl` declara um `VasoFake` **fora de `src/`**, sem
física nenhuma — restrições proporcionais às vazões, `method_config` devolvendo um
`Dict` que nunca tocou o disco — e roda o motor inteiro nele: multi-caso, a propriedade
`Leff_env(d) = max_c Leff_c(d)` em toda a grade, o caminho sem teto, e o `lss_from` com
o fator do TOML **do método** (1,25), que não fecharia se o motor tivesse lido o do
separador. 82 testes novos; os 1223 anteriores continuam verdes, com o separador
reproduzindo d = 6300 mm pelo caminho genérico.

**2. Toda corrente é obrigatoriamente trifásica.**

`stream_from_case` (`src/types/stream.jl:77`) lança se faltar qualquer uma das doze
`STREAM_KEYS`, água inclusa. Um knockout drum bifásico não tem fase aquosa — e, do jeito
que está, o formulário dele mostraria vazão, densidade e viscosidade de água que não
entram em conta nenhuma. Campo que não faz nada é pior que campo ausente: ele mente.

Saída: `stream_keys(m::AbstractSizingMethod)` com default `STREAM_KEYS`, e o bifásico
declarando o subconjunto sem água. `stream_from_case` passa a receber quais chaves
exigir; `AppState` monta `campos` filtrando `stream_parameters()` por `stream_keys`. A
regra de `src/interfaces.jl` continua de pé: a tela filtra por uma lista que o método
declara, sem citar `:q_water` em lugar nenhum.

**3. O desenho tem três fases embutidas.**

`beta_atual` (`app/src/state.jl:327`) chama `separator_constraints` direto para extrair
β, e `vaso.jl` usa `layer_heights(g.d_m, g.beta)` em cinco pontos (`:52, :64, :90, :214`)
mais a cota `β = hₒ/d` (`:256`). Num vaso bifásico β não existe. A saída provável é a
geometria carregar as **camadas** que o resultado descreve (uma lista de
`(fração, cor, rótulo)`) em vez de um β do qual as camadas são deduzidas — decidir isso
faz parte do sprint, e é o único ponto que não é mecânico.

### Os oito pontos que fixam o separador em `app/`

Depois de 1–3, o resto é substituição direta: `AppState` ganha
`equipamento::AbstractEquipment` e `metodo::AbstractSizingMethod`, e estes leem de `st`.

| Arquivo | O que está fixo |
|---|---|
| `app/src/state.jl:121` | os `parameters` que viram o formulário |
| `app/src/state.jl:282` | o par passado a `size_envelope` |
| `app/src/state.jl:327-328` | o recálculo de β para o desenho |
| `app/src/api.jl:48-49` | os rótulos do cabeçalho |
| `app/src/report.jl:112, 148` | o rótulo no CSV e no memorial |

Trocar de equipamento **refaz os casos**: as chaves de um bifásico não são as do
trifásico, e um caso carregado com as chaves erradas cairia todo nos defaults sem
avisar — exatamente a classe de falha silenciosa que o Sprint 2 corrigiu na herança por
posição. Ou se pergunta antes, ou se converte o que casa e se avisa do resto.

### Revisão de conceitos, antes de crescer o core

Pedida entre o passo 1 e o 2, e feita contra o artigo-fonte
(`References/AlvesKomesu_Lajer_2025-1.pdf`) em vez de contra memória. Confirmou como
corretos o coeficiente da Eq. 22 (as seis linhas da Tabela 3 implicam 4,2005×10⁴; o
derivado erra 0,35 %, o impresso 1,9 %), a Eq. 23 (19,29 × 4/3 = 25,72 contra 25,71
publicado), a Eq. 24, o β analítico e o ponto único de conversão de unidades. Achou
quatro coisas, corrigidas antes do passo 2:

**A Eq. 21 custa mais do que a nota dizia.** β é a altura fracionária do **óleo**; a da
água é `0,5 − β`. O artigo divide as duas espessuras por β, e o fator `β/(0,5−β)` vale
~6,3 no caso publicado:

| | `d_max` |
|---|---|
| Eq. 19, água em óleo — `(h_o)max/β` | 16508 mm |
| Eq. 21 publicada — `(h_w)max/β` | 24011 mm → teto 16508 mm, governa **água em óleo** |
| Eq. 21 geométrica — `(h_w)max/(0,5−β)` | **3810 mm** → governa **óleo em água** |

A diferença **inverte o mecanismo governante** e recusaria toda a Tabela 3: no `d`
escolhido a camada de água mede 2395 mm contra os 1644 mm que a gotícula de óleo sobe no
tempo de retenção. O método publicado é não-conservador exatamente no mecanismo que ele
descarta por argumento de tamanho de gotícula. E a nota afirmava que a alternativa ficava
"registrada aqui **e no rastro de cálculo**" — o rastro só tinha a forma publicada.

*Decisão:* a forma publicada continua governando (o propósito do software é reproduzir e
generalizar o método do artigo, e mudá-la faria o caso-ouro deixar de reproduzi-lo), e a
variante geométrica passou a ser **calculada e emitida no rastro** como `Eq. 21*`. Ela
atravessa até o memorial de graça, porque `linha_memorial` já serve tela e `.txt`. Um
teste fixa que as duas existem, que a razão entre elas é `β/(0,5−β)`, e que quem decide
continua sendo a publicada.

**A banda de esbeltez do envelope era união.** `sr_min = minimum(...)`,
`sr_max = maximum(...)`. A grade de diâmetros é união de propósito — procurar mais largo
não perde solução; alargar a **banda de aceitação** é o oposto: com um caso pedindo
`SR ∈ [3, 5]` e outro `[3,5 , 4,5]`, um vaso com `SR = 3,2` era aceito violando o
segundo, e o vaso é um só. Virou interseção, com diagnóstico quando as bandas não se
cruzam. `sr_target` continua sendo a média (é preferência, não restrição) mas agora é
preso à banda.

**O volume ignora os tampos** — 772,5 m³ mostrados contra 837,9 m³ com os tampos 2:1 que
a tela desenha, 8,5 % a menos. Como `Lss` é costura a costura, casco-só é a definição
certa; o rótulo é que prometia demais. Virou "Volume (casco, entre tampos)".

**O exemplo da docstring do módulo não rodava:** mostrava `(5500.0, 4.18…)` com os
defaults, cuja grade é `3000:150:8000` e não contém 5500. O valor real é `(5550.0, 4.08)`.

*Defeito introduzido e corrigido na mesma rodada:* o rótulo da `Eq. 21*` nasceu com 27
caracteres numa coluna de 24, e o valor colou no texto — uma linha ilegível no meio do
memorial que vai anexo ao relatório. Ganhou um teste que confere a largura de **toda**
entrada de rastro contra a coluna que a recebe.

### Passos

1. ✅ Generalizar o motor de envelope (obstáculo 1), **sem** o equipamento novo. Foi
   sozinho de propósito: é o passo que se pode errar sem perceber.
1b. ✅ Revisão de conceitos e as quatro correções acima.
2. ← **próximo.** `stream_keys(m)` e o formulário filtrado (obstáculo 2).
3. `src/sizing/vessel/knockout.jl` + `config/equipment/knockout/*.toml`, com `register!`
   em `__init__` (`src/FPSOSiz.jl:95`). O TOML tem de passar em `test/architecture.jl`:
   todo parâmetro com rótulo, unidade, proveniência e `min ≤ default ≤ max`.
4. As camadas do desenho (obstáculo 3).
5. Seletores de equipamento e método na barra superior, de `equipments()` e
   `methods_for()`; a troca refaz formulário e casos.
6. Caso-ouro do novo método, no molde de `test/golden_alves_komesu.jl`, e a guarda de
   constantes-no-TOML no molde de `test/architecture.jl:73`.

### Aceite

**A invariante que a arquitetura inteira existe para provar: nenhum campo de formulário
escrito à mão em `app/`.** Um teste conta os `<input>` gerados por equipamento e compara
com `length(stream_keys(m)) + length(parameters(m))`. Somados a isso:

- `grep -c 'StewartArnold()\|Separator()' app/src/` volta **zero**;
- o motor de envelope roda para os dois equipamentos, iterado pelo registro;
- o memorial do bifásico sai com os blocos A e C e **sem** um subtítulo B vazio;
- os testes anteriores continuam passando — a generalização não é reescrita.

---

## Sprint 6 — Artefato distribuível de verdade ⏳

O Sprint 2 entregou o `create_app` funcionando e registrou o limite com honestidade: o
bundle gerado no NixOS **linka contra a glibc do `/nix/store`** e não roda em outra
máquina. Hoje existe um executável que só serve para provar que o empacotamento fecha.
Um TCC precisa entregar o programa a quem não vai instalar Julia.

- **Build em container** — imagem de base antiga o bastante para a glibc ser compatível
  para trás (o padrão de fato é a linhagem `manylinux`), rodando `build/build.jl tudo`.
  `build/LEIAME.md` já registra a necessidade; falta o `Containerfile` e o alvo.
- **Windows** — `bootstrap.ps1` existe e nunca rodou numa máquina Windows de verdade.
  Ou se testa, ou se registra como não verificado; o que não pode é ficar no meio.
- **CI** — uma ação que roda `Pkg.test()` e `app/smoke.jl` a cada push, e o build de
  release por tag. A etapa `conferir` de `build/build.jl:316` (executa o binário a partir
  de `/tmp`, com `JULIA_DEPOT_PATH` inexistente) é o portão que já está escrito.
- **Memória** — o `create_app` já roda com `JULIA_NUM_THREADS=1` depois do OOM da rodada
  anterior. O runner de CI precisa do piso registrado em `build/LEIAME.md`.

**Aceite:** o `.tar.gz` gerado no container roda numa máquina Linux **que não é esta** e
grava as seis saídas — verificado por `ldd`, que não pode apontar para `/nix/store`.

---

## Sprint 7 — Verificação, manual e fecho do TCC ⏳

O que falta não é software: é o que transforma o software em trabalho defensável.

- **Segundo caso de validação.** O caso-ouro atual é o da Tabela 3 de Alves & Komesu
  (2025), e ele valida o caminho feliz de um separador trifásico. Um segundo caso de
  literatura — de preferência com geometria ou razão água/óleo bem diferente — é o que
  separa "reproduz o artigo que copiei" de "implementa o método".
- **Manual do usuário**, curto e em português, com as telas: o que é uma faixa, o que é
  um caso de canto, como ler o memorial, onde ficam os arquivos (`dir_saida()` e
  `dir_casos()` respondem coisas diferentes em dev e instalado — isso confunde e precisa
  estar escrito).
- **Apêndice de arquitetura** — as decisões já estão registradas neste arquivo e nos
  cabeçalhos dos módulos; falta consolidá-las. As três que carregam o argumento:
  envelope sobre a curva `Leff(d)` e não sobre os dados de entrada; a interface que
  nunca cita um parâmetro pelo nome; e formatação que existe uma vez só, provada pelo
  teste que compara a tela com o `.txt` linha a linha.
- **Limitações declaradas.** Modelo semiempírico, faixa de validade das correlações,
  ausência de internos (chicanas, coalescedores) no dimensionamento. Um trabalho que
  declara o que não faz é mais forte que um que finge fazer tudo.

**Aceite:** um leitor que só tenha o repositório e o texto consegue instalar, rodar,
reproduzir a Tabela 3 e explicar por que o vaso tem o diâmetro que tem.
