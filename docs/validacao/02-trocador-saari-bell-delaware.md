# Passo 2 — Trocador de calor casco-e-tubos

**Método:** `:saari_lmtd` · **Equipamento:** `:exchanger`
**Fontes:**
- Saari, J., *Heat Exchanger Dimensioning*, Lappeenranta University of Technology
  (cap. 3–6; Algoritmo 4.1, Eq. 4.4–4.12, 5.4–5.7, 6.23; Tabelas 3.1, 4.1, 4.2;
  Figuras 4.2, 4.3, 4.4) — **101 páginas, PDF não cifrado, texto extraível**.
- Branan, C. R., *Rules of Thumb for Chemical Engineers*, 5ª ed., Elsevier, 2012,
  cap. 2 "Heat Exchangers", pp. 41–45 (Eq. 2-13 a 2-29; Tabelas 2-5, 2-6, 2-7) —
  **445 páginas, não cifrado**.

**Arquivos:** [shell_and_tube.jl](../../src/sizing/exchanger/shell_and_tube.jl),
[bell_delaware.jl](../../src/sizing/exchanger/bell_delaware.jl),
[saari_lmtd.toml](../../config/equipment/exchanger/saari_lmtd.toml)

É o maior dos cinco métodos e o de maior superfície: 12 relações de Saari e 13 de Branan,
duas fontes, e um laço de ponto fixo entre elas.

---

## 1. Equação do código × equação da referência

### 1.1 Saari — balanço, ΔT e coeficiente global

| # | Página | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Alg. 4.1 | p. 33 | passo 3 fixa "tubes per pass, thereby determining also a fixed value for tube-side flow velocity and by consequence the convection heat transfer coefficient"; passo 6 fecha o comprimento | eixo de varredura `:n_tubos` | **equivalente** — o artigo prescreve literalmente a varredura implementada |
| Eq. (4.4) | p. 34 | `A = q/(U·ΔT_m)` | [shell_and_tube.jl:493](../../src/sizing/exchanger/shell_and_tube.jl#L493) | **equivalente** — com `F` da Eq. 4.9 |
| Eq. (4.5) | p. 34 | `q = (ṁcp)_h(T_h,i − T_h,o) = (ṁcp)_c(T_c,o − T_c,i)` | [:355](../../src/sizing/exchanger/shell_and_tube.jl#L355) | **equivalente** — literal |
| Eq. (4.6) | p. 35 | `ΔT_lm = (ΔT₁ − ΔT₂)/ln(ΔT₁/ΔT₂)` | [:150](../../src/sizing/exchanger/shell_and_tube.jl#L150) `lmtd` | **equivalente** — literal |
| Eq. (4.7) | p. 36 | contracorrente: `ΔT₁ = T_h,i − T_c,o`, `ΔT₂ = T_h,o − T_c,i` | [:375](../../src/sizing/exchanger/shell_and_tube.jl#L375) | **equivalente** — literal |
| Eq. (4.8) | p. 36 | paralelo: `ΔT₁ = T_h,i − T_c,i`, `ΔT₂ = T_h,o − T_c,o` | não implementado (por escolha) | **não se aplica** — o método é contracorrente + `F` |
| Eq. (4.9) | p. 38 | `q = U·A·F·ΔT_lm` | [:407](../../src/sizing/exchanger/shell_and_tube.jl#L407) | **equivalente** — literal |
| Eq. (4.10) | p. 38 | `P_h = ΔT_h/(T_h,i − T_c,i)` | [:392](../../src/sizing/exchanger/shell_and_tube.jl#L392) | **equivalente** |
| Eq. (4.11)/(4.12) | p. 38–39 | `R_h = Ċ_h/Ċ_c = ΔT_c/ΔT_h` | [:393](../../src/sizing/exchanger/shell_and_tube.jl#L393) | **equivalente** — ver divergência 3 |
| Fig. 4.3 | p. 40 | `F = √(1+R²)·ln[(1−RP)/(1−P)] / {(1−R)·ln[(2−P(1+R−√(1+R²)))/(2−P(1+R+√(1+R²)))]}` | [:199](../../src/sizing/exchanger/shell_and_tube.jl#L199) `f_correction_1_2` | **equivalente** — termo a termo |
| §4.2.3 | p. 40 | `Ċ_h = Ċ_c ⇒ ΔT_lm = ΔT₁ = ΔT₂` | [:153](../../src/sizing/exchanger/shell_and_tube.jl#L153) limite removível | **equivalente** |
| Fig. 4.4 | p. 44 | `ε = (1−e^(−NTU(1−C*)))/(1−C*e^(−NTU(1−C*)))`; `ε = NTU/(1+NTU)` se `C* = 1` | [:281](../../src/sizing/exchanger/shell_and_tube.jl#L281) | **equivalente** — literal, nos dois ramos |
| Eq. (5.4) | p. 55 | `R_w = ln(d_o/d_i)/(2π k_w L)` | dentro de `overall_u` | **equivalente após rearranjo** — ver §2.1 |
| Eq. (5.7a) | p. 56 | `U_h = [1/h_h + R"f,h + A_h R_w + (A_h/A_c)R"f,c + (A_h/A_c)/h_c]⁻¹` | [:263](../../src/sizing/exchanger/shell_and_tube.jl#L263) `overall_u` | **equivalente após rearranjo** — ver §2.1 |
| Eq. (6.23) | p. 68 | `Nu = 0,024 Re^0,8 Pr^0,4` (aquec.); `0,026 Re^0,8 Pr^0,3` (resfr.) | [:240](../../src/sizing/exchanger/shell_and_tube.jl#L240) | **equivalente** — literal |
| Tabela 3.1 | p. 21 | casco de chapa 300–2500 mm; `d_o` 5–55 mm; corte 25 %; passo 1,25–1,5·`d_o`; `L_bc` 0,2–1,0·`D_s`; `v` < 3 m/s (aço) e ~1 m/s por incrustação | defaults e `min`/`max` do TOML | **equivalente** — todos os seis conferidos |

### 1.2 Branan — Bell-Delaware

| # | Página | Forma publicada | Código | Veredito |
|---|---|---|---|---|
| Eq. (2-13) | p. 41 | `Area₁tubo,triangular = (√3/2)(PR·d_o)²` | [:499](../../src/sizing/exchanger/shell_and_tube.jl#L499) | **equivalente** (30°, 60°) |
| Eq. (2-14) | p. 41 | `Area₁tubo,quadrada = (PR·d_o)²` | [:499](../../src/sizing/exchanger/shell_and_tube.jl#L499) | **corrigido nesta fase** — ver defeito 4 |
| Eq. (2-17) | p. 41 | `D_s,min = 2√(A_corr/π) + 2·d_o` | [:520](../../src/sizing/exchanger/shell_and_tube.jl#L520) | **corrigido nesta fase** — ver defeito 5 |
| Eq. (2-18) | p. 42 | `h_o = h_ideal·Jc·Jl·Jb·Js·Jr` | [bell_delaware.jl:394](../../src/sizing/exchanger/bell_delaware.jl#L394) | **equivalente** — literal |
| Eq. (2-19) | p. 42 | `h_ideal = J·c_ps(W_s/A_s)(k_s/(c_ps µ_s))^(2/3)(µ_s/µ_s,w)^0,14` | [:225](../../src/sizing/exchanger/bell_delaware.jl#L225) | **equivalente** — `µ_s/µ_s,w = 1` é hipótese declarada |
| — (A_s) | p. 42 | `A_s = L_bc[D_s − D_otl + (D_otl − d_o)(p_n − d_o)/p_n]`, e com `p_t` no numerador para 45° com `p_t/d_o < 1,707` e 60° com `< 3,732` | [:159](../../src/sizing/exchanger/bell_delaware.jl#L159) `crossflow_area` | **equivalente** — as duas variantes e os dois limiares |
| Eq. (2-20) | p. 43 | `N_Re,s = d_o·W_s/(µ_s·A_s)` | [:176](../../src/sizing/exchanger/bell_delaware.jl#L176) | **equivalente** — literal |
| Eq. (2-21) | p. 43 | `J_ideal = a₁(1,33/(PR/d_o))^a · N_Re,s^a₂`, `a = a₃/(1+0,14 N_Re,s^a₄)` | [:190](../../src/sizing/exchanger/bell_delaware.jl#L190) | **divergente, documentado** — divergência 1 |
| Eq. (2-22) | p. 43 | `Jc = 0,55 + 0,72 Fc`, `Fc = (1/π)[π + 2φ sen(arccos φ) − 2 arccos φ]`, `φ = (D_s−2l_c)/D_otl` | [:248](../../src/sizing/exchanger/bell_delaware.jl#L248) | **equivalente** — literal |
| Eq. (2-23) | p. 43 | `Jl = 0,44(1−r_a) + [1 − **0,044**(1−r_a)]exp(−2,2 r_b)` | [:302](../../src/sizing/exchanger/bell_delaware.jl#L302) | **divergente, nova** — divergência 5 |
| Eq. (2-24) | p. 44 | `A_sb = ½(π − θ₁)D_s d_sb`, `θ₁ = arccos(1 − 2l_c/D_s)` | [:271](../../src/sizing/exchanger/bell_delaware.jl#L271) | **equivalente** — meio ângulo de propósito |
| Eq. (2-25) | p. 44 | `A_tb = π d_o(1−F_w)N_t d_tb/4`, `F_w = (θ₃−sen θ₃)/2π`, `θ₃ = 2 arccos[(D_s−2l_c)/(D_s−C₁)]`, `C₁ = D_s − D_otl` | [:271](../../src/sizing/exchanger/bell_delaware.jl#L271) | **equivalente** — `D_s − C₁ = D_otl`, e é isso que o código escreve |
| Eq. (2-26) | p. 44 | `A_w = A_wg − A_wt`, `A_wg = (D_s²/8)(θ₂ − sen θ₂)`, `θ₂ = arccos(1 − 2l_c/D_s)` | [:271](../../src/sizing/exchanger/bell_delaware.jl#L271) | **divergente, documentado** — divergência 2 |
| Eq. (2-27) | p. 44 | `Jb = exp[−C·r_c(1−(2z)^⅓)]` para `z < ½`, `1` para `z ≥ ½`; `C = 1,35` se `Re ≤ 100`, `1,25` acima | [:324](../../src/sizing/exchanger/bell_delaware.jl#L324) | **equivalente** — literal |
| Eq. (2-28) | p. 45 | `Js = [n_b − 1 + Li^(1−n) + Lo^(1−n)]/[n_b − 1 + Li + Lo]` | [:349](../../src/sizing/exchanger/bell_delaware.jl#L349) | **equivalente** |
| Eq. (2-29) | p. 45 | `Jr = (10/n_r,cc)^0,18` até Re 20, `1` acima de Re 100, linear entre | [:367](../../src/sizing/exchanger/bell_delaware.jl#L367) | **equivalente** |
| Tabela 2-5 | p. 42 | 20 linhas × `a₁ a₂ a₃ a₄` | `[constants.bell_delaware]` | **equivalente** — 80 valores conferidos um a um na página renderizada; ver divergência 4 |
| Tabela 2-6 | p. 43 | `p_n`, `p_p` por layout; **30° e 60° triangulares, 45° e 90° quadrados** | `pn_sobre_pt`, `pp_sobre_pt` | **equivalente** — os oito valores |
| Tabela 2-7 | p. 44 | folga diametral **casco-chicana** TEMA R, 2,540 a 7,620 mm | `folga_dn_max`, `folga_chicana` | **equivalente**; aplicação corrigida no defeito 5 |

### Divergências entre código e texto publicado

| # | Onde | O que a fonte imprime | O que o código faz | Como foi decidido |
|---|---|---|---|---|
| 1 | Branan Eq. (2-21) | `1,33/(PR/d_o)` | `1,33/PR` = `1,33/(p_t/d_o)` | `PR` é definido três linhas acima como adimensional ("PR = tube pitch ratio (usually 1.25, 1.285, 1.33, or 1.5)"); `PR/d_o` tem dimensão 1/comprimento, e `J_ideal` passaria a depender de `d_o` estar em mm ou m. **Checável por dentro** |
| 2 | Branan Eq. (2-26) | `θ₂ = arccos(1 − 2l_c/D_s)` | `θ₂ = 2·arccos(…)` | Sem o fator 2 a "área bruta da janela" sai 6,8× menor que o segmento circular que ela é. Conferido contra `_segment_area`, geometria que o projeto já tinha. **Checável por dentro** |
| 3 | Saari Fig. 4.3 | `R₁ = (T₁ᵢ−T₁ₒ)/(T₂ᵢ−T₂ₒ)` = `ΔT₁/ΔT₂` | `R₁ = ΔT₂/ΔT₁` | Contradiz a **Eq. (4.11) do próprio texto** (`R_h = Ċ_h/Ċ_c`) e a **Eq. (4.12)** (`R_h = ΔT_c/ΔT_h`), e a convenção de Shah & Sekulić, que a própria Fig. 4.3 cita. **Verificado por rota independente** — ver §4 |
| 4 | Branan Tab. 2-5, linha 90°/Re 0–10 | `a₂ = 0,667`, **sem** o sinal de menos | `a₂ = −0,667` | As outras 19 linhas trazem o menos. `j` tem de cair com `Re`, e é o que as outras quatro faixas do mesmo layout fazem. Confirmado na página renderizada: os menos estão nítidos em 19 linhas e ausentes nessa. **Checável por dentro** |
| 5 | Branan Eq. (2-23) | `[1 − **0,044**(1−r_a)]` no segundo colchete | `[1 − 0,44(1−r_a)]` | **Nova nesta fase.** `Jl` é um fator que desconta: com vazamento nulo tem de valer 1. Com 0,44 nos dois lugares dá exatamente 1; com o 0,044 impresso daria **1,396** — um "fator de correção" que amplifica `h_o` em 40 % justamente onde a construção é perfeita. 0,44 nos dois é também a forma de Taborek e de Shah & Sekulić. **Checável por dentro** |

As cinco foram decididas **por dentro** — coerência dimensional, coerência com outra
equação do mesmo texto, ou um limite conhecido a priori —, nunca por preferir outra fonte.

---

## 2. Auditoria dimensional

### 2.1 Eq. (5.7a) — as cinco resistências trazidas à área externa

Saari escreve `U_h` com áreas explícitas; o código escreve resistências por unidade de
área externa. A equivalência é a multiplicação de tudo por `A_o = π d_o L`:

| termo de Saari | × `A_o` | termo do código |
|---|---|---|
| `1/h_h` | — | `1/h_o` |
| `R"f,h` | — | `rf_o` |
| `A_h·R_w` = `π d_o L · ln(d_o/d_i)/(2π k_w L)` | `L` e `π` cancelam | `d_o·log(d_o/d_i)/(2·k_w)` |
| `(A_h/A_c)·R"f,c` | `A_o/A_i = d_o/d_i` | `razao·rf_i` |
| `(A_h/A_c)/h_c` | idem | `razao/h_i` |

`[m²K/W]` nas cinco. Saari acrescenta *"depending on which of the areas is the larger
one"* (p. 56) e o código usa a externa, que é a maior. **Errar a razão `d_o/d_i` é o modo
silencioso de errar `U` num tubo de parede fina** — o número continua plausível —, e é
por isso que o teste a fixa nos dois termos internos separadamente.

### 2.2 Eq. (6.23) — Nusselt, Reynolds e Prandtl são adimensionais, e é preciso que sejam

`Nu = 0,024 Re^0,8 Pr^0,4` só é independente de unidade porque os três grupos são
adimensionais. Isso obriga o lado do tubo a estar **inteiramente em SI**:

| grandeza | fonte | unidade | conversão |
|---|---|---|---|
| `mu_tubo` | formulário, em **cP** | Pa·s | `Units.cp_to_pas` em [`case_input`](../../src/sizing/exchanger/shell_and_tube.jl#L121) — **uma vez, na fronteira** |
| `mu_casco` | formulário, em **cP** | Pa·s | idem, mesma linha |
| `d_externo`, `espessura` | formulário, em **mm** | m | `Units.mm_to_m` em `sizing_constraints` |
| `folga_furo_chicana` | formulário, em **mm** | m | idem |
| `k_tubo`, `k_casco`, `cp`, `ρ`, `ṁ` | formulário | já SI | nenhuma |
| `d_casco` (saída) | m | **mm** | `Units.m_to_mm` em `derived` — só na saída |

`Pr = cp·µ/k` = `[J/kgK][Pa·s]/[W/mK]` = adimensional ✓ com `µ` em Pa·s. Com `µ` em cP o
Prandtl sairia **1000× maior** e `Nu` cresceria por `1000^0,4 ≈ 16`. Verificado: a
conversão acontece **só** em `case_input`, e `ExchangerDuty.mu_tubo`/`mu_casco` estão
comentados `# Pa·s`.

`ExchangerDuty` é o único ponto do projeto em que a conversão de corrente **não** passa
por `field_units` — e é correto que não passe: `field_units` leva a unidades de campo de
Stewart & Arnold (cP, m³/h, kPa), que é o oposto do que este método precisa. O gancho
`case_input` existe exatamente para isso.

### 2.3 Bell-Delaware — comprimentos em metros, uma exceção declarada

Todos os campos de `ShellGeometry` estão em **metros** (o docstring o declara). A única
grandeza que entra em mm é o argumento de `baffle_clearance`, porque a Tabela 2-7 é
indexada por **DN em mm**; a conversão de ida e de volta acontece na mesma expressão, em
[shell_and_tube.jl:519-521](../../src/sizing/exchanger/shell_and_tube.jl#L519):

```julia
folga_mm = baffle_clearance(Units.m_to_mm(d_otl), kbd)
d_s = d_otl + Units.mm_to_m(folga_mm)
```

`J_ideal` (Eq. 2-21) é o ponto onde a divergência 1 importa dimensionalmente: com o
`PR/d_o` impresso, a base do expoente teria dimensão de comprimento e `J_ideal` mudaria
de valor conforme `d_o` estivesse em mm ou em m. Com `1,33/PR` a base é adimensional. **É
a auditoria dimensional que decide a divergência 1** — não uma preferência por outra fonte.

`h_ideal` (Eq. 2-19): `[J/kgK]·[kg/m²s]·[adimensional] = W/m²K` ✓, com `W_s/A_s` em
kg/(m²·s) e `(k/(cp·µ))^(2/3)` adimensional (é `Pr^(−2/3)`).

---

## 3. Limites de validade: declarados × verificados

| limite | declarado pela fonte | verificado no código (antes) | agora |
|---|---|---|---|
| **Dittus-Boelter** | **`10⁴ < Re < 1,2×10⁵` e `0,7 < Pr < 120`** (p. 68), com *"Below Re = 10⁴ the results are much worse"* | **não verificado** | **recusa o feixe** — defeito 3 |
| Dittus-Boelter, `ΔT` parede-fluido | erros maiores acima de ~6 °C (líquidos) / 60 °C (gases), p. 68 | não verificável | **lacuna** — exige `T` de parede, que o método não itera |
| Dittus-Boelter, rugosidade | "fully developed turbulent flows in **smooth pipes**" | não verificado | **lacuna declarada** — não há campo de rugosidade neste método |
| Tabela 2-5 (`J_ideal`) | faixas de Re 0–10, 10–100, 100–1000, 1000–10⁴, **10⁴+** | `re_max` com topo aberto | **correto** — a faixa de topo é aberta *por publicação*; extrapolar acima de 10⁴ é autorizado |
| `Jb` (Eq. 2-27) | `z ≥ ½` ⇒ `Jb = 1` | verificado | inalterado |
| `Jr` (Eq. 2-29) | `Re ≥ 100` ⇒ `Jr = 1`; `≤ 20` ⇒ forma laminar; linear entre | verificado | inalterado |
| `F` do arranjo 1-2 | domínio físico: `P < P_max(R) = 2/(1+R+√(1+R²))` | `den_log ≤ 0` ⇒ `NaN` | **correto** — verificado em §4 |
| `F` mínimo prático | **não é da fonte**; prática TEMA descarta `F < 0,75` | não verificado | **lacuna, decisão pendente** — ver §6 |
| banda de velocidade | Tab. 3.1: erosão < 3 m/s (aço), incrustação ~1 m/s | `v_min`/`v_max` | inalterado |
| `L_bc/D_s` | Tab. 3.1: **0,2 a 1,0** | `min`/`max` do `ParameterSpec` | **correto** — os dois batem com a tabela |
| passo/`d_o` | Tab. 3.1: 1,25 a 1,5 | `min = 1,1`, `max = 2,0` | **mais largo que a fonte** — declarado no `note`; é decisão de projeto |
| nº de passes × `D_s` | Tab. 3.1: "no more than `D_s` in hundreds of mm" — um casco de 200 mm não passa de 2 passes | **não verificado** | **lacuna** — ver §6 |
| `d_casco_max` | Tab. 3.1: chapa enrolada até 2500 mm | verificado em `admissible` | **compara com o FEIXE, não com o casco** — ver §6 |

---

## 4. Casos-ouro

**Saari não publica um exemplo do trocador casco-e-tubos completo.** O único caso
numérico resolvido é o Exemplo 4.1, tubo duplo, com `U` **dado** — ele não fecha o laço
`velocidade → h_i → U`. Branan também não traz exemplo numérico de Bell-Delaware. Isso é
declarado, não contornado.

### 4.1 Exemplo 4.1 (Saari, pp. 36–37) — a cadeia, número a número

| grandeza | publicado | calculado | desvio | tolerância |
|---|---|---|---|---|
| `Ċ_h` | 1500 W/K | 1500,0 | 0 | exato |
| `Ċ_c` | 1260 W/K | 1260,0 | 0 | exato |
| `q` | 75 000 W | 75 000,0 | 0 | exato |
| `T_c,o` | 69,5 °C | 69,5238 | +0,03 % | `atol = 0,05` — a fonte publica 1 decimal |
| `ΔT₁` | 20,5 °C | 20,476 | −0,12 % | `atol = 0,05` |
| `ΔT₂` | 30 °C | 30,0 | 0 | exato |
| `ΔT_lm` | 24,95 °C | 24,9459 | −0,02 % | `atol = 0,02` — 4 algarismos publicados |
| `A` | 15,03 m² | 15,0325 | +0,02 % | `rtol = 2×10⁻³` |
| `L` | 143,2 m | 143,25 | +0,03 % | `rtol = 2×10⁻³` |
| `n` | 79,6 → 80 | 79,58 → 80 | −0,03 % | `rtol = 3×10⁻³` |
| paralelo: `ΔT₂` | −29,5 °C | −29,52 | +0,08 % | `atol = 0,05`; e `lmtd` devolve `NaN` |

**Tolerâncias justificadas pelo arredondamento da publicação**, não escolhidas para
caber: a fonte imprime 1 decimal em temperatura e 4 algarismos em `ΔT_lm`/`A`/`L`, e cada
tolerância é meia casa da última publicada. Todos os desvios ficam abaixo de 0,15 %.

**Dois errata do enunciado, confirmados linha a linha no texto:**

1. **Vazão de água.** O enunciado (p. 36) diz `0.20 kg/s`; a solução (p. 37) escreve
   `Ċ_c = ṁ_c cp,c = 0.30 kg/s · 4200 J/kgK = 1260 W/K` e segue com 1260 até o fim. Com
   0,20 daria `Ċ_c = 840` e `T_c,o = 99,3 °C` — acima da entrada do óleo, tornando o
   exemplo impossível. **0,30 é o certo**, e o teste demonstra a impossibilidade do 0,20.
2. **Comprimento do elemento.** O enunciado diz "built of **1.8** metre long elements"; a
   solução diz "calculate then the required number of **3.6** metre elements" e em
   seguida divide por **1,8** (`n = 143.2/1.8 = 79.6`). **1,8 é o certo.**
3. *(observação)* A solução cita "eq. (4.2)" para o balanço, que no texto é a Eq. (4.5).
   Terceira inconsistência de referência cruzada no mesmo exemplo; sem consequência.

### 4.2 LMTD ↔ ε-NTU — a conferência que §4.1 promete ser exata

§4.1 (p. 32): *"all methods derived from the same basic equations … are essentially
equivalent, and will yield the same results if correctly applied"*. Dado o `A` que o
caminho LMTD produz, o caminho ε-NTU tem de devolver o **mesmo** `q`.

Quatro casos, incluindo os dois limites removíveis (`C* = 1` e `C* ≈ 0`):
**desvio ≤ 10⁻⁹** (`rtol = 1e-9`, ou seja precisão de máquina). Os dois caminhos não
compartilham nenhuma linha de código, então a coincidência é verificação e não tautologia.

### 4.3 Fator `F` — verificado contra a relação P-NTU de Shah & Sekulić

Esta fase acrescentou a conferência que decide a **divergência 3**. A relação P-NTU do
TEMA E 1-2,

```
P₁ = 2 / [1 + R₁ + √(1+R₁²)·coth(NTU₁·√(1+R₁²)/2)]
F  = ln[(1−R₁P₁)/(1−P₁)] / [NTU₁(1−R₁)]
```

não compartilha uma linha com `f_correction_1_2`. Resultado em 12 pontos
(`R` de 0,4 a 2,0 × `NTU` de 0,5 a 3,0):

| desvio relativo máximo | **7,4×10⁻¹⁵** |
|---|---|

Isto é precisão de máquina, e **só fecha com o pareamento `(P₁, R₁ = ΔT₂/ΔT₁)`** — o da
Eq. (4.11)/(4.12), não o da anotação da Fig. 4.3. O arranjo também sai *stream symmetric*
(`F(P₁,R₁) = F(P₂,R₂)` com `P₂ = P₁R₁`, `R₂ = 1/R₁`) à precisão de máquina, que é o que a
p. 39 afirma citando Shah & Sekulić.

### 4.4 Bell-Delaware — o que existe no lugar de um caso-ouro

Não há exemplo numérico. O que ancora o bloco:

- **A regra de bolso do próprio Branan:** *"a total correction of 0.60 may be used
  (h_o = 0.6 h_ideal) since this has long been used as a rule of thumb"*. O produto
  `Jc·Jl·Jb·Js·Jr` calculado fica em **0,42–0,63** ao longo da grade — encosta nos 0,60 e
  o cerca, que é o comportamento esperado.
- **Uma segunda fonte independente para a estrutura:** Toledo-Velázquez et al. (2014)
  publica `h_cc = Ji·Cp(W/S_m)(k/(Cp µ))^(2/3)(µ/µ_w)^0,14·Jc·Jl·Jb·Jr·Js` — os mesmos
  cinco fatores, o mesmo expoente 2/3, o mesmo 0,14, as mesmas variáveis de comando. Duas
  fontes chegando à mesma forma por caminhos diferentes.
- **As faixas que Branan declara para cada fator**, todas verificadas: `Jc` 0,53–1,15;
  `Jl` 0,7–0,8; `Jb` 0,7–0,9; `Js` 0,85–1; `Jr` = 1 acima de Re 100.
- **Geometria exata** onde ela existe: a área da janela conferida contra `_segment_area` à
  precisão de máquina (divergência 2), e `Js = 1` quando as pontas igualam o vão central.

---

## 5. Defeitos encontrados

### Defeito 3 — Dittus-Boelter aplicada fora da faixa, em silêncio
**Classe: físico.**

Saari declara a Eq. (6.23) válida em `10⁴ < Re < 1,2×10⁵` e `0,7 < Pr < 120`, e é
explícito sobre o que há fora: *"Below Re = 10⁴ the results are much worse."*
`nusselt_dittus_boelter` exigia apenas `re > 0 && pr > 0`, e `case_admissible` só olhava
`t.ok` e a banda de velocidade.

**Retrato** (óleo no tubo: 850 kg/m³, 5 cP, `k` = 0,13, `cp` = 2100 ⇒ `Pr = 80,8`,
**dentro** da faixa de Prandtl):

| n/passe | v (m/s) | na banda 1–3? | Re | em 10⁴–1,2×10⁵? | aceito antes? |
|---|---|---|---|---|---|
| 60 | 2,27 | sim | **5 724** | **não** | **sim** |
| 100 | 1,36 | sim | **3 434** | **não** | **sim** |
| 150 | 0,91 | não | 2 289 | não | não |

Em `Re = 3 434` o escoamento é laminar/transicional e a correlação superestima `h_i`
largamente; o erro atravessa `U → A → L` e sai como comprimento de tubo, com a mesma
aparência de qualquer outro resultado. Diferentemente da bomba, **não há segundo ramo**:
o método não implementa correlação laminar de convecção interna.

**Teste:** `@testset "fora da faixa de Dittus-Boelter o feixe é recusado"` — o
sub-testset `"o retrato do defeito: Re fora da faixa, v dentro da banda"` reproduz a
tabela antes de qualquer asserção sobre o comportamento novo.

**Correção.** `nusselt_dittus_boelter` devolve `(Nu, valida)`; `_tubo` carrega
`nu_valido`; `case_admissible` o exige; `selection_message` ganhou o braço que nomeia a
correlação, o `Re`, o `Pr` e as quatro fronteiras, **antes** dos braços de comprimento e
de casco (que são calculados a partir de `h_i`, e diagnosticar por eles seria apontar o
sintoma de um número já reprovado na origem). As quatro fronteiras foram para o TOML.

### Defeito 4 — o feixe usava empacotamento triangular nos quatro layouts
**Classe: físico** (geometria).

`d_feixe = √(4·N·(√3/2)·passo²/π)` era aplicado a 30°, 45°, 60° e 90°. Branan publica
**as duas** áreas de célula lado a lado — Eq. (2-13) triangular e **Eq. (2-14)
quadrada** — e explica cada uma em prosa; a Tabela 2-6 nomeia os layouts: *"30° Triangular
Staggered"*, *"60° Rotated Triangular Staggered"*, *"90° Square Inline"*, *"45° Rotated
Square Staggered"*. Não era geometria sem fonte: era a Eq. (2-14) não implementada.

Efeito: o feixe de passo quadrado saía **7,5 %** estreito (`√(2/√3) − 1`), e o erro
propagava para `D_s`, `A_s`, `Re` do casco e os cinco fatores `J`. Medido para
`N = 200`, `p_t = 23,81 mm`: 353,6 mm (código) contra 380,0 mm (correto).

**Teste:** `@testset "Eq. 2-13 e 2-14 — a área de célula depende do layout"`, com a
guarda de regressão que fixa o default de 30° em `d_tri`.

**Correção.** `area_celula_sobre_pt2 = [√3/2, 1, √3/2, 1]` no TOML, indexado por layout
no mesmo padrão de `pn_sobre_pt`/`pp_sobre_pt`; resolvido em `sizing_constraints` e
guardado em `ExchangerConstraints.area_celula`, para que `_tubo` funcione também com
Bell-Delaware desligado (quando `kbd` está vazio). **O default de 30° não se moveu** —
verificado no formulário e no caso de exemplo.

### Defeito 5 — o casco recebia a folga de chicana no lugar da folga de feixe
**Classe: físico.**

`d_s = d_otl + baffle_clearance(...)`. Mas a Tabela 2-7 é, pelo próprio título,
*"Diametric shell-to-**baffle** clearance"*, e Branan a define como `d_sb = D_s − D_b`,
com `D_b` = diâmetro da **chicana**. Ela entra na área de vazamento `A_sb` (Eq. 2-24), e
o código a usa corretamente ali.

O que ela **não** é: a folga entre o feixe e o casco. Essa é a Eq. (2-17),
`D_s,min = 2√(A_corr/π) + 2·d_o`, ou seja `D_s − D_otl ≈ 2·d_o`.

| | valor | |
|---|---|---|
| `D_s − D_otl` usado hoje (Tab. 2-7) | 2,54–3,18 mm | |
| `D_s − D_otl` pela Eq. (2-17) | **38,1 mm** (`2 × 19,05`) | **12× maior** |

Consequências, medidas no caso default:

| grandeza | efeito |
|---|---|
| `A_s` (Eq. 2-19), 1º termo | subestimada em ~50 % do total |
| `A_bp` (Eq. 2-27) | subestimada 12× ⇒ `r_c` pequeno |
| `Jb` | **0,979** em vez de **0,825** — o desvio pelo vão feixe-casco fica quase todo ignorado |
| `h_o` | **superestimado em 23–28 %** |
| área e comprimento exigidos | subestimados na mesma proporção |

**O sentido do erro é não-conservador:** o trocador sai menor do que o método pediria.

Também não implementada: a Eq. (2-16), `A_corr = D_tight·d_o(n_p − 1) + N_t·Area_tubo`,
que abre a faixa da chapa divisória de passe no campo tubular. Com `n_p = 2` acrescenta
uma faixa; é refinamento de segunda ordem ao lado do item acima.

**Teste:** `@testset "Eq. 2-17 — o casco é o feixe mais dois diâmetros de tubo"`, cujo
sub-testset `"o vão maior derruba Jb"` fixa a queda de `Jb` para dentro da faixa 0,70–0,90
que Branan declara — era 0,979, fora dela por cima.

**Correção** (autorizada pelo usuário, por mudar todos os resultados de trocador):
`d_s = d_otl + 2·c.d_o`. A consulta à Tabela 2-7 passou a usar `d_s`, que é o DN pelo
qual ela é indexada, e não o feixe. `_tubo` devolve `d_shell` nos dois ramos (com e sem
Bell-Delaware); `derived` o expõe; `admissible` compara **ele** com `d_casco_max`, que é
a linha "Shell inside diameter" da Tabela 3.1 — fechando junto a lacuna 5. O cartão e o
memorial ganharam a linha do casco ao lado da do feixe: enquanto o programa reprova pelo
casco, mostrar só o feixe esconderia o número que decide.

**Efeito medido** (caso default do formulário):

| | antes | depois |
|---|---|---|
| `D_s − D_otl` | 2,54 mm | **38,10 mm** |
| `Jb` | 0,979 | **0,825** |
| `h_o` | 2 112 W/m²K | **1 383 W/m²K** (−34 %) |
| `U` | 828,5 W/m²K | **676,9 W/m²K** (−18 %) |
| tubos/passe escolhidos | 40 | **50** |
| área de troca | 27,58 m² | **33,76 m²** (+22 %) |

E no caso de exemplo (`exemplo_trocador.toml`): 60 → **75** tubos/passe, `L` 5,819 →
5,717 m. Os quatro outros métodos não se moveram.

### Defeitos de atribuição corrigidos (não movem número)
**Classe: de unidade.**

1. **O docstring de `f_correction_1_2` reproduzia o `R` invertido da Fig. 4.3.** O código
   sempre esteve certo (§4.3); a documentação copiara a anotação errada da fonte.
   Corrigido, com a demonstração e a rota independente registradas.
2. **O `note` de `h_casco` citava a Tabela 4.1 como ordem de grandeza de `h_o`.** As
   Tabelas 4.1 e 4.2 de Saari tabelam o **coeficiente global `U`**, não o de película.
   Como `1/U = 1/h_o + (parede + incrustação + lado do tubo)`, `h_o` é sempre **maior**
   que `U`, tipicamente 2–4×. Quem seguisse a nota poria um `U` no campo de `h_o` e
   inflaria a área. Corrigido; o `note` agora diz o que a diferença é.
3. **A divergência 5 (o `0,044` da Eq. 2-23) não estava documentada.** O código já usava
   `0,44` nos dois lugares — corretamente —, mas o TOML listava quatro divergências e não
   esta. Documentada, com o teste que a fixa no limite de vazamento nulo.
4. **O comentário do `limiar_diagonal` dizia que `Inf` desliga a variante**, quando o
   valor gravado é `0.0` e o código testa `limiar > 0`. Comportamento certo, comentário
   errado. *(pendente de correção — ver nota ao fim)*

---

## 6. Lacunas não fechadas e decisões pendentes

1. **Não há caso-ouro com o laço de `U` fechado.** Saari é texto de aula (Exemplo 4.1 é
   tubo duplo com `U` dado) e Branan não traz exemplo numérico de Bell-Delaware. O que
   existe está na §4, e é indireto: a cadeia do Exemplo 4.1, o cruzamento LMTD ↔ ε-NTU, a
   rota P-NTU independente para `F`, a regra de bolso de 0,60, a segunda fonte estrutural
   de Toledo-Velázquez, e as faixas de cada fator. **É a lacuna mais séria dos cinco
   métodos** — um exemplo de literatura com o laço fechado a fecharia.

2. **Piso de `F` — decidido: não enforçar.** O código aceita qualquer `F > 0`, recusando
   só o impossível (`F = NaN`, quando `P` passa de `P_max(R)`). A prática TEMA descarta
   `F < 0,75`, porque abaixo disso a curva `F(P)` fica quase vertical e um erro pequeno
   de temperatura move muito a área. **Nenhuma fonte em `References/` declara esse
   piso** — Saari não menciona nenhum. O critério desta fase é recusar fora de faixa
   *declarada pela fonte*, e inventar um limite seria o oposto disso. Fica registrado
   como limite de prática de engenharia não verificado, e `F` já aparece no cartão e no
   memorial para quem quiser julgá-lo.

4. **Nº de passes × diâmetro do casco não verificado.** Tabela 3.1: *"Usually no more
   than D_s,i in hundreds of mm — e.g. a 200 mm shell should have no more than two tube
   passes"*. Com `passes = 2` (o default) e um casco abaixo de 200 mm, a regra é violada
   sem aviso. É limite **de fonte**, e a verificação é uma comparação de uma linha —
   ficou de fora desta rodada apenas por não ter sido levantada a tempo de entrar com o
   defeito 5, que mexe no mesmo `D_s`. Candidata natural a uma rodada de fecho.

5. *(fechada com o defeito 5)* `d_casco_max` agora compara com `D_s`, não com o feixe.

6. **`µ/µ_parede = 1`** (Eq. 2-19). Fechar exigiria iterar a temperatura de parede dentro
   do laço de `L` que já existe. O expoente 0,14 torna o efeito pequeno — razão de
   viscosidade 2 move `h_o` em 10 % — e a hipótese é emitida no rastro. Declarada, não
   fechada.

7. **Rugosidade e `ΔT` de parede na Eq. (6.23).** A correlação supõe tubo liso e erra
   mais quando `T_b − T_s` passa de ~6 °C (líquidos). Nenhum dos dois é verificável com o
   que o método tem em mão.

---

## Resultado

| | antes | depois |
|---|---|---|
| Testes do método | 193 | **264** |
| Suíte completa | 1.943 | **2.014**, zero falhas |
| Equações conferidas contra a fonte | — | **34** (16 de Saari, 18 de Branan) |
| Divergências fonte↔código documentadas | 4 | **5** |
| Defeitos corrigidos | — | **3 físicos + 4 de atribuição** |
| Casos de exemplo ainda viáveis | 5 de 5 | **5 de 5** |
| Resultados de trocador | — | mudam (defeito 5); os outros quatro métodos, não |
