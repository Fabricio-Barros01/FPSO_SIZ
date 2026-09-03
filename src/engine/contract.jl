"""
O contrato entre um método de dimensionamento e o motor de envelope — a versão que não
sabe o que é um vaso.

Até o Sprint 6 o motor era genérico sobre o **equipamento** e específico sobre a
**grandeza**: aceitava qualquer `AbstractEquipment`, mas o corpo do laço dizia
`max(c.d_leff_gas/d, c.d2_leff/d²)`, a linha da varredura se chamava `d_mm`, e o
resultado tinha `lss_m` e `sr`. Isso basta para dois vasos e não basta para mais nada:
uma bomba não tem esbeltez, um trocador não tem teto de decantação, e nenhum dos dois
varre diâmetro de casco.

Escrever uma tela por equipamento resolveria — e duplicaria formulário, gerenciamento de
arquivos, memorial, exportação e guarda de origem, perdendo o multi-caso em cada cópia.
Então generaliza-se o eixo, e a regra que o projeto já tinha para os parâmetros —
*a interface nunca cita um parâmetro pelo nome* — passa a valer também para as grandezas.

# A forma que todo dimensionamento deste programa tem

    para cada x da grade:
        y(x) = max sobre os casos de  requirement(m, x, restrições_do_caso)
        d(x) = derived(m, x, y, ...)          # o que se deriva de (x, y)
        admissível se x ≤ ceiling e admissible(m, ...)
    escolhe-se o x admissível que minimiza objective(m, ...)

Preenchida com vaso: `x` é o diâmetro, `y` é o `Leff` exigido, `derived` dá `Lss`, `SR` e
volume, `ceiling` é o teto de decantação e `objective` é `|SR − alvo|`. Preenchida com
bomba: `x` é o diâmetro nominal da tubulação, `y` é a carga do sistema, `derived` dá
velocidade, Reynolds, NPSH e potência, não há teto e `objective` é o menor DN.

# Os hooks

| hook | quem despacha | tem default? |
|---|---|---|
| [`case_input`](@ref) | o método | sim — `StreamState` |
| [`sweep_axis`](@ref) | o método | não |
| [`requirement`](@ref) | as **restrições** | vaso, em `constraints.jl` |
| [`governing_of`](@ref) | as restrições | idem |
| [`ceiling_of`](@ref) | as restrições | sim — `Inf` |
| [`derived`](@ref) | o método | não |
| [`admissible`](@ref) | o método | não |
| [`objective`](@ref) | o método | não |
| [`result_fields`](@ref) | o método | não |
| [`sweep_columns`](@ref) | o método | não |
| [`trace_blocks`](@ref) | o método | sim — ordem de aparição |

`requirement`, `governing_of` e `ceiling_of` despacham no **tipo das restrições**, e não
no do método. É de propósito: quem produz um [`VesselConstraints`](@ref) ganha o
comportamento de vaso inteiro sem declarar nada — foi assim que o vaso bifásico do
Sprint 5 nasceu com nove linhas de física e nenhuma de varredura.
"""

# ---------------------------------------------------------------------------
# Descritores de apresentação
# ---------------------------------------------------------------------------

"""
O eixo de varredura: o que o cursor da tela move e o que vai no eixo x dos gráficos.

`values` é a grade já materializada, porque é ela que o motor percorre e a tela oferece —
as duas têm de ser a mesma lista, ou o cursor aponta para um ponto que não foi calculado.
"""
struct SweepAxis
    key::Symbol            # :d, :dn, :n_tubos
    label::String          # "diâmetro"
    unit::String           # "mm"
    values::Vector{Float64}
end

"""
Um campo do cartão de resultados.

`value` é número **ou** texto: "capacidade de gás" e o nome do caso governante não são
grandezas, e forçá-los a virar código numérico só criaria uma tabela de tradução a mais.
Número é formatado pela interface (`Formato.num`, com `digits` casas), porque a regra
PT-BR existe uma vez só e ela mora lá.

`status` é `:neutro`, `:ok` ou `:erro` — o sinal de que **este campo** aprova ou reprova
o projeto, que a tela pinta e marca com ✓/✗. Existe porque a esbeltez fora da banda era
o aviso mais direto de que o vaso não fecha naquele diâmetro, e ele não pode depender de
a interface saber que existe uma grandeza chamada esbeltez.
"""
struct ResultField
    label::String
    value::Union{Float64,String}
    unit::String
    digits::Int
    highlight::Bool
    status::Symbol
end

ResultField(label, value; unit = "", digits = 2, highlight = false,
            status::Symbol = :neutro) =
    ResultField(String(label), value isa AbstractString ? String(value) : float(value),
                String(unit), digits, highlight, status)

"""
Uma coluna da tabela de varredura, e da varredura exportada em CSV.

`key` é `:x`, `:y` ou o nome de um derivado. `label` já traz a unidade, porque é
cabeçalho de tabela e não rótulo de campo.
"""
struct SweepColumn
    label::String          # "d (mm)"
    key::Symbol            # :x | :y | chave de `derivados`
    digits::Int
end

SweepColumn(label, key; digits = 2) = SweepColumn(String(label), Symbol(key), digits)

# ---------------------------------------------------------------------------
# Os hooks
# ---------------------------------------------------------------------------

"""
    case_input(m, vals) -> entrada

Traduz o dicionário de um caso na estrutura que a física do método consome.

O default é a [`StreamState`](@ref) de três fases, filtrada pelas
[`stream_keys`](@ref) do método — é o que os vasos usam. Um equipamento cujas entradas
não são correntes de óleo/água/gás (uma bomba pede vazão, comprimento de linha e Σk)
devolve a sua própria estrutura, e nada acima disto precisa saber qual é.

Lança `ArgumentError` para entrada ausente ou inválida; o motor converte em
inviabilidade com o nome do caso.
"""
case_input(m::AbstractSizingMethod, vals::AbstractDict) =
    stream_from_case(vals; required = stream_keys(m))

"""
    sweep_axis(m, p) -> SweepAxis

A grade que o motor percorre, com o rótulo e a unidade que a tela mostra no cursor e no
eixo x dos gráficos. `p` são os parâmetros já mesclados com os defaults.
"""
function sweep_axis end

"""
    requirement(m, x, cons) -> Float64

A grandeza envelopada: quanto este caso exige, no ponto `x` do eixo.

É a única coisa que o motor toma o máximo entre casos, e por isso é a única que precisa
ser "maior = mais exigente". Para um vaso é o `Leff`; para uma bomba, a carga do sistema.
"""
function requirement end

"""
    governing_of(m, x, cons) -> Symbol

Qual restrição está governando em `x` — o que o cartão e o CSV mostram na coluna
"governa". Símbolo livre; quem o traduz para texto é [`result_fields`](@ref).
"""
function governing_of end

"""
    ceiling_of(m, cons) -> Float64

Teto do eixo imposto pela física deste caso, ou `Inf` se o método não impõe nenhum.

O default é `Inf`: a maioria dos equipamentos não tem um. O vaso trifásico tem (o teto
de decantação das Eq. 19/21) e o declara em `constraints.jl`.
"""
ceiling_of(::AbstractSizingMethod, cons) = Inf

"""
    derived(m, x, y, gov, cons, k, p) -> Dict{Symbol,Float64}

O que se deriva do par `(x, y)` — tudo que a tela mostra além dos dois eixos.

Num vaso: `:lss`, `:sr` e `:volume`. Numa bomba: `:v`, `:re`, `:f`, `:npsh`, `:potencia`.
As chaves são as mesmas que [`sweep_columns`](@ref) e [`result_fields`](@ref) citam.
"""
function derived end

"""
    admissible(m, x, der, p) -> Bool

Se o ponto `x`, com os derivados `der`, é aceitável. O teto de
[`ceiling_of`](@ref) já foi aplicado antes e não precisa ser reconferido aqui.

Num vaso é a banda de esbeltez; numa bomba, a banda de velocidade superficial mais a
margem de NPSH.
"""
function admissible end

"""
    objective(m, x, der, p) -> Float64

O critério de desempate entre os pontos **já admissíveis**; o motor escolhe o de menor
valor. Num vaso, `|SR − alvo|`; numa bomba, o próprio DN (o menor é o mais barato).
"""
function objective end

"""
    selection_message(m, rows, ceiling, p) -> String

Por que o conjunto admissível ficou vazio — a frase que a tela mostra no lugar do
resultado. Recebe todas as linhas calculadas, para poder dizer entre que valores a
grandeza ficou em vez de só constatar o vazio.
"""
function selection_message end

"""
    result_fields(m, r) -> Vector{ResultField}

O cartão de resultados, na ordem em que a tela o mostra.

Este hook é o que faz a coluna da direita deixar de ser oito `<dt>` escritos à mão em
`index.html`. Quem sabe que um vaso tem esbeltez e uma bomba tem NPSH é o método; a tela
itera e desenha, do mesmo jeito que já faz com o formulário desde o Sprint 0.
"""
function result_fields end

"""
    sweep_columns(m) -> Vector{SweepColumn}

As colunas da tabela de varredura da tela e do CSV exportado — as mesmas nos dois, para
que o arquivo e a tela não possam divergir.
"""
function sweep_columns end

"""
    trace_blocks(m) -> Vector{Pair{Symbol,String}}

Os blocos do memorial, na ordem do cálculo, com o título que a tela mostra.

Vazio (o default) significa "sem ordem declarada": a interface agrupa pela ordem de
aparição no rastro e usa o próprio símbolo como título. É um default que funciona — um
método novo ganha memorial legível sem escrever nada — e que se substitui assim que os
títulos merecerem português.
"""
trace_blocks(::AbstractSizingMethod) = Pair{Symbol,String}[]

"""
    global_keys(m) -> Vector{Symbol}

Os parâmetros que são **decisão de projeto**, e não dado de corrente: a grade que se
varre e a banda que se aceita. A interface os tira do formulário por caso e os põe num
painel único, porque repeti-los em cada caso sugeriria que se pode ter uma grade por
corrente — e não se pode, o equipamento é um só.

Vazio (o default) significa "nenhum": um método cujas escolhas de projeto estejam todas
nas constantes do TOML não mostra painel de ajustes, em vez de mostrar um painel vazio.
"""
global_keys(::AbstractSizingMethod) = Symbol[]

"""
    column_value(row, col) -> Float64

Lê de uma linha de varredura o valor que a coluna pede. `:x` e `:y` são os dois eixos;
qualquer outra chave vem dos derivados, e uma chave que o método não produziu vira `NaN`
— que a interface mostra como travessão, em vez de zero, que seria um número.
"""
column_value(row, col::SweepColumn) =
    col.key === :x ? row.x :
    col.key === :y ? row.y : get(row.derivados, col.key, NaN)

"Lê um derivado pelo nome, com `NaN` para o que o método não produziu."
der(r, k::Symbol) = get(r.derivados, k, NaN)
