"""
O encaixe da Análise Pinch no contrato de varredura — o **envoltório** do núcleo puro.

# Por que este arquivo existe separado de `analysis/pinch.jl`

`src/analysis/pinch.jl` é incluído logo depois de `units.jl`, **antes** de
`interfaces.jl`. Lá dentro `ParameterSpec` e `AbstractSizingMethod` não existem — não são
"evitados", são impossíveis de citar —, e `test/pinch.jl` tem uma guarda textual que
verifica isso. Essa é a única garantia estrutural que a execução anterior estabeleceu, e
fundir os dois arquivos a destruiria.

Aqui, ao contrário, tudo aquilo existe: este arquivo é incluído depois de
`interfaces.jl`, de `engine/contract.jl` e de `sizing/constraints.jl`. Ele não recalcula
nada — traduz. Toda a física continua em [`PinchAnalysis.problem_table`](@ref).

# Por que em `analysis/` e não em `sizing/pinch/`

`src/sizing/` é organizado por **família de equipamento**: `separator/`, `knockout/`,
`treater/`, `pump/`, `exchanger/`. Abrir um `sizing/pinch/` diria que pinch é uma dessas
famílias — que é exatamente a confusão que este box existe para não fazer. Pinch não
dimensiona casco nenhum.

O par fica em `analysis/`, lado a lado: `pinch.jl` (o algoritmo) e `pinch_method.jl` (a
tradução). Quem abrir a pasta vê as duas metades do mesmo assunto, e a pureza continua
sendo imposta pela **ordem de include** em `FPSOSiz.jl`, que é onde ela sempre esteve —
não pela árvore de diretórios, que não impõe nada.

# O que se varre, e o que a escolha significa

O eixo é o **ΔTmin**, e a grandeza envelopada é o **QHmin**. Isso é legítimo porque
`QHmin` é não-decrescente em ΔTmin — aproximar mais as curvas nunca pode custar *mais*
utilidade quente —, e `test/pinch.jl` prova a propriedade sobre dois conjuntos de
correntes antes de qualquer código deste arquivo existir. É ela que autoriza chamar
QHmin de "exigência" e tomar o máximo entre casos.

Cada caso é um **cenário de operação da mesma rede**: as mesmas N correntes com vazões
ou temperaturas diferentes. O envelope entrega a utilidade quente que atende ao pior
cenário, que é o que se compra.

# A escolha do ponto NÃO é otimização, e o arquivo não finge que é

`objective = |ΔTmin − alvo|` escolhe o ponto da grade mais próximo do ΔTmin que o
projetista **declarou**. O programa não modela área de troca nem custo de capital, logo
não tem como construir a curva do §3.7 de Kemp (Figura 3.25, p. 82) em que capital sobe,
energia desce e o total tem mínimo. Sem ela não há critério próprio para preferir um
ΔTmin a outro, e inventar um seria dar a um número arbitrado a aparência de otimizado.

A limitação está declarada em `docs/validacao/06-pinch-kemp.md` §6.1, e a fonte é
explícita em que o ótimo é econômico e **achatado** (§3.7.2, p. 82: o custo total fica a
~10 % do ótimo de 5 °C a 50 °C). Uma faixa de dez para um. Não há banda estreita a impor,
e impor uma seria inventar rigor.

Por isso `case_admissible` e `admissible` devolvem `true` e `ceiling_of` fica no `Inf`
default: **todo ΔTmin da grade é um projeto possível.** A varredura não filtra — ela
mostra. O que a tabela entrega é o meio-termo energético inteiro (QHmin, QCmin e o pinch
a cada ΔTmin), que é a metade da troca que este programa sabe calcular.

# Fonte

Kemp, I.C., *Pinch Analysis and Process Integration*, 2ª ed., Butterworth-Heinemann,
2007. As páginas e equações estão em `config/equipment/pinch/kemp.toml`, uma por
descritor, e em `docs/validacao/06-pinch-kemp.md`.
"""

const PA = PinchAnalysis

"""
O objeto da análise. **Não é um equipamento**, e o nome não finge que seja: o que a
Análise Pinch caracteriza é a *rede* de correntes, antes de existir trocador.

Existe porque o contrato pede um: [`applies_to`](@ref) devolve um `AbstractEquipment`,
`size_envelope` confere o par equipamento↔método (`engine/envelope.jl:52`) e um box
`ativo` do catálogo tem de resolver os dois no registro (`test/architecture.jl:243`).
Registrar um alvo em vez de um casco é o menor desvio possível dessa exigência — e
deixa o box fora da lista de métodos do trocador, que é onde ele **não** deve estar.
"""
struct PinchTarget <: AbstractEquipment end
method_id(::PinchTarget) = :pinch
label(::PinchTarget) = "Rede térmica de processo"

"A Problem Table de Kemp, vestida de método do registro."
struct PinchKemp <: AbstractSizingMethod end
method_id(::PinchKemp) = :pinch_kemp
applies_to(::PinchKemp) = PinchTarget()

const _PINCH_CONFIG = ("equipment", "pinch", "kemp.toml")

method_config(::PinchKemp) = load_config(_PINCH_CONFIG...)
label(::PinchKemp) = config_label(method_config(PinchKemp()),
                                 "Kemp — Problem Table (Análise Pinch)")
parameters(::PinchKemp) = parameter_specs(method_config(PinchKemp()))
parameter_groups(::PinchKemp) = group_specs(method_config(PinchKemp()))

"""
A rede não tem corrente de óleo, água e gás — tem N correntes térmicas, cada uma com as
suas duas temperaturas e o seu `ṁ·cp`.

`stream_keys` vazio significa que `config/stream.toml` não contribui com campo nenhum; o
formulário inteiro vem de [`parameters`](@ref). É o mesmo caminho que o trocador já
percorre (`shell_and_tube.jl:89`), e pela mesma razão.
"""
stream_keys(::PinchKemp) = ()

"""
    global_keys(::PinchKemp)

As três da grade de ΔTmin e o alvo — decisão de projeto, não dado de corrente, e por
isso num painel único em vez de repetidas em cada cenário. É o mesmo canal por onde
`sr_target` chega à tela (`sizing/constraints.jl:158`).
"""
global_keys(::PinchKemp) = [:dt_min_min, :dt_min_max, :dt_min_step, :dt_min_alvo]

# ---------------------------------------------------------------------------
# Fronteira de tradução: o dicionário do caso vira correntes
# ---------------------------------------------------------------------------

"""
    case_input(m::PinchKemp, vals) -> Vector{ThermalStream}

As correntes que o caso descreve, lidas pelas chaves sintetizadas de
[`instance_key`](@ref) — `:corrente_1_t_in`, `:corrente_1_t_out`, `:corrente_1_mcp`, e
assim por diante.

**Este é o único ponto deste arquivo que lança**, e é o idioma correto: `case_input` é
fronteira de tradução, e `engine/envelope.jl:76-79` a envolve num `try` que converte a
exceção em inviabilidade com o nome do caso. Tudo o mais devolve estado.

O nome da corrente é **sintetizado do índice**, e não pedido ao usuário. `ParameterSpec`
descreve grandeza numérica (`default`, `min` e `max` são `Float64`) e `CaseUI` guarda
`Dict{Symbol,Float64}`: um campo de texto exigiria que as duas estruturas, o arquivo de
casos e a validação carregassem não-números para servir a um rótulo. O índice já
distingue as correntes nas mensagens de `validate_streams`, que é para o que o nome
serve aqui.

Uma instância **pela metade** é recusada em vez de completada com defaults. Uma corrente
com `t_in` e sem `mcp` é um dado que o usuário começou a escrever; preenchê-la com o
default do descritor produziria uma corrente que ninguém informou entrando no alvo de
energia sem nada denunciando — a mesma classe de falha silenciosa que
`carregar_casos!` recusa em `app/src/state.jl:175-195`.
"""
function case_input(m::PinchKemp, vals::AbstractDict)
    g = _grupo_corrente(m)
    campos = _campos_do_grupo(m, g.key)

    correntes = PA.ThermalStream[]
    for i in 1:g.max
        chaves = [instance_key(g.key, i, s.key) for s in campos]
        presentes = filter(k -> haskey(vals, k), chaves)
        isempty(presentes) && continue
        length(presentes) == length(chaves) || throw(ArgumentError(
            "$(g.label) $i está pela metade: falta " *
            join(String.(setdiff(chaves, presentes)), ", ") *
            ". Uma corrente incompleta não é completada com valores de fábrica."))

        v = s -> float(vals[instance_key(g.key, i, s)])
        push!(correntes, PA.ThermalStream("$(g.label) $i",
                                          v(:t_in), v(:t_out), v(:mcp)))
    end

    isempty(correntes) && throw(ArgumentError(
        "o caso não descreve nenhuma $(lowercase(g.label)): não há rede a integrar."))
    return correntes
end

"O cabeçalho do único grupo que este método declara."
function _grupo_corrente(m::PinchKemp)
    gs = parameter_groups(m)
    isempty(gs) && error("kemp.toml não declara nenhum bloco [[group]]")
    return first(gs)
end

"Os moldes de campo que pertencem ao grupo `g`, na ordem do arquivo."
_campos_do_grupo(m::PinchKemp, g::Symbol) = filter(s -> s.group === g, parameters(m))

# ---------------------------------------------------------------------------
# Restrições: o que não depende do ΔTmin
# ---------------------------------------------------------------------------

"""
A rede, já validada, e as duas somas que não dependem de ΔTmin nenhum.

`q_hot` e `q_cold` existem para a conferência cruzada que a p. 24 manda fazer:
`QCmin − QHmin = ΣQ_quente − ΣQ_frio`, que é o balanço de entalpia do problema inteiro e
vale em **qualquer** ΔTmin. É um invariante barato que pega erro de dado e erro de
cascata, e é o que o memorial mostra no fecho.
"""
struct PinchConstraints
    streams::Vector{PA.ThermalStream}
    q_hot::Float64      # kW
    q_cold::Float64     # kW
    n_hot::Int
    n_cold::Int
end

"""
    sizing_constraints(m::PinchKemp, correntes, p, k)

Valida a rede e soma as cargas. Nada aqui depende do ΔTmin, que é justamente o eixo.

A validação usa `PinchAnalysis.validate_streams`, que **devolve mensagens e não lança** —
é a forma de `validate(specs, values)` de `src/interfaces.jl:45`. O ΔTmin passado é o
alvo declarado, e serve só para satisfazer a assinatura: nenhuma das regras de recusa de
corrente (isotérmica, mCp não positivo, segmentos descontínuos, mudança de direção)
depende dele, e os pontos da grade são positivos por construção do descritor.
"""
function sizing_constraints(m::PinchKemp, correntes::Vector{PA.ThermalStream},
                            p::AbstractDict, k::AbstractDict)
    tr = CalcTrace()

    queixas = PA.validate_streams(correntes, p[:dt_min_alvo])
    isempty(queixas) || return (false, join(queixas, " "), tr)

    cargas = PA.heat_loads(correntes)
    quentes = count(s -> PA.stream_type(s) === :hot, correntes)
    frias   = length(correntes) - quentes

    for s in correntes
        seg = first(s.segments)
        trace!(tr, :correntes, "Tab. 2.2",
               "$(s.name) ($(PA.stream_type(s) === :hot ? "quente" : "fria"))",
               "$(seg.t_in) → $(seg.t_out) °C, CP = $(seg.mcp) kW/°C",
               PA.heat_load(s), "kW")
    end
    trace!(tr, :correntes, "§2.1.4", "ΣQ quente", "soma das cargas que cedem calor",
           cargas.hot, "kW")
    trace!(tr, :correntes, "§2.1.4", "ΣQ frio", "soma das cargas que recebem calor",
           cargas.cold, "kW")

    return (true, PinchConstraints(correntes, cargas.hot, cargas.cold, quentes, frias), tr)
end

# ---------------------------------------------------------------------------
# O contrato de engine/contract.jl
# ---------------------------------------------------------------------------

"""
    sweep_axis(m::PinchKemp, p)

A grade de ΔTmin. Os limites do descritor saem de §3.7.2, p. 82 — a faixa em que Kemp
declara o custo total dentro de ~10 % do ótimo.
"""
sweep_axis(::PinchKemp, p::AbstractDict) =
    SweepAxis(:dt_min, "ΔT mínimo de aproximação", "°C",
              collect(p[:dt_min_min]:p[:dt_min_step]:p[:dt_min_max]))

"""
    requirement(m::PinchKemp, dt_min, c)

`QHmin` — a utilidade quente que a rede exige, no mínimo, com esta aproximação.

É a grandeza envelopada porque é **não-decrescente em ΔTmin**, que é a condição para o
motor tomar o máximo entre casos e chamar o resultado de exigência. A propriedade está
provada em `test/pinch.jl`, sobre dois conjuntos de correntes e 600 valores de ΔTmin.
"""
requirement(::PinchKemp, dt_min::Real, c::PinchConstraints) =
    PA.problem_table(c.streams, dt_min).q_h_min

"""
Uma rede tem **uma** exigência, e o símbolo existe porque o motor carimba um. Nomeá-la
`:utilidade_quente` é mais honesto que reaproveitar `:gas` ou `:liquido` de um vaso.
"""
governing_of(::PinchKemp, dt_min::Real, c::PinchConstraints) = :utilidade_quente

governing_label(::PinchKemp, g::Symbol) =
    g === :utilidade_quente ? "utilidade quente (QHmin)" : String(g)

requirement_spec(::PinchKemp) = ("utilidade quente mínima QHmin", "kW")

"""
    derived(m::PinchKemp, dt_min, q_h, gov, c, k, p)

Tudo o que a Problem Table entrega além do QHmin.

**As temperaturas de pinch saem do núcleo como VETORES** — o passo 9 de §3.9.1 (p. 96)
diz *"the point(s) at which there is zero net heat flow"*, no plural, e um problema pode
ter mais de um pinch. Um `Dict{Symbol,Float64}` não guarda vetor, então a convenção é:
reporta-se o **mais quente** (as fronteiras vêm em ordem decrescente, logo é o primeiro)
e diz-se quantos são em `:n_pinch`. Vetor vazio vira `NaN`, que a tela mostra como
travessão — e `:threshold` diz por quê, em vez de deixar o travessão sem explicação.

`:recuperacao` é `ΣQ_quente − QCmin`: o calor que a rede troca consigo mesma. Não é um
número novo do algoritmo, é a leitura do balanço da p. 24 que responde à pergunta que o
usuário de fato tem.
"""
function derived(m::PinchKemp, dt_min::Real, q_h::Real, gov::Symbol,
                 c::PinchConstraints, k::AbstractDict, p::AbstractDict)
    r = PA.problem_table(c.streams, dt_min)
    primeiro(v) = isempty(v) ? NaN : float(first(v))
    return Dict{Symbol,Float64}(
        :qhmin              => r.q_h_min,
        :qcmin              => r.q_c_min,
        :t_pinch_deslocada  => primeiro(r.t_pinch_shifted),
        :t_pinch_quente     => primeiro(r.t_pinch_hot),
        :t_pinch_fria       => primeiro(r.t_pinch_cold),
        :n_pinch            => float(length(r.t_pinch_shifted)),
        :threshold          => r.threshold ? 1.0 : 0.0,
        :q_hot              => c.q_hot,
        :q_cold             => c.q_cold,
        :n_correntes        => float(length(c.streams)),
        :n_quentes          => float(c.n_hot),
        :n_frias            => float(c.n_cold),
        :n_intervalos       => float(length(r.intervals)),
        # O calor que a rede troca consigo mesma, e o que ele significa em fração da
        # carga quente disponível — o número que o relatório de fato cita.
        :recuperacao        => c.q_hot - r.q_c_min,
        :fracao_recuperada  => c.q_hot > 0 ? (c.q_hot - r.q_c_min) / c.q_hot : NaN,
    )
end

"""
    admissible(m::PinchKemp, dt_min, der, p)

Sempre verdadeiro, e é uma afirmação, não uma omissão: **todo ΔTmin da grade descreve
uma rede possível.** O que separa um do outro é troca energia × capital, que este
programa não modela — ver o cabeçalho deste arquivo e §6.1 da doc de validação.

Um `false` aqui teria de vir de um critério, e não há critério a citar.
"""
admissible(::PinchKemp, dt_min::Real, der::AbstractDict, p::AbstractDict) = true

"""
    objective(m::PinchKemp, dt_min, der, p)

Distância ao ΔTmin declarado — **seleção por declaração, não otimização.** O programa
cumpre o ΔTmin que o projetista pediu; ele não o escolhe, e não alega escolher.

Com `admissible` sempre verdadeiro, isto equivale a "o ponto da grade mais próximo do
alvo". É deliberado: a varredura existe para mostrar o meio-termo, não para decidi-lo.
"""
objective(::PinchKemp, dt_min::Real, der::AbstractDict, p::AbstractDict) =
    abs(dt_min - p[:dt_min_alvo])

"""
    envelope_params(m::PinchKemp, params)

Uma grade e um alvo para os N cenários — a rede é uma só.

A grade é **união** (menor mínimo, maior máximo, menor passo), pela mesma razão que nos
vasos: ampliar onde se procura não perde solução. Não há banda a interseccionar, porque
não há banda: nenhum ΔTmin é inadmissível.

O alvo é a **média**, presa à grade. Ele é preferência, não restrição — o mesmo estatuto
de `sr_target` —, e nenhum cenário tem direito de veto sobre o gosto dos outros. Na
prática os N valores são idênticos, porque o alvo é um ajuste global e a tela o manda
uma vez só; a média existe para o caminho sem tela, em que um `CaseSet` é montado à mão.
"""
function envelope_params(::PinchKemp, params::Vector{<:AbstractDict})
    lo   = minimum(p[:dt_min_min]  for p in params)
    hi   = maximum(p[:dt_min_max]  for p in params)
    step = minimum(p[:dt_min_step] for p in params)
    alvo = sum(p[:dt_min_alvo] for p in params) / length(params)
    return (true, Dict{Symbol,Float64}(
        :dt_min_min  => lo,
        :dt_min_max  => hi,
        :dt_min_step => step,
        :dt_min_alvo => clamp(alvo, lo, hi)))
end

"""
    selection_message(m::PinchKemp, rows, teto, p)

Só é alcançada com a grade vazia: como nenhum ΔTmin é inadmissível, o conjunto
admissível só fica vazio quando não há ponto nenhum a admitir. A frase diz isso, em vez
de sugerir que houve uma recusa física.
"""
function selection_message(::PinchKemp, rows, teto::Real, p::AbstractDict;
                           mechanism::Symbol = :none)
    isempty(rows) && return "A grade de ΔTmin ficou vazia: confira mínimo " *
                            "($(p[:dt_min_min]) °C), máximo ($(p[:dt_min_max]) °C) e " *
                            "passo ($(p[:dt_min_step]) °C)."
    return "Nenhum ΔTmin da grade foi admitido. Como a Análise Pinch não recusa " *
           "aproximação nenhuma — todo ΔTmin descreve uma rede possível —, isto " *
           "indica grade mal formada e não um limite físico."
end

grid_hint(::PinchKemp, p::AbstractDict) =
    "Verifique ΔTmin mínimo ($(p[:dt_min_min]) °C), máximo ($(p[:dt_min_max]) °C) e " *
    "passo ($(p[:dt_min_step]) °C)."

"""
    result_fields(m::PinchKemp, r)

O cartão. O primeiro campo é o **aviso de escopo**, e vem daqui e não do HTML: a regra do
projeto é que a interface não escreve texto de domínio, e "isto não dimensiona um
trocador" é texto de domínio.
"""
function result_fields(m::PinchKemp, r)
    tem = r.feasible && isfinite(r.x)
    txt(v) = tem ? v : "—"
    n_pinch = der(r, :n_pinch)
    limiar  = der(r, :threshold) == 1.0

    # O que o pinch é, e onde ele não está. Um problema-limiar não tem pinch interior, e
    # mostrar um travessão sem dizer isso deixaria o leitor procurando um defeito.
    pinch_txt = !tem ? "—" :
                limiar && !isfinite(der(r, :t_pinch_deslocada)) ?
                    "sem pinch (problema-limiar)" :
                isfinite(n_pinch) && n_pinch > 1 ?
                    "$(round(Int, n_pinch)) pinches — mostrado o mais quente" :
                    "um pinch"

    return ResultField[
        ResultField("O que esta tela entrega",
                    "Metas de energia da rede (QHmin, QCmin) e a temperatura de pinch. " *
                    "NÃO dimensiona casco-e-tubos e NÃO sintetiza a rede de trocadores."),
        ResultField("ΔTmin adotado", tem ? r.x : NaN; unit = "°C", highlight = true),
        ResultField("Utilidade quente mínima QHmin", tem ? r.y : NaN; unit = "kW",
                    digits = 1, highlight = true),
        ResultField("Utilidade fria mínima QCmin", der(r, :qcmin); unit = "kW",
                    digits = 1, highlight = true),
        ResultField("Calor recuperado na rede", der(r, :recuperacao); unit = "kW",
                    digits = 1),
        ResultField("Fração da carga quente recuperada", der(r, :fracao_recuperada);
                    digits = 3),
        ResultField("Situação do pinch", pinch_txt),
        ResultField("T de pinch (deslocada)", der(r, :t_pinch_deslocada); unit = "°C"),
        ResultField("T de pinch, lado quente", der(r, :t_pinch_quente); unit = "°C"),
        ResultField("T de pinch, lado frio", der(r, :t_pinch_fria); unit = "°C"),
        ResultField("Correntes na rede", der(r, :n_correntes); digits = 0),
        ResultField("Quentes / frias",
                    tem ? "$(round(Int, der(r, :n_quentes))) / " *
                          "$(round(Int, der(r, :n_frias)))" : "—"),
        ResultField("Intervalos de temperatura", der(r, :n_intervalos); digits = 0),
        ResultField("Carga quente disponível ΣQ", der(r, :q_hot); unit = "kW",
                    digits = 1),
        ResultField("Carga fria requerida ΣQ", der(r, :q_cold); unit = "kW", digits = 1),
        ResultField("Cenário governante", txt(_driver_case(r))),
    ]
end

sweep_columns(::PinchKemp) = [
    SweepColumn("ΔTmin (°C)",  :x; digits = 1),
    SweepColumn("QHmin (kW)",  :y; digits = 1),
    SweepColumn("QCmin (kW)",  :qcmin; digits = 1),
    SweepColumn("recuperado (kW)", :recuperacao; digits = 1),
    SweepColumn("T pinch (°C)", :t_pinch_deslocada; digits = 1),
]

trace_blocks(::PinchKemp) = [
    :correntes => "Bloco A — as correntes e as cargas (Tabela 2.2, p. 21)",
    :selection => "Seleção do ΔTmin",
]

"""
    trace_selection!(m::PinchKemp, tr, best, p)

Carimba no memorial **por que** este ponto foi escolhido, e a conferência cruzada da
p. 24: `QCmin − QHmin` tem de dar `ΣQ_quente − ΣQ_frio` em qualquer ΔTmin. É invariante
barato que pega erro de dado e erro de cascata, e é o que faz o memorial ser conferível
à mão contra o livro.
"""
function trace_selection!(m::PinchKemp, tr::CalcTrace, best, p::AbstractDict)
    d = best.derivados
    trace!(tr, :selection, "§3.7.3", "ΔTmin",
           "declarado pelo projetista ($(p[:dt_min_alvo]) °C); não há troca " *
           "energia × capital modelada, logo não há ótimo a procurar", best.x, "°C")
    trace!(tr, :selection, "§3.9.1 p. 8", "QHmin", "o fluxo mais negativo da cascata, " *
           "levado a zero no topo", best.y, "kW")
    trace!(tr, :selection, "§3.9.1 p. 9", "QCmin", "o que sobra no pé da cascata factível",
           get(d, :qcmin, NaN), "kW")
    trace!(tr, :selection, "p. 24", "QCmin − QHmin",
           "balanço de entalpia: tem de igualar ΣQ_quente − ΣQ_frio " *
           "(= $(round(get(d, :q_hot, NaN) - get(d, :q_cold, NaN), digits = 3)) kW), " *
           "em qualquer ΔTmin",
           get(d, :qcmin, NaN) - best.y, "kW")
    trace!(tr, :selection, "§3.9.1 p. 9", "T de pinch (deslocada)",
           get(d, :threshold, 0.0) == 1.0 && !isfinite(get(d, :t_pinch_deslocada, NaN)) ?
               "problema-limiar (§3.3.2, p. 54): uma das utilidades zerou e não há " *
               "pinch interior" :
               "fronteira em que o fluxo líquido é nulo",
           get(d, :t_pinch_deslocada, NaN), "°C")
    return nothing
end

size_equipment(eq::PinchTarget, m::PinchKemp, correntes::Vector{PA.ThermalStream},
               params::AbstractDict) = size_single(eq, m, correntes, params)
