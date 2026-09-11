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

# `group`: o descritor que se repete

`:none` (o default) é um campo avulso — um por caso, e é o que os cinco primeiros
métodos têm. Um `group` diferente de `:none` diz que este campo pertence a uma
**instância repetível**: a Análise Pinch pede N correntes, cada uma com as mesmas três
grandezas, e N é do usuário.

É **atributo**, e não um tipo irmão, por uma razão mecânica. `test/architecture.jl:112`
itera `vcat(parameters(m), stream_parameters(m))` esperando `Vector{ParameterSpec}`, e é
essa iteração que confere rótulo, unidade, proveniência e faixa de **todo** campo do
programa. Um `GroupSpec` sairia silenciosamente dessa cobertura: os campos de corrente
ficariam sem verificação nenhuma e a guarda continuaria verde — uma guarda que fica verde
verificando menos é pior que uma guarda que falha.

O que se repete é o **descritor**; o que o método declara em [`parameters`](@ref) é o
**molde**, um por grandeza. Quem expande o molde nas N instâncias é a camada que sabe
quanto vale N — ver [`group_instance`](@ref) e [`instance_key`](@ref).

# `instance`: molde ou campo concreto

`0` é o molde que o método declara; `≥ 1` é a instância que o formulário desenha. Os
dois carregam o **mesmo** `group`, e é por isso que são dois campos e não um: a
instância precisa continuar sendo reconhecível como campo de grupo (é o que lhe dá uma
caixa só, ver [`single_box`](@ref)) e ao mesmo tempo não pode ser expandida de novo.
Apagar o grupo na expansão resolveria o segundo problema criando o primeiro — e o
primeiro é a restrição dura da contagem de cantos.
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
    group::Symbol        # :none = campo avulso; outro = pertence a um grupo repetível
    instance::Int        # 0 = molde declarado pelo método; ≥1 = campo concreto da tela
end

"""
Forma de oito argumentos — um campo avulso, `group = :none`, `instance = 0`.

Existe para que as ~19 construções posicionais que já havia (o parser de
`config.jl`, os três helpers de reetiquetagem de `two_phase.jl`, `moran.jl` e
`electrostatic.jl`, e os quinze descritores fictícios de `test/`) continuem
compilando sem uma linha de mudança. Acrescentar campo a um `struct` sem isto obrigaria
a reescrever todas elas, e cada reescrita é uma chance de trocar um `min` por um `max`
em silêncio.
"""
ParameterSpec(key, label, unit, default, min, max, advanced, note) =
    ParameterSpec(key, label, unit, default, min, max, advanced, note, :none, 0)

"Forma de nove argumentos — o molde de um campo de grupo, ainda não instanciado."
ParameterSpec(key, label, unit, default, min, max, advanced, note, group) =
    ParameterSpec(key, label, unit, default, min, max, advanced, note, group, 0)

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
# Descritores repetíveis: o molde e as suas instâncias
# ---------------------------------------------------------------------------

"""
    instance_key(group, i, key) -> Symbol

A chave da `i`-ésima instância do campo `key` do grupo `group` — `:corrente_2_t_in`.

Esta função é a **única** convenção de nome entre as três camadas que precisam
concordar: o formulário, que escreve a caixa; [`case_input`](@ref), que lê o caso de
volta; e o arquivo de casos em disco, que guarda a chave literal. Escrevê-la em três
lugares seria três oportunidades de discordar, e a discórdia apareceria como um caso que
salva e reabre com uma corrente a menos.
"""
instance_key(group::Symbol, i::Integer, key::Symbol) = Symbol(group, "_", i, "_", key)

"Verdadeiro se o descritor pertence a um grupo repetível — molde ou instância."
in_group(s::ParameterSpec) = s.group !== :none

"Verdadeiro se é o **molde** que o método declara, ainda não expandido."
is_template(s::ParameterSpec) = in_group(s) && s.instance == 0

"""
    group_instance(s, i; prefixo) -> ParameterSpec

O molde `s` vestido de `i`-ésima instância: chave sintetizada, rótulo prefixado e
`instance = i`.

Expandir uma instância é erro de programação, não de dado, e por isso lança: o resultado
seria `:corrente_2_corrente_2_t_in`, uma chave que nenhum caso tem e que sumiria do
formulário sem nada denunciar.
"""
function group_instance(s::ParameterSpec, i::Integer; prefixo::AbstractString = "")
    is_template(s) ||
        throw(ArgumentError("group_instance espera um molde de grupo; recebi " *
                            "'$(s.key)' (group = $(s.group), instance = $(s.instance))"))
    i >= 1 || throw(ArgumentError("instância tem de ser ≥ 1; recebi $i"))
    return ParameterSpec(instance_key(s.group, i, s.key),
                         (isempty(prefixo) ? "" : "$prefixo $i — ") * s.label,
                         s.unit, s.default, s.min, s.max, s.advanced, s.note,
                         s.group, Int(i))
end

"""
    single_box(s) -> Bool

Se a tela dá **uma** caixa a este campo, em vez do par mín/máx.

Campo de grupo dá uma só, e isto é restrição dura, não estética. `app/public/app.js`
oferece duas caixas a todo descritor de `st.campos`, e `src/types/cases.jl` expande cada
par com `mín ≠ máx` num canto — com `max_corners = 256` e três campos por corrente, seis
correntes dadas como faixa já estouram o limite. A contagem de cantos não pode crescer
com o número de correntes: uma rede de dez correntes é **um** problema de pinch, não
2¹⁰ deles.

Quem quiser varrer a incerteza de uma corrente usa o que o programa já tem para isso —
um caso por cenário, que é o motor de envelope.
"""
single_box(s::ParameterSpec) = in_group(s)

"""
    parameter_groups(m) -> Vector{NamedTuple}

Os grupos de campos repetíveis que o método declara: `key`, `label`, `min` e `max`
instâncias. Vazio (o default) significa "nenhum" — é o caso dos cinco primeiros métodos.

Devolve `NamedTuple`, e não um tipo próprio, pelo motivo registrado em
[`ParameterSpec`](@ref): um tipo irmão sairia da cobertura da guarda de proveniência.
O que este valor carrega é o **cabeçalho** do grupo (como se chama, quantas instâncias
são admitidas); os campos continuam sendo `ParameterSpec`, e continuam dentro da guarda.
"""
parameter_groups(::AbstractSizingMethod) =
    @NamedTuple{key::Symbol, label::String, min::Int, max::Int}[]

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
