"""
O contrato entre um método de dimensionamento e o motor de envelope.

Este arquivo existe porque o motor multi-caso — o diferencial do software — estava
escrito sobre os tipos concretos do separador: `size_envelope(::Separator,
::StewartArnold, …)`, com o corpo lendo o TOML do separador, montando um vetor de
`SeparatorConstraints` e chamando `separator_constraints`. Um segundo equipamento
registrado ganharia formulário e dimensionamento de caso único, e **perderia o
multi-caso**, sem que nada denunciasse a perda.

A generalização é pequena porque a costura já existia. Os blocos de Stewart & Arnold
produzem **três números que não dependem de `d`**, e é só disso que o motor precisa:

    Leff_exigido(d) = max( d·Leff/d , d²·Leff/d² )      # gás, líquido
    d admissível    ⟺ d ≤ d_max

Qualquer método que consiga responder essas três coisas atravessa o motor inteiro —
grade comum, envelope de `Leff(d)`, teto mais restritivo, escolha por `|SR − alvo|` —
sem que o motor saiba de que equipamento se trata.

# O que um método implementa

| Função | Papel |
|---|---|
| [`sizing_constraints`](@ref) | os três números, mais o rastro de cálculo |
| [`method_config`](@ref) | qual TOML de `config/` carrega as constantes |
| [`lss_from`](@ref) | como `Lss` sai de `Leff` (tem default, ver abaixo) |

Mais os quatro de `src/interfaces.jl` (`method_id`, `label`, `parameters`,
`applies_to`) e o `size_equipment` do caso único — que a família resolve com uma linha
delegando a [`size_vessel`](@ref).

# Os seis descritores que o motor exige por nome

A regra de `src/interfaces.jl` — *a interface nunca cita um parâmetro pelo nome* — é
sobre a **tela**, não sobre o motor. O motor cita seis, e é melhor que estejam escritos
aqui do que descobertos por `KeyError`: `d_min`, `d_max` e `d_step` definem a grade de
varredura, e `sr_min`, `sr_max` e `sr_target` a banda de esbeltez e o alvo dentro dela.
Todo método que atravesse este contrato tem de declará-los em `parameters(m)`. Quem usa
o [`lss_from`](@ref) default precisa, além disso, de `lss_liquid_factor` nas constantes
do seu TOML.
"""

"""
As restrições que não dependem do diâmetro — o que o motor de envelope consome.

`d_leff_gas` [mm·m] é o produto exigido pelo bloco de capacidade de gás; `d2_leff`
[mm²·m] o exigido pelo bloco de capacidade de líquido; `d_max_mm` o teto de diâmetro e
`mechanism` o que o impôs.

Três campos admitem "não se aplica", e é o que permite um mesmo motor servir a vasos
diferentes:

- `d_max_mm = Inf` — o método não impõe teto. Um vaso bifásico não tem decantação
  líquido-líquido, então não tem o que limitar o diâmetro por cima;
- `mechanism = :none` — sem teto, não há mecanismo a nomear;
- `beta` e `aw_over_a` = `NaN` — geometria de três camadas, que só o trifásico tem.

`NaN` e não `0.0` de propósito: zero é um β possível (fase aquosa ocupando toda a
metade inferior, que o trifásico recusa com mensagem própria), e usá-lo como "ausente"
faria um desenho errado passar por desenho válido. `NaN` se propaga e aparece.
"""
struct VesselConstraints
    d_leff_gas::Float64
    d2_leff::Float64
    d_max_mm::Float64
    mechanism::Symbol
    beta::Float64
    aw_over_a::Float64
end

"Construtor para um método sem teto de decantação nem geometria de três camadas."
VesselConstraints(d_leff_gas, d2_leff) =
    VesselConstraints(d_leff_gas, d2_leff, Inf, :none, NaN, NaN)

"""
    sizing_constraints(m, s::StreamState, p, k) -> (ok::Bool, resultado, trace)

Avalia os blocos do método `m` para a corrente `s`. Em caso de sucesso `resultado` é um
[`VesselConstraints`](@ref); em caso de falha, a **mensagem diagnóstica** — nunca uma
exceção, que é o contrato do projeto inteiro: inviabilidade é estado retornado.

`p` são os parâmetros já mesclados com os defaults e `k` as constantes do TOML.
"""
function sizing_constraints end

"""
    method_config(m) -> Dict

O TOML de `config/` de onde saem as constantes e os descritores do método. Existe para
que o motor de envelope carregue as constantes **do método que recebeu**, em vez de as
do separador.
"""
function method_config end

"""
    lss_from(m, d_mm, leff, gov, k) -> Float64

Comprimento real `Lss` a partir do `Leff` exigido, em metros.

O default implementa a relação de Stewart & Arnold, e é o que separador trifásico e
vaso bifásico compartilham: quando o **gás** governa, `Lss = Leff + d` (Eq. 15) — a
gotícula ainda precisa do trecho de entrada e do extrator de névoa; quando o **líquido**
governa, `Lss = f·Leff` (Eq. 23), com `f` no TOML do método.

Não é uma lei universal: é a geometria desta família de vasos. Um método com outra
geometria define o seu próprio — é para isso que a função é despachada pelo método, e
não uma constante lida pelo motor.
"""
lss_from(::AbstractSizingMethod, d_mm::Real, leff::Real, gov::Symbol, k::AbstractDict) =
    gov === :gas ? leff + d_mm / 1000.0 : float(k[:lss_liquid_factor]) * leff

# ---------------------------------------------------------------------------
# Geometria a partir das restrições — comum a qualquer método que as produza
# ---------------------------------------------------------------------------

"Grade de diâmetros da varredura, em mm."
diameter_grid(p::AbstractDict) = collect(p[:d_min]:p[:d_step]:p[:d_max])

"""
    sweep_row(m, d_mm, cons, k, sr_min, sr_max) -> SweepRow

Geometria para um diâmetro: o `Leff` governante, o `Lss` pela relação do bloco que
governa e a esbeltez `SR = Lss/d`.
"""
function sweep_row(m::AbstractSizingMethod, d_mm::Real, cons::VesselConstraints,
                   k::AbstractDict, sr_min::Real, sr_max::Real)
    leff_gas = cons.d_leff_gas / d_mm
    leff_liq = cons.d2_leff / d_mm^2
    gov      = leff_gas > leff_liq ? :gas : :liquid
    leff     = max(leff_gas, leff_liq)
    lss      = lss_from(m, d_mm, leff, gov, k)
    sr       = lss / (d_mm / 1000.0)
    return SweepRow(d_mm, leff_gas, leff_liq, leff, lss, sr, gov, sr_min <= sr <= sr_max)
end

"""
    selection_diagnosis(rows, d_max, mechanism, sr_min, sr_max) -> String

Explica **por que** o conjunto admissível ficou vazio: se foi o teto de diâmetro ou a
banda de esbeltez. É o que a tela mostra no lugar do resultado.
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

"Rótulo PT-BR do mecanismo que impôs o teto de diâmetro."
mechanism_label(m::Symbol) = m === :water_in_oil ? "água em óleo" :
                             m === :oil_in_water ? "óleo em água" :
                             m === :none         ? "sem teto de decantação" : String(m)

# ---------------------------------------------------------------------------
# Dimensionamento de caso único, comum à família
# ---------------------------------------------------------------------------

"""
    size_vessel(eq, m, s::StreamState, params) -> SizingResult

Dimensiona um vaso de caso único a partir das restrições que `m` produz: varre a grade
de diâmetros, descarta o que passa do teto ou sai da banda de esbeltez, e escolhe o de
`SR` mais próximo do alvo.

Nada aqui é do separador — é a mesma sequência para qualquer vaso cujas restrições
caibam em [`VesselConstraints`](@ref). Um método a adota com uma linha:

    size_equipment(eq::MeuVaso, m::MeuMetodo, s, params) = size_vessel(eq, m, s, params)

Inviabilidade sai como `feasible = false` com a mensagem que
[`selection_diagnosis`](@ref) escreve, nunca como exceção.
"""
function size_vessel(eq::AbstractEquipment, m::AbstractSizingMethod,
                     s::StreamState, params::AbstractDict)
    p = with_defaults(parameters(m), params)
    k = constants(method_config(m))

    ok, cons, tr = sizing_constraints(m, s, p, k)
    ok || return infeasible(method_id(m), cons; trace = tr)

    grid = diameter_grid(p)

    isempty(grid) && return infeasible(method_id(m),
        "Grade de diâmetros vazia: verifique d_min ($(p[:d_min])), " *
        "d_max ($(p[:d_max])) e passo ($(p[:d_step])).";
        trace = tr, d_max_mm = cons.d_max_mm, d_max_mechanism = cons.mechanism)

    sweep = [sweep_row(m, d, cons, k, p[:sr_min], p[:sr_max]) for d in grid]
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
