"""
Trocador casco-e-tubos: LMTD com fator de correção, coeficiente global das resistências
em série e o comprimento de tubo que fecha a área — Saari, *Heat Exchanger Dimensioning*
(Lappeenranta University of Technology).

## O que se varre, e por quê

O que um trocador tem no lugar do diâmetro de um vaso é o **número de tubos**. Fixado
`N`, a Algoritmo 4.1 de Saari fecha sozinha:

    q       = ṁ·cp·ΔT                              balanço (Eq. 4.5)
    ΔT_lm   = (ΔT₁ − ΔT₂)/ln(ΔT₁/ΔT₂)              contracorrente (Eq. 4.6/4.7)
    F       = f(P, R)                              arranjo 1-2 (Fig. 4.3)
    v(N)    = ṁ_t/(ρ·N·πd_i²/4)                    velocidade no tubo
    h_i(N)  = Nu·k/d_i,  Nu = a·Re^0,8·Pr^b        Dittus-Boelter (Eq. 6.23)
    U(N)    = [1/h_o + R"f,o + d_o ln(d_o/d_i)/2k_w + (d_o/d_i)(R"f,i + 1/h_i)]⁻¹
    A(N)    = q/(U·F·ΔT_lm)                        (Eq. 4.4/4.9)
    L(N)    = A/(N·π·d_o)                          comprimento de tubo

`L` é o que o motor envelopa: dois casos de operação pedem comprimentos diferentes com o
mesmo feixe, e o trocador tem de atender ao maior.

**A varredura não é um traçado de hipérbole.** `L = A/(N·πd_o)` sozinha daria
`L ∝ 1/N` e a escolha de `N` seria arbitrária. Ela não é, porque `U` depende de `N`:
mais tubos é menos velocidade por tubo, e menos velocidade é menos `h_i`, mais área. O
efeito líquido é que `A` **cresce** com `N`, e é isso que faz a varredura ter conteúdo —
e o que faz a banda de velocidade da Tabela 3.1 ser a restrição que decide.

## Onde a fonte para, e o que se pôs no lugar

1. **Coeficiente do lado do casco — fechado por outra fonte.** O escoamento cruzado
   sobre feixe com chicanas (§6.4.3) exige geometria de chicana, folgas e correções de
   vazamento: o método de Bell-Delaware, que Saari descreve e **não fecha** em fórmula.
   Enquanto foi assim, `h_o` era entrada do usuário — o que o passo 3 do Algoritmo 4.1
   de fato manda fazer, mas que punha o número de maior peso do cálculo (a maior das
   cinco resistências em série) fora do alcance de qualquer conferência.

   Quem fecha é **Branan**, cap. 2, Eq. 2-18 a 2-29 — e fecha com a bibliografia que o
   próprio Saari cita. `h_o` passou a ser calculado a partir do corte e do espaçamento
   de chicana, das folgas de fabricação e das faixas de vedação; ver
   `sizing/exchanger/bell_delaware.jl`. O campo `h_casco` continua existindo como
   caminho de saída, usado quando `bell_delaware.ativo = false`.

   **Isso muda a forma da varredura.** Com `h_o` constante, só o lado do tubo variava
   com `N`; agora o diâmetro do feixe muda com `N`, e com ele a área de escoamento
   cruzado, o Reynolds do casco e os cinco fatores. E introduz um **ponto fixo**: `Js`
   depende do número de chicanas, que depende do comprimento de tubo, que é o que a
   varredura devolve — resolvido dentro de [`_tubo`](@ref), ver
   [`_tubo_bell_delaware`](@ref).
2. **Sem exemplo numérico do trocador inteiro.** Saari é texto de aula e traz um exemplo
   resolvido — o Exemplo 4.1, de tubo duplo, com `U` **dado**. Ele não fecha o laço de
   `U`, então o caso-ouro deste método reproduz a **cadeia** que ele publica
   (`q → T_c,o → ΔT_lm → A → L → n`) chamando as mesmas funções que o método usa, e
   fecha o resto pelo cruzamento LMTD ↔ ε-NTU, que o §4.3 afirma ser exato. Ver
   `test/golden_saari.jl`.
3. **Dois erros de digitação no Exemplo 4.1**, encontrados ao reproduzi-lo — ver
   [`lmtd`](@ref) e o teste.

## O que é do casco, e o que é do tubo

Os dois lados se chamam **tubo** e **casco**, e não quente e frio. Quem é quente sai da
comparação das temperaturas de entrada, e por isso o mesmo formulário serve para
aquecer e para resfriar sem um campo de escolha que o usuário teria de manter coerente
com os números que digitou logo acima.
"""

struct ShellTubeExchanger <: AbstractEquipment end
method_id(::ShellTubeExchanger) = :exchanger
label(::ShellTubeExchanger) = "Trocador de Calor Casco-e-Tubos"

struct SaariLMTD <: AbstractSizingMethod end
method_id(::SaariLMTD) = :saari_lmtd
applies_to(::SaariLMTD) = ShellTubeExchanger()

const _SAARI_CONFIG = ("equipment", "exchanger", "saari_lmtd.toml")

method_config(::SaariLMTD) = load_config(_SAARI_CONFIG...)
label(::SaariLMTD) = config_label(method_config(SaariLMTD()), "Saari — LMTD com fator F")
parameters(::SaariLMTD) = parameter_specs(method_config(SaariLMTD()))

"""
Um trocador não tem corrente de óleo, água e gás: tem **dois** escoamentos, cada um com
vazão mássica, calor específico e temperaturas próprias.

`stream_keys` vazio significa que `config/stream.toml` não contribui com nenhum campo —
o formulário inteiro vem de `parameters(m)`. É o caso que [`stream_keys`](@ref) foi
escrita para admitir, e é a primeira vez que ele acontece.
"""
stream_keys(::SaariLMTD) = ()

"""
As duas correntes de um trocador, já em SI.

Existe porque [`case_input`](@ref) precisa devolver algo, e uma [`StreamState`](@ref)
aqui seria doze campos `NaN` com três que significam outra coisa. A estrutura própria é
o que o hook existe para permitir.
"""
struct ExchangerDuty
    m_tubo::Float64      # kg/s
    cp_tubo::Float64     # J/kg·K
    t_tubo_in::Float64   # °C
    t_tubo_out::Float64  # °C
    rho_tubo::Float64    # kg/m³
    mu_tubo::Float64     # Pa·s
    k_tubo::Float64      # W/m·K  (condutividade do fluido, para o Prandtl)
    m_casco::Float64
    cp_casco::Float64
    t_casco_in::Float64
    # As duas do lado do casco que só Bell-Delaware consome. Antes não eram pedidas
    # porque `h_casco` era digitado; agora ele é calculado, e sem viscosidade e
    # condutividade do fluido do casco não há Reynolds nem Prandtl daquele lado.
    mu_casco::Float64    # Pa·s
    k_casco::Float64     # W/m·K
end

"Chaves que [`case_input`](@ref) exige de um caso, na ordem em que o formulário as mostra."
const EXCHANGER_KEYS = (:m_tubo, :cp_tubo, :t_tubo_in, :t_tubo_out,
                        :rho_tubo, :mu_tubo, :k_tubo,
                        :m_casco, :cp_casco, :t_casco_in, :mu_casco, :k_casco)

function case_input(::SaariLMTD, vals::AbstractDict)
    faltando = [k for k in EXCHANGER_KEYS if !haskey(vals, k)]
    isempty(faltando) ||
        throw(ArgumentError("caso sem as entradas do trocador: " *
                            join(faltando, ", ")))
    v = k -> float(vals[k])
    return ExchangerDuty(v(:m_tubo), v(:cp_tubo), v(:t_tubo_in), v(:t_tubo_out),
                         v(:rho_tubo), Units.cp_to_pas(v(:mu_tubo)), v(:k_tubo),
                         v(:m_casco), v(:cp_casco), v(:t_casco_in),
                         Units.cp_to_pas(v(:mu_casco)), v(:k_casco))
end

# ---------------------------------------------------------------------------
# As equações de Saari
# ---------------------------------------------------------------------------

"""
    lmtd(dt1, dt2) -> ΔT_lm

Diferença média logarítmica, Eq. (4.6): `(ΔT₁ − ΔT₂)/ln(ΔT₁/ΔT₂)`.

`NaN` quando um dos dois é ≤ 0 — o que significa **cruzamento de temperatura**: a saída
de um fluido passou da entrada do outro, e nenhum trocador em contracorrente faz isso.
O Exemplo 4.1 de Saari usa exatamente esse sinal para concluir que o arranjo em
paralelo do enunciado é impossível (`ΔT₂ = −29,5 °C`).

O caso `ΔT₁ = ΔT₂` (capacidades térmicas iguais) é o limite `ΔT_lm = ΔT₁`, que §4.2.3
declara; a razão `1/ln(1)` seria `0/0` e é tratada aqui em vez de virar `NaN`.
"""
function lmtd(dt1::Real, dt2::Real)
    (isfinite(dt1) && isfinite(dt2) && dt1 > 0 && dt2 > 0) || return NaN
    r = dt1 / dt2
    isapprox(r, 1.0; atol = 1e-9) && return float(dt1)
    return (dt1 - dt2) / log(r)
end

"""
    f_correction_1_2(p, r) -> F

Fator de correção do arranjo 1 passe no casco / 2 passes nos tubos, Figura 4.3:

    F = √(1+R²)·ln[(1−RP)/(1−P)] / { (1−R)·ln[(2 − P(1+R−√(1+R²)))/(2 − P(1+R+√(1+R²)))] }

com

    P = (T₁ₒ − T₁ᵢ)/(T₂ᵢ − T₁ᵢ)     efetividade térmica do fluido 1
    R = (T₂ᵢ − T₂ₒ)/(T₁ₒ − T₁ᵢ)     = Ċ₁/Ċ₂ — o ΔT do OUTRO fluido sobre o próprio

O arranjo é *stream symmetric* — Saari o registra citando Shah & Sekulić —, então tanto
faz calcular com o fluido do tubo ou com o do casco, desde que os dois parâmetros venham
do mesmo.

# A Figura 4.3 imprime `R` invertido

A anotação sob a Figura 4.3 traz `R₁ = (T₁ᵢ − T₁ₒ)/(T₂ᵢ − T₂ₒ)`, ou seja `ΔT₁/ΔT₂`. Isso
contradiz a **Eq. (4.11) do próprio texto**, que define `R_h = Ċ_h/Ċ_c`, e a Eq. (4.12),
que a reescreve como `R_h = (T_c,o − T_c,i)/(T_h,i − T_h,o)` = `ΔT_c/ΔT_h` — o ΔT do
outro fluido sobre o próprio, que é também a convenção de Shah & Sekulić, a fonte que a
própria Figura 4.3 cita.

A forma implementada é a da Eq. (4.11)/(4.12). Conferida por rota independente: a relação
P-NTU do TEMA E 1-2 de Shah & Sekulić,

    P₁ = 2 / [1 + R₁ + √(1+R₁²)·coth(NTU₁·√(1+R₁²)/2)]

com `F = ln[(1−R₁P₁)/(1−P₁)] / [NTU₁(1−R₁)]`, reproduz esta função à precisão de máquina
(≤ 8×10⁻¹⁵) para `R` de 0,4 a 2,0 e `NTU` de 0,5 a 3,0 — e as duas rotas não compartilham
uma linha de código. Ver `test/golden_saari.jl` e `docs/validacao/02-*.md`, divergência 3.

`R = 1` é removível: numerador e denominador zeram juntos, e o limite é finito. Sem o
tratamento, o caso mais comum de todos (capacidades térmicas iguais) devolveria `NaN` —
que o desenho propagaria em silêncio, como o β do Sprint 5.

`NaN` fora do domínio **não** é falha: para cada `R` existe um `P` máximo que o arranjo
1-2 alcança com área infinita, `P_max = 2/(1 + R + √(1+R²))`. Pedir mais que isso é pedir
um trocador que não existe, e o `den_log ≤ 0` é o sinal — em `R = 2` o teto é 0,382, e
`P = 0,4` sai `NaN` por essa via.
"""
function f_correction_1_2(p::Real, r::Real)
    (isfinite(p) && isfinite(r)) || return NaN
    p <= 0 && return 1.0                       # sem troca: F não corrige nada
    (p >= 1 || r * p >= 1) && return NaN        # fora do domínio físico do arranjo
    s = sqrt(1 + r^2)
    den_log = (2 - p * (1 + r - s)) / (2 - p * (1 + r + s))
    (isfinite(den_log) && den_log > 0) || return NaN

    if isapprox(r, 1.0; atol = 1e-6)
        # Limite R → 1: ln[(1−RP)/(1−P)]/(1−R) → P/(1−P).
        return sqrt(2.0) * (p / (1 - p)) / log(den_log)
    end
    return s * log((1 - r * p) / (1 - p)) / ((1 - r) * log(den_log))
end

"""
    nusselt_dittus_boelter(re, pr, aquecendo, k) -> (Nu, valida)

Eq. (6.23): `Nu = 0,024·Re^0,8·Pr^0,4` aquecendo, `0,026·Re^0,8·Pr^0,3` resfriando.

Os coeficientes são os que **Saari publica** (p. 68), e não o `0,023 / Pr^0,4 ou 0,3` que
a maioria dos textos traz: o §6.3.1 distingue os dois casos com coeficientes distintos, e
o critério do projeto é seguir a fonte. A diferença sobre o `0,023` clássico é de 4 % em
`h_i`, bem dentro dos "-26…+7 % para água" que o próprio §6.3.1 declara como erro da
correlação.

`aquecendo` é do ponto de vista do fluido **do tubo**: `true` quando ele recebe calor.

# `valida` — a faixa que a fonte declara

Logo abaixo da Eq. (6.23): *"Equation (6.23) is valid within 10⁴ < Re < 1,2·10⁵ and
0,7 < Pr < 120"*, e o período seguinte não deixa dúvida sobre o que há fora: *"Below
Re = 10⁴ the results are much worse."*

`valida = false` **não** é erro de cálculo: `Nu` sai, e sai plausível. É o ponto — a
correlação devolve número em qualquer `Re`, e o número não avisa. Devolver o par é o
mesmo idioma de `colebrook_white`, `converge_drag` e `darcy_friction`, e é o que permite
a [`case_admissible`](@ref) recusar o feixe em vez de dimensionar por extrapolação.

As quatro fronteiras vêm do TOML porque são premissa revisável **declarada pela fonte**.
"""
function nusselt_dittus_boelter(re::Real, pr::Real, aquecendo::Bool, k::AbstractDict)
    (isfinite(re) && re > 0 && isfinite(pr) && pr > 0) || return (NaN, false)
    nu = aquecendo ?
        float(k[:dittus_boelter_heating]) * re^0.8 * pr^float(k[:dittus_boelter_pr_heating]) :
        float(k[:dittus_boelter_cooling]) * re^0.8 * pr^float(k[:dittus_boelter_pr_cooling])
    valida = float(k[:dittus_boelter_re_min]) <= re <= float(k[:dittus_boelter_re_max]) &&
             float(k[:dittus_boelter_pr_min]) <= pr <= float(k[:dittus_boelter_pr_max])
    return (nu, valida)
end

"""
    overall_u(h_i, h_o, rf_i, rf_o, d_i, d_o, k_w) -> U referido à área EXTERNA

Eq. (5.7a) escrita para tubo: as cinco resistências em série, todas trazidas à área
externa `A_o = π·d_o·L`, que é a maior das duas — §5.1 é explícito em que se use a maior.

    1/U_o = 1/h_o + R"f,o + d_o·ln(d_o/d_i)/(2k_w) + (d_o/d_i)·R"f,i + (d_o/d_i)/h_i

O termo de parede é a Eq. (5.4) `ln(d_o/d_i)/(2π k_w L)` multiplicada por `A_o`; os dois
termos do lado interno ganham `d_o/d_i` porque a área lá é menor, e é a razão de áreas
que os traz para a mesma referência. Errar essa razão é o modo silencioso de errar `U`
num trocador de tubo fino: o número continua plausível.
"""
function overall_u(h_i::Real, h_o::Real, rf_i::Real, rf_o::Real,
                   d_i::Real, d_o::Real, k_w::Real)
    (h_i > 0 && h_o > 0 && d_i > 0 && d_o > d_i && k_w > 0) || return NaN
    razao = d_o / d_i
    r_tot = 1 / h_o + rf_o + d_o * log(razao) / (2 * k_w) + razao * rf_i + razao / h_i
    return 1 / r_tot
end

"""
    effectiveness_ntu_counterflow(ntu, c_star) -> ε

Relação ε-NTU para contracorrente puro (§4.3.2), usada **só** para a conferência
cruzada do caso-ouro: §4.1 afirma que os dois métodos são "essentially equivalent, and
will yield the same results if correctly applied", e é a única verificação forte
disponível para este box, já que a fonte não traz o exemplo do trocador completo.

`C* = 1` é o limite removível `ε = NTU/(1+NTU)`.
"""
function effectiveness_ntu_counterflow(ntu::Real, c_star::Real)
    (isfinite(ntu) && ntu >= 0 && isfinite(c_star) && 0 <= c_star <= 1) || return NaN
    isapprox(c_star, 1.0; atol = 1e-9) && return ntu / (1 + ntu)
    e = exp(-ntu * (1 - c_star))
    return (1 - e) / (1 - c_star * e)
end

# ---------------------------------------------------------------------------
# Restrições
# ---------------------------------------------------------------------------

"O que não depende do número de tubos: o dever térmico, o ΔT corrigido e a geometria."
struct ExchangerConstraints
    q::Float64            # W
    dt_lm::Float64        # K
    f::Float64            # fator de correção do arranjo
    ua_exigido::Float64   # q/(F·ΔT_lm), em W/K — o produto U·A que fecha o balanço
    t_casco_out::Float64  # °C
    aquecendo::Bool       # o fluido do tubo recebe calor?
    m_tubo::Float64
    rho_tubo::Float64
    mu_tubo::Float64
    pr_tubo::Float64
    k_tubo::Float64
    d_i::Float64          # m
    d_o::Float64          # m
    passes::Int
    h_casco::Float64      # informado; usado quando Bell-Delaware está desligado
    rf_tubo::Float64
    rf_casco::Float64
    k_parede::Float64
    area_tubo::Float64    # m² por tubo, seção livre
    passo_m::Float64      # espaçamento entre centros de tubo, m
    # Área que cada tubo ocupa no campo tubular, em múltiplos de passo² — Eq. (2-13) para
    # os layouts triangulares (30°, 60°) e Eq. (2-14) para os quadrados (45°, 90°).
    # Resolvida aqui, e não em `_tubo`, porque `_tubo` roda também com Bell-Delaware
    # desligado, quando `kbd` está vazio: fixá-la na construção evita um `get` com valor
    # default espalhado pelo caminho quente.
    area_celula::Float64
    # --- lado do casco (Bell-Delaware) -------------------------------------
    m_casco::Float64      # kg/s
    cp_casco::Float64     # J/kg·K
    mu_casco::Float64     # Pa·s
    k_casco::Float64      # W/m·K
    layout::Int           # 30 | 45 | 60 | 90
    corte_chicana::Float64    # lc/Ds
    espac_chicana::Float64    # Lbc/Ds
    pares_veda::Float64
    folga_furo_m::Float64     # dtb, m
    faixas_divisoras::Float64
    bd_ativo::Bool
    kbd::Dict{Symbol,Any}     # o bloco [constants.bell_delaware]
    k::Dict{Symbol,Any}
end

"""
    sizing_constraints(m::SaariLMTD, e::ExchangerDuty, p, k)

Balanço, ΔT_lm, fator F e a geometria do tubo. Nada aqui depende de `N`.

A temperatura de saída do casco **não** é pedida ao usuário: ela sai do balanço, e
pedi-la abriria a porta para um caso em que as quatro temperaturas e as duas vazões não
fecham entre si — quatro números descrevendo três graus de liberdade, que é a receita
para um resultado errado sem nenhum sinal.
"""
function sizing_constraints(m::SaariLMTD, e::ExchangerDuty,
                            p::AbstractDict, k::AbstractDict)
    tr = CalcTrace()

    c_tubo  = e.m_tubo * e.cp_tubo
    c_casco = e.m_casco * e.cp_casco
    (isfinite(c_tubo) && c_tubo > 0) || return (false,
        "Capacidade térmica do lado tubo inválida: confira vazão mássica e cp.", tr)
    (isfinite(c_casco) && c_casco > 0) || return (false,
        "Capacidade térmica do lado casco inválida: confira vazão mássica e cp.", tr)

    q = c_tubo * (e.t_tubo_out - e.t_tubo_in)      # >0 se o tubo aquece
    aquecendo = q > 0
    abs(q) > 0 || return (false,
        "As temperaturas de entrada e saída do lado tubo são iguais: não há calor a " *
        "trocar, e não há trocador a dimensionar.", tr)

    t_casco_out = e.t_casco_in - q / c_casco
    trace!(tr, :balanco, "Eq. 4.5", "q", "ṁ·cp·(T_saída − T_entrada) no tubo", q, "W")
    trace!(tr, :balanco, "Eq. 4.5", "T_casco,saída", "T_casco,ent − q/(ṁ·cp)_casco",
           t_casco_out, "°C")

    # A entrada mais quente tem de ser a do lado que cede calor; se não for, o caso
    # pede transferir calor do frio para o quente, e o sinal do ΔT já denuncia.
    quente_in, quente_out, frio_in, frio_out = aquecendo ?
        (e.t_casco_in, t_casco_out, e.t_tubo_in, e.t_tubo_out) :
        (e.t_tubo_in, e.t_tubo_out, e.t_casco_in, t_casco_out)

    dt1 = quente_in - frio_out
    dt2 = quente_out - frio_in
    dtlm = lmtd(dt1, dt2)
    trace!(tr, :balanco, "Eq. 4.7", "ΔT₁", "T_quente,ent − T_frio,saída", dt1, "K")
    trace!(tr, :balanco, "Eq. 4.7", "ΔT₂", "T_quente,saída − T_frio,ent", dt2, "K")

    isfinite(dtlm) || return (false,
        "Cruzamento de temperatura: com estas vazões e capacidades térmicas, um fluido " *
        "ultrapassaria a temperatura de entrada do outro (ΔT₁ = " *
        "$(round(dt1, digits = 1)) K, ΔT₂ = $(round(dt2, digits = 1)) K). Nenhum " *
        "trocador em contracorrente faz isso — reveja vazões, cp ou temperaturas.", tr)
    trace!(tr, :balanco, "Eq. 4.6", "ΔT_lm", "(ΔT₁ − ΔT₂)/ln(ΔT₁/ΔT₂)", dtlm, "K")

    # ------------------------------------------------------------ fator F
    passes = clamp(round(Int, p[:passes_tubo]), 1, 2)
    fator = 1.0
    if passes == 2
        p_ef = (e.t_tubo_out - e.t_tubo_in) / (e.t_casco_in - e.t_tubo_in)
        r_ef = (e.t_casco_in - t_casco_out) / (e.t_tubo_out - e.t_tubo_in)
        fator = f_correction_1_2(abs(p_ef), abs(r_ef))
        trace!(tr, :balanco, "Fig. 4.3", "P", "ΔT do tubo / (T_casco,ent − T_tubo,ent)",
               abs(p_ef), "–")
        trace!(tr, :balanco, "Fig. 4.3", "R", "ΔT do casco / ΔT do tubo", abs(r_ef), "–")
        isfinite(fator) && fator > 0 || return (false,
            "O arranjo 1-2 não fecha com estas temperaturas: o fator de correção F " *
            "sai do domínio da Fig. 4.3. Em contracorrente puro (1 passe) o caso é " *
            "viável — o cruzamento interno de um segundo passe é que não é.", tr)
    end
    trace!(tr, :balanco, passes == 2 ? "Fig. 4.3" : "§4.2.1", "F",
           passes == 2 ? "correção do arranjo 1-2" : "contracorrente puro: F = 1",
           fator, "–")

    ua = abs(q) / (fator * dtlm)
    trace!(tr, :balanco, "Eq. 4.9", "U·A", "q/(F·ΔT_lm)", ua, "W/K")

    # ------------------------------------------------------------ geometria
    d_o = Units.mm_to_m(p[:d_externo])
    d_i = d_o - 2 * Units.mm_to_m(p[:espessura])
    d_i > 0 || return (false,
        "A espessura de parede ($(p[:espessura]) mm) consome o diâmetro externo " *
        "($(p[:d_externo]) mm): não sobra seção livre no tubo.", tr)

    pr = e.cp_tubo * e.mu_tubo / e.k_tubo
    (isfinite(pr) && pr > 0) || return (false,
        "Prandtl do fluido do tubo inválido: confira cp, viscosidade e " *
        "condutividade térmica.", tr)
    trace!(tr, :tubo, "§6.1.1", "Pr", "cp·µ/k", pr, "–")
    trace!(tr, :tubo, "§3.2.2", "d_i", "d_o − 2·espessura", Units.m_to_mm(d_i), "mm")

    # ------------------------------------------------ lado do casco (Bell-Delaware)
    kbd = Dict{Symbol,Any}(get(k, :bell_delaware, Dict{Symbol,Any}()))
    bd_ativo = !isempty(kbd) && Bool(get(kbd, :ativo, false))

    if bd_ativo
        (isfinite(e.mu_casco) && e.mu_casco > 0) || return (false,
            "Viscosidade do fluido do casco inválida: sem ela não há Reynolds do " *
            "casco, e o coeficiente h_o não pode ser calculado.", tr)
        (isfinite(e.k_casco) && e.k_casco > 0) || return (false,
            "Condutividade do fluido do casco inválida: sem ela não há Prandtl do " *
            "casco, e o coeficiente h_o não pode ser calculado.", tr)
        pr_c = e.cp_casco * e.mu_casco / e.k_casco
        trace!(tr, :casco, "§6.1.1", "Pr (casco)", "cp·µ/k", pr_c, "–")
        trace!(tr, :casco, "Br. 2-18", "hipótese",
               "(µ/µ_parede)^0,14 = 1 — T de parede não iterada", 1.0, "–")
    end

    layout = let l = round(Int, p[:layout_tubos])
        # Só os quatro da Tabela 2-6 existem; qualquer outro cai no mais comum.
        l in (30, 45, 60, 90) ? l : 30
    end

    # Eq. (2-13)/(2-14): triangular ocupa (√3/2)·passo² por tubo, quadrado ocupa passo².
    # A Tabela 2-6 é quem diz qual é qual — 30° e 60° são triangulares, 45° e 90° são
    # quadrados. O default de `√3/2` cobre o caminho com Bell-Delaware desligado, em que
    # o bloco de constantes pode nem existir.
    area_celula = let lays = Int.(get(kbd, :layouts, [30, 45, 60, 90])),
                      raz = Float64.(get(kbd, :area_celula_sobre_pt2,
                                         [sqrt(3)/2, 1.0, sqrt(3)/2, 1.0])),
                      i = findfirst(==(layout), lays)
        i === nothing ? sqrt(3)/2 : raz[i]
    end

    cons = ExchangerConstraints(
        abs(q), dtlm, fator, ua, t_casco_out, aquecendo,
        e.m_tubo, e.rho_tubo, e.mu_tubo, pr, e.k_tubo, d_i, d_o, passes,
        p[:h_casco], p[:rf_tubo], p[:rf_casco], p[:k_parede],
        π * d_i^2 / 4, p[:razao_passo] * d_o, area_celula,
        e.m_casco, e.cp_casco, e.mu_casco, e.k_casco, layout,
        p[:corte_chicana], p[:espacamento_chicana], p[:pares_veda],
        Units.mm_to_m(p[:folga_furo_chicana]), p[:faixas_divisoras],
        bd_ativo, kbd, Dict{Symbol,Any}(k))
    return (true, cons, tr)
end

"""
    _tubo(c, n) -> NamedTuple

Tudo o que depende do número de tubos: velocidade, Reynolds, `h_i`, `U`, a área exigida
e o comprimento de tubo que a entrega. Uma função só, pelo mesmo motivo de
`_hidraulica` na bomba — as quatro travessias do contrato pedem as mesmas grandezas no
mesmo ponto.

**`n` é o número de tubos por passe**, e não o total. É a contagem que fixa a
velocidade, que é o que a Tabela 3.1 restringe; num arranjo de 2 passes o total é `2n`,
e é o total que preenche a área e o casco.
"""
function _tubo(c::ExchangerConstraints, n::Real)
    vazio = (; v = Inf, re = NaN, h_i = NaN, h_o = NaN, u = NaN, area = Inf, l = Inf,
             n_total = 0.0, d_casco = Inf, d_shell = Inf, re_casco = NaN, jc = NaN,
             jl = NaN, jb = NaN, js = NaN, jr = NaN, j_produto = NaN, h_ideal = NaN,
             n_chicanas = NaN, nu_valido = false, ok = false)
    n >= 1 || return vazio
    n_total = n * c.passes

    v  = c.m_tubo / (c.rho_tubo * n * c.area_tubo)
    re = reynolds_pipe(c.rho_tubo, v, c.d_i, c.mu_tubo)
    nu, nu_valido = nusselt_dittus_boelter(re, c.pr_tubo, c.aquecendo, c.k)
    h_i = nu * c.k_tubo / c.d_i

    # Campo tubular: cada tubo ocupa `area_celula·passo²`, com `area_celula` = √3/2 nos
    # layouts triangulares (30°, 60°) e 1 nos quadrados (45°, 90°). É geometria de
    # empacotamento, e Branan a publica nas duas formas — Eq. (2-13) e (2-14) —, com a
    # Tabela 2-6 dizendo qual layout é qual. O fator vem resolvido de
    # `sizing_constraints`; usar o triangular nos quatro subestimava o feixe quadrado em
    # 7,5 %, e o erro atravessava D_s, A_s, Re do casco e os cinco fatores J.
    d_feixe = sqrt(4 * n_total * c.area_celula * c.passo_m^2 / π)

    if !c.bd_ativo
        u = overall_u(h_i, c.h_casco, c.rf_tubo, c.rf_casco, c.d_i, c.d_o, c.k_parede)
        area = c.ua_exigido / u
        l = area / (n_total * π * c.d_o)
        # Mesmo sem Bell-Delaware o casco existe e é ele que `admissible` limita: a
        # Eq. (2-17) é geometria de montagem, não parte do método de coeficiente.
        return (; v, re, h_i, h_o = c.h_casco, u, area, l,
                n_total = float(n_total), d_casco = d_feixe,
                d_shell = d_feixe + 2 * c.d_o, re_casco = NaN,
                jc = NaN, jl = NaN, jb = NaN, js = NaN, jr = NaN, j_produto = NaN,
                h_ideal = NaN, n_chicanas = NaN, nu_valido,
                ok = isfinite(u) && u > 0)
    end

    return _tubo_bell_delaware(c, n, n_total, v, re, h_i, d_feixe, nu_valido, vazio)
end

"""
    _tubo_bell_delaware(c, n, n_total, v, re, h_i, d_feixe, vazio) -> NamedTuple

O ramo com o coeficiente do casco calculado — e o **ponto fixo em `L`** que ele obriga.

`Js` (Eq. 2-28) depende do número de chicanas, o número de chicanas depende do
comprimento de tubo, e o comprimento de tubo é justamente o que este cálculo devolve:

    L₀  ←  com Js = 1
    repetir:  n_b(L) → Js → h_o → U → A = (U·A)/U → L = A/(N·π·d_o)
    até |ΔL| < tol

Converge em poucas passagens porque `Js ∈ [0,85 , 1]` — o laço mexe em `L` por menos de
15 % na primeira volta e por muito menos depois. Devolve `ok`, e não um número solto:
um `L` que não convergiu é indistinguível de um que convergiu se só o número atravessar,
que é a mesma regra de `colebrook_white` e `converge_drag`.

O laço mora **aqui dentro** de propósito. `_tubo` é a única função que o contrato de
`engine/contract.jl` consulta — `requirement`, `derived`, `admissible` e
`case_admissible` passam todas por ela —, então os quatro veem o mesmo `L` por
construção. Espalhá-lo seria abrir a porta para a varredura e o cartão discordarem.
"""
function _tubo_bell_delaware(c::ExchangerConstraints, n::Real, n_total::Real,
                             v::Real, re::Real, h_i::Real, d_feixe::Real,
                             nu_valido::Bool, vazio)
    kbd = c.kbd
    tol   = float(get(kbd, :tolerancia, 1e-9))
    maxit = Int(get(kbd, :max_iter, 60))

    # O casco envolve o feixe, e a folga entre os dois é a Eq. (2-17):
    #
    #     D_s,min = 2·√(A_corrigida/π) + 2·d_o
    #
    # O primeiro termo é o diâmetro do círculo que o feixe ocupa, isto é `D_otl` — logo
    # `D_s = D_otl + 2·d_o`.
    #
    # NÃO é a folga da Tabela 2-7. Aquela é, pelo título da própria tabela, "Diametric
    # shell-to-BAFFLE clearance", e Branan a define como `d_sb = D_s − D_b`, com `D_b` o
    # diâmetro da chicana: é tolerância de fabricação, de 2,5 a 7,6 mm, e o seu lugar é a
    # área de vazamento `A_sb` da Eq. (2-24) — onde ela continua entrando, logo abaixo.
    #
    # Usar `d_sb` como vão feixe-casco subestimava `D_s − D_otl` em 12× (3,2 mm contra
    # 38,1 mm), o que subestimava a área de desvio `A_bp` na mesma proporção e levava
    # `Jb` a 0,98 quando o valor é ~0,83 — ou seja, concluía que quase nada desviava pelo
    # vão. O erro era NÃO CONSERVADOR: inflava `h_o` em 23-28 % e encolhia o trocador.
    # Ver docs/validacao/02-trocador-saari-bell-delaware.md, defeito 5.
    d_otl = d_feixe
    d_s = d_otl + 2 * c.d_o

    # A Tabela 2-7 é indexada pelo DN do CASCO, então a consulta usa `d_s` — e não o
    # feixe, como fazia quando os dois eram quase o mesmo número.
    folga_mm = baffle_clearance(Units.m_to_mm(d_s), kbd)

    p_n, p_p, _ = layout_pitches(c.layout, c.passo_m, kbd)
    l_bc = c.espac_chicana * d_s
    geo = ShellGeometry(d_s, d_otl, c.d_o, c.passo_m, p_n, p_p,
                        c.corte_chicana * d_s, l_bc,
                        Units.mm_to_m(folga_mm), c.folga_furo_m,
                        float(n_total), c.pares_veda, c.faixas_divisoras,
                        2 * c.d_o, c.layout)

    l = NaN; u = NaN; area = NaN; h_o = NaN; fat = nothing; n_b = 1.0; ok = false
    for it in 1:maxit
        # Na primeira volta não há L ainda: Js = 1 é o valor que a própria Eq. 2-28 dá
        # quando as pontas igualam o vão central, então partir dele não é um chute.
        n_b = isfinite(l) && l > 0 && l_bc > 0 ? max(l / l_bc - 1, 1.0) : 1.0
        h_o, fat, bd_ok = bell_delaware(geo, c.m_casco, c.cp_casco, c.mu_casco,
                                        c.k_casco, n_b, l_bc, l_bc, kbd)
        bd_ok || return merge(vazio, (; v, re, h_i, n_total = float(n_total),
                                      d_casco = d_feixe, d_shell = d_s,
                                      re_casco = fat.re,
                                      h_ideal = fat.h_ideal, nu_valido))

        u = overall_u(h_i, h_o, c.rf_tubo, c.rf_casco, c.d_i, c.d_o, c.k_parede)
        (isfinite(u) && u > 0) || return merge(vazio, (; v, re, h_i, h_o,
                                              n_total = float(n_total),
                                              d_casco = d_feixe, d_shell = d_s,
                                              nu_valido))
        area = c.ua_exigido / u
        novo = area / (n_total * π * c.d_o)
        if isfinite(l) && abs(novo - l) <= tol * max(1.0, abs(novo))
            l = novo; ok = true; break
        end
        l = novo
        it == maxit && (ok = false)
    end

    return (; v, re, h_i, h_o, u, area, l, n_total = float(n_total),
            d_casco = d_feixe, d_shell = d_s,
            re_casco = fat.re, jc = fat.jc, jl = fat.jl,
            jb = fat.jb, js = fat.js, jr = fat.jr, j_produto = fat.produto,
            h_ideal = fat.h_ideal, n_chicanas = n_b, nu_valido, ok)
end

# ---------------------------------------------------------------------------
# O contrato de engine/contract.jl
# ---------------------------------------------------------------------------

sweep_axis(::SaariLMTD, p::AbstractDict) =
    SweepAxis(:n_tubos, "tubos por passe", "–",
              collect(p[:n_min]:p[:n_step]:p[:n_max]))

global_keys(::SaariLMTD) =
    [:n_min, :n_max, :n_step, :v_min, :v_max, :d_casco_max, :l_tubo_max]

requirement(::SaariLMTD, n::Real, c::ExchangerConstraints) = _tubo(c, n).l

# Um trocador tem uma restrição térmica só; o símbolo existe porque o motor carimba um,
# e nomear ":termica" é mais honesto que reaproveitar ":liquido" de um vaso.
governing_of(::SaariLMTD, n::Real, c::ExchangerConstraints) = :termica

function derived(m::SaariLMTD, n::Real, l::Real, gov::Symbol,
                 c::ExchangerConstraints, k::AbstractDict, p::AbstractDict)
    t = _tubo(c, n)
    return Dict{Symbol,Float64}(
        :v        => t.v,
        :re       => t.re,
        :h_tubo   => t.h_i,
        :h_casco  => t.h_o,
        :re_casco => t.re_casco,
        :h_ideal  => t.h_ideal,
        :jc       => t.jc,
        :jl       => t.jl,
        :jb       => t.jb,
        :js       => t.js,
        :jr       => t.jr,
        :j_produto => t.j_produto,
        :n_chicanas => t.n_chicanas,
        # A faixa da Eq. (6.23) e os dois números que a decidem. Saem como 0/1 e como
        # valor porque `selection_message` precisa dizer POR QUE recusou, e o CSV precisa
        # deixar o leitor conferir a margem sem reabrir o TOML.
        :nu_valido => t.nu_valido ? 1.0 : 0.0,
        :pr       => c.pr_tubo,
        :re_min_correlacao => float(get(k, :dittus_boelter_re_min, NaN)),
        :re_max_correlacao => float(get(k, :dittus_boelter_re_max, NaN)),
        :u        => t.u,
        :area     => t.area,
        :n_total  => t.n_total,
        :d_casco  => Units.m_to_mm(t.d_casco),
        # O feixe e o CASCO são números diferentes desde a correção da Eq. (2-17):
        # o feixe é o que o cartão mostra, o casco é o que `admissible` limita contra a
        # Tabela 3.1 ("Shell inside diameter"). Enquanto o vão valia 3 mm a distinção não
        # pagava; com os 38 mm da fonte, paga.
        :d_shell  => Units.m_to_mm(t.d_shell),
        # O comprimento que a ENVELOPE exigiu, e não o que este caso pediria sozinho:
        # é ele que `admissible` compara com o tubo comercial mais longo, e é ele que
        # será cortado na oficina. Coincidem quando há um caso só.
        :l        => float(l),
        :l_sobre_d => t.d_casco > 0 ? l / t.d_casco : NaN,
        :q        => c.q,
        :dt_lm    => c.dt_lm,
        :f        => c.f,
        # O arranjo é derivado, e não lido do formulário pela figura: a figura acompanha
        # o CURSOR sobre um resultado já calculado, e o formulário pode ter sido editado
        # desde então. Um desenho de 2 passes sobre um resultado de 1 seria uma figura
        # que contradiz o número ao lado dela.
        :passes   => float(c.passes))
end

"""
    case_admissible(m::SaariLMTD, n, c, p)

A banda de velocidade no tubo (Tabela 3.1 de Saari) e a **faixa de validade de
Dittus-Boelter** (Eq. 6.23), deste caso.

É por caso porque a velocidade é `ṁ/(ρ·n·A)` e o Reynolds sai dela, e a vazão mássica é
do caso: com dois casos no envelope, o de maior vazão pode erodir o tubo enquanto o
governante (o de maior comprimento exigido) passa folgado.

# Por que a faixa da correlação recusa o feixe

Saari declara a Eq. (6.23) válida em `10⁴ < Re < 1,2×10⁵` e `0,7 < Pr < 120`, e é
explícito sobre o que há abaixo: *"Below Re = 10⁴ the results are much worse."* Fora
disso o programa não tem correlação de convecção interna — não há um segundo ramo, como
`f = 64/Re` é para a bomba no laminar.

E `h_i` não é um número de canto: ele atravessa `U → A → L`, e `L` é o que a varredura
devolve. Aceitar o ponto seria devolver um comprimento de tubo que nenhuma equação desta
implementação sustenta, com a mesma aparência de todos os outros. Um ponto fora do
domínio de validade não é necessariamente impossível — é um ponto que o modelo
implementado **não está autorizado a avaliar**.
"""
function case_admissible(::SaariLMTD, n::Real, c::ExchangerConstraints,
                         p::AbstractDict)
    t = _tubo(c, n)
    # `ok = false` é feixe cujo laço de Bell-Delaware não fechou, ou cujo `U` não é
    # número. Aceitá-lo seria escolher um trocador a partir de um `L` que ninguém
    # calculou — o mesmo defeito que o `convergiu` de `colebrook_white` evita na bomba.
    return t.ok && t.nu_valido && p[:v_min] <= t.v <= p[:v_max]
end

"""
    admissible(m::SaariLMTD, n, der, p)

As duas medidas do casco — diâmetro do feixe e comprimento de tubo — que são do
**conjunto**: saem do número de tubos e do comprimento que a envelope exigiu, não da
vazão de nenhum caso.

O teto de diâmetro é a Tabela 3.1 de Saari — cuja linha se chama **"Shell inside
diameter"**, casco de chapa enrolada até 2500 mm. Acima disso o serviço deixa de caber
num casco e vira dois em paralelo.

Por isso a comparação é com `:d_shell`, e não com `:d_casco`, que é o **feixe**. Os dois
eram quase o mesmo número enquanto o vão feixe-casco valia 3 mm; com os 38 mm da
Eq. (2-17) de Branan a distinção passou a valer 38 mm de casco, e comparar o feixe com um
limite de casco deixaria passar um trocador que não cabe. Ver o defeito 5 em
`docs/validacao/02-trocador-saari-bell-delaware.md`.

**O teto de comprimento não é de Saari** — ele não trata do assunto. É limite de
fabricação: tubo de trocador vem em comprimento de estoque, e o mais longo comum é
6 m (20 ft). Sem ele o programa escolheria o feixe de menor área com tubos de treze
metros, que minimiza a conta e não existe no catálogo de ninguém. É parâmetro
justamente porque é limite comercial e não física: quem tiver tubo de 12 m muda o
número.
"""
admissible(::SaariLMTD, n::Real, der::AbstractDict, p::AbstractDict) =
    get(der, :d_shell, Inf) <= p[:d_casco_max] &&
    get(der, :l, Inf) <= p[:l_tubo_max]

"""
    objective(m::SaariLMTD, n, der, p)

A **menor área de troca** entre os pontos admissíveis: é ela que paga o trocador, e é o
que a Algoritmo 4.1 procura minimizar ao repetir os passos 3–7.

Como `U` cai com a velocidade e a velocidade cai com `n`, o mínimo de área encosta na
ponta de maior velocidade da banda — que é onde a perda de carga e a erosão também
apertam. É por isso que a banda tem os dois lados, e é por isso que a tabela mostra a
área em cada `n`: o desvio para um feixe mais folgado custa área, e a área está à vista.
"""
objective(::SaariLMTD, n::Real, der::AbstractDict, p::AbstractDict) =
    get(der, :area, Inf)

function envelope_params(::SaariLMTD, params::Vector{<:AbstractDict})
    v_min = maximum(p[:v_min] for p in params)
    v_max = minimum(p[:v_max] for p in params)
    v_min <= v_max || return (false,
        "As bandas de velocidade no tubo pedidas pelos casos não se cruzam: um exige " *
        "v ≥ $(v_min) m/s e outro v ≤ $(v_max) m/s. O feixe é um só.")
    return (true, Dict{Symbol,Float64}(
        :n_min  => minimum(p[:n_min]  for p in params),
        :n_max  => maximum(p[:n_max]  for p in params),
        :n_step => minimum(p[:n_step] for p in params),
        :v_min  => v_min,
        :v_max  => v_max,
        :d_casco_max => minimum(p[:d_casco_max] for p in params),
        :l_tubo_max  => minimum(p[:l_tubo_max]  for p in params)))
end

function selection_message(m::SaariLMTD, rows, teto::Real, p::AbstractDict;
                           mechanism::Symbol = :none)
    isempty(rows) && return "A grade de números de tubos ficou vazia."
    vs = filter(isfinite, [get(r.derivados, :v, NaN) for r in rows])
    na_banda = filter(r -> p[:v_min] <= get(r.derivados, :v, NaN) <= p[:v_max], rows)
    if isempty(na_banda)
        lo, hi = isempty(vs) ? (NaN, NaN) : extrema(vs)
        return "Nenhum feixe da grade mantém a velocidade no tubo na banda " *
               "$(p[:v_min])–$(p[:v_max]) m/s: na grade oferecida ela varia de " *
               "$(round(lo, digits = 2)) a $(round(hi, digits = 2)) m/s. Amplie a " *
               "grade de tubos, mude o diâmetro do tubo, ou reveja a banda."
    end
    # Fora da faixa da Eq. (6.23) vem ANTES do comprimento e do casco: `L` e `d_casco`
    # são calculados A PARTIR de `h_i`, e diagnosticar por eles seria apontar o sintoma
    # de um número que já foi reprovado na origem.
    k = constants(method_config(m))
    validos = filter(r -> get(r.derivados, :nu_valido, 1.0) != 0.0, na_banda)
    if isempty(validos)
        res = filter(isfinite, [get(r.derivados, :re, NaN) for r in na_banda])
        lo, hi = isempty(res) ? (NaN, NaN) : extrema(res)
        prs = filter(isfinite, [get(r.derivados, :pr, NaN) for r in na_banda])
        pr = isempty(prs) ? NaN : first(prs)
        return "Na banda de velocidade $(p[:v_min])–$(p[:v_max]) m/s todos os feixes " *
               "caem fora da faixa em que Saari declara a correlação de Dittus-Boelter " *
               "(Eq. 6.23): o Reynolds no tubo vai de $(round(lo, digits = 0)) a " *
               "$(round(hi, digits = 0)) e o Prandtl vale $(round(pr, digits = 1)), " *
               "contra $(round(float(k[:dittus_boelter_re_min]), digits = 0))–" *
               "$(round(float(k[:dittus_boelter_re_max]), digits = 0)) e " *
               "$(k[:dittus_boelter_pr_min])–$(k[:dittus_boelter_pr_max]). Como h_i " *
               "atravessa U, a área e o comprimento, o programa não extrapola. Mude o " *
               "diâmetro do tubo, reveja a viscosidade ou a temperatura do fluido do " *
               "tubo, ou desloque a banda de velocidade."
    end
    na_banda = validos

    curto = filter(r -> get(r.derivados, :l, Inf) <= p[:l_tubo_max], na_banda)
    if isempty(curto)
        menor_l = minimum(get(r.derivados, :l, Inf) for r in na_banda)
        return "Na banda de velocidade $(p[:v_min])–$(p[:v_max]) m/s todos os feixes " *
               "pedem tubo mais longo que o limite de $(p[:l_tubo_max]) m — o mais " *
               "curto dá $(round(menor_l, digits = 2)) m. Amplie a grade para mais " *
               "tubos, aceite tubo mais longo, ou melhore o coeficiente do casco."
    end
    menor = minimum(get(r.derivados, :d_shell, Inf) for r in curto)
    return "Na banda de velocidade todos os feixes pedem casco maior que o limite de " *
           "$(p[:d_casco_max]) mm — o menor deles dá $(round(menor, digits = 0)) mm. " *
           "Use tubo de menor diâmetro, passo mais apertado, ou divida o serviço em " *
           "dois cascos em paralelo."
end

governing_label(::SaariLMTD, g::Symbol) =
    g === :termica ? "área de troca térmica" : String(g)

requirement_spec(::SaariLMTD) = ("comprimento de tubo", "m")

function result_fields(m::SaariLMTD, r)
    tem = r.feasible && isfinite(r.x)
    txt(v) = tem ? v : "—"
    ok = !tem ? :neutro : (hasproperty(r, :ok) ? r.ok : true) ? :ok : :erro
    return ResultField[
        ResultField("Tubos por passe", tem ? r.x : NaN; digits = 0, highlight = true),
        ResultField("Comprimento do tubo L", tem ? r.y : NaN; unit = "m",
                    highlight = true),
        ResultField("Área de troca A", der(r, :area); unit = "m²"),
        ResultField("Tubos no total", der(r, :n_total); digits = 0),
        ResultField("Diâmetro do feixe", der(r, :d_casco); unit = "mm", digits = 0),
        # O casco, e não só o feixe: é ele que `admissible` compara com a Tabela 3.1, e
        # um cartão que mostra apenas o feixe esconde justamente o número que reprova.
        ResultField("Diâmetro do casco", der(r, :d_shell); unit = "mm", digits = 0),
        ResultField("Esbeltez do feixe L/D", der(r, :l_sobre_d)),
        ResultField("Velocidade no tubo", der(r, :v); unit = "m/s", status = ok),
        ResultField("Reynolds no tubo", der(r, :re); digits = 0),
        ResultField("Coeficiente interno h_i", der(r, :h_tubo); unit = "W/m²K",
                    digits = 0),
        ResultField("Coeficiente do casco h_o", der(r, :h_casco); unit = "W/m²K",
                    digits = 0),
        ResultField("Correção de Bell-Delaware", der(r, :j_produto); digits = 3),
        ResultField("Coeficiente global U", der(r, :u); unit = "W/m²K", digits = 1),
        ResultField("Carga térmica q", der(r, :q); unit = "W", digits = 0),
        ResultField("ΔT médio logarítmico", der(r, :dt_lm); unit = "K"),
        ResultField("Fator de correção F", der(r, :f); digits = 3),
        ResultField("Caso governante", txt(_driver_case(r))),
    ]
end

sweep_columns(::SaariLMTD) = [
    SweepColumn("tubos/passe", :x; digits = 0),
    SweepColumn("L (m)",       :y),
    SweepColumn("A (m²)",      :area; digits = 1),
    SweepColumn("v (m/s)",     :v),
    SweepColumn("U (W/m²K)",   :u; digits = 0),
]

trace_blocks(::SaariLMTD) = [
    :balanco   => "Bloco A — balanço térmico e ΔT médio",
    :tubo      => "Bloco B — lado do tubo",
    :casco     => "Bloco C — lado do casco (Bell-Delaware)",
    :selection => "Seleção do feixe",
]

grid_hint(::SaariLMTD, p::AbstractDict) =
    "Verifique tubos mínimo ($(p[:n_min])), máximo ($(p[:n_max])) e passo ($(p[:n_step]))."

function trace_selection!(m::SaariLMTD, tr::CalcTrace, best, p::AbstractDict)
    d = best.derivados
    trace!(tr, :selection, "—", "tubos por passe",
           "menor área com $(p[:v_min]) ≤ v ≤ $(p[:v_max]) m/s", best.x, "–")
    trace!(tr, :selection, "§3.2.2", "v", "ṁ/(ρ·n·πd_i²/4)", get(d, :v, NaN), "m/s")
    trace!(tr, :selection, "§6.3", "Re", "ρvd_i/µ", get(d, :re, NaN), "–")
    trace!(tr, :selection, "Eq. 6.23", "h_i", "Nu·k/d_i (Dittus-Boelter)",
           get(d, :h_tubo, NaN), "W/m²K")
    # O lado do casco, fator por fator: é o que faz `h_o` deixar de ser um número no
    # fim de uma caixa-preta e passar a ser conferível à mão contra o cap. 2 de Branan.
    if isfinite(get(d, :j_produto, NaN))
        trace!(tr, :selection, "Br. 2-20", "Re (casco)", "d_o·W_s/(µ_s·A_s)",
               get(d, :re_casco, NaN), "–")
        trace!(tr, :selection, "Br. 2-19", "h_ideal",
               "j·cp·(W_s/A_s)·(k/(cp·µ))^(2/3)", get(d, :h_ideal, NaN), "W/m²K")
        trace!(tr, :selection, "Br. 2-22", "Jc", "corte e espaçamento de chicana",
               get(d, :jc, NaN), "–")
        trace!(tr, :selection, "Br. 2-23", "Jl", "vazamento casco- e tubo-chicana",
               get(d, :jl, NaN), "–")
        trace!(tr, :selection, "Br. 2-27", "Jb", "desvio pelo vão feixe-casco",
               get(d, :jb, NaN), "–")
        trace!(tr, :selection, "Br. 2-28", "Js", "pontas de chicana alargadas",
               get(d, :js, NaN), "–")
        trace!(tr, :selection, "Br. 2-29", "Jr", "gradiente adverso (laminar)",
               get(d, :jr, NaN), "–")
        trace!(tr, :selection, "Br. 2-18", "h_o", "h_ideal·Jc·Jl·Jb·Js·Jr",
               get(d, :h_casco, NaN), "W/m²K")
    else
        trace!(tr, :selection, "Tab. 4.1", "h_o", "informado (Bell-Delaware desligado)",
               get(d, :h_casco, NaN), "W/m²K")
    end
    trace!(tr, :selection, "Eq. 5.7a", "U", "resistências em série, área externa",
           get(d, :u, NaN), "W/m²K")
    trace!(tr, :selection, "Eq. 4.4", "A", "q/(U·F·ΔT_lm)", get(d, :area, NaN), "m²")
    trace!(tr, :selection, "—", "L", "A/(N·π·d_o)", best.y, "m")
    trace!(tr, :selection, "Br. 2-13", "d_feixe", "√(4·N·A_célula/π)",
           get(d, :d_casco, NaN), "mm")
    trace!(tr, :selection, "Br. 2-17", "D_casco", "d_feixe + 2·d_o",
           get(d, :d_shell, NaN), "mm")
    return nothing
end

size_equipment(eq::ShellTubeExchanger, m::SaariLMTD, e::ExchangerDuty,
               params::AbstractDict) = size_single(eq, m, e, params)
