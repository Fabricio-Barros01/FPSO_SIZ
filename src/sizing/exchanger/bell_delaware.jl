"""
Método de Bell-Delaware — o coeficiente de convecção do lado do **casco**, com as cinco
correções de geometria de chicana. Branan, *Rules of Thumb for Chemical Engineers*,
cap. 2, Eq. (2-18) a (2-29) e Tabelas 2-5, 2-6 e 2-7.

Vive separado de `shell_and_tube.jl` pelo mesmo motivo que `hydraulics.jl` vive separado
de `moran.jl` e `gas_capacity.jl` vive fora dos dois vasos: **é física de feixe, não de
método.** Qualquer trocador de casco-e-tubos que o programa venha a dimensionar usa
isto; o que é do método de Saari é a sequência de cálculo e o critério de escolha.

# Por que ele existe

Até aqui `h_casco` era um `ParameterSpec`: o usuário digitava um número. Não era
desleixo — Saari descreve Bell-Delaware (§6.4.3) e **não o fecha em fórmula**, e o
Algoritmo 4.1 dele manda mesmo arbitrar `U` no passo 3. O problema é o peso: `h_o` é a
maior das cinco resistências em série (1/500 = 2,0×10⁻³ contra 1,5×10⁻⁴ do lado do
tubo), então o número que mais decidia o tamanho do trocador era o único que ninguém
calculava. Branan fecha o método, e fecha com a mesma bibliografia que Saari cita.

# A forma

    h_o = h_ideal · Jc · Jl · Jb · Js · Jr                                  (2-18)

`h_ideal` é o banco de tubos ideal em escoamento cruzado puro; os cinco `J` descontam o
que a construção real tira dele:

| fator | o que desconta | faixa típica |
|---|---|---|
| `Jc` | escoamento longitudinal na janela da chicana | 0,53 – 1,15 |
| `Jl` | vazamento casco-chicana e tubo-chicana | 0,7 – 0,8 |
| `Jb` | desvio pelo espaço entre feixe e casco | 0,7 – 0,9 |
| `Js` | espaçamento maior de chicana nas pontas | 0,85 – 1,0 |
| `Jr` | gradiente adverso em regime laminar | 1,0 acima de Re 100 |

O produto dos cinco cai tipicamente em 0,5–0,7 — Branan registra que **0,60** "has long
been used as a rule of thumb" quando a geometria é desconhecida, e é contra esse número
que o resultado se confere (ver `test/golden_saari.jl`).

# Divergências encontradas ao reproduzir a fonte

As quatro estão escritas, com o argumento de cada uma, no `[constants.bell_delaware]` de
`config/equipment/exchanger/saari_lmtd.toml`. Em resumo: a Eq. 2-21 imprime `PR/d_o`
onde a forma dimensionalmente possível é `p_t/d_o`; a Tabela 2-5 perde um sinal de menos
na linha 90°/Re 0-10; a Eq. 2-26 perde um fator 2 no ângulo da janela (o que erraria a
área da janela em 6,8×); e a Eq. 2-24, que usa o **meio** ângulo, está certa como
impressa. As três primeiras são checáveis por dentro, e é assim que foram decididas —
não por comparação com outra fonte.

# Por que não a correlação de Toledo-Velázquez et al. (2014)

`References/Delaware_Method_Improvement_for_the_Shell_and_Tube.pdf` (*Engineering* 6,
193-201) trata do mesmo assunto e resolve um problema que **este projeto não tem**: o
Delaware original de 1963 apresenta os fatores de correção em forma de **gráfico**, e o
artigo ajusta equações a essas curvas para que um programa possa calculá-los. Branan já
publica as formas fechadas, então o buraco que o artigo tapa aqui já estava tapado.

E as formas dele são muito maiores: `Jc` é um polinômio de 4ª ordem com dois regimes de
coeficientes, `Jl` tem dezesseis constantes, `Jb` e `J*r` têm vinte e quatro cada — cerca
de setenta ao todo, contra as dez de Branan. Transcrever setenta constantes de um PDF
cujo texto extraído perde sinais acrescentaria risco, não o reduziria.

O que ele **vale**, e para o que é usado em `test/golden_saari.jl`: é uma **segunda
fonte independente para a estrutura**. Ele publica

    h_cc = Ji·Cp·(W/S_m)·(k/(Cp·µ))^(2/3)·(µ/µ_w)^0,14 · Jc·Jl·Jb·Jr·Js

— os mesmos cinco fatores, o mesmo expoente 2/3 no Prandtl, o mesmo 0,14 na razão de
viscosidades, e as mesmas variáveis de comando (`Fc` para `Jc`; a fração de área de
recirculação e `Nss/Nc` para `Jb`; `Re < 100` para `Jr`). Duas fontes que chegaram à
mesma forma por caminhos diferentes é a verificação mais forte que este box tem, já que
nenhuma das duas traz um exemplo numérico fechado.

Ele também registra o erro dos próprios ajustes contra as curvas originais — 4 % em
`Ji`, 5 % em `Jc`, 2 % em `Jl` —, que é a ordem de grandeza da incerteza do método
inteiro e serve de referência para quem for ler o resultado.
"""

# ---------------------------------------------------------------------------
# Geometria do feixe e da chicana
# ---------------------------------------------------------------------------

"""
    ShellGeometry

O que Bell-Delaware precisa saber da construção, e que o balanço térmico não sabe.

Todos os comprimentos em **metros**. `d_sb` (folga casco-chicana) e `p_n`/`p_p` não são
pedidos ao usuário: saem de `D_s` pela Tabela 2-7 e de `p_t` pela Tabela 2-6. Pedi-los
abriria a porta para uma geometria que se contradiz — quatro números descrevendo dois
graus de liberdade, que é a mesma razão pela qual a temperatura de saída do casco não é
campo de formulário.
"""
struct ShellGeometry
    d_s::Float64        # diâmetro interno do casco, m
    d_otl::Float64      # diâmetro do limite externo do feixe, m
    d_o::Float64        # diâmetro externo do tubo, m
    p_t::Float64        # passo do feixe, m
    p_n::Float64        # passo normal ao escoamento, m
    p_p::Float64        # passo paralelo ao escoamento, m
    l_c::Float64        # corte da chicana (altura da janela), m
    l_bc::Float64       # espaçamento central de chicana, m
    d_sb::Float64       # folga diametral casco-chicana, m
    d_tb::Float64       # folga furo-tubo na chicana, m
    n_t::Float64        # número total de tubos
    n_ss::Float64       # pares de faixas de vedação
    n_dp::Float64       # faixas divisoras de passe paralelas ao escoamento
    w_p::Float64        # largura da faixa divisora, m
    layout::Int         # 30, 45, 60 ou 90
end

"""
    baffle_clearance(d_s_mm, k) -> mm

Folga diametral casco-chicana da Tabela 2-7 (TEMA classe R), interpolada por faixa de DN.

É tabela e não fórmula porque é tolerância de fabricação: 2,54 mm até DN 325, subindo em
degraus até 7,62 mm acima de DN 1375. Branan registra que ela "strongly influences the
calculation of Jl" — e é por isso que ela sai do diâmetro em vez de ser um default solto.
"""
function baffle_clearance(d_s_mm::Real, k::AbstractDict)
    tetos  = Float64.(k[:folga_dn_max])
    folgas = Float64.(k[:folga_chicana])
    i = findfirst(t -> d_s_mm <= t, tetos)
    return folgas[i === nothing ? length(folgas) : i]
end

"""
    layout_pitches(layout, p_t, k) -> (p_n, p_p, limiar_diagonal)

Tabela 2-6: os dois passos que o escoamento vê, em múltiplos do passo do feixe.

    30°  p_n = p_t        p_p = (√3/2)·p_t
    45°  p_n = √2·p_t     p_p = p_t/√2
    60°  p_n = √3·p_t     p_p = p_t/2
    90°  p_n = p_t        p_p = p_t
"""
function layout_pitches(layout::Integer, p_t::Real, k::AbstractDict)
    lays = Int.(k[:layouts])
    i = findfirst(==(Int(layout)), lays)
    i === nothing && return (float(p_t), float(p_t), 0.0)
    return (float(k[:pn_sobre_pt][i]) * p_t,
            float(k[:pp_sobre_pt][i]) * p_t,
            float(k[:limiar_diagonal][i]))
end

"""
    crossflow_area(g, k) -> A_s [m²]

Eq. (2-19): a área livre de escoamento cruzado na linha de centro do casco, entre duas
chicanas.

    A_s = L_bc · [ (D_s − D_otl) + (D_otl − d_o)·(p_ref − d_o)/p_n ]

`p_ref` é `p_n` no caso geral e `p_t` quando o passo é apertado o bastante para que a
folga da **diagonal** passe a ser a garganta — 45° com `p_t/d_o < 1,707` (= 1 + 1/√2) e
60° com `p_t/d_o < 3,732` (= 2 + √3). São os dois limiares que Branan tabela, e são
exatamente onde a geometria troca de garganta.
"""
function crossflow_area(g::ShellGeometry, k::AbstractDict)
    (g.p_n > 0 && g.l_bc > 0) || return NaN
    limiar = layout_pitches(g.layout, g.p_t, k)[3]
    p_ref  = (limiar > 0 && g.p_t / g.d_o < limiar) ? g.p_t : g.p_n
    return g.l_bc * ((g.d_s - g.d_otl) + (g.d_otl - g.d_o) * (p_ref - g.d_o) / g.p_n)
end

"""
    shell_reynolds(d_o, w_s, mu_s, a_s) -> Re

Eq. (2-20): `Re = d_o·W_s/(µ_s·A_s)`, com o **diâmetro externo do tubo** como
comprimento característico e a velocidade mássica `W_s/A_s` na garganta.

Não é o `reynolds_pipe` de `hydraulics.jl` nem o `reynolds` de gotícula de `drag.jl`:
são três comprimentos característicos diferentes, e unificá-los daria uma função com
três significados. Ver a nota em `reynolds_pipe`.
"""
shell_reynolds(d_o::Real, w_s::Real, mu_s::Real, a_s::Real) =
    (a_s > 0 && mu_s > 0) ? d_o * w_s / (mu_s * a_s) : NaN

"""
    colburn_ideal(re_s, layout, p_t, d_o, k) -> j

Eq. (2-21) com a Tabela 2-5:

    j = a₁ · (1,33/(p_t/d_o))^a · Re^a₂,        a = a₃/(1 + 0,14·Re^a₄)

Os coeficientes dependem do layout e da faixa de Reynolds. Sobre o `p_t/d_o` no lugar do
`PR/d_o` impresso, e sobre o sinal de `a₂` na linha 90°/Re 0-10, ver as divergências 1 e
2 no TOML.
"""
function colburn_ideal(re_s::Real, layout::Integer, p_t::Real, d_o::Real,
                       k::AbstractDict)
    (isfinite(re_s) && re_s > 0 && d_o > 0) || return NaN

    lays = Int.(k[:layouts])
    il = findfirst(==(Int(layout)), lays)
    il === nothing && return NaN

    tetos = Float64.(k[:re_max])
    ir = findfirst(t -> re_s <= t, tetos)
    ir === nothing && (ir = length(tetos))

    a1 = float(k[Symbol("a1_", layout)][ir])
    a2 = float(k[Symbol("a2_", layout)][ir])
    a3 = float(k[:a3][il])
    a4 = float(k[:a4][il])

    a = a3 / (1 + 0.14 * re_s^a4)
    return a1 * (1.33 / (p_t / d_o))^a * re_s^a2
end

"""
    h_ideal(j, cp_s, w_s, a_s, k_s, mu_s; mu_ratio) -> W/m²K

Eq. (2-19): o coeficiente do banco de tubos ideal, na forma de Colburn.

    h_ideal = j · c_ps · (W_s/A_s) · (k_s/(c_ps·µ_s))^(2/3) · (µ_s/µ_s,w)^0,14

**`mu_ratio = 1` é hipótese declarada.** O fator `(µ/µ_w)^0,14` corrige o perfil de
velocidade junto à parede, e exige a temperatura da parede — que só se conhece depois de
`U`, que depende deste `h_o`. Fechar esse segundo laço exigiria iterar a temperatura de
parede dentro do laço de `L` que já existe, e o expoente 0,14 torna o efeito pequeno:
uma razão de viscosidade de 2 move `h_o` em 10 %. Fica declarado no rastro de cálculo em
vez de escondido — é a mesma regra do `dm_water` do tratador.
"""
function h_ideal(j::Real, cp_s::Real, w_s::Real, a_s::Real, k_s::Real, mu_s::Real;
                 mu_ratio::Real = 1.0)
    (isfinite(j) && j > 0 && a_s > 0 && cp_s > 0 && k_s > 0 && mu_s > 0) || return NaN
    pr_term = (k_s / (cp_s * mu_s))^(2 / 3)
    return j * cp_s * (w_s / a_s) * pr_term * mu_ratio^0.14
end

# ---------------------------------------------------------------------------
# Os cinco fatores de correção
# ---------------------------------------------------------------------------

"""
    j_baffle_cut(g, k) -> Jc

Eq. (2-22): `Jc = 0,55 + 0,72·Fc`, corte e espaçamento de chicana.

`Fc` é a fração dos tubos em escoamento cruzado:

    Fc = (1/π)·[ π + 2φ·sen(arccos φ) − 2·arccos φ ],   φ = (D_s − 2·l_c)/D_otl

Vai de ~0,53 num corte grande a ~1,15 numa janela pequena de alta velocidade — mais de
2× entre os extremos, e é por isso que o corte de chicana é campo de formulário.
"""
function j_baffle_cut(g::ShellGeometry, k::AbstractDict)
    g.d_otl > 0 || return NaN
    phi = clamp((g.d_s - 2 * g.l_c) / g.d_otl, -1.0, 1.0)
    ac  = acos(phi)
    fc  = (π + 2 * phi * sin(ac) - 2 * ac) / π
    return float(k[:jc_a]) + float(k[:jc_b]) * fc
end

"""
    leakage_areas(g) -> (A_sb, A_tb, A_w)

Eq. (2-24) a (2-26): as três áreas que o vazamento usa.

    A_sb = ½·(π − θ₁)·D_s·d_sb                    casco → chicana
    A_tb = π·d_o·(1 − F_w)·N_t·d_tb/4             tubo  → furo da chicana
    A_w  = A_wg − A_wt                            área livre na janela

com `θ₁ = arccos(1 − 2·l_c/D_s)` — **meio** ângulo, e é assim que a Eq. 2-24 fecha com a
forma padrão `(2π − θ_janela)/4·D_s·d_sb` —, `A_wg = (D_s²/8)·(θ₂ − sen θ₂)` com
`θ₂ = 2·arccos(1 − 2·l_c/D_s)` — ângulo **inteiro**, e aqui o fator 2 que a Eq. 2-26
imprimida perde: sem ele a área da janela sai 6,8× menor que a do segmento circular que
ela é. Ver a divergência 3 no TOML e o teste que confere contra `_segment_area`.
"""
function leakage_areas(g::ShellGeometry)
    g.d_s > 0 || return (NaN, NaN, NaN)
    c = clamp(1 - 2 * g.l_c / g.d_s, -1.0, 1.0)

    t1 = acos(c)                       # meio ângulo — Eq. 2-24
    a_sb = 0.5 * (π - t1) * g.d_s * g.d_sb

    t2 = 2 * acos(c)                   # ângulo inteiro — área do segmento
    a_wg = g.d_s^2 / 8 * (t2 - sin(t2))

    # F_w = fração dos tubos numa janela; θ₃ mede o feixe, e não o casco.
    c1 = g.d_s - g.d_otl
    den = g.d_s - c1
    t3 = den > 0 ? 2 * acos(clamp((g.d_s - 2 * g.l_c) / den, -1.0, 1.0)) : 0.0
    f_w = (t3 - sin(t3)) / (2π)

    a_tb = π * g.d_o * (1 - f_w) * g.n_t * g.d_tb / 4
    a_wt = π / 4 * (f_w * g.n_t) * g.d_o^2
    return (a_sb, a_tb, a_wg - a_wt)
end

"""
    j_leakage(a_sb, a_tb, a_w, k) -> Jl

Eq. (2-23): `Jl = 0,44(1 − r_a) + [1 − 0,44(1 − r_a)]·exp(−2,2·r_b)`, com
`r_a = A_sb/(A_sb + A_tb)` e `r_b = (A_sb + A_tb)/A_w`.

É o fator que mais desconta — tipicamente 0,7 a 0,8 — e o que mais depende de tolerância
de fabricação. Chicana apertada demais aumenta a fração da vazão que vaza em vez de
cruzar o feixe, o que é o contrário do que a intuição sugere.
"""
function j_leakage(a_sb::Real, a_tb::Real, a_w::Real, k::AbstractDict)
    s = a_sb + a_tb
    (isfinite(s) && s > 0 && isfinite(a_w) && a_w > 0) || return NaN
    ra = a_sb / s
    rb = s / a_w
    base = float(k[:jl_a]) * (1 - ra)
    return base + (1 - base) * exp(-float(k[:jl_b]) * rb)
end

"""
    j_bypass(g, a_s, re_s, k) -> Jb

Eq. (2-27): `Jb = exp[−C·r_c·(1 − (2z)^(1/3))]` para `z < ½`, e `1` para `z ≥ ½`.

`r_c = A_bp/A_s` é a fração da seção que desvia pelo vão entre feixe e casco, com
`A_bp = L_bc·(D_s − D_otl + 0,5·n_dp·w_p)`; `z = n_ss/n_r,cc` é o número de pares de
faixas de vedação por fileira cruzada. `C` vale 1,35 em regime laminar (`Re ≤ 100`) e
1,25 acima.

Uma vedação a cada seis fileiras é a regra de bolso que Branan cita; a API 660 pede
dispositivo a cada 5-7 passos de tubo, o que dá `z ≈ 0,17`.
"""
function j_bypass(g::ShellGeometry, a_s::Real, re_s::Real, k::AbstractDict)
    (isfinite(a_s) && a_s > 0 && g.p_p > 0) || return NaN
    n_rcc = (g.d_s - 2 * g.l_c) / g.p_p
    n_rcc > 0 || return NaN
    z = g.n_ss / n_rcc
    z >= 0.5 && return 1.0
    a_bp = g.l_bc * (g.d_s - g.d_otl + 0.5 * g.n_dp * g.w_p)
    rc = a_bp / a_s
    c = re_s <= float(k[:jb_re_corte]) ? float(k[:jb_c_laminar]) :
                                         float(k[:jb_c_turbulento])
    return exp(-c * rc * (1 - cbrt(2z)))
end

"""
    j_spacing(n_b, l_bi, l_bo, l_bc, laminar, k) -> Js

Eq. (2-28): o espaçamento maior de chicana nas pontas, para acomodar os bocais, baixa a
velocidade local e com ela a troca.

    Js = [n_b − 1 + Li^(1−n) + Lo^(1−n)] / [n_b − 1 + Li + Lo],
    Li = L_bi/L_bc,  Lo = L_bo/L_bc,  n = 3/5 turbulento ou 1/3 laminar

Com as pontas iguais ao vão central (`Li = Lo = 1`) dá exatamente 1, que é o que a
álgebra tem de devolver quando não há ponta alargada — e é o que o teste fixa.
"""
function j_spacing(n_b::Real, l_bi::Real, l_bo::Real, l_bc::Real, laminar::Bool,
                   k::AbstractDict)
    (l_bc > 0 && n_b >= 1) || return 1.0
    li, lo = l_bi / l_bc, l_bo / l_bc
    n = laminar ? float(k[:js_n_laminar]) : float(k[:js_n_turbulento])
    den = n_b - 1 + li + lo
    den > 0 || return 1.0
    return (n_b - 1 + li^(1 - n) + lo^(1 - n)) / den
end

"""
    j_laminar(re_s, g, k) -> Jr

Eq. (2-29): o gradiente adverso de temperatura que se acumula em regime laminar.

`Jr = (10/n_r,cc)^0,18` até `Re 20`, `1` a partir de `Re 100`, e interpolação linear
entre os dois — que é o que Branan manda fazer, e não uma terceira correlação.
"""
function j_laminar(re_s::Real, g::ShellGeometry, k::AbstractDict)
    lo, hi = float(k[:jr_re_min]), float(k[:jr_re_max])
    (isfinite(re_s) && re_s > 0) || return NaN
    re_s >= hi && return 1.0
    g.p_p > 0 || return NaN
    n_rcc = (g.d_s - 2 * g.l_c) / g.p_p
    n_rcc > 0 || return NaN
    jr20 = min((10 / n_rcc)^float(k[:jr_expoente]), 1.0)
    re_s <= lo && return jr20
    return jr20 + (1 - jr20) * (re_s - lo) / (hi - lo)
end

# ---------------------------------------------------------------------------
# Eq. (2-18)
# ---------------------------------------------------------------------------

"""
    bell_delaware(g, w_s, cp_s, mu_s, k_s, n_b, l_bi, l_bo, k)
        -> (h_o, fatores::NamedTuple, ok::Bool)

Eq. (2-18): `h_o = h_ideal·Jc·Jl·Jb·Js·Jr`, em W/m²K.

`ok = false` traz `h_o = NaN` e diz que a geometria não fecha — não lança, que é o
contrato do projeto inteiro. `fatores` traz os cinco `J`, o produto, `h_ideal` e o
Reynolds do casco, para que o memorial mostre **de que** o coeficiente é feito em vez de
imprimir um número no fim de uma caixa-preta.
"""
function bell_delaware(g::ShellGeometry, w_s::Real, cp_s::Real, mu_s::Real, k_s::Real,
                       n_b::Real, l_bi::Real, l_bo::Real, k::AbstractDict)
    vazio = (; jc = NaN, jl = NaN, jb = NaN, js = NaN, jr = NaN,
             produto = NaN, h_ideal = NaN, re = NaN, a_s = NaN)

    a_s = crossflow_area(g, k)
    (isfinite(a_s) && a_s > 0) || return (NaN, vazio, false)

    re = shell_reynolds(g.d_o, w_s, mu_s, a_s)
    (isfinite(re) && re > 0) || return (NaN, vazio, false)

    j  = colburn_ideal(re, g.layout, g.p_t, g.d_o, k)
    hi = h_ideal(j, cp_s, w_s, a_s, k_s, mu_s)
    isfinite(hi) && hi > 0 || return (NaN, vazio, false)

    jc = j_baffle_cut(g, k)
    a_sb, a_tb, a_w = leakage_areas(g)
    jl = j_leakage(a_sb, a_tb, a_w, k)
    jb = j_bypass(g, a_s, re, k)
    js = j_spacing(n_b, l_bi, l_bo, g.l_bc, re <= float(k[:jb_re_corte]), k)
    jr = j_laminar(re, g, k)

    todos = (jc, jl, jb, js, jr)
    all(x -> isfinite(x) && x > 0, todos) ||
        return (NaN, (; jc, jl, jb, js, jr, produto = NaN, h_ideal = hi, re, a_s), false)

    produto = prod(todos)
    return (hi * produto, (; jc, jl, jb, js, jr, produto, h_ideal = hi, re, a_s), true)
end
