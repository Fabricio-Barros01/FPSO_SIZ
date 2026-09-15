"""
Camada de propriedades do módulo dinâmico — **não é de Song**.

O artigo de Song et al. (2023) consome `ρ`, `µ` e `z` sem dizer de onde vêm. Esta
camada é a origem: quatro correlações publicadas, cada uma com a sua proveniência e a
sua faixa de validade, e **override direto do usuário em todas**. Correlação usada fora
da faixa é **carimbada** (ver [`Carimbo`](@ref)), nunca aplicada em silêncio.

# Por que este arquivo é puro

Como `analysis/pinch.jl`, este módulo entra em `FPSOSiz.jl` **logo depois de
`units.jl`**, antes de `interfaces.jl`. Nenhum `ParameterSpec`, `AbstractSizingMethod`
nem `field_units` existe ainda quando ele compila; citá-los não é evitado, é impossível.
Ele não importa nada de `src/sizing/`, e a conversão de unidades acontece no adaptador
(que entra depois de `config.jl`), nunca aqui: as funções recebem e devolvem **SI**
(T em K, P em Pa, Pc em Pa, µ em Pa·s, ρ em kg/m³, M em kg/mol).

# As quatro correlações e a conferência (valores no cabeçalho do sprint)

| propriedade | correlação | validade |
|---|---|---|
| `z`      | Peng-Robinson (1976/1978), regra de mistura clássica (k_ij = 0) | — |
| `µ_óleo` | Beggs & Robinson (1975), óleo morto, do °API e da T           | API 16–58, T 21–146 °C |
| `µ_água` | Vogel                                                          | 0–370 °C |
| `µ_gás`  | Lee-Gonzalez-Eakin (1966), de M, T e ρ_g                       | ~T 38–171 °C |

Conferidas na implementação: Beggs-Robinson dá 7,98 cP (ρ=850, 40 °C); Vogel 0,651 cP
(40 °C); LGE 0,0121 cP (M=16,61, 40 °C, ρ_g≈7,51); API(850)=34,97≈35,0.
"""
module Propriedades

export Componente, Fluido, Carimbo
export z_peng_robinson, densidade_gas, api_do_oleo
export viscosidade_oleo_bg, viscosidade_agua_vogel, viscosidade_gas_lge
export construir_fluido, compressibilidade

# ---------------------------------------------------------------------------
# Componente e o carimbo de fora-de-faixa
# ---------------------------------------------------------------------------

"""
Um componente da composição, em SI. `y` é a fração molar (0–1); `Tc` em K, `Pc` em Pa,
`M` em kg/mol, `omega` o fator acêntrico. Os pseudocomponentes da Tabela 2 do artigo
(`Tc`, `Pc`, fator acêntrico) entram por aqui como qualquer outro.
"""
struct Componente
    nome::String
    y::Float64
    M::Float64      # kg/mol
    Tc::Float64     # K
    Pc::Float64     # Pa
    omega::Float64
end

"""
Um registro de correlação **fora da faixa de validade**: qual propriedade e o detalhe do
valor de entrada que saiu da faixa. É o "carimbo" que o memorial precisa — a regra do
sprint é que fora de faixa nunca é silencioso.
"""
struct Carimbo
    propriedade::String
    detalhe::String
end

# ---------------------------------------------------------------------------
# Peng-Robinson — o fator de compressibilidade z
# ---------------------------------------------------------------------------

"""
    _maior_raiz_real_cubica(a2, a1, a0) -> Float64

Maior raiz real de `z³ + a2·z² + a1·z + a0 = 0`, por depressão + fórmula de
Cardano/trigonométrica. Determinística e sem dependência — a raiz do gás é a maior das
reais. Substitui uma bisseção porque a cúbica de PR pode ter uma ou três raízes reais e
a maior é a de vapor.
"""
function _maior_raiz_real_cubica(a2::Float64, a1::Float64, a0::Float64)
    # Depressão z = t − a2/3  ⇒  t³ + p·t + q = 0
    p = a1 - a2^2 / 3
    q = 2a2^3 / 27 - a2 * a1 / 3 + a0
    off = -a2 / 3
    Δ = (q / 2)^2 + (p / 3)^3
    if Δ > 0                                   # uma raiz real
        s = sqrt(Δ)
        t = cbrt(-q / 2 + s) + cbrt(-q / 2 - s)
        return t + off
    end
    # três raízes reais (inclui Δ = 0): forma trigonométrica
    r = sqrt(-p / 3)
    cosarg = clamp(-q / (2 * r^3), -1.0, 1.0)
    φ = acos(cosarg)
    m = -Inf
    for kk in 0:2
        m = max(m, 2r * cos((φ + 2π * kk) / 3))
    end
    return m + off
end

"""
    z_peng_robinson(comps, T, P; R = 8.314) -> z

Fator de compressibilidade `z` pela equação de estado de Peng-Robinson, com regra de
mistura clássica (`k_ij = 0`, de modo que `aα_mix = (Σ yᵢ √(aαᵢ))²`). `T` em K, `P` em
Pa, `Pc` de cada componente em Pa. Verificado no cabeçalho do sprint: para o gás da
Tabela 1, `z` vai de 0,9659 a 0,9917 na faixa 500–1350 kPa e 20–60 °C.

O `κ` usa o ramo de Peng-Robinson (1978) para `ω > 0,49` — os pseudocomponentes pesados
da Tabela 2 têm `ω > 1`, onde o `κ` de 1976 não vale; na fase gasosa eles pesam ~0, mas
o ramo correto mantém a função utilizável para qualquer composição.
"""
z_peng_robinson(comps::AbstractVector{Componente}, T::Float64, P::Float64;
                R::Float64 = 8.314) = _z_pr(comps, T, P, R)

# Núcleo POSICIONAL: o caminho quente (`compressibilidade` por passo) o chama sem
# keyword, porque o argumento nomeado `R` vindo de um campo aloca ~64 B por chamada — e o
# critério de aceitação 8 é passo com ZERO alocação. A forma com keyword acima é o API.
function _z_pr(comps::AbstractVector{Componente}, T::Float64, P::Float64, R::Float64)
    aα_mix, b_mix = _mistura_pr(comps, T, R)
    return _z_de_mistura(aα_mix, b_mix, P, R, T)
end

"""
    _mistura_pr(comps, T, R) -> (aα_mix, b_mix)

Os dois parâmetros de mistura de Peng-Robinson que dependem **só** de `T` (constante numa
simulação), não de `P`: `aα_mix = (Σ yᵢ√(aαᵢ))²` e `b_mix = Σ yᵢ bᵢ`. Calculados **uma
vez** na construção do [`Fluido`](@ref) — é o que tira o laço sobre a composição do
caminho quente e faz `z` por passo ser aritmética escalar (zero-alloc, crit. 8).
"""
function _mistura_pr(comps::AbstractVector{Componente}, T::Float64, R::Float64)
    soma_sqrt_aα = 0.0
    b_mix = 0.0
    for c in comps
        a = 0.45724 * R^2 * c.Tc^2 / c.Pc
        b = 0.07780 * R * c.Tc / c.Pc
        κ = c.omega <= 0.49 ?
            0.37464 + 1.54226 * c.omega - 0.26992 * c.omega^2 :
            0.379642 + 1.48503 * c.omega - 0.164423 * c.omega^2 + 0.016666 * c.omega^3
        α = (1 + κ * (1 - sqrt(T / c.Tc)))^2
        soma_sqrt_aα += c.y * sqrt(a * α)
        b_mix += c.y * b
    end
    return (soma_sqrt_aα^2, b_mix)
end

"`z` a partir dos parâmetros de mistura já calculados e da pressão `P` — o passo quente."
function _z_de_mistura(aα_mix::Float64, b_mix::Float64, P::Float64, R::Float64, T::Float64)
    RT = R * T
    A = aα_mix * P / RT^2
    B = b_mix * P / RT
    # z³ − (1−B)z² + (A − 3B² − 2B)z − (AB − B² − B³) = 0
    a2 = -(1 - B)
    a1 = A - 3B^2 - 2B
    a0 = -(A * B - B^2 - B^3)
    return _maior_raiz_real_cubica(a2, a1, a0)
end

"""
Densidade do gás pela lei dos gases reais: `ρ_g = P·M/(z·R·T)`. `M` em kg/mol, `P` em Pa.
`R` é **posicional** (com default) de propósito: o caminho quente o chama sem keyword para
não alocar (ver [`_z_pr`](@ref)); um keyword vindo de campo aloca ~32 B por chamada.
"""
densidade_gas(P::Float64, M::Float64, z::Float64, T::Float64, R::Float64 = 8.314) =
    P * M / (z * R * T)

# ---------------------------------------------------------------------------
# Viscosidades
# ---------------------------------------------------------------------------

"°API do óleo a partir da densidade (kg/m³): `API = 141,5/SG − 131,5`, `SG = ρ/1000`."
api_do_oleo(rho_oleo::Float64) = 141.5 / (rho_oleo / 1000.0) - 131.5

"""
    viscosidade_oleo_bg(rho_oleo, T) -> Pa·s

Beggs & Robinson (1975), óleo morto: `µ_od = 10^x − 1`, `x = y·T[°F]^(−1,163)`,
`y = 10^(3,0324 − 0,02023·API)`. `rho_oleo` em kg/m³, `T` em K, saída em Pa·s.
Conferido: ρ=850 (API 35,0) → 7,98 cP a 40 °C, 21,5 cP a 25 °C.
"""
function viscosidade_oleo_bg(rho_oleo::Float64, T::Float64)
    api = api_do_oleo(rho_oleo)
    T_F = (T - 273.15) * 9 / 5 + 32
    y = 10.0^(3.0324 - 0.02023 * api)
    x = y * T_F^(-1.163)
    return (10.0^x - 1) * 1e-3               # cP → Pa·s
end

"Faixa de validade de Beggs & Robinson: API 16–58, T 21–146 °C."
function faixa_oleo_bg(rho_oleo::Float64, T::Float64)
    api = api_do_oleo(rho_oleo)
    T_C = T - 273.15
    fora = String[]
    (16 <= api <= 58)  || push!(fora, "°API = $(round(api, digits = 1)) fora de 16–58")
    (21 <= T_C <= 146) || push!(fora, "T = $(round(T_C, digits = 1)) °C fora de 21–146")
    return fora
end

"""
    viscosidade_agua_vogel(T) -> Pa·s

Vogel: `µ = 2,414×10⁻⁵·10^(247,8/(T[K] − 140))`, válida de 0 a 370 °C. `T` em K.
Conferido: 0,890 cP a 25 °C, 0,651 a 40 °C, 0,463 a 60 °C.
"""
viscosidade_agua_vogel(T::Float64) = 2.414e-5 * 10.0^(247.8 / (T - 140.0))

"Faixa de validade de Vogel: 0–370 °C."
function faixa_agua_vogel(T::Float64)
    T_C = T - 273.15
    (0 <= T_C <= 370) ? String[] :
        ["T = $(round(T_C, digits = 1)) °C fora de 0–370"]
end

"""
    viscosidade_gas_lge(M, T, rho_g) -> Pa·s

Lee-Gonzalez-Eakin (1966): `µ[µP] = K·exp(X·ρ_g^Y)`, com `T` em °R, `M` em g/mol e
`ρ_g` em g/cm³. Entrada em SI (`M` em kg/mol, `T` em K, `ρ_g` em kg/m³), saída em Pa·s.
Conferido: M=16,61 → 0,0121 cP a 40 °C (ρ_g≈7,51 kg/m³).
"""
function viscosidade_gas_lge(M::Float64, T::Float64, rho_g::Float64)
    Mg = M * 1000.0                          # g/mol
    T_R = T * 9 / 5                          # K → °R
    rho = rho_g / 1000.0                     # kg/m³ → g/cm³
    K = (9.4 + 0.02 * Mg) * T_R^1.5 / (209 + 19 * Mg + T_R)
    X = 3.5 + 986 / T_R + 0.01 * Mg
    Y = 2.4 - 0.2 * X
    return K * exp(X * rho^Y) * 1e-7         # µP → Pa·s
end

"Faixa de validade de LGE (aproximada, do sprint): T 38–171 °C."
function faixa_gas_lge(T::Float64)
    T_C = T - 273.15
    (38 <= T_C <= 171) ? String[] :
        ["T = $(round(T_C, digits = 1)) °C fora de ~38–171"]
end

# ---------------------------------------------------------------------------
# O fluido resolvido — correlação OU override, com carimbo de fora-de-faixa
# ---------------------------------------------------------------------------

"""
Propriedades resolvidas para uma simulação. `z` **não** entra aqui como número: como a
pressão muda a cada passo, guarda-se a composição (`comps`) e `z` é recalculado por
[`compressibilidade`](@ref) a cada passo — a menos que o usuário fixe `z_fixo`
(`NaN` = usar Peng-Robinson). As viscosidades e densidades são de T constante e resolvem
uma vez. `carimbos` lista as correlações aplicadas fora da faixa.
"""
struct Fluido
    comps::Vector{Componente}   # composição do gás, para z por passo
    M::Float64                  # massa molar do gás, kg/mol
    rho_oleo::Float64           # kg/m³
    rho_agua::Float64           # kg/m³
    mu_oleo::Float64            # Pa·s
    mu_agua::Float64            # Pa·s
    mu_gas::Float64             # Pa·s
    z_fixo::Float64             # NaN = Peng-Robinson por passo
    T::Float64                  # K
    R::Float64                  # J/(mol·K)
    aalpha_mix::Float64         # (Σ yᵢ√(aαᵢ))² — depende só de T, precalculado
    b_mix::Float64              # Σ yᵢ bᵢ — depende só de T, precalculado
    carimbos::Vector{Carimbo}
end

"""
    compressibilidade(f, P) -> z

`z` do fluido à pressão `P` (Pa): o override `z_fixo`, se finito, senão Peng-Robinson
sobre a composição à temperatura `f.T`.
"""
compressibilidade(f::Fluido, P::Float64) =
    isfinite(f.z_fixo) ? f.z_fixo :
    _z_de_mistura(f.aalpha_mix, f.b_mix, P, f.R, f.T)

"""
    construir_fluido(comps, T, R; ρ_oleo, ρ_agua, P_ref,
                     z_fixo, µ_oleo, µ_agua, µ_gas) -> Fluido

Monta o [`Fluido`](@ref) resolvendo cada propriedade por correlação, a menos que o
override correspondente seja finito. `P_ref` (Pa) é a pressão de referência para a
densidade e a viscosidade do gás (a inicial da simulação). Cada override em SI:
`z_fixo`, `µ_oleo`, `µ_agua`, `µ_gas` em Pa·s. `NaN` em qualquer um significa "usar a
correlação". Correlação fora de faixa vira um [`Carimbo`](@ref), nunca uma recusa.
"""
function construir_fluido(comps::AbstractVector{Componente}, T::Float64, R::Float64;
                          rho_oleo::Float64, rho_agua::Float64, P_ref::Float64,
                          z_fixo::Float64 = NaN, mu_oleo::Float64 = NaN,
                          mu_agua::Float64 = NaN, mu_gas::Float64 = NaN)
    carimbos = Carimbo[]
    M = sum(c.y * c.M for c in comps)

    mu_o = if isfinite(mu_oleo)
        mu_oleo
    else
        for d in faixa_oleo_bg(rho_oleo, T)
            push!(carimbos, Carimbo("µ_óleo (Beggs-Robinson)", d))
        end
        viscosidade_oleo_bg(rho_oleo, T)
    end

    mu_w = if isfinite(mu_agua)
        mu_agua
    else
        for d in faixa_agua_vogel(T)
            push!(carimbos, Carimbo("µ_água (Vogel)", d))
        end
        viscosidade_agua_vogel(T)
    end

    z_ref = isfinite(z_fixo) ? z_fixo : _z_pr(comps, T, P_ref, R)
    rho_g_ref = densidade_gas(P_ref, M, z_ref, T, R)

    mu_g = if isfinite(mu_gas)
        mu_gas
    else
        for d in faixa_gas_lge(T)
            push!(carimbos, Carimbo("µ_gás (Lee-Gonzalez-Eakin)", d))
        end
        viscosidade_gas_lge(M, T, rho_g_ref)
    end

    aα_mix, b_mix = _mistura_pr(comps, T, R)   # dependem só de T: uma vez, aqui
    return Fluido(collect(comps), M, rho_oleo, rho_agua, mu_o, mu_w, mu_g,
                  z_fixo, T, R, aα_mix, b_mix, carimbos)
end

end # module Propriedades
