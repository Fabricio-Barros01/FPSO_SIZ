"""
Dimensionamento de separador trifásico horizontal — modelo semiempírico de
Stewart & Arnold (2008), na forma apresentada por Alves & Komesu (2025).

Três blocos, avaliados sobre uma varredura de diâmetros:

* **A — capacidade de gás** (Eq. 9–15): a gotícula de líquido arrastada tem de decantar
  antes de chegar ao extrator de névoa. Fixa um `d·Leff` mínimo.
* **B — decantação líquido-líquido** (Eq. 16–21): água em óleo e óleo em água, por
  Stokes. Fixa um **teto** de diâmetro, `d_max`.
* **C — capacidade de líquido** (Eq. 22–24): tempo de retenção das duas fases líquidas.
  Fixa um `d²·Leff` mínimo.

O `Leff` exigido é o maior entre A e C; a relação `Lss(Leff)` é a do bloco que governa
(Eq. 15 para gás, Eq. 23 para líquido). Entre os diâmetros admissíveis escolhe-se o de
esbeltez mais próxima de `sr_target`, dentro da banda recomendada 3 ≤ SR ≤ 5.

Os três blocos produzem apenas **três números** — `d·Leff`, `d²·Leff` e `d_max` — que
não dependem de `d`. Por isso [`sizing_constraints`](@ref) é o ponto de entrada
real: tanto o dimensionamento de caso único quanto o motor de envelope o consomem, e a
física não é duplicada.

## Divergências conhecidas em relação ao texto publicado

1. **Eq. 22.** O artigo imprime `4,12×10⁴`, valor inconsistente com a própria Tabela 3
   do artigo (que implica `4,20×10⁴`). Usamos o coeficiente derivado da forma em
   unidades de campo de Stewart & Arnold, `4,2152×10⁴` — ver
   [`Units.liquid_capacity_coefficient`](@ref). Reproduz a Tabela 3 com 0,35 %; o
   `4,12×10⁴` erra 1,9 %.

2. **Tabela 1, viscosidade do gás.** Os `0,6 cP` tabelados são viscosidade de líquido
   (gás natural a 28 °C / 2300 kPa fica em ~0,012 cP). A tabela repete `1,1` para a
   densidade relativa e a viscosidade da água, e `0,6` para as duas do gás — as colunas
   foram trocadas na transcrição. O bloco A é sensível a isso: `µ_g = 0,012` dá
   `Leff ≈ 0,065 m` (que é a Tabela 2 do artigo) e `µ_g = 0,6` dá `Leff ≈ 1,6 m`. Em
   nenhum dos dois o gás governa, então a conclusão do artigo se mantém; expomos `µ_g`
   como entrada explícita para que a escolha fique visível.

3. **Eq. 21.** O artigo divide `(h_w)max` por `β`, o mesmo β da Eq. 19. Geometricamente
   a altura fracionária da fase água é `0,5 − β`, não `β`. Seguimos o texto publicado
   (β nos dois), porque é o que reproduz o resultado do artigo; a alternativa fica
   registrada aqui e no rastro de cálculo.
"""

struct Separator <: AbstractEquipment end
method_id(::Separator) = :separator
label(::Separator) = "Separador Trifásico Horizontal"

struct StewartArnold <: AbstractSizingMethod end
method_id(::StewartArnold) = :stewart_arnold
applies_to(::StewartArnold) = Separator()

const _SA_CONFIG = ("equipment", "separator", "stewart_arnold.toml")

"O TOML deste método — a implementação de [`method_config`](@ref) para o separador."
method_config(::StewartArnold) = load_config(_SA_CONFIG...)

label(::StewartArnold) = config_label(method_config(StewartArnold()), "Stewart & Arnold (2008)")
parameters(::StewartArnold) = parameter_specs(method_config(StewartArnold()))

# ---------------------------------------------------------------------------
# Restrições — os três números que resumem a física
# ---------------------------------------------------------------------------

"""
    sizing_constraints(m::StewartArnold, s::StreamState, p, k)
        -> (ok::Bool, result, trace::CalcTrace)

Avalia os blocos A, B e C. Em caso de sucesso `result` é um
[`VesselConstraints`](@ref) — `d·Leff` da Eq. 14, `d²·Leff` da Eq. 22 e o teto de
decantação das Eq. 19/21, com o mecanismo que o impôs; em caso de falha, a mensagem
diagnóstica. `p` são os parâmetros já mesclados com os defaults e `k` as constantes
do TOML.

Esta é a implementação do separador trifásico do contrato de
`src/sizing/constraints.jl` — é por ela que o motor de envelope chega à física daqui
sem conhecer nenhum dos dois.
"""
function sizing_constraints(m::StewartArnold, s::StreamState,
                            p::AbstractDict, k::AbstractDict)
    fu = field_units(s)
    tr = CalcTrace()

    dm_gas, dm_oil, dm_water = p[:dm_gas], p[:dm_oil], p[:dm_water]
    tr_o, tr_w = p[:tr_oil], p[:tr_water]

    c_eq14 = float(k[:eq14_coefficient])
    c_eq17 = float(k[:eq17_coefficient])
    c_eq22 = float(k[:eq22_coefficient])
    cd0    = float(k[:cd_initial])
    relax  = float(k[:cd_relaxation])

    # ---------------------------------------------------------------- bloco A
    drag = converge_drag(fu.rho_o, fu.rho_g, dm_gas, fu.mu_g; cd0, relax)
    trace!(tr, :gas, "Eq. 9–11", "C_D", "iteração sub-relaxada de 24/Re + 3/√Re + 0,34",
           drag.cd, "–")
    trace!(tr, :gas, "Eq. 11", "V_t", "0,0036·[((ρl−ρg)/ρg)·(dm/C_D)]^0,5", drag.vt, "m/s")
    trace!(tr, :gas, "Eq. 10", "Re", "0,001·ρg·dm·V_t/µg", drag.re, "–")

    drag.converged || return (false,
        "O coeficiente de arrasto não convergiu em $(drag.iterations) iterações. " *
        "Verifique a viscosidade do gás (µ_g = $(round(fu.mu_g, digits = 4)) cP).", tr)

    K = souders_brown(fu.rho_o, fu.rho_g, dm_gas, drag.cd)
    trace!(tr, :gas, "Eq. 13", "K", "[(ρg/(ρl−ρg))·(C_D/dm)]^0,5", K, "–")

    d_leff_gas = c_eq14 * (fu.t_k * fu.z * fu.q_g / fu.p_kpa) * K
    trace!(tr, :gas, "Eq. 14", "d·Leff", "34,5·[T·Z·Qg/P]·K", d_leff_gas, "mm·m")

    # ---------------------------------------------------------------- bloco B
    dsg = fu.sg_w - fu.sg_o
    trace!(tr, :settling, "Eq. 16", "ΔSG", "(SG)w − (SG)o", dsg, "–")

    dsg > 0 || return (false,
        "Densidade do óleo ≥ densidade da água (ΔSG = $(round(dsg, digits = 4))): " *
        "não há separação gravitacional líquido-líquido.", tr)

    ho_max = c_eq17 * tr_o * dsg * dm_water^2 / fu.mu_o
    hw_max = c_eq17 * dsg * tr_w * dm_oil^2 / fu.mu_w
    trace!(tr, :settling, "Eq. 17", "(h_o)max", "0,033·(tr)o·ΔSG·dm²/µo", ho_max, "mm")
    trace!(tr, :settling, "Eq. 20", "(h_w)max", "0,033·ΔSG·(tr)w·dm²/µw", hw_max, "mm")

    awa  = water_area_fraction(fu.q_o, fu.q_w, tr_o, tr_w)
    beta = beta_coefficient(awa)
    trace!(tr, :settling, "Eq. 18", "Aw/A", "0,5·Qw(tr)w/((tr)oQo+(tr)wQw)", awa, "–")
    trace!(tr, :settling, "Fig. 3", "β",
           "0,5 − h_w/d (segmento circular, vaso meio cheio)", beta, "–")

    beta > 0 || return (false,
        "A fase aquosa ocupa toda a metade inferior do vaso (Aw/A = " *
        "$(round(awa, digits = 4))): não sobra altura para a camada de óleo.", tr)

    d_max_wio = ho_max / beta
    d_max_oiw = hw_max / beta
    trace!(tr, :settling, "Eq. 19", "d_max (água em óleo)", "(h_o)max/β", d_max_wio, "mm")
    trace!(tr, :settling, "Eq. 21", "d_max (óleo em água)", "(h_w)max/β", d_max_oiw, "mm")

    d_max, mechanism = d_max_wio <= d_max_oiw ? (d_max_wio, :water_in_oil) :
                                                (d_max_oiw, :oil_in_water)

    # ---------------------------------------------------------------- bloco C
    d2_leff = c_eq22 * (tr_o * fu.q_o + tr_w * fu.q_w)
    trace!(tr, :liquid, "Eq. 22", "d²·Leff", "C·((tr)oQo + (tr)wQw)", d2_leff, "mm²·m")

    return (true, VesselConstraints(d_leff_gas, d2_leff, d_max, mechanism, beta, awa), tr)
end

# A geometria a partir das restrições (`diameter_grid`, `sweep_row`, `lss_from`) não
# está mais aqui: ela nunca foi do separador, e vive em `src/sizing/constraints.jl`
# junto ao contrato que o motor de envelope consome. O que sobra neste arquivo é o que
# é de fato de Stewart & Arnold — os três blocos e as divergências documentadas acima.

# ---------------------------------------------------------------------------
# Dimensionamento de caso único
# ---------------------------------------------------------------------------

"""
    size_equipment(::Separator, ::StewartArnold, s::StreamState, params) -> SizingResult

`params` é um `Dict{Symbol,Float64}` com as chaves declaradas em
`config/equipment/separator/stewart_arnold.toml`. Valores ausentes assumem o default
do descritor. Inviabilidade é devolvida como `feasible = false`, nunca lançada.

O corpo está em [`size_vessel`](@ref), compartilhado com os demais vasos da família:
dadas as restrições, a varredura e a escolha do diâmetro não têm nada de trifásico.
Fica como método de `size_equipment` — e não como o próprio `size_vessel` despachado no
tipo abstrato — porque `size_equipment` é o ponto de extensão declarado em
`src/interfaces.jl`: um equipamento que não seja um vaso (uma bomba, um trocador) tem
de poder escrever o seu do zero.
"""
size_equipment(eq::Separator, m::StewartArnold, s::StreamState, params::AbstractDict) =
    size_vessel(eq, m, s, params)
