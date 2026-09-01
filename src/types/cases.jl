"""
Casos e intervalos — a entrada do motor de envelope.

O diferencial do software: qualquer entrada escalar pode ser dada como um
[`Interval`](@ref) em vez de um número. Intervalos são expandidos em **casos de
canto** (produto cartesiano dos extremos) antes do dimensionamento.

Por que cantos e não "o pior valor": as restrições de Stewart & Arnold não são
monótonas em cada entrada isoladamente — o bloco de decantação depende da razão
`Aw/A` e das viscosidades, então o pior caso pode estar num canto misto (ex.: `Q_w`
máximo com `µ_o` mínimo). Enumerar os cantos é correto por construção.
"""

"""
    Interval(lo, hi)

Faixa de valores para uma entrada. `lo` e `hi` são ordenados na construção.
"""
struct Interval
    lo::Float64
    hi::Float64
    function Interval(lo, hi)
        lo, hi = float(lo), float(hi)
        lo > hi && ((lo, hi) = (hi, lo))
        new(lo, hi)
    end
end

Base.show(io::IO, i::Interval) = print(io, "[", i.lo, ", ", i.hi, "]")

"Um valor de entrada: escalar fixo ou faixa."
const InputValue = Union{Float64, Interval}

"Extremos de um valor de entrada (um escalar tem um só extremo)."
corners(x::Float64)  = (x,)
corners(i::Interval) = i.lo == i.hi ? (i.lo,) : (i.lo, i.hi)

"""
    Case(name, values; enabled = true)

Um caso de operação: um nome e o conjunto completo de entradas, cada uma escalar ou
[`Interval`](@ref).
"""
struct Case
    name::String
    values::Dict{Symbol,InputValue}
    enabled::Bool
end
Case(name, values::Dict{Symbol,<:Any}; enabled = true) =
    Case(String(name), Dict{Symbol,InputValue}(k => _asvalue(v) for (k, v) in values), enabled)

_asvalue(v::Interval) = v
_asvalue(v::Real)     = float(v)
_asvalue(v::Tuple{<:Real,<:Real}) = Interval(v[1], v[2])
_asvalue(v::AbstractVector) = length(v) == 2 ? Interval(v[1], v[2]) :
    throw(ArgumentError("faixa deve ter exatamente 2 elementos [min, max]; recebi $(length(v))"))

"Chaves cujo valor é uma faixa, em ordem determinística."
interval_keys(c::Case) = sort!([k for (k, v) in c.values if v isa Interval && v.lo != v.hi])

"Número de casos de canto que este caso gera."
corner_count(c::Case) = 2^length(interval_keys(c))

"Conjunto de casos a dimensionar em conjunto."
struct CaseSet
    cases::Vector{Case}
end
CaseSet() = CaseSet(Case[])

active(cs::CaseSet) = filter(c -> c.enabled, cs.cases)

"Total de casos de canto que o conjunto ativo gera."
corner_count(cs::CaseSet) = sum(corner_count, active(cs); init = 0)

"""
    expand(cs::CaseSet; max_corners = 256)

Expande cada caso ativo nos seus casos de canto. Devolve um vetor de
`(nome, Dict{Symbol,Float64})`, onde o nome ganha um sufixo identificando o canto
quando o caso original tinha faixas.

Lança `ArgumentError` se o total exceder `max_corners` — a GUI usa isso para avisar
antes de rodar.
"""
function expand(cs::CaseSet; max_corners::Int = 256)
    total = corner_count(cs)
    total == 0 && return Tuple{String,Dict{Symbol,Float64}}[]
    total > max_corners && throw(ArgumentError(
        "expansão geraria $total casos de canto (limite $max_corners). " *
        "Reduza o número de entradas dadas como faixa."))

    out = Tuple{String,Dict{Symbol,Float64}}[]
    for c in active(cs)
        keys_iv = interval_keys(c)
        if isempty(keys_iv)
            push!(out, (c.name, Dict{Symbol,Float64}(k => _scalar(v) for (k, v) in c.values)))
            continue
        end
        for combo in Iterators.product((corners(c.values[k]) for k in keys_iv)...)
            vals = Dict{Symbol,Float64}(k => _scalar(v) for (k, v) in c.values)
            tags = String[]
            for (k, v) in zip(keys_iv, combo)
                vals[k] = v
                iv = c.values[k]::Interval
                push!(tags, string(k, v == iv.lo ? "↓" : "↑"))
            end
            push!(out, (string(c.name, " [", join(tags, " "), "]"), vals))
        end
    end
    return out
end

_scalar(v::Float64)  = v
_scalar(i::Interval) = i.lo   # só alcançado para faixas degeneradas (lo == hi)
