"""
Resultados de dimensionamento e o rastro de cálculo.

Contrato do projeto: **inviabilidade é um estado retornado, nunca uma exceção**.
`feasible = false` mais uma `message` diagnóstica — a GUI mostra o motivo em vez de
quebrar.
"""

# ---------------------------------------------------------------------------
# Rastro de cálculo (memorial)
# ---------------------------------------------------------------------------

"""
Uma linha do memorial de cálculo: de qual bloco e equação veio, a fórmula simbólica,
o valor e a unidade. Alimenta o painel "memorial" da GUI e o relatório exportado.
"""
struct TraceEntry
    block::Symbol       # :gas | :settling | :liquid | :selection
    eq::String          # "Eq. 11"
    var::String         # "V_t"
    formula::String     # "0,0036·[((ρl−ρg)/ρg)·(dm/CD)]^0,5"
    value::Float64
    unit::String
end

"Coleção ordenada de [`TraceEntry`](@ref)."
struct CalcTrace
    entries::Vector{TraceEntry}
end
CalcTrace() = CalcTrace(TraceEntry[])

function trace!(t::CalcTrace, block, eq, var, formula, value, unit)
    push!(t.entries, TraceEntry(block, eq, var, formula, value, unit))
    return value
end

Base.length(t::CalcTrace) = length(t.entries)
Base.isempty(t::CalcTrace) = isempty(t.entries)

"Filtra o rastro por bloco de cálculo."
block_entries(t::CalcTrace, block::Symbol) = filter(e -> e.block === block, t.entries)

# ---------------------------------------------------------------------------
# Varredura em diâmetro
# ---------------------------------------------------------------------------

"""
Uma linha da tabela de varredura: para um diâmetro `d`, o `Leff` exigido por cada
restrição, o `Leff` governante e a geometria resultante.

`leff_gas` vem da Eq. 14 (capacidade de gás) e `leff_liquid` da Eq. 22 (capacidade de
líquido). Note que cada bloco tem sua própria relação `Lss(Leff)` — Eq. 15 para gás,
Eq. 23 para líquido — por isso `lss_m` depende de qual governa.
"""
struct SweepRow
    d_mm::Float64
    leff_gas_m::Float64
    leff_liquid_m::Float64
    leff_m::Float64        # max(gas, líquido)
    lss_m::Float64
    sr::Float64
    governing::Symbol      # :gas | :liquid
    sr_ok::Bool
end

# ---------------------------------------------------------------------------
# Resultado de um caso único
# ---------------------------------------------------------------------------

"""
Resultado do dimensionamento de um caso. `diameter_mm` etc. só têm significado se
`feasible` for `true`; caso contrário `message` explica o que impediu.
"""
struct SizingResult
    feasible::Bool
    message::String
    diameter_mm::Float64
    leff_m::Float64
    lss_m::Float64
    sr::Float64
    volume_m3::Float64
    governing::Symbol            # :gas | :liquid
    d_max_mm::Float64            # teto de decantação (Eq. 19/21)
    d_max_mechanism::Symbol      # :water_in_oil | :oil_in_water
    method_id::Symbol
    sweep::Vector{SweepRow}
    trace::CalcTrace
end

"Constrói um [`SizingResult`](@ref) inviável com diagnóstico."
function infeasible(method_id::Symbol, message::AbstractString;
                    sweep = SweepRow[], trace = CalcTrace(), d_max_mm = NaN,
                    d_max_mechanism = :none)
    SizingResult(false, String(message), NaN, NaN, NaN, NaN, NaN, :none,
                 d_max_mm, d_max_mechanism, method_id, sweep, trace)
end

"Volume do cilindro reto, em m³ (`d` em mm, `l` em m)."
vessel_volume(d_mm, l_m) = π * (d_mm / 1000.0)^2 / 4 * l_m

# ---------------------------------------------------------------------------
# Resultado envelope (multi-caso)
# ---------------------------------------------------------------------------

"""
Uma linha da varredura envelope: para cada `d`, o `Leff` exigido por **cada** caso e
o máximo entre eles, com o nome do caso que produziu esse máximo.
"""
struct EnvelopeRow
    d_mm::Float64
    leff_m::Float64                  # envelope: max sobre os casos
    lss_m::Float64
    sr::Float64
    governing::Symbol                # restrição governante no caso governante
    driver_case::String              # caso que produziu o máximo
    per_case_leff::Vector{Float64}   # alinhado com EnvelopeResult.case_names
    sr_ok::Bool
end

"""
Resultado do dimensionamento envelope: **um** vaso que atende a todos os casos, com
rastreabilidade de qual caso governa cada restrição.
"""
struct EnvelopeResult
    feasible::Bool
    message::String
    diameter_mm::Float64
    leff_m::Float64
    lss_m::Float64
    sr::Float64
    volume_m3::Float64
    governing::Symbol
    driver_case::String              # caso que governa o Leff no d escolhido
    d_max_mm::Float64                # menor teto de decantação entre os casos
    d_max_case::String               # caso que impôs esse teto
    case_names::Vector{String}
    rows::Vector{EnvelopeRow}
    slack_m::Vector{Float64}         # Leff_envelope − Leff_caso, no d escolhido
    per_case::Vector{SizingResult}   # dimensionamento individual de cada caso
end

"Constrói um [`EnvelopeResult`](@ref) inviável com diagnóstico."
function infeasible_envelope(message::AbstractString; case_names = String[],
                             rows = EnvelopeRow[], per_case = SizingResult[],
                             d_max_mm = NaN, d_max_case = "")
    EnvelopeResult(false, String(message), NaN, NaN, NaN, NaN, NaN, :none, "",
                   d_max_mm, d_max_case, case_names, rows, Float64[], per_case)
end
