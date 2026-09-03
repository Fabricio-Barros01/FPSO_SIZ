"""
Resultados de dimensionamento e o rastro de cálculo.

Contrato do projeto: **inviabilidade é um estado retornado, nunca uma exceção**.
`feasible = false` mais uma `message` diagnóstica — a GUI mostra o motivo em vez de
quebrar.

## Por que os campos se chamam `x`, `y` e `derivados`

Porque um resultado de dimensionamento neste programa tem sempre a mesma forma — um
ponto escolhido num eixo varrido, a grandeza que o envelope exigiu ali, e o que se
deriva dos dois — e **só o vaso chama esses três de `d`, `Leff` e `Lss`**. Uma bomba
chama de DN, carga do sistema e velocidade; um trocador, de número de tubos, comprimento
e área.

Até o Sprint 6 os campos tinham os nomes do vaso, e era o bastante para dois vasos.
Mantê-los seria pedir que a bomba guardasse a sua velocidade num campo chamado `sr` —
exatamente a classe de rótulo mentiroso que este projeto vem caçando desde a herança por
posição do Sprint 2. Os nomes de vaso não sumiram: vivem nos `label` que
[`result_fields`](@ref) e [`sweep_columns`](@ref) declaram, que é onde a tela os lê e o
leitor os vê.
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

"""
    trace_block_order(t) -> Vector{Symbol}

Os blocos presentes no rastro, na ordem em que apareceram. É o que a interface usa para
montar o memorial de um método que não declarou [`trace_blocks`](@ref) — um memorial na
ordem do cálculo é legível mesmo sem títulos em português; um memorial em ordem
alfabética não é.
"""
function trace_block_order(t::CalcTrace)
    vistos = Symbol[]
    for e in t.entries
        e.block in vistos || push!(vistos, e.block)
    end
    return vistos
end

# ---------------------------------------------------------------------------
# Varredura
# ---------------------------------------------------------------------------

"""
Uma linha da varredura de um caso: no ponto `x` do eixo, o que cada restrição exigiu,
o que a governante exigiu (`y`) e o que se derivou disso.

`per_constraint` guarda a exigência de **cada** bloco, e não só a maior: é o que permite
ao memorial e ao gráfico mostrarem que o gás pedia 0,065 m enquanto o líquido pedia 18,6
— a folga entre os dois é o argumento de que o vaso está dimensionado pelo bloco certo.
"""
struct SweepRow
    x::Float64
    y::Float64
    per_constraint::Dict{Symbol,Float64}
    derivados::Dict{Symbol,Float64}
    governing::Symbol
    ok::Bool
end

# ---------------------------------------------------------------------------
# Resultado de um caso único
# ---------------------------------------------------------------------------

"""
Resultado do dimensionamento de um caso. `x`, `y` e `derivados` só têm significado se
`feasible` for `true`; caso contrário `message` explica o que impediu.
"""
struct SizingResult
    feasible::Bool
    message::String
    x::Float64
    y::Float64
    derivados::Dict{Symbol,Float64}
    governing::Symbol
    ceiling::Float64             # teto do eixo (Inf = o método não impõe nenhum)
    ceiling_mechanism::Symbol    # o que impôs o teto (:none quando não há)
    method_id::Symbol
    sweep::Vector{SweepRow}
    trace::CalcTrace
end

"Constrói um [`SizingResult`](@ref) inviável com diagnóstico."
function infeasible(method_id::Symbol, message::AbstractString;
                    sweep = SweepRow[], trace = CalcTrace(), ceiling = NaN,
                    ceiling_mechanism = :none)
    SizingResult(false, String(message), NaN, NaN, Dict{Symbol,Float64}(), :none,
                 ceiling, ceiling_mechanism, method_id, sweep, trace)
end

"Volume do cilindro reto, em m³ (`d` em mm, `l` em m)."
vessel_volume(d_mm, l_m) = π * (d_mm / 1000.0)^2 / 4 * l_m

# ---------------------------------------------------------------------------
# Resultado envelope (multi-caso)
# ---------------------------------------------------------------------------

"""
Uma linha da varredura envelope: para cada `x`, a exigência de **cada** caso e o máximo
entre elas, com o nome do caso que produziu esse máximo.
"""
struct EnvelopeRow
    x::Float64
    y::Float64                       # envelope: max sobre os casos
    derivados::Dict{Symbol,Float64}
    governing::Symbol                # restrição governante no caso governante
    driver_case::String              # caso que produziu o máximo
    per_case_y::Vector{Float64}      # alinhado com EnvelopeResult.case_names
    ok::Bool
end

"""
Resultado do dimensionamento envelope: **um** equipamento que atende a todos os casos,
com rastreabilidade de qual caso governa cada restrição.
"""
struct EnvelopeResult
    feasible::Bool
    message::String
    x::Float64
    y::Float64
    derivados::Dict{Symbol,Float64}
    governing::Symbol
    driver_case::String              # caso que governa o `y` no `x` escolhido
    ceiling::Float64                 # menor teto entre os casos
    ceiling_case::String             # caso que impôs esse teto
    ceiling_mechanism::Symbol
    case_names::Vector{String}
    rows::Vector{EnvelopeRow}
    slack::Vector{Float64}           # y_envelope − y_caso, no `x` escolhido
    per_case::Vector{SizingResult}   # dimensionamento individual de cada caso
end

"Constrói um [`EnvelopeResult`](@ref) inviável com diagnóstico."
function infeasible_envelope(message::AbstractString; case_names = String[],
                             rows = EnvelopeRow[], per_case = SizingResult[],
                             ceiling = NaN, ceiling_case = "",
                             ceiling_mechanism = :none)
    EnvelopeResult(false, String(message), NaN, NaN, Dict{Symbol,Float64}(), :none, "",
                   ceiling, ceiling_case, ceiling_mechanism, case_names, rows,
                   Float64[], per_case)
end
