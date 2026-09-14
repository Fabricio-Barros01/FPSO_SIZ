# Passo 7 — Separador trifásico dinâmico (Song 2023)

**Módulo:** `dynamics` · **Não é um método de dimensionamento** (não devolve `SizingResult`).
**Fonte:** Song, S.; Liu, X.; Li, C.; Li, Z.; Zhang, S.; Wu, W.; Shi, B.; Kang, Q.; Wu, H.;
Gong, J. *Dynamic Simulator for Three-Phase Gravity Separators in Oil Production
Facilities.* **ACS Omega 2023, 8, 6078−6089**, doi 10.1021/acsomega.2c08267.
**Arquivos:** [song.jl](../../src/dynamics/song.jl),
[propriedades.jl](../../src/dynamics/propriedades.jl),
[song_method.jl](../../src/dynamics/song_method.jl),
[song.toml](../../config/dynamics/song.toml).

O artigo é PDF com as equações em **imagem** — não extraíveis por texto. As Eq. 1–16
foram transcritas do sprint (que as leu símbolo por símbolo) e conferidas contra a
verificação numérica de §3. Este documento registra o que fecha, o que é leitura
interpretativa e o que fica **provisório** para a validação seguinte.

---

## 1. As dezesseis equações

| bloco | Eq. | o que faz | onde |
|---|---|---|---|
| Níveis | 1–3 | `V_l`, `V_w` (acumulação) e `H(V)` por inversão da Eq. 3 | `niveis_e_pressao`, `nivel_volume` |
| Pressão | 4–5 | mols de gás e `P = z·R·T·n/V_g` | `niveis_e_pressao` |
| Válvulas | 6–8 | vazão ISA, α, coeficiente de expansão Y | `vazao_valvula` |
| Fase dispersa | 9–12 | densidade numérica σ, transporte upwind, `v_x` | `_transporte_k!`, `passo!` |
| Vel. terminal | 13–15 | três ramos (Stokes / intermediário / Newton) + `d₁`,`d₂` | `velocidade_terminal` |
| Malhas PI | 16 | forma incremental, saturação, anti-windup | `pi_incremental`, `passo!` |

`H(V(H)) = H` com resíduo **< 1e-9 m** sobre toda a faixa `0 < H < D` (teste em
`test/fisica.jl`). Determinismo bit a bit entre 1 e N threads: **igualdade exata** de
`φ`, `P` e níveis (verificado com 4 threads).

---

## 2. As três leituras interpretativas do artigo

1. **O `1` solto na Eq. 6** (p. 6080, após o radical do termo de gás) é símbolo espúrio,
   ignorado. O `2,73` deriva de `Kv/Cv` (`W = 27,34·Cv·√(ΔP[bar]·ρ)`, em kPa 2,734);
   registrado em `song.toml` como `isa_coeficiente`.
2. **`φ` (água no óleo)** não tem equação numerada. Inferida da Eq. 9:
   `φ = Σ_k σ_k·(π/6)·d_k³`, medida à esquerda (campo) e à direita (conferência).
3. **Vazão de gás**: 3,696 kmol/h e 0,1936 m³/h não fecham (0,1936 m³/h implicaria
   ρ_g ≈ 317 kg/m³). Default reconstruído **8,175 m³/h** (ρ_g de PR ≈ 7,51 kg/m³).

---

## 3. Leituras geométricas e a correção de sinal

- **`H_o := H_l`** (nível de líquido total à esquerda) e **`V_g`** = vaso inteiro menos o
  líquido com `H_l` estendido a `L_total`. Isoladas em `niveis_e_pressao`.
- **Ação reversa das três malhas** — a correção que fez §3.2 fechar. As três válvulas são
  de **saída**: abrir a de gás baixa a pressão, abrir a de nível baixa o nível (conferido
  numericamente). Com o erro `(setpoint − medido)` do texto e ganho positivo, o laço seria
  realimentação **positiva** e a pressão dispararia (medido: 2500 kPa, válvula de gás em
  0 %). A direção reversa `(medido − setpoint)` — o que a Figura 3 codifica — estabiliza.

---

## 4. Camada de propriedades — conferência

| propriedade | correlação | conferência (no teste) |
|---|---|---|
| `µ_óleo` | Beggs & Robinson (1975) | ρ=850 (API 35,0) → **7,98 cP** a 40 °C |
| `µ_água` | Vogel | **0,651 cP** a 40 °C |
| `µ_gás` | Lee-Gonzalez-Eakin (1966) | M=16,61 → **0,0121 cP** a 40 °C |
| `z` | Peng-Robinson (mistura clássica) | gás da Tabela 1: 0,90 < z < 1,0 (esperado 0,966–0,992) |

Override direto em todas; correlação fora de faixa vira `Carimbo` (nunca silêncio) — o
teste de degeneração confere que T = 200 °C carimba.

---

## 5. O que o caso-ouro cobra, e o que se mediu

Ordem A.10: **§3.1 fecha antes de §3.2 ser tentado.**

| | publicado (AAD contra campo) | medido aqui |
|---|---|---|
| §3.1 `φ` (água no óleo) | 17,45 % | **≈ 17,9 %** (`φ_esq`), com `φ_dir < φ_esq` |
| §3.2 pressão | acima de 1150 kPa, válvula de gás em 100 % | **1201 kPa, ab_gas = 1,0** |
| §3.2 níveis | AAD nível de água 0,0022, óleo 0,043 | Hw = 1,547, Ho = 1,6 (travam no setpoint) |

O achado central de §3.2 — *"even with the gas valve fully open, the separator pressure is
still higher than the setpoint... the flow capacity of the gas phase outlet valve is
insufficient"* — é **reproduzido**: a válvula de gás satura em 100 % e a pressão estabiliza
acima do alvo. Como o sprint manda, cobra-se a **ordem de grandeza**, não o AAD exato: com
17 % e 26 % publicados nessa saída, exigir mais precisão seria construir um teste que mente.

---

## 6. O que fica PROVISÓRIO (ajustar na validação com as figuras)

- **Distribuição de gotícula (Figura 4)**: imagem no PDF, não extraída. `song.toml` traz
  uma leitura monótona decrescente, marcada como provisória. Ajustar à figura.
- **`phi_agua_oleo_in`** (carga de água no óleo de entrada): fixa a **escala absoluta** de
  `φ`; default 0,25 escolhido para aproximar 17,45 %. Não é número do artigo.
- **`h_tampo` (h_i da Eq. 3)**: não publicado; default D/4 (tampo 2:1).
- **Reconciliação esquerda/direita do nível de óleo**: o artigo mede o óleo à direita do
  vertedouro (1 m), a implementação de poço único usa `H_l ≥ H_w` à esquerda. O default de
  `sp_oleo` (1,6 m) reflete a implementação, não o valor de campo. É o primeiro ponto a
  reconciliar se a validação com as figuras 5–8 pedir.

---

## 7. Tolerâncias e cobertura de teste

`test/fisica.jl` (E.4): `H(V(H))` < 1e-9 m; `σ ≥ 0`; `0 ≤ φ ≤ 1`; `φ_dir ≤ φ_esq` em
regime; CFL violado devolve `Inviabilidade` (nunca exceção); determinismo bit a bit
1 vs N threads; degenerações (vazão nula, ΔP negativo, correlação fora de faixa) sem
lançar; conservação de massa por passo (Eq. 1/2, acumulação exata) resíduo < 1e-12.
Suíte inteira: **3270/3270** com `-t 1` e `-t 4`; `app/smoke` **2912/2912**.
