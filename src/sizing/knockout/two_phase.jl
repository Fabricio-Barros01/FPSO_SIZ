"""
Vaso de knockout gás-líquido horizontal, meio cheio — Stewart & Arnold (2008), cap. 3.

O segundo equipamento do registro, e a prova de que a arquitetura dos Sprints 0–5 vale
o que promete: **este arquivo não tem varredura, nem escolha de diâmetro, nem motor de
envelope.** Ele declara o que o vaso é e devolve dois números; o resto vem de graça de
`src/sizing/constraints.jl` e `src/engine/envelope.jl`.

## Dois blocos, não três

| | trifásico (Alves & Komesu) | bifásico (este) |
|---|---|---|
| A — capacidade de gás | Eq. 14 | **Eq. 3.8b — a mesma equação** |
| B — decantação líquido-líquido | Eq. 16–21 | **não existe** |
| C — capacidade de líquido | Eq. 22, duas fases | Eq. 3.9b, uma fase |
| `Lss(Leff)` | Eq. 15 / 23 | Eq. 3.10b / 3.11 — as mesmas |
| Banda de esbeltez | 3–5 | **3–4** (§3.8.5) |

O bloco B some porque não há duas fases líquidas: sem gotícula de água no óleo nem de
óleo na água, nada impõe teto de diâmetro. É o caminho `d_max = Inf` de
[`VesselConstraints`](@ref) — e é por isso que o construtor de dois argumentos existe.

O bloco A não é reescrito: `gas_capacity_dleff` é literalmente o mesmo código que o
trifásico usa, porque é literalmente a mesma equação. Muda a numeração citada no
memorial, para que o leitor confira no livro e não num artigo sobre trifásicos.

## A fase líquida ocupa a posição do "óleo"

`StreamState` tem três posições (óleo, água, gás) porque foi desenhado para o
trifásico. Aqui o líquido único vive na posição do óleo, e a da água chega `NaN` — ver
[`stream_from_case`](@ref). Os rótulos do formulário são reescritos abaixo para dizer
"líquido": num knockout de linha de gás o líquido é condensado, e chamá-lo de óleo na
tela seria pedir ao usuário um dado que ele não reconhece.

## Erratum da fonte, encontrado ao reproduzi-la

O Exemplo 3.2 do livro imprime `dLeff = 55,04 in·ft`, mas a Tabela 3.4 do **próprio
exemplo** só fecha com `39,85` — que é o que a Eq. 3.8a dá com os dados dados
(420 × 4,368 × 0,021724). As sete linhas da tabela conferem com 39,85 a menos de 6 %, e
com 55,04 erram 38 %. O texto está errado e a tabela certa; `test/golden_knockout.jl`
reproduz a tabela.
"""

struct KnockoutDrum <: AbstractEquipment end
method_id(::KnockoutDrum) = :knockout
label(::KnockoutDrum) = "Vaso de Knockout Bifásico (gás–líquido)"

struct StewartArnoldTwoPhase <: AbstractSizingMethod end
method_id(::StewartArnoldTwoPhase) = :stewart_arnold_2f
applies_to(::StewartArnoldTwoPhase) = KnockoutDrum()

const _SA2F_CONFIG = ("equipment", "knockout", "stewart_arnold_2f.toml")

method_config(::StewartArnoldTwoPhase) = load_config(_SA2F_CONFIG...)

label(::StewartArnoldTwoPhase) =
    config_label(method_config(StewartArnoldTwoPhase()), "Stewart & Arnold (2008) — bifásico")
parameters(::StewartArnoldTwoPhase) =
    parameter_specs(method_config(StewartArnoldTwoPhase()))

"""
Oito entradas, não doze.

Saem as três da fase aquosa — este vaso não tem uma. Sai também a **viscosidade do
líquido**: o bloco A usa a densidade do líquido (na Eq. 3.7b, como ρl) e a viscosidade
do *gás* (no Reynolds), e o bloco C usa só a vazão. A viscosidade do líquido não entra
em conta nenhuma aqui, e pedi-la seria o mesmo defeito que motivou `stream_keys`.

Ver [`stream_keys`](@ref).
"""
stream_keys(::StewartArnoldTwoPhase) =
    (:q_oil, :q_gas, :rho_oil, :rho_gas, :mu_gas, :pressure, :temperature, :z)

"Chaves da posição do óleo que a tela deve chamar de 'líquido' neste vaso."
const _ROTULOS_LIQUIDO = Dict(
    :q_oil   => ("Vazão de líquido",       "Fase líquida única (condensado, óleo). Eq. 3.9b."),
    :rho_oil => ("Densidade do líquido",   "Fase líquida única. Entra na Eq. 3.7b como ρl."),
)

"""
    stream_parameters(::StewartArnoldTwoPhase)

Os descritores de corrente com a fase líquida reetiquetada.

`config/stream.toml` é compartilhado e fala em "óleo" porque foi escrito para o
trifásico, onde óleo e água são fases distintas e a distinção importa. Num knockout há
uma fase líquida só — chamá-la de óleo na tela pediria ao usuário um dado que ele não
reconhece como o seu. O descritor é reescrito, não duplicado: unidade, faixa e ordem
continuam vindo do arquivo.
"""
function stream_parameters(m::StewartArnoldTwoPhase)
    # A filtragem é a mesma do default; escrita aqui em vez de `invoke` porque `invoke`
    # é frágil (quebra se a assinatura do default mudar) e ilegível para quem revisa.
    specs = filter(s -> s.key in stream_keys(m), stream_parameters())
    return map(specs) do s
        novo = get(_ROTULOS_LIQUIDO, s.key, nothing)
        novo === nothing && return s
        return ParameterSpec(s.key, novo[1], s.unit, s.default, s.min, s.max,
                             s.advanced, novo[2])
    end
end

"""
    sizing_constraints(m::StewartArnoldTwoPhase, s, p, k)

Blocos A e C. Sem bloco B, então sem teto de diâmetro: o
[`VesselConstraints`](@ref) sai pelo construtor de dois argumentos, com `d_max = Inf`,
`mechanism = :none` e a geometria de três camadas em `NaN`.

O memorial não ganha um subtítulo "Bloco B" vazio por causa disso —
`BLOCOS_MEMORIAL` em `app/src/report.jl` já pula bloco sem entradas.
"""
function sizing_constraints(m::StewartArnoldTwoPhase, s::StreamState,
                            p::AbstractDict, k::AbstractDict)
    tr = CalcTrace()
    fu = field_units(s)

    ok, d_leff_gas, msg = gas_capacity_dleff(
        s, p[:dm_gas], float(k[:gas_capacity_coefficient]),
        float(k[:cd_initial]), float(k[:cd_relaxation]), tr; eqs = EQS_GAS_LIVRO)
    ok || return (false, msg, tr)

    # ---------------------------------------------------------------- bloco C
    d2_leff = float(k[:liquid_capacity_coefficient]) * p[:tr_liquid] * fu.q_o
    trace!(tr, :liquid, "Eq. 3.9b", "d²·Leff", "42441·tr·Ql", d2_leff, "mm²·m")

    isfinite(d2_leff) || return (false,
        "Vazão de líquido não informada ou inválida: a capacidade de líquido " *
        "(Eq. 3.9b) não pôde ser avaliada.", tr)

    return (true, VesselConstraints(d_leff_gas, d2_leff), tr)
end

"""
    lss_from(::StewartArnoldTwoPhase, d_mm, leff, gov, k)

`Lss` pelo **maior** dos dois candidatos, e não pelo do bloco que governa o `Leff`.

Stewart & Arnold §3.8.4 é explícito: *"the seam-to-seam length of a vessel may be
estimated as the larger of the following"* — Eq. 3.10b (`Leff + d/1000`, o trecho de
distribuição na entrada mais o extrator de névoa) e Eq. 3.11 (`(4/3)·Leff`). São duas
folgas construtivas independentes; o vaso precisa atender às duas, então vale a maior.

O default de `lss_from` escolhe pela restrição que governa, que é o que Alves & Komesu
fazem — e é uma **simplificação do artigo**, não do livro. Ela coincide com a regra do
livro sempre que o líquido governa e `d` é pequeno em relação a `Leff`, e diverge quando
não é: nas três últimas linhas da Tabela 3 do artigo (d ≥ 5650 mm) o `Leff + d` é o
maior, e o `Lss` publicado é curto em até 5 %. Ver a nota 4 em `stewart_arnold.jl`.

Aqui a fonte é o livro, então segue-se o livro. É exatamente para diferenças assim que
`lss_from` é despachada pelo método, em vez de ser uma constante lida pelo motor.
"""
lss_from(::StewartArnoldTwoPhase, d_mm::Real, leff::Real, gov::Symbol,
         k::AbstractDict) =
    max(leff + d_mm / 1000.0, float(k[:lss_liquid_factor]) * leff)

size_equipment(eq::KnockoutDrum, m::StewartArnoldTwoPhase, s::StreamState,
               params::AbstractDict) = size_vessel(eq, m, s, params)
