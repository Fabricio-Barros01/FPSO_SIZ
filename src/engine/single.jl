"""
Dimensionamento de **caso único** — a mesma varredura do motor de envelope, com um caso.

Existe separado de `engine/envelope.jl` porque os dois têm papéis diferentes: o envelope
entrega o equipamento que atende a N correntes, e este entrega o que cada corrente
pediria sozinha. O segundo é o que o memorial mostra caso a caso (a linha "→ d = … mm"
no fim de cada bloco) e o que torna visível a folga que o envelope impôs.

O corpo não cita nenhuma grandeza: é `sweep_axis` → `requirement` → `derived` →
`case_admissible`/`admissible` → `objective`, os hooks de `contract.jl`. Até o Sprint 6 ele se chamava
`size_vessel` e vivia em `sizing/constraints.jl`, com o `Lss` e a esbeltez escritos no
corpo. Continua existindo com esse nome — [`size_vessel`](@ref) é hoje um apelido da
família dos vasos —, mas quem não é vaso adota o mesmo caminho com uma linha.
"""

"""
    size_single(eq, m, entrada, params) -> SizingResult

Varre a grade do eixo, descarta o que passa do teto ou sai da banda, e escolhe o ponto
que minimiza [`objective`](@ref).

Inviabilidade sai como `feasible = false` com a mensagem que [`selection_message`](@ref)
escreve, nunca como exceção — é o contrato do projeto inteiro.
"""
function size_single(eq::AbstractEquipment, m::AbstractSizingMethod,
                     entrada, params::AbstractDict)
    p = with_defaults(parameters(m), params)
    k = constants(method_config(m))

    ok, cons, tr = sizing_constraints(m, entrada, p, k)
    ok || return infeasible(method_id(m), cons; trace = tr)

    eixo  = sweep_axis(m, p)
    teto  = ceiling_of(m, cons)
    mecan = ceiling_mechanism_of(m, cons)

    isempty(eixo.values) && return infeasible(method_id(m),
        strip("Grade de $(eixo.label) vazia. " * grid_hint(m, p));
        trace = tr, ceiling = teto, ceiling_mechanism = mecan)

    sweep      = [sweep_row(m, x, cons, k, p) for x in eixo.values]
    admissivel = filter(r -> r.ok, sweep)

    if isempty(admissivel)
        return infeasible(method_id(m),
            selection_message(m, sweep, teto, p; mechanism = mecan);
            sweep, trace = tr, ceiling = teto, ceiling_mechanism = mecan)
    end

    best = argmin(r -> objective(m, r.x, r.derivados, p), admissivel)
    trace_selection!(m, tr, best, p)

    return SizingResult(true, "", best.x, best.y, best.derivados, best.governing,
                        teto, mecan, method_id(m), sweep, tr)
end

"""
    sweep_row(m, x, cons, k, p) -> SweepRow

Uma linha da varredura: a exigência de cada restrição, a governante e os derivados.
"""
function sweep_row(m::AbstractSizingMethod, x::Real, cons, k::AbstractDict,
                   p::AbstractDict)
    y   = requirement(m, x, cons)
    gov = governing_of(m, x, cons)
    d   = derived(m, x, y, gov, cons, k, p)
    ok  = x <= ceiling_of(m, cons) && case_admissible(m, x, cons, p) &&
          admissible(m, x, d, p)
    return SweepRow(x, y, per_constraint(m, x, cons), d, gov, ok)
end

"""
    per_constraint(m, x, cons) -> Dict{Symbol,Float64}

A exigência de cada bloco separadamente, para o memorial e para os gráficos. O default é
vazio — um método que não queira abrir os blocos não precisa dizer nada.
"""
per_constraint(::AbstractSizingMethod, x::Real, cons) = Dict{Symbol,Float64}()

"""
    ceiling_mechanism_of(m, cons) -> Symbol

O que impôs o teto do eixo, para o cartão e para a mensagem de inviabilidade. `:none`
quando não há teto — que é o default, porque a maioria dos equipamentos não tem.
"""
ceiling_mechanism_of(::AbstractSizingMethod, cons) = :none

"""
    grid_hint(m, p) -> String

Complemento da mensagem de grade vazia, dizendo quais descritores conferir. Default
vazio: a frase genérica já nomeia o eixo, e um método que não queira detalhar não deve.
"""
grid_hint(::AbstractSizingMethod, p::AbstractDict) = ""

"""
    trace_selection!(m, tr, best, p) -> nothing

Carimba no memorial por que este ponto foi escolhido. Default: nada — a escolha já está
implícita no resultado, e um método sem critério interessante não deve inventar linha.
"""
trace_selection!(::AbstractSizingMethod, tr::CalcTrace, best, p::AbstractDict) = nothing
