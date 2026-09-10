# Passo 5 — Vaso flash / knockout drum bifásico

**Método:** `:stewart_arnold_2f` · **Equipamento:** `:knockout`
**Fonte:** Stewart, M. & Arnold, K. (2008), *Gas-Liquid and Liquid-Liquid Separators*,
cap. 3 — §3.8.2 a §3.8.6, Exemplo 3.1 e 3.2, Tabela 3.4 (pp. 113–129).
**Arquivos:** [two_phase.jl](../../src/sizing/knockout/two_phase.jl),
[gas_capacity.jl](../../src/sizing/gas_capacity.jl),
[drag.jl](../../src/sizing/separator/drag.jl),
[stewart_arnold_2f.toml](../../config/equipment/knockout/stewart_arnold_2f.toml)

O método mais curto do programa — **nove linhas de física, nenhuma de geometria** — e o
segundo com caso-ouro publicado. Compartilha o bloco A e a iteração de arrasto com o
separador trifásico, literalmente: é o **mesmo código**, porque é a mesma equação.

---

## 1. Equação do código × equação da referência

| # | Página | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Eq. (3.6) | 111 | `C_D = 24/Re + 3/√Re + 0,34` | [drag.jl:44](../../src/sizing/separator/drag.jl#L44) | **equivalente** — a mesma da Eq. (9) do artigo |
| Eq. (3.7b) | 112 | `V_t = 0,0036[((ρ_l−ρ_g)/ρ_g)(d_m/C_D)]^½` | [drag.jl:29](../../src/sizing/separator/drag.jl#L29) | **equivalente** — literal |
| Eq. (3.1) | 105 | `K = [(ρ_g/(ρ_l−ρ_g))(C_D/d_m)]^½` | [drag.jl:88](../../src/sizing/separator/drag.jl#L88) | **equivalente** — literal |
| Eq. (3.8b) | 115 | `d·L_eff = 34,5·[TZQ_g/P]·[(ρ_g/(ρ_l−ρ_g))(C_D/d_m)]^½` | [gas_capacity.jl:56](../../src/sizing/gas_capacity.jl#L56) | **equivalente** — literal, e é o **mesmo código** da Eq. (14) do trifásico |
| Eq. (3.8a) | 115 | campo: `420·[…]` | — (referência de conferência) | ver §2.2 |
| Eq. (3.9b) | 116 | `d²L_eff = 42.441·t_r·Q_l` | [two_phase.jl:124](../../src/sizing/knockout/two_phase.jl#L124) | **equivalente** — literal |
| Eq. (3.9a) | 116 | campo: `d²L_eff = t_r·Q_l/0,7` | — | ver §2.3 |
| Eq. (3.10b) | 117 | `L_ss = L_eff + d/1000` *for gas capacity* | [two_phase.jl:155](../../src/sizing/knockout/two_phase.jl#L155) | **equivalente** — literal |
| Eq. (3.11) | 117 | `L_ss = (4/3)L_eff`, "should not exceed" para capacidade de líquido | [two_phase.jl:155](../../src/sizing/knockout/two_phase.jl#L155) | **equivalente** — o `max(…)`, resolvido em §5 |
| §3.8.5 | 118 | *"Most two-phase separators are designed for slenderness ratios between **3 and 4**"* | `sr_min = 3`, `sr_max = 4`, `sr_target = 3,5` | **equivalente** — e é a diferença deliberada para os 3–5 do trifásico |

**Nenhuma divergência entre código e texto publicado neste método.** É o único dos cinco
em que os coeficientes usados são exatamente os que a fonte imprime, sem errata a
contornar — ver §2.

### O que este vaso **não** tem, e por quê

| bloco | trifásico | bifásico |
|---|---|---|
| A — capacidade de gás | Eq. 14 | **Eq. 3.8b — a mesma equação, o mesmo código** |
| B — decantação líquido-líquido | Eq. 16–21 | **não existe** |
| C — capacidade de líquido | Eq. 22, duas fases | Eq. 3.9b, uma fase |
| banda de esbeltez | 3–5 (§4.9.2) | **3–4 (§3.8.5)** |

O bloco B some porque não há duas fases líquidas: sem gotícula de água no óleo nem de
óleo na água, nada impõe teto de diâmetro. É o caminho `d_max = Inf` de
`VesselConstraints`, e o teste verifica que `mechanism === :none`, que `beta` e
`aw_over_a` saem `NaN` (e não zero), e que o rastro **não tem bloco de decantação nenhum**.

---

## 2. Auditoria dimensional

### 2.1 Unidades de entrada, constantes e saída

Idênticas às do trifásico (`03-*.md` §2.4, `04-*.md` §2.1): `field_units` é o único ponto
de conversão, e `two_phase.jl` **não importa nem menciona `Units`**. A única divisão por
1000 é o `d/1000` da Eq. (3.10b), que é a conversão mm→m dentro da própria equação
publicada.

A fonte confirma as unidades campo↔SI par a par, no bloco de nomenclatura sob a Eq. (3.8):
`d` in (**mm**), `L_eff` ft (**m**), `T` °R (**K**), `Q_g` MMscfd (**scmh** = m³/h),
`P` psia (**kPa**), `d_m` micron, `ρ` lb/ft³ (**kg/m³**). ✓ São exatamente as unidades que
`field_units` entrega.

Coerência do bloco C: `[mm²·m·h/(min·m³)]·[min]·[m³/h] = mm²·m` ✓, e
`L_eff = d²L_eff/d²` sai em m com `d` em mm ✓.

### 2.2 O `34,5` da Eq. (3.8b) — 0,87 % acima do equivalente exato do `420`

Convertendo a Eq. (3.8a) de campo termo a termo:

```
34,5_equiv = (25,4 × 0,3048) × 420 × 1,8 × [24/(10⁶ × 0,028316846592)] × 6,894757
           = 34,202
```

| candidato | desvio |
|---|---|
| `34,5` (publicado, e o que o código usa) | **+0,87 %** |

**Segue-se o publicado.** Não há contradição interna a resolver — as duas formas da fonte
concordam a menos de 1 % —, e o critério do projeto é seguir a fonte salvo quando ela se
contradiz. É o contraste deliberado com a Eq. (22) do trifásico, onde o impresso erra
1,9 % contra a **tabela do próprio artigo**, e por isso lá o valor é derivado.

O teste amarra as duas pontas: que o equivalente exato é `34,202` (`rtol = 10⁻³`), que a
razão `34,5/34,202 = 1,0087` (`rtol = 10⁻³`), e que a constante do TOML **é** `34,5` — de
modo que "corrigir" para o derivado quebre o teste e obrigue quem o fizer a justificar.

### 2.3 O `42.441` da Eq. (3.9b) — 0,081 % do equivalente exato

```
42.441_equiv = (25,4² × 0,3048) × (1/0,7) × [24/0,158987294928] = 42.406,6
```

| candidato | desvio |
|---|---|
| `42.441` (publicado, e o que o código usa) | **+0,081 %** |

O menor desvio fonte↔derivação de todo o projeto. **Segue-se o publicado**, pelo mesmo
critério.

### 2.4 O `0,0036` da Eq. (3.7b) e o `0,001` do Reynolds

Mesmas derivações do trifásico (`04-*.md` §2.2 e §2.3): o `0,001` fecha **exato**; o
`0,0036` trunca `√(4×9,81×10⁻⁶/3) = 3,6166×10⁻³` em **0,46 %**, sem impacto no resultado
porque `V_t` entra só no Reynolds da iteração e não em `K`.

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código | veredito |
|---|---|---|---|
| iteração de `C_D` | Exemplo 3.1 itera à mão até "OK" | `converge_drag` devolve `converged`; recusa com mensagem se falhar | **verificado** |
| faixa de `Re` da Eq. (3.6) | **não declarada** | não verificado | **lacuna** — igual ao trifásico |
| esbeltez | §3.8.5: **3 a 4**; e "must be at least 1 or more" pela Eq. (3.11) | `sr_min`/`sr_max` | **verificado** |
| teto de decantação | **não existe** neste vaso | `d_max = Inf`, `mechanism = :none` | **verificado, e é uma afirmação** — testado |
| nível de líquido 50 % | §3.8.3: "For a vessel 50 % full of liquid" | fixo por construção (Eq. 3.9b é a do meio cheio) | **verificado** — §3.8.7 trata `α ≠ 0,5` e não é este método |
| `Q_l` > 0 | implícito | checado, com mensagem própria | **verificado** |

---

## 4. Casos-ouro

### 4.1 Exemplo 3.2 e Tabela 3.4 — o erratum do texto

**Dados** (unidades de campo): gás 10 MMscfd a SG 0,6; óleo 2000 BOPD a 40 °API;
`P` = 1000 psia; `T` = 60 °F; `d_m` = 140 µm; `t_r` = 3 min; `Z` = 0,84;
`ρ_g` = 3,71 lb/ft³; `ρ_l` = 51,5 lb/ft³; `C_D` = 0,851.

**O texto do exemplo imprime `d·L_eff = 55,04`.** A Tabela 3.4 do **próprio exemplo** não
fecha com esse número:

| d (in) | `L_eff,gás` publicado | `39,85/d` → arred. | `55,04/d` → arred. |
|---|---|---|---|
| 16 | 2,5 | 2,49 → **2,5** ✓ | 3,44 → 3,4 ✗ |
| 20 | 2,0 | 1,99 → **2,0** ✓ | 2,75 → 2,8 ✗ |
| 24 | 1,7 | 1,66 → **1,7** ✓ | 2,29 → 2,3 ✗ |
| 30 | 1,3 | 1,33 → **1,3** ✓ | 1,83 → 1,8 ✗ |
| 36 | 1,1 | 1,11 → **1,1** ✓ | 1,53 → 1,5 ✗ |
| 42 | 0,9 | 0,95 → **0,9** ✓ | 1,31 → 1,3 ✗ |
| 48 | 0,8 | 0,83 → **0,8** ✓ | 1,15 → 1,1 ✗ |

**Sete de sete linhas fecham com 39,85; nenhuma com 55,04.** E `39,85` é o que a
Eq. (3.8a) dá com os dados do próprio enunciado:

```
420 × (520 × 0,84 × 10/1000) × [(3,71/47,79)(0,851/140)]^½
  = 420 × 4,368 × 0,0217228 = 39,85
```

**O texto está errado e a tabela certa.** É o mesmo padrão dos outros errata deste
projeto: a conta publicada ao lado do número publicado denuncia o número.

O teste fixa **as duas afirmações**: que a tabela é consistente com 39,85
(`round(39,85/d, 1) == publicado` nas sete linhas) e que **não** é com 55,04
(`round(55,04/d, 1) != publicado` nas sete).

### 4.2 A coluna de gás, em SI

| grandeza | publicado | calculado | desvio | tolerância |
|---|---|---|---|---|
| `d·L_eff` (convertido a in·ft) | 39,85 | 40,372 | **+1,31 %** | `rtol = 0,015` |
| `C_D` convergido | 0,851 | 0,8594 | **+0,99 %** | `rtol = 0,02` |

**Justificativa da tolerância de 1,5 %.** O desvio é dominado por duas parcelas
identificadas, não por erro de implementação:

| parcela | contribuição |
|---|---|
| o `34,5` estar 0,87 % acima do equivalente exato do `420` (§2.2) | **+0,87 %** |
| o `C_D` do livro (0,851) ser uma **iteração interrompida** — o ponto fixo real é 0,859 | ~+0,4 % |

Somadas, ~1,3 % — que é exatamente o desvio medido. A tolerância de 1,5 % é a menor que
acomoda as duas, e as duas estão quantificadas, não estimadas.

**Por que `C_D = 0,8594` e não `0,851`:** o Exemplo 3.1 itera à mão e para quando o valor
"fecha"; `converge_drag` vai até a convergência de verdade (sub-relaxada, tolerância
10⁻¹⁰). A diferença de 1 % é a distância entre a última iteração manual do livro e o ponto
fixo. **O programa está mais convergido que a fonte** — e o teste declara isso em vez de
afrouxar a tolerância sem explicação.

### 4.3 A coluna de líquido — Eq. (3.9b)

| d (in) | publicado (ft) | calculado (ft) | desvio |
|---|---|---|---|
| 16 | 33,5 | 33,51 | +0,03 % |
| 20 | 21,4 | 21,45 | +0,21 % |
| 24 | 14,9 | 14,89 | −0,05 % |
| 30 | 9,5 | 9,53 | +0,33 % |
| 36 | 6,6 | 6,62 | +0,29 % |
| 42 | 4,9 | 4,86 | **−0,75 %** |
| 48 | 3,7 | 3,72 | +0,63 % |

**Tolerância adotada: `rtol = 0,02` (2 %).**

*Justificativa.* A tabela publica **uma casa decimal em pés**. Em `d = 42 in` o valor é
4,9 ft, e meia casa (0,05 ft) já vale **1,0 %**; em `d = 48 in` o valor é 3,7 ft e meia
casa vale 1,4 %. A tolerância tem de acomodar o arredondamento da publicação, e 2 % é o
menor valor que o faz com margem. O desvio real fica em ±0,75 %, ou seja bem dentro — o
que confirma que o `42.441` está certo, já que um coeficiente errado em 2 % apareceria.

Note o contraste com o trifásico, onde a tolerância é **0,5 %**: lá a Tabela 3 publica
quatro algarismos e o desvio é sistemático e explicado; aqui a tabela publica dois e o
desvio é disperso, que é a assinatura de arredondamento.

### 4.4 O bloco de gás é literalmente o mesmo do trifásico

A Eq. (3.8b) do livro e a Eq. (14) do artigo **são a mesma equação**, e o programa as
resolve com o **mesmo código** (`gas_capacity_dleff`). O que muda é só a numeração citada
no memorial, para que o leitor confira no livro e não num artigo sobre trifásicos. Há
teste que verifica que os dois caminhos dão o mesmo número — se algum dia divergirem, é
porque alguém duplicou a física.

---

## 5. Defeitos encontrados

**Nenhum defeito.** Este passo fechou sem correção de código.

### E uma ambiguidade que ficou resolvida — pela própria fonte

Os passos 3 e 5 abriram a mesma pergunta, sobre o `L_ss` de um vaso governado por
**capacidade de líquido**. O §3.8.4 (e o §4.9.1, idêntico) diz duas coisas:

- *"the seam-to-seam length of a vessel may be estimated as **the larger of the
  following**"* — Eq. (3.10b) `L_eff + d/1000` e Eq. (3.11) `(4/3)L_eff`;
- e logo abaixo: *"For vessels sized on a liquid capacity basis… The seam-to-seam length
  **should not exceed** the following: `L_ss = (4/3)L_eff`"*.

Lidas isoladamente, a primeira manda tomar o **máximo** e a segunda manda tratar
`(4/3)L_eff` como **teto**. O código usa o máximo.

**A Tabela 3.4 do próprio livro decide a favor do máximo.** As três últimas linhas
(`d` = 36, 42, 48 in) são governadas por líquido — a coluna de líquido é 6 a 30 vezes a de
gás —, e nelas o `L_ss` publicado **excede** `(4/3)L_eff`:

| d (in) | `L_eff,líq` | `(4/3)L_eff` | `L_ss` publicado | excede o "teto"? |
|---|---|---|---|---|
| 30 | 9,5 | 12,67 | 12,7 | não — o `(4/3)` governa |
| 36 | 6,6 | 8,80 | **9,1** | **sim** |
| 42 | 4,9 | 6,53 | **7,4** | **sim** |
| 48 | 3,7 | 4,93 | **6,2** | **sim** |

E a nota de rodapé da tabela é explícita: **"`L_ss = L_eff + 2,5` governs"** nessas três
linhas. Ou seja: **o livro, no seu próprio exemplo resolvido, toma o maior dos dois mesmo
num vaso de capacidade de líquido.** A leitura "teto" fica descartada, e o `max(…)` do
código é a leitura certa — para este vaso e para o tratador.

Isso **fecha a pendência aberta em `03-*.md` §6.4**, sem precisar de decisão de engenharia.

### Um sexto erratum da fonte, sem consequência para o programa

O `+2,5` da nota de rodapé **não** é `d/12`: para `d = 36 in`, `d/12 = 3,0 ft`, e
`6,6 + 3,0 = 9,6`, não os 9,1 publicados. Os três valores só fecham com um `+2,5 ft`
constante — que é `d/12` congelado em `d = 30 in`.

Ou seja, a coluna `L_ss` da Tabela 3.4 **não é reproduzível pela Eq. (3.10a)** que o
próprio passo 5 do exemplo manda usar. O programa segue a **equação publicada**, e por
isso o caso-ouro **não testa a coluna `L_ss`** — testa `d·L_eff` e a coluna de líquido,
que são as duas que a fonte sustenta. A discrepância fica registrada aqui em vez de
virar uma tolerância inflada que a escondesse.

| d (in) | `L_ss` publicado | pela Eq. (3.10a) + (3.11) | diferença |
|---|---|---|---|
| 36 | 9,1 | 9,60 | +5,5 % |
| 42 | 7,4 | 8,40 | +13,5 % |
| 48 | 6,2 | 7,70 | +24,2 % |

---

## 6. Lacunas não fechadas

1. **A Eq. (3.6) não tem faixa de validade declarada.** Idêntico ao trifásico
   (`04-*.md` §6.1): o ajuste `24/Re + 3/√Re + 0,34` não vem com faixa em nenhuma das
   fontes. O que a fonte pede — convergência — é verificado.

2. **Um só caso-ouro.** O Exemplo 3.2, em unidades de campo, com sete linhas. É bom
   (fixa o coeficiente de gás e o de líquido independentemente) mas é um só, e o `L_ss`
   dele não é reproduzível. A mesma pendência do trifásico.

3. **O `C_D` do livro é uma iteração interrompida.** Não é lacuna do programa — é
   diferença conhecida e quantificada (§4.2), e o programa está do lado certo dela.

4. **`α = 0,5` fixo.** O §3.8.7 do livro trata vasos com fração de líquido diferente de
   meio cheio (Eq. 3.12/3.13, com constantes de projeto lidas das Figuras 3.47 e 3.48).
   Este método **não** o implementa, e nem finge: a Eq. (3.9b) é a do vaso meio cheio, e
   é o que o `note` do TOML declara. Quem precisar de outro nível não tem equipamento no
   registro que sirva — é lacuna de escopo, declarada.

---

## Resultado

| | |
|---|---|
| Testes do método | 68 (inalterado) |
| Equações conferidas contra a fonte | **10** |
| Divergências fonte↔código | **0** — único método sem errata a contornar |
| Erratas da fonte encontradas | 2 (o `55,04` do texto; o `+2,5` da Tabela 3.4) |
| Defeitos encontrados | **0** |
| Ambiguidades resolvidas | **1** — o `L_ss`, pela Tabela 3.4 do próprio livro |
| Caso-ouro | Tabela 3.4: gás +1,31 % (tol. 1,5 %), líquido ±0,75 % (tol. 2 %) |
