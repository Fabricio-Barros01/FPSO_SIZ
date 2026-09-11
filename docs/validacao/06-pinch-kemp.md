# Passo 6 — Análise Pinch (alvos de energia)

**Módulo:** `FPSOSiz.PinchAnalysis` · **Equipamento:** nenhum — não é dimensionamento
**Fonte:** Kemp, I.C. (2007), *Pinch Analysis and Process Integration: A User Guide on
Process Integration for the Efficient Use of Energy*, 2ª ed., Butterworth-Heinemann,
ISBN 978-0-7506-8260-2 — cap. 2 (§2.1.4, pp. 21–24) e cap. 3 (§3.1.3 p. 44, §3.3.2 p. 54,
§3.7 p. 82, apêndice §3.9.1 pp. 95–96).
**Arquivos:** [pinch.jl](../../src/analysis/pinch.jl),
[test/pinch.jl](../../test/pinch.jl), [test/golden_kemp.jl](../../test/golden_kemp.jl)

O primeiro passo desta fase que **não dimensiona nada**. A Análise Pinch responde quanta
utilidade quente e fria uma *rede* de correntes exige, no mínimo, antes de qualquer
trocador existir — é alvo termodinâmico, não projeto de equipamento. O
[saari_lmtd.toml](../../config/equipment/exchanger/saari_lmtd.toml) registrava a ausência
dela como falta de fonte, e o [SPRINTS.md](../../SPRINTS.md) condicionava a aba pinch a
*"haver Kemp/Linnhoff em `References/`"*. A condição está satisfeita.

É também o passo com o **caso-ouro mais completo do projeto**. Não há aqui o buraco do
passo 2, onde Saari não publica exemplo fechado: Kemp publica as correntes, a tabela de
intervalos, **as duas cascatas** e os alvos com a temperatura de pinch. Tudo o que o
programa calcula está impresso no livro.

**Esta execução entrega só o núcleo.** Não há interface, não há registro, não há
`ParameterSpec`. A entrada é `Vector{ThermalStream}` + ΔTmin; a saída é um `PinchResult`.

---

## 1. Equação do código × equação da referência

| # | Página | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Eq. (2.3) | p. 21 | `ΔH_i = (S_i − S_{i+1})·(ΣCP_H − ΣCP_C)_i` | [:375](../../src/analysis/pinch.jl#L375) | **idêntica** |
| §3.9.1 passo 2 | p. 95 | quentes `S = T − ΔTmin/2`; frias `S = T + ΔTmin/2` | [`shifted_temperatures`:328-332](../../src/analysis/pinch.jl#L328-L332) | **idêntica** |
| §3.9.1 passos 3–4 | p. 95 | listar as `S` e ordenar em ordem **decrescente** | [:362](../../src/analysis/pinch.jl#L362) | **idêntica** |
| §3.9.1 passo 5 | p. 95 | `CP_net` = soma das quentes menos soma das frias | [:369-374](../../src/analysis/pinch.jl#L369-L374) | **idêntica** |
| §3.9.1 passo 7 | p. 95 | cascata a partir de **zero** no topo | [:379-383](../../src/analysis/pinch.jl#L379-L383) | **idêntica** |
| §3.9.1 passo 8 | p. 95 | `QHmin` = o fluxo mais negativo, **ou zero** | [:386-387](../../src/analysis/pinch.jl#L386-L387) | **idêntica** — o "ou zero" é o `max(0,·)`, e é o que produz o problema-limiar |
| §3.9.1 passo 9 | p. 96 | pinch = ponto(s) de fluxo líquido nulo | [:402](../../src/analysis/pinch.jl#L402) | **restringida ao interior** — ver §5 |
| Nota 2 | p. 24 | três formas de aproximar as curvas; o livro adota a **terceira** | `shifted_temperatures` | **idêntica** — a terceira |
| Notas 1 e (c) | pp. 24, 96 | excedente **positivo**, `ΣCP_H − ΣCP_C` | `TemperatureInterval.dh` | **idêntica** — é a convenção da 2ª ed. |
| §3.1.3 | p. 44 | carga latente **não** entra como CP infinito | `validate_streams` | **implementada como recusa** — ver §3 |

### O que este módulo **não** tem, e por quê

Kemp cobre muito mais do que alvos de energia. O que ficou de fora está de fora por
escopo declarado, não por esquecimento — e nada no código alega o contrário:

- **síntese de rede de trocadores** (§2.3) — é a disciplina seguinte, e é o que
  transformaria um alvo num projeto;
- **grand composite curve** (§2.1.5) — seria o gráfico da cascata factível, e os dados
  para traçá-la já estão no `PinchResult`; o que falta é a camada de desenho;
- **alvo de área e de número de unidades** (§3.6) — exigem coeficientes de película por
  corrente, que esta entrada não pede;
- **utilidades múltiplas** (§3.4) — a v1 tem uma quente e uma fria;
- **ΔTcont por corrente** (§3.3.1, p. 53) — o algoritmo admite, e a Nota (b) da p. 96 diz
  como; a v1 usa ΔTmin global;
- **CP polinomial em T** (§3.1.3, p. 45) — a v1 é CP constante **por segmento**, que é o
  método padrão do livro; a linearização por trechos é justamente o remédio que o §3.1.3
  recomenda, e os segmentos existem para isso.

---

## 2. Auditoria dimensional

### 2.1 Unidades de entrada, intermediárias e de saída

| grandeza | unidade | onde |
|---|---|---|
| `t_in`, `t_out` | °C | `StreamSegment` |
| `mcp` (`ṁ·cp`) | kW/°C | `StreamSegment` |
| `S` (temperatura deslocada) | °C | `shifted_temperatures` |
| `cp_net` | kW/°C | `TemperatureInterval` |
| `dh` | kW | `TemperatureInterval` |
| `QHmin`, `QCmin`, cascatas | kW | `PinchResult` |

`[kW/°C] × [°C] = [kW]`. **Não há um único fator de conversão no módulo** — nem 3600, nem
1000, nem coeficiente de correlação. É consequência de a entrada já estar em unidades
coerentes, e é o que distingue este arquivo dos outros cinco métodos, onde a Eq. (14) e a
Eq. (22) carregam coeficientes que só existem para reconciliar `in`, `ft`, `BPD` e `mm`.

### 2.2 Por que °C, e por que isso não é escolha de física

A convenção interna é **°C**, declarada no cabeçalho do módulo. Não é arbitrária nem
inconsequente — é *inócua*, e é preciso mostrar que é:

- `cp_net · (S_top − S_bot)` usa uma **diferença** de temperatura, e `ΔT` é numericamente
  idêntico em °C e em K;
- `S = T ∓ ΔTmin/2` desloca, e o deslocamento é ele próprio uma diferença;
- as fronteiras `S` só entram no cálculo por subtração entre si.

A origem da escala **nunca aparece**. Trocar tudo para K somaria 273,15 a cada `S` e não
mudaria um único `ΔH`, `QHmin` ou posição relativa de pinch — mudaria só o rótulo das
temperaturas relatadas. A escolha é de legibilidade contra a fonte (Kemp trabalha em °C
nos caps. 2 e 3), e `Units.celsius_to_kelvin` fica disponível para a fronteira.

Uma exceção honesta: a p. 82 dá a faixa criogênica em **K** (*"∆Tmin,s of 2–3 K are
common"*). Como é uma diferença, o número vale igual em °C.

### 2.3 Onde o ΔTmin/2 é aplicado — uma vez só, e verificado

[`shifted_temperatures`](../../src/analysis/pinch.jl#L328-L332) é o **único** ponto do
módulo que desloca temperatura. Depois dela, `problem_table` guarda apenas
`(lo, hi, mcp, quente)` já deslocados, e nenhuma temperatura real volta a ser lida.

Isso importa mais do que parece. Um ΔTmin/2 aplicado duas vezes em algum caminho não
produz erro visível: produz um pinch plausível na temperatura errada, e alvos plausíveis
e errados. Por isso a restrição é estrutural (a informação original é descartada) e não
apenas documentada. O teste `"o deslocamento é aplicado uma vez só"` fixa os três casos
que separam ΔTmin/2 de ΔTmin e de ΔTmin/4: deslocamento em 0, 10 e 20 °C.

### 2.4 Por que **não** há TOML de constantes

A regra do projeto é que constante de correlação mora em TOML, para ficar auditável, e a
guarda 3 de [architecture.jl](../../test/architecture.jl) varre os `.jl` atrás de literais
usados em conta. **Este algoritmo não tem constante empírica nenhuma.**

O único literal numérico com significado é o `2` de `ΔTmin/2`, e ele é **estrutural**: é a
metade de um intervalo, o passo 2 de §3.9.1, e a Nota 2 da p. 24 explica que a alternativa
não é "outro valor" e sim outra das três convenções de deslocamento — nenhuma delas com um
coeficiente ajustável. Não há premissa revisável a expor.

Um TOML aqui seria decoração: um arquivo com um campo que ninguém pode mudar sem trocar de
método. A ausência é decisão registrada, e o teste de pureza varre o fonte atrás dos
literais com operador, no mesmo formato da guarda 3.

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código |
|---|---|---|
| **CP constante no segmento** | §3.1.3, p. 45: *"streams should be linearised in sections. This operation maintains the validity of the Problem Table algorithm"* | **por construção** — `StreamSegment` é a seção linearizada; o teste de invariância de segmentação prova que partir não muda resultado |
| **carga latente ≠ CP infinito** | §3.1.3, p. 44, com a receita completa | **recusa com diagnóstico** — a mensagem cita a página e diz o que fazer |
| **ΔTmin > 0** | implícito: ΔTmin = 0 faz as compostas se tocarem em todo o trecho | **recusa** — uma regra, um teste |
| **mCp > 0** | implícito: `CP = ṁ·cp`, e ambos positivos | **recusa** — zero, negativo, `NaN` e `Inf` |
| **direção derivada de `T_in − T_out`** | Tabela 2.2 publica o tipo, mas ele é redundante com as temperaturas | **derivado, e nunca aceito** — não há campo de tipo em `StreamSegment` |
| corrente que esquenta e esfria | não tratada pela fonte: seriam duas correntes | **recusa** — regra própria, declarada |
| segmentos com buraco entre si | não tratada pela fonte | **recusa** — regra própria, declarada |
| ΔTcont por corrente | §3.3.1 p. 53 e Nota (b) p. 96 autorizam | **não implementado** — lacuna §6.3 |
| CP dependente de T | §3.1.3 p. 45 e Nota (d) p. 96 dão o caminho por entalpia | **não implementado** — lacuna §6.3 |
| faixa usual de ΔTmin | §3.7.2–3.7.3, p. 82: ótimo 15–20 °C, achatado de 5 a 50 °C; 10 °C para operação contínua; 2–3 K criogênico | **não verificado** — é escolha do projetista, e o núcleo aceita qualquer ΔTmin positivo; ver §6.1 |

As três últimas linhas são as que importam para quem for ler o resultado: o programa
**não** julga se o ΔTmin escolhido é razoável, e não tem como julgar — ver §6.1.

---

## 4. Casos-ouro

Dois, ambos publicados, ambos da mesma fonte. Tolerância **0,01 °C** em temperatura e
**0,1 %** em calor. Na prática o acordo é **exato** em todos os números: o algoritmo é
aritmética sobre os dados, sem correlação empírica no meio, e as folgas só existem para o
arredondamento que o próprio livro faz no "5,55 °C" do §3.3.2.

### 4.1 Tabela 2.2 e 2.3, Figura 2.9 — a cascata número a número

As quatro correntes (Tabela 2.2, p. 21), com ΔTmin = 10 °C:

| # | tipo | CP (kW/K) | TS (°C) | TT (°C) | SS (°C) | ST (°C) |
|---|---|---|---|---|---|---|
| 1 | fria | 2 | 20 | 135 | 25 | 140 |
| 2 | quente | 3 | 170 | 60 | 165 | 55 |
| 3 | fria | 4 | 80 | 140 | 85 | 145 |
| 4 | quente | 1,5 | 150 | 30 | 145 | 25 |

O tipo da coluna 2 **não é entrada**: sai do sinal de `TS − TT`, e o teste verifica que os
quatro saem certos.

Os cinco intervalos (Tabela 2.3, p. 22), fronteiras `S` = 165, 145, 140, 85, 55, 25 °C:

| i | `S_i − S_{i+1}` (°C) | `ΣCP_q − ΣCP_f` (kW/°C) | `ΔH_i` (kW) | publicado | código | desvio |
|---|---|---|---|---|---|---|
| 1 | 20 | 3,0 | excedente | +60 | +60 | **0** |
| 2 | 5 | 0,5 | excedente | +2,5 | +2,5 | **0** |
| 3 | 55 | −1,5 | déficit | −82,5 | −82,5 | **0** |
| 4 | 30 | 2,5 | excedente | +75 | +75 | **0** |
| 5 | 30 | −0,5 | déficit | −15 | −15 | **0** |

As duas cascatas (Figura 2.9, p. 23):

| | topo | | | | | base |
|---|---|---|---|---|---|---|
| **(a) infactível** | 0 | 60 | 62,5 | **−20** | 55 | 40 |
| **(b) factível** | **20** | 80 | 82,5 | **0** | 75 | **60** |

O `−20` da cascata (a) é o que a torna termodinamicamente impossível, e é ele que fixa
`QHmin`. O `0` da cascata (b) é o pinch.

**Alvos (p. 24):** `QHmin` = 20 kW, `QCmin` = 60 kW, pinch na fronteira de **85 °C
deslocada** — *"hot streams at 90 °C and cold at 80 °C"*. Os seis números batem exatos.

### 4.2 As conferências cruzadas que a própria p. 24 manda fazer

O livro fecha o exemplo com três verificações independentes, e o teste as reproduz:

| conferência | publicado | código |
|---|---|---|
| `ΣQ` das correntes quentes | 510 | 510 |
| `ΣQ` das correntes frias | 470 | 470 |
| recuperação por `ΣQ_q − QCmin` | 450 | 450 |
| recuperação por `ΣQ_f − QHmin` | 450 | 450 |
| `QCmin − QHmin` = último nó da cascata (a) | 40 | 40 |

A última é a mais forte, e virou invariante testado para **todo** ΔTmin (§4.3): o balanço
de entalpia do problema é fixado pelos dados, não pela aproximação térmica escolhida. Se
`QCmin − QHmin` se mover com ΔTmin, a cascata está errada.

### 4.3 O problema-limiar do §3.3.2, e a forma fechada

§3.3.2, p. 54, sobre as **mesmas** quatro correntes:

> *"as ∆Tmin is reduced, a point is reached (at 5.55 °C) where no hot utility is required;
> at all lower values of ∆Tmin, the only utility needed is 40 kW cold utility."*

É um segundo caso-ouro de graça, e é o que dá ao teste de problema-limiar um **número
publicado** em vez de um construído para passar. Verificado em ΔTmin = 0,5; 1; 2; 3; 4; 5
e 5,5 °C: `QHmin` = 0, `QCmin` = 40 kW, e **sem pinch**.

Dele sai uma verificação mais forte. Para estas correntes, o nó que governa a cascata está
na fronteira `80 + ΔTmin/2` e vale `25 − 9·(ΔTmin/2)`, donde

```
QHmin(ΔTmin) = max(0; 4,5·ΔTmin − 25),   válida em 0 ≤ ΔTmin ≤ 10 °C
```

A forma fechada reproduz os **dois** pontos publicados — os 20 kW da p. 24 em ΔTmin = 10, e
a raiz em `50/9 = 5,5556 °C`, que é o "5,55" da p. 54 arredondado. O teste a confere em 40
pontos da grade, e verifica a inclinação de 4,5 kW/°C. Isso sustenta a monotonicidade de
`QHmin` **analiticamente**, e não por amostragem — ver §4.4.

O ΔTmin exato do limiar é o caso de borda que justifica `threshold` e `t_pinch_shifted`
serem campos separados: ali `QHmin` = 0 **e** ainda existe um pinch interior, em
`80 + 25/9 = 82,78 °C`. Abaixo dele, não há mais pinch. Um flag só perderia a distinção.

### 4.4 Monotonicidade de `QHmin` — o que existe no lugar de caso-ouro

O livro não publica a curva `QHmin(ΔTmin)` em tabela; publica o **gráfico** (Figura 3.6,
p. 54) e o ponto em que ela cruza zero. Então não há aqui um caso-ouro no sentido dos
outros — há uma propriedade, verificada de duas formas independentes:

1. **Contra a forma fechada** (§4.3), exata, em `0 ≤ ΔTmin ≤ 10`.
2. **Por varredura**, em `0,1 ≤ ΔTmin ≤ 60 °C` com passo de 0,1, sobre as correntes de
   Kemp **e** sobre um segundo conjunto sem relação com o livro: `QHmin` e `QCmin` são
   não decrescentes em toda a faixa.

Isto não é decoração de teste. É a propriedade que autoriza tratar `QHmin` como
"exigência" numa varredura sobre ΔTmin — aproximar mais as curvas compostas não pode
custar **mais** utilidade quente. Se ela cair, o encaixe do motor está errado, não o teste.

### 4.5 O que existe no lugar de caso-ouro para rede, GCC e área

**Nada, e é declarado.** Síntese de rede, grand composite curve e alvo de área não estão
implementados (§1), então não há o que confrontar com a fonte. Esta subseção existe para
que a ausência fique escrita, no formato do §4.4 do [passo 2](02-trocador-saari-bell-delaware.md):
um relatório que silencia sobre o que não fez deixa o leitor supor que fez.

O que **existe** no lugar, e que vale registrar: os dados para traçar a GCC já estão no
`PinchResult` (`cascade_feasible` contra `boundaries` é literalmente a GCC, §2.1.5 p. 25).
Falta só a camada de desenho. Alvo de área e síntese de rede exigem entrada que o módulo
não pede, e essas são lacunas de escopo, não de implementação.

---

## 5. Defeitos encontrados

**Nenhum defeito.** Este passo fechou sem correção de código pré-existente — como os
passos 3, 4 e 5. O próximo número disponível continua sendo o **6**: os defeitos numerados
vão até 5 ([passo 1](01-bomba-moran.md): 1–2; [passo 2](02-trocador-saari-bell-delaware.md):
3–5), e os passos 3, 4 e 5 fecharam em zero.

Era o desfecho esperado, e vale dizer por quê para que não passe por mérito: **o código é
novo e nasceu lendo a fonte**. Os outros passos confrontaram implementações que já
existiam; aqui não havia nada para estar errado. O valor deste relatório está em §1 e §2,
que fixam o que o código faz, e em §6, que fixa o que ele não faz.

### Dois errata da fonte, que não movem número

**Classe: de unidade.** Registrados pela mesma razão que os de Stewart & Arnold, de Alves
& Komesu e de Saari: quem for conferir os testes contra o livro precisa saber por que dois
números não são o que a página diz.

1. **O apêndice do capítulo 3 é citado com o número errado.** O §3.3 (p. 53) manda ver os
   algoritmos em *"Section 3.11"*, e o §2.1.4 (p. 24) repete: *"A step-by-step algorithm
   for calculating the Problem Table is given in Section 3.11."* O apêndice é **§3.9**
   (p. 95), e **não existe §3.11** no livro — o capítulo 3 termina em §3.9. O índice
   (p. vi) traz o número certo. Sem consequência para o programa; consequência para quem
   procurar o algoritmo pela referência do texto corrido, que é o caminho natural.

2. **As cargas da p. 24 aparecem em kWh onde são kW.** O texto diz *"adding the heat loads
   for all the hot streams and all the cold streams – 510 and 470 kWh"* e *"Subtracting the
   cold and hot utility targets (60 and 20 kWh)"*. São **taxas**: `CP` é kW/K e a
   temperatura é °C, logo o produto é kW — como a própria Tabela 2.3 (p. 22) e a Figura 2.6
   (p. 20) trazem. O erro é só de digitação do texto; todas as figuras e tabelas do mesmo
   exemplo usam kW.

---

## 6. Lacunas não fechadas e decisões pendentes

### 6.1 Não há troca energia × capital — e por isso não há ótimo

**É a limitação que mais importa declarar.** O programa não modela área de troca nem custo
de capital. Logo não existe a curva que o §3.7 de Kemp constrói (Figura 3.25, p. 82:
capital sobe, energia desce, o total tem mínimo) e **não há critério próprio para preferir
um ΔTmin a outro**.

A consequência para o encaixe no motor de varredura, já decidida e registrada aqui:

> `objective = |ΔTmin − alvo|` é **seleção por declaração, não otimização.** O programa
> cumpre o ΔTmin que o projetista pedir; ele não o escolhe, e não alega escolher.

É o mesmo estatuto de `sr_target` nos vasos — preferência, não restrição —, com uma
diferença que vale escrever: no caso da esbeltez a fonte recomenda uma **banda** (3 a 5),
e sair dela é sinal de projeto ruim. Aqui a fonte é explícita em que o ótimo é **econômico
e achatado**: §3.7.2, p. 82, *"the total cost is within about 10% of the optimum for a
range from about 5 °C to 50 °C"*. Uma faixa de dez para um, dentro de 10 % do ótimo. Não
há banda estreita a impor, e impor uma seria inventar rigor.

O que fecharia a lacuna é *supertargeting* (§2.4 e §3.7), que exige alvo de área — que
exige coeficiente de película por corrente, que esta entrada não pede. É lacuna de escopo,
em cadeia, e declarada.

### 6.2 Os ajustes globais não persistem entre sessões

Pendência **do projeto, não deste passo**, e registrada aqui porque o alvo de ΔTmin vai
herdá-la quando a interface existir.

Os parâmetros que a tela trata como decisão de projeto (`global_keys`) vivem em
`st.globais` e **não são gravados no arquivo de casos**:
[`salvar_casos!`](../../app/src/state.jl#L269-L273) passa um dicionário vazio, de propósito
e documentado. Dentro da sessão o valor sobrevive ao ciclo abrir→editar→salvar
([`carregar_casos!`](../../app/src/state.jl#L170-L217) não toca `st.globais`). Fora dela,
não: ao reabrir, o construtor re-semeia dos defaults do TOML
([state.jl:138-139](../../app/src/state.jl#L138-L139)), e o `.toml` entregue a outra pessoa
não carrega o valor — ela reproduz a corrida com o *seu* default.

Atinge igualmente **`sr_target` e os quatro métodos já existentes**. Está fora do escopo
desta execução, e a correção (gravar os globais no arquivo de casos e relê-los) é uma
rodada própria, porque muda `state.jl` e o formato do arquivo.

### 6.3 ΔTcont por corrente e CP dependente de T

Os dois estão no livro com o caminho pronto — §3.3.1 (p. 53) e Nota (b) da p. 96 para o
ΔTcont; §3.1.3 (p. 45) e Nota (d) da p. 96 para o CP variável — e nenhum dos dois está
implementado.

O ΔTcont é o que permite dar a uma corrente viscosa ou incrustante uma aproximação maior,
compensando o `U` baixo sem inflar o ΔTmin global. É a extensão mais barata: muda só
`shifted_temperatures`, que já é o único ponto de deslocamento. A v1 usa ΔTmin global.

O CP polinomial é mais caro e menos urgente: a linearização por segmentos, que **está**
implementada, é o remédio que o próprio §3.1.3 recomenda, e o livro só recorre à entalpia
quando o software não admite segmentos.

### 6.4 O `note` do parâmetro de ΔTmin, quando ele existir

Registrado aqui porque a decisão foi tomada e a fonte, conferida — o parâmetro em si é da
execução seguinte, que cria o `ParameterSpec` e o TOML.

O `default` é **10 °C**, e a nota tem fonte direta. §3.7.3, p. 82:

> *"for typical bulk duties of reasonably free-flowing liquids, 20 °C is a reasonable
> ∆Tmin. For high throughputs or continuous three shift operation, a value of 10 °C may be
> more appropriate. For cryogenics, as the cost of refrigeration is extremely high,
> ∆Tmin,s of 2–3 K are common."*

Um FPSO é operação contínua, que é literalmente o caso que a frase cita: os 10 °C ficam
justificados **para esta aplicação**, e não como "valor típico de partida". O `min`/`max`
do descritor sai do §3.7.2 da mesma página (ótimo achatado de 5 a 50 °C).

Duas ressalvas que a nota precisa carregar, porque a fonte não diz o que seria cômodo:

- a faixa criogênica é **2–3 K**, não 3–5 °C;
- o livro explica o ΔTmin alto por **`U` baixo e capital caro** (§3.7.3: o ótimo migra para
  30 °C com `U` pela metade e 50 °C com `U` a um quinto), **não** por "energia barata". O
  enquadramento por custo de energia é plausível e não é o da fonte — e a nota é
  proveniência, então tem de dizer o que a página diz.

---

## Resultado

| | antes | depois |
|---|---|---|
| Testes do módulo | — | **304** (156 de núcleo, 148 de caso-ouro) |
| Suíte completa | 2.014 | **2.318**, zero falhas |
| Equações conferidas contra a fonte | — | **10** |
| Casos-ouro publicados | — | **2** (Tabela 2.2/2.3 + §3.3.2) |
| Desvio máximo no caso-ouro | — | **0** — acordo exato em todos os números |
| Defeitos encontrados | — | **0** |
| Erratas de fonte documentadas | 10 | **12** |
| Constantes empíricas introduzidas | — | **0** |
| Arquivos de `app/` tocados | — | **0** |
