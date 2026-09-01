"""
Registro de equipamentos e métodos.

Um método declarado **fora** de `src/` (num plugin, num teste, no 2º plano) aparece na
GUI só por chamar [`register!`](@ref). É o mecanismo que faz bomba, tratador,
trocador e vaso flash entrarem por adição, sem tocar em `app/`.
"""

const _EQUIPMENT = Dict{Symbol,AbstractEquipment}()
const _METHODS   = Dict{Symbol,Vector{AbstractSizingMethod}}()

"""
    register!(equipment)
    register!(method)

Registra um equipamento ou um método de dimensionamento. Idempotente: registrar o
mesmo `method_id` de novo substitui o anterior.
"""
function register!(eq::AbstractEquipment)
    _EQUIPMENT[method_id(eq)] = eq
    get!(_METHODS, method_id(eq), AbstractSizingMethod[])
    return eq
end

function register!(m::AbstractSizingMethod)
    eq_id = method_id(applies_to(m))
    list = get!(_METHODS, eq_id, AbstractSizingMethod[])
    idx = findfirst(x -> method_id(x) === method_id(m), list)
    idx === nothing ? push!(list, m) : (list[idx] = m)
    return m
end

"Equipamentos registrados, em ordem de id."
equipments() = [_EQUIPMENT[k] for k in sort!(collect(keys(_EQUIPMENT)))]

"Métodos registrados para um equipamento."
methods_for(eq::AbstractEquipment) = get(_METHODS, method_id(eq), AbstractSizingMethod[])
methods_for(eq_id::Symbol)         = get(_METHODS, eq_id, AbstractSizingMethod[])

"Busca um equipamento pelo id; `nothing` se não registrado."
equipment(id::Symbol) = get(_EQUIPMENT, id, nothing)

"Busca um método pelo id dentro de um equipamento; `nothing` se não registrado."
function sizing_method(eq_id::Symbol, m_id::Symbol)
    for m in methods_for(eq_id)
        method_id(m) === m_id && return m
    end
    return nothing
end

"Limpa o registro. Só para testes."
function _reset_registry!()
    empty!(_EQUIPMENT)
    empty!(_METHODS)
    return nothing
end
