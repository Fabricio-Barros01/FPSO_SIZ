"""
As interfaces que sustentam a extensibilidade do projeto.

Regra: a GUI **nunca** cita um parâmetro pelo nome. Ela itera sobre os
[`ParameterSpec`](@ref) que o método declara e monta o formulário sozinha.
Registrar um novo equipamento no core (bomba, tratador, trocador, vaso flash) faz a
tela aparecer sem editar uma linha de `app/`.
"""

abstract type AbstractEquipment end
abstract type AbstractSizingMethod end

"""
    ParameterSpec

Descritor de um parâmetro de entrada — é **dado**, não código, e vem dos TOML em
`config/`. Carrega o que a GUI precisa para renderizar e validar o campo, e a
proveniência que o memorial de cálculo precisa para citar a fonte.
"""
struct ParameterSpec
    key::Symbol
    label::String        # rótulo PT-BR exibido na GUI
    unit::String         # unidade exibida junto ao campo
    default::Float64
    min::Float64
    max::Float64
    advanced::Bool       # se true, fica atrás do toggle "avançado"
    note::String         # proveniência: equação, tabela, referência
end

"Valida um valor contra o descritor. Devolve `nothing` se ok, ou a mensagem de erro."
function validate(spec::ParameterSpec, value::Real)
    isfinite(value) || return "$(spec.label): valor não numérico"
    value < spec.min && return "$(spec.label): abaixo do mínimo ($(spec.min) $(spec.unit))"
    value > spec.max && return "$(spec.label): acima do máximo ($(spec.max) $(spec.unit))"
    return nothing
end

"""
    validate(specs, values) -> Vector{String}

Valida um dicionário de valores contra os descritores. Devolve todas as mensagens de
erro encontradas (vazio = tudo válido). Não lança: a GUI destaca os campos.
"""
function validate(specs::Vector{ParameterSpec}, values::AbstractDict)
    msgs = String[]
    for spec in specs
        haskey(values, spec.key) || continue
        m = validate(spec, values[spec.key])
        m === nothing || push!(msgs, m)
    end
    return msgs
end

"Dicionário `key => default` a partir dos descritores."
defaults(specs::Vector{ParameterSpec}) = Dict{Symbol,Float64}(s.key => s.default for s in specs)

"Mescla os valores fornecidos sobre os defaults, ignorando chaves desconhecidas."
function with_defaults(specs::Vector{ParameterSpec}, values::AbstractDict)
    out = defaults(specs)
    known = Set(s.key for s in specs)
    for (k, v) in values
        Symbol(k) in known && (out[Symbol(k)] = float(v))
    end
    return out
end

# ---------------------------------------------------------------------------
# Contrato que todo método de dimensionamento implementa
# ---------------------------------------------------------------------------

"Identificador estável do método (usado em resultados e arquivos)."
function method_id end

"Rótulo legível, exibido na GUI."
function label end

"Descritores dos parâmetros do método."
function parameters end

"Tipo de equipamento a que o método se aplica."
function applies_to end

"""
    size_equipment(equipment, method, stream, params) -> SizingResult

Dimensiona `equipment` pelo `method`, para a corrente `stream`, com `params`
(dicionário `Symbol => Float64` já validado). Nunca lança por inviabilidade —
devolve `SizingResult` com `feasible = false`.
"""
function size_equipment end
