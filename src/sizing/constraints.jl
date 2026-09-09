"""
A família dos vasos: a implementação do contrato de `src/engine/contract.jl` para
equipamentos que se dimensionam varrendo um diâmetro.

Os blocos de Stewart & Arnold produzem **três números que não dependem de `d`**, e é só
disso que o motor precisa:

    Leff_exigido(d) = max( d·Leff/d , d²·Leff/d² )      # gás, líquido
    d admissível    ⟺ d ≤ d_max

Quem devolve um [`VesselConstraints`](@ref) ganha, sem declarar mais nada, a varredura em
diâmetro, o `Lss`, a esbeltez, a banda, o teto e o critério de escolha. Foi assim que o
vaso bifásico do Sprint 5 nasceu com nove linhas de física e nenhuma de geometria.

# O que um método de vaso implementa

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
sobre a **tela**, não sobre o motor. A família dos vasos cita seis, e é melhor que
estejam escritos aqui do que descobertos por `KeyError`: `d_min`, `d_max` e `d_step`
definem a grade de varredura, e `sr_min`, `sr_max` e `sr_target` a banda de esbeltez e o
alvo dentro dela. Todo `AbstractVesselMethod` tem de declará-los em `parameters(m)`.
Quem usa o [`lss_from`](@ref) default precisa, além disso, de `lss_liquid_factor` nas
constantes do seu TOML.
"""

"""
Método que dimensiona um vaso: varre diâmetro, produz [`VesselConstraints`](@ref) e usa
a esbeltez como critério.

O tipo existe para que os hooks de apresentação — grade, banda, cartão, colunas, blocos
do memorial — sejam declarados **uma vez** para a família inteira, em vez de repetidos em
cada vaso. Um equipamento que não seja vaso (bomba, trocador) estende
`AbstractSizingMethod` direto e escreve os seus.
"""
abstract type AbstractVesselMethod <: AbstractSizingMethod end

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
- `beta` e `aw_over_a` = `NaN` — há uma interface líquido-líquido a repartir, que só o
  trifásico e o tratador têm.

`NaN` e não `0.0` de propósito: zero é um β possível (fase aquosa ocupando toda a
metade inferior, que o trifásico recusa com mensagem própria), e usá-lo como "ausente"
faria um desenho errado passar por desenho válido. `NaN` se propaga e aparece.

# `beta` é a altura do óleo **dentro da fração líquida**, e não dentro do vaso

`beta = h_o/d`, e o que muda entre os vasos é **até onde vai o líquido**. No trifásico e
no bifásico o vaso é meio cheio, e `β ∈ [0 , 0,5]`: o que sobra abaixo da metade é água.
Num tratador eletrostático o vaso é **cheio** (α = 1, §4.9.6), e `β ∈ [0 , 1]`: o que
sobra é água, e não há metade de gás nenhuma.

**Quem consome este campo não pode deduzir as camadas dele.** Deduzir "água = 0,5 − β,
gás = 0,5" é correto para dois dos três vasos e produz, no terceiro, uma camada de água
de altura NEGATIVA e uma fase gasosa que o equipamento não tem. Quem quiser as faixas
pergunta a [`cross_section`](@ref), que é despachada pelo método e sabe quantas fases o
vaso tem — o campo aqui é o coeficiente, não a geometria.
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
    sizing_constraints(m, entrada, p, k) -> (ok::Bool, resultado, trace)

Avalia os blocos do método `m` para a `entrada` que [`case_input`](@ref) produziu. Em
caso de sucesso `resultado` é o objeto de restrições do método (um
[`VesselConstraints`](@ref), para a família dos vasos); em caso de falha, a **mensagem
diagnóstica** — nunca uma exceção, que é o contrato do projeto inteiro: inviabilidade é
estado retornado.

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
    method_reference(m) -> String

A referência bibliográfica que o memorial exportado cita, declarada no TOML do método.

Existe porque o cabeçalho do memorial trazia "Alves & Komesu (2025)" fixo no código.
Isso estava certo enquanto havia um método; com dois, o memorial de um vaso bifásico
mandaria o leitor conferir as contas num artigo sobre separadores trifásicos. Cada
método cita a fonte que de fato o define.
"""
method_reference(m::AbstractSizingMethod) =
    String(get(method_config(m), "reference", ""))

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
# O contrato de `engine/contract.jl`, preenchido para a família dos vasos
# ---------------------------------------------------------------------------

"Grade de diâmetros da varredura, em mm."
diameter_grid(p::AbstractDict) = collect(p[:d_min]:p[:d_step]:p[:d_max])

sweep_axis(::AbstractVesselMethod, p::AbstractDict) =
    SweepAxis(:d, "diâmetro", "mm", diameter_grid(p))

# Os seis do cabeçalho deste arquivo: três da grade, três da banda de esbeltez.
global_keys(::AbstractVesselMethod) =
    [:d_min, :d_max, :d_step, :sr_min, :sr_max, :sr_target]

requirement_spec(::AbstractVesselMethod) = ("comprimento efetivo Leff", "m")

"""
Uma faixa de fase na seção transversal, do fundo para o topo.

`fase` é `:water`, `:oil` ou `:gas`; `fracao` é a **altura** fracionária que ela ocupa
(as frações somam 1). Não carrega cor: cor é apresentação e vive em `app/`.
"""
struct PhaseLayer
    fase::Symbol
    fracao::Float64
end

"""
    cross_section(m, cons) -> Vector{PhaseLayer}

Como a seção transversal se reparte entre as fases, de baixo para cima.

Substitui o β que o desenho recebia. β é a altura fracionária do óleo **num vaso meio
cheio**, e o desenho deduzia dele as três camadas — o que embutia duas hipóteses que
nem todo vaso satisfaz: que existe fase gasosa, e que o líquido para em `d/2`.

Um tratador eletrostático é **cheio de líquido**: com β no lugar de camadas, ele saía
desenhado com metade de gás em cima, mentindo sobre o equipamento na figura que o
usuário confere antes de assinar. É a mesma classe de defeito que o Sprint 5 corrigiu
quando `camadas(d, β)` nasceu — corrigida uma camada abaixo, agora no core, que é quem
sabe quantas fases o vaso tem.

Vazio (o default) significa "não sei repartir": o desenho mostra o casco sem fases, que
é honesto, em vez de inventar duas.
"""
cross_section(::AbstractSizingMethod, cons) = PhaseLayer[]

"""
    cross_section(m, c::VesselConstraints)

Os vasos meio cheios de Stewart & Arnold: três faixas quando há interface
líquido-líquido (`β` finito), duas quando não há — e em ambos os casos a metade de cima
é gás, porque é o que "meio cheio" quer dizer.
"""
function cross_section(::AbstractSizingMethod, c::VesselConstraints)
    isnan(c.beta) && return [PhaseLayer(:oil, 0.5), PhaseLayer(:gas, 0.5)]
    return [PhaseLayer(:water, 0.5 - c.beta),
            PhaseLayer(:oil, c.beta),
            PhaseLayer(:gas, 0.5)]
end

# Estes três despacham nas RESTRIÇÕES, não no método: quem produzir um
# `VesselConstraints` recebe o comportamento de vaso mesmo sem ser da família.
requirement(::AbstractSizingMethod, d_mm::Real, c::VesselConstraints) =
    max(c.d_leff_gas / d_mm, c.d2_leff / d_mm^2)

governing_of(::AbstractSizingMethod, d_mm::Real, c::VesselConstraints) =
    c.d_leff_gas / d_mm > c.d2_leff / d_mm^2 ? :gas : :liquid

ceiling_of(::AbstractSizingMethod, c::VesselConstraints) = c.d_max_mm

"""
    derived(m::AbstractVesselMethod, d_mm, leff, gov, cons, k, p)

`Lss` pela relação do bloco que governa, a esbeltez e o volume do casco entre tampos.

"Entre tampos" não é preciosismo: `vessel_volume` é o cilindro sobre `Lss`, que é a
medida costura a costura de Stewart & Arnold. Os tampos elípticos 2:1 que o desenho
mostra somariam ~8,5 %, e quem comparasse os dois sem o rótulo concluiria que um dos
dois está errado.
"""
function derived(m::AbstractVesselMethod, d_mm::Real, leff::Real, gov::Symbol,
                 cons, k::AbstractDict, p::AbstractDict)
    lss = lss_from(m, d_mm, leff, gov, k)
    return Dict{Symbol,Float64}(
        :lss    => lss,
        :sr     => lss / (d_mm / 1000.0),
        :volume => vessel_volume(d_mm, lss))
end

admissible(::AbstractVesselMethod, d_mm::Real, der::AbstractDict, p::AbstractDict) =
    p[:sr_min] <= der[:sr] <= p[:sr_max]

objective(::AbstractVesselMethod, d_mm::Real, der::AbstractDict, p::AbstractDict) =
    abs(der[:sr] - p[:sr_target])

"""
    envelope_params(m::AbstractVesselMethod, params) -> (ok, p_ou_msg)

Funde os parâmetros dos N casos num só conjunto, para que o motor tenha uma grade e uma
banda — o vaso é um só.

**A grade é união e a banda é interseção**, e a assimetria é deliberada. A grade é onde
se PROCURA: uni-la (menor `d_min`, maior `d_max`, menor passo) só amplia a busca, e
ampliar busca não perde solução. A banda é o que se ACEITA: uni-la afrouxaria a
exigência. Com um caso pedindo SR ∈ [3, 5] e outro [3,5 , 4,5], a união aceitaria um vaso
com SR = 3,2 — que viola o segundo caso. A interseção é a única leitura em que "atende a
todos os casos" continua verdadeira.

`sr_target` é PREFERÊNCIA, não restrição: é o desempate entre diâmetros já admissíveis.
Por isso a média, e não um extremo — nenhum caso tem direito de veto sobre o gosto dos
outros. Depois de fixado, é preso à banda, senão um alvo fora dela empurraria a escolha
sempre para a mesma ponta.
"""
function envelope_params(::AbstractVesselMethod, params::Vector{<:AbstractDict})
    sr_min = maximum(p[:sr_min] for p in params)
    sr_max = minimum(p[:sr_max] for p in params)
    sr_min <= sr_max || return (false,
        "As bandas de esbeltez pedidas pelos casos não se cruzam: o mais exigente pede " *
        "SR ≥ $(sr_min) e outro pede SR ≤ $(sr_max). Como o vaso é um só, não há " *
        "esbeltez que atenda a todos.")

    return (true, Dict{Symbol,Float64}(
        :d_min  => minimum(p[:d_min]  for p in params),
        :d_max  => maximum(p[:d_max]  for p in params),
        :d_step => minimum(p[:d_step] for p in params),
        :sr_min => sr_min,
        :sr_max => sr_max,
        :sr_target => clamp(sum(p[:sr_target] for p in params) / length(params),
                            sr_min, sr_max)))
end

"""
    selection_message(m::AbstractVesselMethod, rows, ceiling, p) -> String

Explica **por que** o conjunto admissível ficou vazio: se foi o teto de diâmetro ou a
banda de esbeltez. É o que a tela mostra no lugar do resultado.
"""
function selection_message(m::AbstractVesselMethod, rows, ceiling::Real,
                           p::AbstractDict; mechanism::Symbol = :none)
    under = filter(r -> r.x <= ceiling, rows)
    if isempty(under)
        return "Nenhum diâmetro da grade respeita o teto de decantação " *
               "d_max = $(round(ceiling, digits = 0)) mm " *
               "($(mechanism_label(mechanism))). Reduza d_min, ou reveja as " *
               "viscosidades e os tempos de retenção."
    end
    lo, hi = extrema(r.derivados[:sr] for r in under)
    return "Nenhum diâmetro admissível tem esbeltez na banda " *
           "$(p[:sr_min])–$(p[:sr_max]): abaixo do teto de decantação " *
           "($(round(ceiling, digits = 0)) mm) o SR varia de $(round(lo, digits = 2)) " *
           "a $(round(hi, digits = 2)). Amplie a grade de diâmetros ou a banda de SR."
end

"Rótulo PT-BR do mecanismo que impôs o teto de diâmetro."
mechanism_label(m::Symbol) = m === :water_in_oil ? "água em óleo" :
                             m === :oil_in_water ? "óleo em água" :
                             m === :none         ? "sem teto de decantação" : String(m)

"Rótulo PT-BR da restrição que governa o `Leff`."
governing_label(::AbstractVesselMethod, g::Symbol) =
    g === :gas    ? "capacidade de gás" :
    g === :liquid ? "capacidade de líquido" : String(g)

"""
    result_fields(m::AbstractVesselMethod, r) -> Vector{ResultField}

O cartão de resultados de um vaso: os mesmos oito campos que `index.html` trazia
escritos à mão até o Sprint 6, agora declarados por quem sabe que eles existem.
"""
function result_fields(m::AbstractVesselMethod, r)
    tem = r.feasible && isfinite(r.x)
    txt(v) = tem ? v : "—"
    # O ✓/✗ da esbeltez: no ponto escolhido pelo motor ela está na banda por
    # construção, mas o cartão segue o CURSOR, e o usuário pode arrastá-lo para fora.
    na_banda = !tem ? :neutro : (hasproperty(r, :ok) ? r.ok : true) ? :ok : :erro
    return ResultField[
        ResultField("Diâmetro d", tem ? r.x : NaN; unit = "mm", digits = 0,
                    highlight = true),
        ResultField("Comprimento efetivo Leff", tem ? r.y : NaN; unit = "m"),
        ResultField("Comprimento real Lss", der(r, :lss); unit = "m"),
        ResultField("Esbeltez SR", der(r, :sr); status = na_banda),
        ResultField("Volume (casco, entre tampos)", der(r, :volume);
                    unit = "m³", digits = 0),
        ResultField("Restrição governante", txt(governing_label(m, r.governing))),
        ResultField("Caso governante", txt(_driver_case(r))),
        ResultField("Teto de decantação",
                    isfinite(r.ceiling) ? r.ceiling : NaN; unit = "mm", digits = 0),
    ]
end

# Um `SizingResult` não tem caso governante — ele É um caso. O cartão é o mesmo nos dois,
# então a diferença vira travessão em vez de dois cartões quase iguais.
_driver_case(r) = hasproperty(r, :driver_case) ? r.driver_case : "—"

sweep_columns(::AbstractVesselMethod) = [
    SweepColumn("d (mm)",    :x;   digits = 0),
    SweepColumn("Leff (m)",  :y),
    SweepColumn("Lss (m)",   :lss),
    SweepColumn("SR",        :sr),
]

"""
Blocos do memorial, na ordem do cálculo, com o nome que a tela mostra.

Os símbolos são os que os métodos carimbam em cada `TraceEntry`. A ordem é a em que o
método os percorre, e não alfabética: um memorial só se lê de cima para baixo. As letras
A/B/C são as de Stewart & Arnold — o vaso bifásico usa A e C sem o B, e o bloco vazio
simplesmente não aparece.
"""
trace_blocks(::AbstractVesselMethod) = [
    :gas       => "Bloco A — capacidade de gás",
    :settling  => "Bloco B — decantação",
    :liquid    => "Bloco C — capacidade de líquido",
    :selection => "Seleção do diâmetro",
]

# ---------------------------------------------------------------------------
# Dimensionamento de caso único, comum à família
# ---------------------------------------------------------------------------

per_constraint(::AbstractSizingMethod, d_mm::Real, c::VesselConstraints) =
    Dict{Symbol,Float64}(:gas => c.d_leff_gas / d_mm, :liquid => c.d2_leff / d_mm^2)

ceiling_mechanism_of(::AbstractSizingMethod, c::VesselConstraints) = c.mechanism

grid_hint(::AbstractVesselMethod, p::AbstractDict) =
    "Verifique d_min ($(p[:d_min])), d_max ($(p[:d_max])) e passo ($(p[:d_step]))."

"""
    slenderness_equation(m) -> String

Onde a esbeltez está definida na fonte **deste** método, para o memorial citar.

Era o literal `"Eq. 24"` dentro de [`trace_selection!`](@ref), que é a numeração de
Alves & Komesu. O memorial do vaso bifásico — cuja referência declarada é o livro —
mandava o leitor conferir a esbeltez numa equação que não existe lá; o mesmo defeito
que `method_reference` corrigiu no cabeçalho no Sprint 5, sobrevivendo uma linha abaixo.

O default é um travessão, e não um palpite: um vaso novo prefere não citar nada a citar
a fonte errada.
"""
slenderness_equation(::AbstractVesselMethod) = "—"

function trace_selection!(m::AbstractVesselMethod, tr::CalcTrace, best, p::AbstractDict)
    trace!(tr, :selection, slenderness_equation(m), "SR", "Lss/(d/1000)",
           best.derivados[:sr], "–")
    trace!(tr, :selection, "—", "d escolhido",
           "menor |SR − $(p[:sr_target])| com $(p[:sr_min]) ≤ SR ≤ $(p[:sr_max])",
           best.x, "mm")
    return nothing
end

"""
    size_vessel(eq, m, s, params) -> SizingResult

Dimensiona um vaso de caso único a partir das restrições que `m` produz: varre a grade
de diâmetros, descarta o que passa do teto ou sai da banda de esbeltez, e escolhe o de
`SR` mais próximo do alvo.

É [`size_single`](@ref) sob outro nome, e o nome é o ponto: a sequência não tem nada de
vaso, mas os oito arquivos que a chamam falam de vasos, e `size_vessel(…)` lê melhor
neles do que `size_single(…)`. Um método a adota com uma linha:

    size_equipment(eq::MeuVaso, m::MeuMetodo, s, params) = size_vessel(eq, m, s, params)
"""
size_vessel(eq::AbstractEquipment, m::AbstractSizingMethod, s, params::AbstractDict) =
    size_single(eq, m, s, params)
