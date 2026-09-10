# Passo 1 — Bomba centrífuga e linha de recalque

**Método:** `:moran` · **Equipamento:** `:pump`
**Fonte:** Moran, S., *"Pump Sizing: Bridging the Gap Between Theory and Practice"*,
**Chemical Engineering Progress**, dez/2016, pp. 38–44 (série *Back to Basics*, AIChE).
**Arquivos:** [src/sizing/pump/hydraulics.jl](../../src/sizing/pump/hydraulics.jl),
[src/sizing/pump/moran.jl](../../src/sizing/pump/moran.jl),
[config/equipment/pump/moran.toml](../../config/equipment/pump/moran.toml)

## Como a fonte foi lida

O PDF é cifrado (AES-128, `/P -1340`) e concede `print:yes`, `copy:no`; as fórmulas são
imagem, e nenhuma extração de texto as alcança. Até o Sprint 8 as formas implementadas
tinham sido **reconstruídas da prosa**, que nomeia cada símbolo, a unidade e a faixa de
validade de todas elas.

Nesta fase as páginas foram **rasterizadas** (`pdftoppm -r 150`, usando a permissão de
impressão que o documento concede) e as sete equações lidas símbolo por símbolo. É o que
torna a tabela abaixo uma conferência e não uma repetição do que o código já dizia de si.

---

## 1. Equação do código × equação da referência

| # | Fonte | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Eq. (1) | p. 40 | `h_f = k·v²/(2g)`, `h_f` em mwg, `k` total, `v` superficial (m/s), `g = 9,81 m/s²` | [hydraulics.jl:197](../../src/sizing/pump/hydraulics.jl#L197) `fittings_head` | **equivalente** — literal |
| Eq. (2) | p. 41 | `1/√f_D = −2log(ε/(3,7·D_h) + 2,51/(Re·√f_D))`, declarada para `Re > 4.000` | [hydraulics.jl:82](../../src/sizing/pump/hydraulics.jl#L82) `colebrook_white` | **equivalente** — ponto fixo em `x = 1/√f`; `2,51` e `3,7` conferidos |
| Eq. (3) | p. 41 | `Re = ρvD/µ`, `D` = diâmetro interno | [hydraulics.jl:58](../../src/sizing/pump/hydraulics.jl#L58) `reynolds_pipe` | **equivalente** — literal |
| Eq. (4) | p. 41 | `Δp/L = f_D·ρv²/(2D)` | [hydraulics.jl:186](../../src/sizing/pump/hydraulics.jl#L186) `straight_run_head` | **equivalente após rearranjo** — ver §2.1 |
| Eq. (5) | p. 41 | `log P_v = A − B/(C + T)` | [hydraulics.jl:209](../../src/sizing/pump/hydraulics.jl#L209) `antoine_pressure` | **equivalente** — `C+T` = `T+C`; `×10⁵` converte bar→Pa, ver §2.2 |
| Eq. (6) | p. 41 | `NPSH = P_o/(ρg) + h_o − h_Sf − P_v/(ρg)` | [moran.jl:208](../../src/sizing/pump/moran.jl#L208) + [moran.jl:249](../../src/sizing/pump/moran.jl#L249) | **equivalente** — ver §2.3 |
| Eq. (7) | p. 42 | `P = QρgH/(3,6×10⁶·η)`, `P` kW, `Q` m³/h, `H` m de fluido | [units.jl](../../src/units.jl) `hydraulic_power_kw` | **equivalente** — literal; ver §2.4 |
| Tabela 1 | p. 40 | oito `k` de acessório | default de `k_sucao`/`k_recalque` no TOML | **equivalente** — soma amarrada em teste |
| Tabela 3 | p. 41 | água a 30 °C: A = 5,40221; B = 1.838,675; C = −31,737 → `P_v = 0,042438 bar` | defaults do TOML | **equivalente** — ver §4 |
| Figura 3 | p. 40 | nomograma, "25 mm a 1 m/s ⇒ cerca de 6 m/100 m" | conferência em teste | **equivalente na tolerância da figura** — ver §4 |
| — | **não é do artigo** | `f = 64/Re` (Hagen-Poiseuille), laminar | [hydraulics.jl:165](../../src/sizing/pump/hydraulics.jl#L165) `darcy_friction` | **acréscimo declarado** — ver §3 |

### Divergências e acréscimos

**Nenhuma divergência de forma.** As sete equações do artigo estão implementadas como
publicadas. É o único dos cinco métodos deste programa em que isso acontece: os outros
quatro têm ao menos uma errata de fonte a contornar.

**Uma limitação declarada que se revelou falsa.** O cabeçalho de `hydraulics.jl` afirmava
que os coeficientes da **Tabela 2** (Zigrang-Sylvester e Haaland) "também são imagem e não
têm número conferível no texto". Rasterizadas, as duas formas estão impressas por extenso,
com a faixa de rugosidade de cada uma (`ε = 0,00004–0,05` e `0,000001–0,05`) e a nota de
que ambas também valem só para `Re > 4.000`. As duas continuam **fora** do programa — mas
agora por escolha (Colebrook-White é a que o autor declara preferir, e acrescentar uma
segunda correlação não valida nenhuma das duas), e não por indisponibilidade. O cabeçalho
foi corrigido.

**Uma atribuição corrigida.** O cabeçalho de `moran.jl` dizia que o piso de velocidade de
~1 m/s vinha da "literatura de processo" e não do artigo. Vem do artigo: a p. 39 lista
`water-like fluids with settleable solids: >1, <1,5 m/sec`. O `note` do TOML já estava
certo; o docstring do `.jl` estava errado, e foi corrigido.

---

## 2. Auditoria dimensional

### 2.1 Eq. (4) — de queda de pressão para metros de coluna

O artigo publica queda de **pressão**; o programa soma **metros**. A conversão é uma
divisão por `ρg`, e é exata:

```
Δp = f·(L/D)·(ρv²/2)          [Pa]
h  = Δp/(ρg) = f·(L/D)·v²/(2g) [m de coluna do próprio fluido]
```

`ρ` cancela — é por isso que `straight_run_head` não recebe densidade, e a ausência do
argumento é a prova de que a conversão foi feita uma vez só. A unidade resultante é a
"mwg" em que o próprio artigo soma tudo (p. 40, ao definir a Eq. 1).

### 2.2 Eq. (5) — Antoine devolve bar, o NPSH consome pascal

A forma do NIST que o artigo manda usar dá `P_v` em **bar** (a Tabela 3 imprime as duas
colunas, `0,042438 bar` e `4.243,81 Pa`, o que fixa a unidade sem ambiguidade).
`antoine_pressure` multiplica por `10⁵` e devolve pascal — uma vez, no ponto onde a
correlação termina, e não espalhado no meio da expressão do NPSH.

`T` entra em **kelvin**: `C = −31,737` só faz sentido com `T` absoluto (com `T` em °C a
30 °C daria `A − B/(−1,737)`, ou seja `P_v` da ordem de `10⁶` bar). A Tabela 3 publica as
duas colunas de temperatura, `30 °C` e `303,15 K`, o que confirma.

### 2.3 Eq. (6) — as três parcelas do NPSH

| parcela | código | unidade |
|---|---|---|
| `P_o/(ρg) − P_v/(ρg)` | `(p_suc - pv)/(rho*g)` | Pa/(kg/m³·m/s²) = m ✓ |
| `h_o` | `p[:h_sucao]` | m (parâmetro do TOML) ✓ |
| `−h_Sf` | `− hid.hf_suc`, em `_hidraulica` | m ✓ |

A separação em `npsh_estatico` (o que não depende do diâmetro) e `− hf_suc` (o que depende)
não é algébrica: é a mesma partição que o artigo faz entre estático e dinâmico, e é o que
permite avaliar `hf_suc` uma vez por ponto de grade.

### 2.4 Eq. (7) — o `3,6×10⁶` é conversão, não coeficiente empírico

```
3,6×10⁶ = 3600 [s/h]  ×  1000 [W/kW]
```

Conferido pelo caminho longo em SI puro: `ρ·g·(Q/3600)·H/η/1000` devolve **exatamente** o
mesmo `Float64` que `ρgQH/(3,6×10⁶η)` (`19,425357 kW` para ρ = 998, Q = 100 m³/h,
H = 50 m, η = 0,7). Por isso a constante mora em `Units` e não no `[constants]` do TOML —
a regra do projeto é que o TOML guarda premissa **revisável**, e uma conversão de unidade
não é revisável.

### 2.5 Onde `Units` é aplicado — e o único ponto que foge da regra, com razão

A regra do projeto (docstring de `field_units`, [stream.jl:139](../../src/types/stream.jl#L139))
é *"nenhuma outra função do módulo de dimensionamento deve converter unidades"*. A bomba a
respeita, e **de propósito não usa `field_units` para a viscosidade**:

| grandeza | de onde vem | unidade | por quê |
|---|---|---|---|
| `rho` | `fu.rho_o` | kg/m³ | SI nos dois mundos |
| `mu` | **`s.oil.viscosity`** (cru, não `fu.mu_o`) | **Pa·s** | ver abaixo |
| `q_m3h` | `fu.q_o` | m³/h | a unidade da Eq. (7) |
| `q_m3s` | `Units.m3h_to_m3s(q_h)` | m³/s | a unidade de `v = Q/A` |
| `rugosidade_m` | `Units.mm_to_m(p[:rugosidade])` | m | TOML em mm |
| `p_rec` | `Units.kpa_to_pa(p[:p_recalque])` | Pa | TOML em kPa |

`field_units` existe para levar SI às unidades **de campo de Stewart & Arnold** (cP, m³/h,
kPa). A bomba não usa nenhuma correlação de campo: Eq. (2), (3) e (4) são adimensionais ou
puramente SI. Ler `fu.mu_o` (cP) e pôr no `reynolds_pipe` daria um `Re` **1.000× menor** —
o defeito de unidade mais silencioso possível, porque `Re = 26` em vez de `26.347` continua
sendo um número plausível e simplesmente muda o regime declarado. Verificado: o código lê
`s.oil.viscosity`, o campo `PumpConstraints.mu` está comentado `# Pa·s`, e
[`reynolds_pipe`](../../src/sizing/pump/hydraulics.jl#L58) recebe Pa·s.

**Redundância encontrada (sem consequência numérica).** Em
[moran.jl:193](../../src/sizing/pump/moran.jl#L193), `p_suc = Units.kpa_to_pa(fu.p_kpa)`
faz uma ida-e-volta: `fu.p_kpa` já é `pa_to_kpa(s.pressure)`, então a expressão inteira é
`kpa_to_pa(pa_to_kpa(s.pressure))`. Testado em `Float64` para 101,3 / 400 / 2.300 /
987,654 kPa: **exato nos quatro**, erro relativo 0. Não é defeito — é ruído de leitura, e
`s.pressure` diria o mesmo. Fica registrado e **não** foi alterado: mexer nisso não muda
número nenhum e a fase está em *feature freeze* de forma.

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código (antes) | agora |
|---|---|---|---|
| Colebrook-White | **`Re > 4.000`** (p. 41, explícito) | detectado (`confiavel`) e **descartado** | **recusa o ponto** — defeito 1 |
| `f = 64/Re` | não é da fonte; exata para laminar plenamente desenvolvido em duto circular | `Re ≤ 2.300` (TOML) | inalterado — passa, e o memorial agora o cita |
| zona 2.300 < `Re` < 4.000 | **nenhuma correlação vale** | Colebrook-White + `confiavel = false` | **recusa o ponto**, com mensagem própria |
| banda de velocidade | `<1,5 m/s` bombeado; `>1, <1,5` com sólidos decantáveis (p. 39) | `v_min`/`v_max` em `case_admissible` | inalterado |
| NPSH | Eq. (6) só para bomba **centrífuga** (p. 41, explícito) | o equipamento é `CentrifugalPump` | inalterado — o tipo é a garantia |
| Antoine | faixa de `T` de cada conjunto A/B/C (NIST) | **não verificado** | **lacuna** — ver §6 |
| rugosidade `ε` | as faixas da Tabela 2 são das *alternativas*; Eq. (2) não declara faixa de `ε` | `min`/`max` do `ParameterSpec` | inalterado |
| DN × diâmetro interno | o artigo trata os dois como o mesmo número (p. 40 lê "25-mm nominal-bore" num eixo "Internal Diameter") | tratado igual, e declarado na nota 3 do cabeçalho | inalterado |

---

## 4. Casos-ouro

O artigo é didático e **não traz um caso resolvido de ponta a ponta** — não há um par
`(Q, H)` publicado. Traz dois números fechados, e é contra eles que a implementação se
amarra.

| caso-ouro | publicado | calculado | desvio | tolerância | justificativa da tolerância |
|---|---|---|---|---|---|
| Tabela 3 — Antoine, água a 30 °C | `4.243,81 Pa` | `4.243,8065 Pa` | **−8,3×10⁻⁵ %** | `rtol = 10⁻⁴` | a publicação traz 6 algarismos significativos; o desvio é o arredondamento da última casa dela, não erro do cálculo |
| Figura 3 — DN 25 a 1 m/s | "about 6 m per 100 m" | `5,362 m/100 m` | **−10,6 %** | `rtol = 0,20` **e** `5,0 < h < 6,5` | a própria figura declara *"Approximate values only"*; é leitura de régua sobre escala log de nomograma, e 20 % é o que uma leitura assim sustenta. A banda absoluta é o que impede a tolerância larga de aceitar qualquer coisa |

**Sobre o −10,6 %.** É o maior desvio dos cinco métodos, e é da figura, não do código: o
nomograma é de catálogo de fabricante de tubo ABS, a temperatura declarada é 10 °C
(µ = 1,307 cP), o `ε` do ABS é ~0,0015 mm, e o "about 6" é lido a olho de uma reta traçada
com régua. O `Re` resultante (19.122) é turbulento e a correlação está dentro da sua faixa.
Não há aqui discrepância a explicar além da precisão da fonte.

**Verificações estruturais, que valem tanto quanto um número publicado.** Onde a fonte não
dá número, o teste fixa propriedade — e são elas que pegariam um sinal invertido:

- o resíduo da forma implícita de Colebrook-White é `< 10⁻⁸` no ponto convergido;
- no limite plenamente rugoso, `f` deixa de depender de `Re` e vale o limite de
  von Kármán `1/√f = −2log₁₀(ε/3,7D)` (5×10⁻³);
- `f` cresce com a rugosidade a `Re` fixo, e cai com `Re` em tubo liso;
- `P_v` **cresce** com `T` (um sinal errado em B ou C daria curva decrescente e um NPSH
  que melhora com o líquido mais quente — o oposto da física), e água a 100 °C ferve a
  1 atm (5 %);
- Darcy é exatamente 4× Fanning — o artigo dedica um parágrafo ao engano porque ele erra a
  perda por 4× sem produzir nada absurdo na tela;
- a perda cresce com `v²` e com `L`, e cai com `D`;
- os `k` default somam exatamente a contagem de acessórios descrita no `note` do TOML
  (este teste já pegou uma divergência real: `k_recalque` nasceu 13,9 com um `note` que
  somava 13,8).

---

## 5. Defeitos encontrados

### Defeito 1 — o programa detecta operação fora de faixa e descarta o sinal
**Classe: físico** (escolhe um diâmetro a partir de uma perda de carga que nenhuma equação
implementada sustenta).

`darcy_friction` devolve `(f, regime, confiavel)` e `_hidraulica` propagava os três — e
**nada os consumia**. `derived` não expunha `confiavel`, `case_admissible` não o olhava, e
`trace_selection!` não o imprimia. O docstring de `trace_selection!` afirmava ser "a única
via por onde o regime de escoamento chega ao leitor"; o regime não chegava.

**Retrato** (óleo, 60 m³/h, 900 kg/m³, **45 cP**, defaults do TOML, banda 1,0–1,5 m/s):

| DN | v (m/s) | Re | f | regime | `confiavel` | aceito antes? |
|---|---|---|---|---|---|---|
| 100 | 2,12 | 4.244 | 0,0397 | turbulento | ✓ | não (fora da banda de v) |
| **125** | **1,36** | **3.395** | **0,0422** | **transição** | **✗** | **sim — e era o escolhido** |
| 150 | 0,94 | 2.829 | 0,0446 | transição | ✗ | não (fora da banda de v) |

O NPSH em DN 125 está **folgado**, então nem o diagnóstico de cavitação apareceria: o vaso
saía especificado, com o `f` de Colebrook-White avaliada 15 % abaixo do `Re` mínimo em que
o artigo a declara, e nada em nenhuma tela ou memorial dizia.

**Teste que o expõe:** `@testset "fora da faixa de Colebrook-White o ponto é recusado"`
em [test/golden_moran.jl](../../test/golden_moran.jl) — o sub-testset
`"o retrato do defeito: transição dentro da banda de velocidade"` reproduz a linha de
DN 125 antes de qualquer asserção sobre o comportamento novo.

**Correção.** `case_admissible` passou a exigir `hid.confiavel`; `derived` expõe
`:confiavel` (0/1), `:re_min_correlacao` e `:re_max_laminar`; `selection_message` ganhou o
braço que nomeia a zona de transição e a fronteira de 4.000, **antes** do braço de
cavitação — porque o NPSH desconta `hf_suc`, que é justamente a perda recusada, e acusar
cavitação a partir dela seria diagnosticar com o número reprovado.

O regime **laminar não é recusado**: `f = 64/Re` é exata para escoamento plenamente
desenvolvido em duto circular. A distinção já estava codificada no flag — recusar tudo o
que está "fora de Colebrook-White" reprovaria todo óleo pesado sem motivo.

### Defeito 2 — o memorial credita `f` à equação errada no regime laminar
**Classe: de unidade** (atribuição: manda o leitor conferir a conta na equação errada; não
muda nenhum número).

`trace_selection!` carimbava sempre `"Colebrook" | "1/√f = −2log₁₀(…)"`. Com óleo de
200 cP o `Re` cai a 764, o `f = 0,0838` vem de Hagen-Poiseuille, e o memorial — que é a
peça que vai anexa ao relatório — atribuía o número a Colebrook-White.

**Teste que o expõe:** `"e o memorial credita a equação que de fato produziu f"`, dentro de
`@testset "laminar continua admissível: Hagen-Poiseuille é exata"`.

**Correção.** A citação passou a vir de `friction_equation(regime)`
([hydraulics.jl:139](../../src/sizing/pump/hydraulics.jl#L139)), e a classificação de
regime de `flow_regime(re, k)` ([hydraulics.jl:116](../../src/sizing/pump/hydraulics.jl#L116)),
que `darcy_friction` **também** passou a usar. Uma classificação só, consultada nos dois
lugares: duas cópias divergiriam no dia em que uma fronteira mudasse de valor no TOML, e a
divergência apareceria exatamente como este defeito.

O memorial ganhou também a linha `regime`, que declara as duas fronteiras e se a
correlação vale ali (`1`/`0` em "válida?").

### Observação (não é defeito) — o campo `eq` do memorial tem 10 colunas
`linha_memorial` (em `app/src/report.jl`, fora do escopo desta fase) alinha `e.eq` em 10
colunas; o rótulo mais longo que o core emite tem 9 (`Eq. 4.15b`). `"Hagen-Poiseuille"`
tem 16 e colaria no nome da variável — a primeira versão da correção o usou e foi trocada
por `"Hagen"`, com o nome inteiro na coluna de fórmula, que não tem largura fixa.

**A invariante não tem teste.** Não foi acrescentado um porque o teste pertenceria à
formatação de `app/`, que esta fase não toca. Fica registrado como risco conhecido: o
próximo rótulo de 10+ caracteres quebra o alinhamento do memorial sem que nada avise.

---

## 6. Lacunas não fechadas

1. **Não há caso-ouro de linha inteira.** A fonte não publica um `(Q, H)` resolvido, e por
   isso a **cadeia** montada (estática + reta + localizada → `H`) não tem amarra externa —
   só as sete formas, conferidas uma a uma, e os dois números pontuais. Fechar isso exige
   outra fonte com um exemplo de linha resolvido. É a lacuna mais séria deste método.

2. **A faixa de temperatura da Antoine não é verificada.** Cada conjunto A/B/C do NIST vale
   numa faixa de `T` (o da água da Tabela 3 vale ~275–370 K). Fora dela a equação devolve
   número como qualquer outra correlação extrapolada. O programa aceita `T` de −50 a
   300 °C sem confrontar com a faixa dos coeficientes — que ele **não tem como conhecer**,
   porque A, B e C são entrada do usuário e a faixa de validade não é. Acrescentar dois
   campos de faixa seria pedir ao usuário um dado que ele quase nunca copia do NIST junto
   dos coeficientes; deixar como está é extrapolação silenciosa. **É uma decisão de
   engenharia e não foi tomada sozinha** — está na lista de perguntas ao fim desta fase.

3. **A rugosidade não tem faixa de validade declarada pela Eq. (2).** As faixas de `ε` que
   a Tabela 2 publica são das alternativas (Zigrang-Sylvester, Haaland), não de
   Colebrook-White. Não há o que verificar contra a fonte.

4. **Não há critério econômico.** O artigo dá regras de bolso de velocidade, não um ótimo
   de custo; o programa escolhe o menor DN admissível, que é a escolha de menor capital e
   a maior de energia. Está declarado na nota 4 do cabeçalho de `moran.jl` e é escolha de
   projeto, não lacuna de validação.

---

## Resultado

| | antes | depois |
|---|---|---|
| Testes do método | 71 | **98** |
| Suíte completa | 1.916 | **1.943**, zero falhas |
| Equações conferidas contra a fonte | 0 de 7 (reconstruídas da prosa) | **7 de 7**, lidas |
| Defeitos corrigidos | — | 2 (1 físico, 1 de atribuição) |
| Casos de exemplo ainda viáveis | 5 de 5 | **5 de 5** |
