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
não dependem de `d`. Por isso [`separator_constraints`](@ref) é o ponto de entrada
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

_sa_config() = load_config(_SA_CONFIG...)

label(::StewartArnold) = config_label(_sa_config(), "Stewart & Arnold (2008)")
parameters(::StewartArnold) = parameter_specs(_sa_config())

# ---------------------------------------------------------------------------
# Restrições — os três números que resumem a física
# ---------------------------------------------------------------------------

"""
As restrições de Stewart & Arnold que não dependem do diâmetro.

`d_leff_gas` [mm·m] é o produto exigido pela Eq. 14; `d2_leff` [mm²·m] o exigido pela
Eq. 22; `d_max_mm` o teto de decantação (Eq. 19/21) e `mechanism` qual das duas
decantações o impôs.
"""
struct SeparatorConstraints
    d_leff_gas::Float64
    d2_leff::Float64
    d_max_mm::Float64
    mechanism::Symbol
    beta::Float64
    aw_over_a::Float64
end

"""
    separator_constraints(m::StewartArnold, s::StreamState, p, k)
        -> (ok::Bool, result, trace::CalcTrace)

Avalia os blocos A, B e C. Em caso de sucesso `result` é um
[`SeparatorConstraints`](@ref); em caso de falha, a mensagem diagnóstica.
`p` são os parâmetros já mesclados com os defaults e `k` as constantes do TOML.
"""
function separator_constraints(m::StewartArnold, s::StreamState,
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

    return (true, SeparatorConstraints(d_leff_gas, d2_leff, d_max, mechanism, beta, awa), tr)
end

# ---------------------------------------------------------------------------
# Geometria a partir das restrições
# ---------------------------------------------------------------------------

"Grade de diâmetros da varredura, em mm."
diameter_grid(p::AbstractDict) = collect(p[:d_min]:p[:d_step]:p[:d_max])

"""
    sweep_row(d_mm, cons, f_lss, sr_min, sr_max) -> SweepRow

Geometria para um diâmetro: `Leff` governante, `Lss` pela relação do bloco que governa
(Eq. 15 para gás, Eq. 23 para líquido) e a esbeltez da Eq. 24.
"""
function sweep_row(d_mm::Real, cons::SeparatorConstraints, f_lss::Real,
                   sr_min::Real, sr_max::Real)
    leff_gas = cons.d_leff_gas / d_mm
    leff_liq = cons.d2_leff / d_mm^2
    gov      = leff_gas > leff_liq ? :gas : :liquid
    leff     = max(leff_gas, leff_liq)
    lss      = gov === :gas ? leff + d_mm / 1000.0 : f_lss * leff
    sr       = lss / (d_mm / 1000.0)
    return SweepRow(d_mm, leff_gas, leff_liq, leff, lss, sr, gov, sr_min <= sr <= sr_max)
end

"Geometria envelope para um diâmetro, dado o `Leff` já enveloppado e quem governa."
function envelope_geometry(d_mm::Real, leff::Real, gov::Symbol, f_lss::Real)
    lss = gov === :gas ? leff + d_mm / 1000.0 : f_lss * leff
    return (lss, lss / (d_mm / 1000.0))
end

# ---------------------------------------------------------------------------
# Dimensionamento de caso único
# ---------------------------------------------------------------------------

"""
    size_equipment(::Separator, ::StewartArnold, s::StreamState, params) -> SizingResult

`params` é um `Dict{Symbol,Float64}` com as chaves declaradas em
`config/equipment/separator/stewart_arnold.toml`. Valores ausentes assumem o default
do descritor. Inviabilidade é devolvida como `feasible = false`, nunca lançada.
"""
function size_equipment(eq::Separator, m::StewartArnold, s::StreamState,
                        params::AbstractDict)
    p = with_defaults(parameters(m), params)
    k = constants(_sa_config())

    ok, cons, tr = separator_constraints(m, s, p, k)
    ok || return infeasible(method_id(m), cons; trace = tr)

    f_lss = float(k[:lss_liquid_factor])
    grid  = diameter_grid(p)

    isempty(grid) && return infeasible(method_id(m),
        "Grade de diâmetros vazia: verifique d_min ($(p[:d_min])), " *
        "d_max ($(p[:d_max])) e passo ($(p[:d_step])).";
        trace = tr, d_max_mm = cons.d_max_mm, d_max_mechanism = cons.mechanism)

    sweep = [sweep_row(d, cons, f_lss, p[:sr_min], p[:sr_max]) for d in grid]
    admissible = filter(r -> r.d_mm <= cons.d_max_mm && r.sr_ok, sweep)

    if isempty(admissible)
        return infeasible(method_id(m),
            selection_diagnosis(sweep, cons.d_max_mm, cons.mechanism,
                                p[:sr_min], p[:sr_max]);
            sweep, trace = tr, d_max_mm = cons.d_max_mm,
            d_max_mechanism = cons.mechanism)
    end

    best = argmin(r -> abs(r.sr - p[:sr_target]), admissible)
    trace!(tr, :selection, "Eq. 24", "SR", "Lss/(d/1000)", best.sr, "–")
    trace!(tr, :selection, "—", "d escolhido",
           "menor |SR − $(p[:sr_target])| com $(p[:sr_min]) ≤ SR ≤ $(p[:sr_max])",
           best.d_mm, "mm")

    return SizingResult(true, "", best.d_mm, best.leff_m, best.lss_m, best.sr,
                        vessel_volume(best.d_mm, best.lss_m), best.governing,
                        cons.d_max_mm, cons.mechanism, method_id(m), sweep, tr)
end

"""
    selection_diagnosis(rows, d_max, mechanism, sr_min, sr_max) -> String

Explica **por que** o conjunto admissível ficou vazio: se foi o teto de decantação ou
a banda de esbeltez. É o que a GUI mostra no lugar do resultado.
"""
function selection_diagnosis(rows, d_max_mm, mechanism, sr_min, sr_max)
    under = filter(r -> r.d_mm <= d_max_mm, rows)
    if isempty(under)
        return "Nenhum diâmetro da grade respeita o teto de decantação " *
               "d_max = $(round(d_max_mm, digits = 0)) mm " *
               "($(mechanism_label(mechanism))). Reduza d_min, ou reveja as " *
               "viscosidades e os tempos de retenção."
    end
    lo, hi = extrema(r.sr for r in under)
    return "Nenhum diâmetro admissível tem esbeltez na banda $(sr_min)–$(sr_max): " *
           "abaixo do teto de decantação ($(round(d_max_mm, digits = 0)) mm) o SR " *
           "varia de $(round(lo, digits = 2)) a $(round(hi, digits = 2)). " *
           "Amplie a grade de diâmetros ou a banda de SR."
end

"Rótulo PT-BR do mecanismo de decantação que impôs o teto de diâmetro."
mechanism_label(m::Symbol) = m === :water_in_oil ? "água em óleo" :
                             m === :oil_in_water ? "óleo em água" : String(m)
