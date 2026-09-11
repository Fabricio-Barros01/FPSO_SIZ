"""
Núcleo da **Análise Pinch** — o algoritmo da "Problem Table" (Linnhoff e Flower, 1978).

Fonte: Kemp, I.C., *Pinch Analysis and Process Integration: A User Guide on Process
Integration for the Efficient Use of Energy*, 2ª ed., Butterworth-Heinemann, 2007
(ISBN 978-0-7506-8260-2). O algoritmo passo a passo está no apêndice do cap. 3,
**§3.9.1, pp. 95-96**; a Eq. (2.3) do balanço por intervalo, na **p. 21**.

Responde a uma pergunta que nenhum box de dimensionamento responde: dado um conjunto de
correntes que precisam ser aquecidas e resfriadas, **quanto de utilidade quente e fria a
rede exige, no mínimo**, antes de qualquer trocador ser desenhado. É alvo termodinâmico,
não projeto de equipamento.

# Por que este arquivo é puro

Não há aqui `ParameterSpec`, `Case`, `AbstractSizingMethod` nem TOML. A entrada é um
`Vector{ThermalStream}` e um ΔTmin; a saída é um [`PinchResult`](@ref). Isso não é
disciplina: é estrutural. O arquivo é incluído em `FPSOSiz.jl` **logo depois de
`units.jl`**, antes de `interfaces.jl` — nenhum daqueles tipos existe ainda quando este
módulo é compilado, então citá-los não é "evitado", é impossível. Um ciclo de import não
tem por onde nascer.

O encaixe no contrato de varredura (`SweepAxis`, `requirement`, `objective`) e a entrada
de correntes pela tela são outra camada, e moram em outro arquivo.

# Convenção de temperatura: °C

Declarada, e não herdada por acidente. Kemp trabalha em °C nos caps. 2-3, e **toda**
grandeza deste algoritmo é ou uma *diferença* de temperatura — idêntica em °C e K — ou
uma temperatura deslocada que só aparece dentro de diferenças. A origem da escala nunca
entra na conta, então a escolha é de legibilidade contra a fonte, não de física.
`Units.celsius_to_kelvin` existe para quem precisar da fronteira.

# Onde o deslocamento de ΔTmin/2 é aplicado

Em [`shifted_temperatures`](@ref), no nível do **segmento**, antes de qualquer intervalo
existir — e em lugar nenhum mais. É o passo 2 de §3.9.1 (p. 95). A Nota 2 da p. 24
registra que há três formas de aproximar as curvas compostas em ΔTmin; o livro adota a
terceira (quentes −ΔTmin/2, frias +ΔTmin/2), e é a que está aqui.

# Sem constantes empíricas, logo sem TOML

A regra do projeto é que constante de correlação mora em TOML, para ficar auditável.
**Este algoritmo não tem nenhuma.** O único literal numérico com significado é o `2` de
ΔTmin/2, que é estrutural — metade de um intervalo, §3.9.1 passo 2 —, não premissa
revisável. A ausência do TOML é decisão registrada, não esquecimento.

# Sinal: excedente é POSITIVO

`CP_net = ΣCP_quente − ΣCP_fria`, e um intervalo com excedente de calor tem `ΔH > 0`.
É a convenção da 2ª edição, e o livro é explícito sobre ela ter sido invertida na 1ª:
ver Nota 1 da p. 24 e Nota (c) da p. 96, ambas chamando a convenção antiga de
contraintuitiva.

# Recusa de entrada, sem exceção

O núcleo **não lança em nenhum caminho**. [`validate_streams`](@ref) devolve as mensagens
e não lança — é a forma de `validate(specs, values)` de `src/interfaces.jl`, sem o tipo,
que aqui não existe. Entrada recusada vira um [`PinchResult`](@ref) inviável com
diagnóstico, no padrão de `infeasible` de `src/types/results.jl`. Exceção é o padrão só em
`case_input`, que é fronteira de tradução — e não há fronteira nenhuma neste arquivo.

# Escopo declarado

**Entrega:** deslocamento de temperaturas, tabela de intervalos, cascata infactível e
factível, QHmin, QCmin, temperaturas de pinch (deslocada, quente e fria) e sinalização de
problema-limiar.

**NÃO entrega e NÃO alega:** síntese de rede de trocadores, *grand composite curve*, alvo
de área, utilidades múltiplas, número mínimo de unidades, ΔTcont por corrente (§3.3.1,
p. 53 — o algoritmo admite, esta versão usa ΔTmin global) e CP polinomial em T (§3.1.3,
p. 45 — esta versão é CP constante por segmento, que é o método padrão do livro).
"""
module PinchAnalysis

export StreamSegment, ThermalStream, TemperatureInterval, PinchResult,
       validate_streams, shifted_temperatures, problem_table,
       is_hot, is_cold, stream_type, heat_load, heat_loads, pinch_infeasible

# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------

"""
Um trecho de corrente com `CP` constante.

`mcp` é a **capacidade calorífica de fluxo** `ṁ·cp`, em kW/°C — uma taxa, não uma
propriedade. `t_in` e `t_out` são as temperaturas reais (não deslocadas) em °C.

**Não há campo de tipo, e nenhum é aceito.** Que o segmento seja quente ou frio é
consequência do sinal de `t_in − t_out`, e perguntá-lo ao usuário criaria um dado que
pode contradizer os dois números logo acima. É a mesma decisão que `shell_and_tube.jl`
tomou ao chamar os lados de "tubo" e "casco" em vez de "quente" e "frio".
"""
struct StreamSegment
    t_in::Float64      # °C
    t_out::Float64     # °C
    mcp::Float64       # kW/°C
end

"""
Uma corrente de processo, como uma sequência de segmentos de `CP` constante.

Segmentos existem porque `CP` real depende da temperatura, e o remédio do livro é
linearizar por trechos (§3.1.3, p. 45): *"streams should be linearised in sections. This
operation maintains the validity of the Problem Table algorithm"*. Uma corrente de um
segmento só é o caso comum, e tem construtor próprio.

Os segmentos têm de ser **contíguos** (o `t_out` de um é o `t_in` do seguinte) e ter a
**mesma direção**. Uma corrente que esquenta e depois esfria são duas correntes: fundi-las
num objeto só esconderia que o fluido passa duas vezes pela mesma faixa de temperatura.
"""
struct ThermalStream
    name::String
    segments::Vector{StreamSegment}
end

"""
Corrente de um segmento só — o caso comum.

Não há construtor externo para a forma de dois argumentos: o que Julia gera a partir dos
campos já converte `SubString` em `String` e já aceita inteiros onde o campo é `Float64`.
Escrever um por cima sobrescreveria o gerado, que é erro de precompilação.
"""
ThermalStream(name::AbstractString, t_in, t_out, mcp) =
    ThermalStream(name, [StreamSegment(t_in, t_out, mcp)])

"Um segmento é quente quando esfria: `t_in > t_out`. Derivado, nunca declarado."
is_hot(seg::StreamSegment) = seg.t_in > seg.t_out

"Um segmento é frio quando esquenta: `t_in < t_out`."
is_cold(seg::StreamSegment) = seg.t_in < seg.t_out

"""
    stream_type(s) -> :hot | :cold

O tipo da corrente, **derivado** do primeiro segmento. Só tem sentido depois de
[`validate_streams`](@ref) aprovar, que é quem garante que todos os segmentos concordam
em direção.
"""
stream_type(s::ThermalStream) = is_hot(first(s.segments)) ? :hot : :cold

"Carga térmica do segmento, em kW — sempre positiva."
heat_load(seg::StreamSegment) = seg.mcp * abs(seg.t_in - seg.t_out)

"Carga térmica da corrente inteira, em kW."
heat_load(s::ThermalStream) = sum(heat_load, s.segments)

"""
    heat_loads(streams) -> (; hot, cold)

As cargas totais das correntes quentes e das frias, em kW.

Existe para a conferência cruzada que a própria p. 24 manda fazer: `QCmin − QHmin` tem de
ser igual a `ΣQ_quente − ΣQ_fria`, que é o balanço de entalpia do problema inteiro e não
depende de ΔTmin nenhum. É um invariante barato que pega erro de dado e erro de cascata.
"""
function heat_loads(streams)
    quente = 0.0
    fria   = 0.0
    for s in streams, seg in s.segments
        is_hot(seg) ? (quente += heat_load(seg)) : (fria += heat_load(seg))
    end
    return (; hot = quente, cold = fria)
end

# ---------------------------------------------------------------------------
# Saída
# ---------------------------------------------------------------------------

"""
Um intervalo de temperatura **deslocada**, entre duas fronteiras consecutivas.

`cp_net` é `ΣCP_quente − ΣCP_fria` das correntes que atravessam o intervalo (§3.9.1
passo 5); `dh` é o calor líquido liberado, positivo quando há excedente (passo 6, e
Eq. (2.3) da p. 21).
"""
struct TemperatureInterval
    s_top::Float64     # fronteira superior, deslocada, °C
    s_bot::Float64     # fronteira inferior, deslocada, °C
    cp_net::Float64    # kW/°C
    dh::Float64        # kW — excedente positivo
end

"""
Resultado da Problem Table.

`x`, `y` e derivados não têm significado se `feasible` for `false`; aí `message` explica o
que impediu. É o mesmo contrato de `SizingResult`.

As duas cascatas vêm juntas de propósito. A infactível é a que o leitor consegue conferir
contra a Figura 2.9(a) do livro, e o seu último nó é o balanço de entalpia do problema; a
factível é a que dá os alvos. Guardar só a segunda economizaria um vetor e tiraria do
memorial a metade auditável da conta.

`t_pinch_shifted` é **vetor**: o passo 9 de §3.9.1 diz *"the point(s) at which there is
zero net heat flow"*, no plural, e um problema pode ter mais de um pinch.

`threshold` e `isempty(t_pinch_shifted)` são coisas diferentes, e por isso são dois
campos. Um problema-limiar é aquele em que **uma** das utilidades zera (§3.3.2, p. 54);
no ΔTmin exato do limiar isso acontece *e* ainda há um pinch interior. Abaixo dele, não
há mais pinch. Fundir os dois num flag só perderia essa distinção.
"""
struct PinchResult
    feasible::Bool
    message::String
    dt_min::Float64
    intervals::Vector{TemperatureInterval}
    cascade_infeasible::Vector{Float64}   # n+1 nós, começando em 0 no topo
    cascade_feasible::Vector{Float64}     # n+1 nós, começando em QHmin no topo
    boundaries::Vector{Float64}           # n+1 fronteiras deslocadas, decrescentes
    q_h_min::Float64                      # kW
    q_c_min::Float64                      # kW
    t_pinch_shifted::Vector{Float64}      # °C, deslocada
    t_pinch_hot::Vector{Float64}          # °C, real, lado quente
    t_pinch_cold::Vector{Float64}         # °C, real, lado frio
    threshold::Bool
end

"Constrói um [`PinchResult`](@ref) inviável com diagnóstico. Espelha `infeasible`."
pinch_infeasible(message::AbstractString; dt_min = NaN) =
    PinchResult(false, String(message), float(dt_min),
                TemperatureInterval[], Float64[], Float64[], Float64[],
                NaN, NaN, Float64[], Float64[], Float64[], false)

# ---------------------------------------------------------------------------
# Recusa de entrada — devolve mensagens, não lança
# ---------------------------------------------------------------------------

"""
    validate_streams(streams, dt_min) -> Vector{String}

Todas as queixas contra as correntes e o ΔTmin (vazio = tudo válido). **Não lança**: é a
forma de `validate(specs, values)` de `src/interfaces.jl:43`, para uma entrada que não é
descrita por `ParameterSpec` — e não poderia ser, porque uma corrente tem número variável
de segmentos e um descritor descreve um campo de formulário.

Uma regra por mensagem, e cada mensagem nomeia a corrente, para que a queixa seja
acionável sem abrir o depurador.
"""
function validate_streams(streams, dt_min::Real)
    msgs = String[]

    isfinite(dt_min) && dt_min > 0 ||
        push!(msgs, "ΔTmin tem de ser um número positivo (recebi $dt_min °C).")

    isempty(streams) &&
        push!(msgs, "Lista de correntes vazia: não há o que integrar.")

    for s in streams
        nome = isempty(s.name) ? "(sem nome)" : s.name

        if isempty(s.segments)
            push!(msgs, "Corrente '$nome' não tem nenhum segmento.")
            continue
        end

        for (i, seg) in enumerate(s.segments)
            onde = length(s.segments) == 1 ? "'$nome'" : "'$nome', segmento $i"

            if !isfinite(seg.t_in) || !isfinite(seg.t_out)
                push!(msgs, "$onde: temperatura não numérica " *
                            "($(seg.t_in) → $(seg.t_out) °C).")
                continue
            end

            # A recusa que mais precisa explicar-se: CP infinito. Kemp §3.1.3, p. 44,
            # diz que a carga latente "pode ser considerada" uma corrente a temperatura
            # fixa com CP infinito, e na frase seguinte dá a prática que o software usa
            # no lugar — porque o pinch é sempre causado por uma corrente COMEÇANDO, e
            # preservar a temperatura de suprimento mantém o pinch exato. A mensagem
            # tem de carregar essa receita, senão o usuário só sabe que foi recusado.
            if seg.t_in == seg.t_out
                push!(msgs, "$onde: segmento isotérmico ($(seg.t_in) °C). " *
                            "Mudança de fase não entra como CP infinito. Kemp §3.1.3, " *
                            "p. 44: mantenha a temperatura de suprimento e desloque a " *
                            "de destino em ~0,1 °C — para cima se a corrente é fria " *
                            "(vaporizando), para baixo se é quente (condensando).")
                continue
            end

            isfinite(seg.mcp) && seg.mcp > 0 ||
                push!(msgs, "$onde: mCp tem de ser positivo (recebi $(seg.mcp) kW/°C).")
        end

        # As duas regras que só fazem sentido entre segmentos. Rodam depois, e só se
        # cada segmento já é válido por si: acusar descontinuidade entre dois segmentos
        # com `NaN` seria ruído em cima da queixa que importa.
        if length(s.segments) > 1 && all(seg -> isfinite(seg.t_in) &&
                                                isfinite(seg.t_out) &&
                                                seg.t_in != seg.t_out, s.segments)
            quente = is_hot(first(s.segments))
            all(seg -> is_hot(seg) == quente, s.segments) ||
                push!(msgs, "Corrente '$nome' muda de direção entre segmentos: " *
                            "uma corrente que esquenta e depois esfria são duas " *
                            "correntes, não uma.")

            for i in 1:(length(s.segments) - 1)
                a, b = s.segments[i], s.segments[i + 1]
                a.t_out == b.t_in ||
                    push!(msgs, "Corrente '$nome': o segmento $i termina em " *
                                "$(a.t_out) °C e o $(i + 1) começa em $(b.t_in) °C. " *
                                "Os segmentos têm de ser contíguos.")
            end
        end
    end

    return msgs
end

# ---------------------------------------------------------------------------
# Passo 2 de §3.9.1 — o ÚNICO lugar onde ΔTmin/2 é aplicado
# ---------------------------------------------------------------------------

"""
    shifted_temperatures(seg, dt_min) -> (s_in, s_out)

As temperaturas deslocadas do segmento, em °C.

Subtrai ΔTmin/2 de corrente quente e soma ΔTmin/2 a corrente fria (§3.9.1 passo 2, p. 95).
É a terceira das três formas que a Nota 2 da p. 24 lista, e a que o livro adota.

**Esta função é o único ponto do módulo que desloca temperatura.** Todo o resto opera
sobre o que ela devolve. É deliberado: um deslocamento aplicado em dois lugares é um
ΔTmin/2 aplicado duas vezes em algum caminho, e o erro apareceria como um pinch
plausível no lugar errado.
"""
function shifted_temperatures(seg::StreamSegment, dt_min::Real)
    meio = dt_min / 2
    return is_hot(seg) ? (seg.t_in - meio, seg.t_out - meio) :
                         (seg.t_in + meio, seg.t_out + meio)
end

# ---------------------------------------------------------------------------
# O algoritmo — §3.9.1, pp. 95-96
# ---------------------------------------------------------------------------

"""
    problem_table(streams, dt_min) -> PinchResult

Os alvos de energia de um conjunto de correntes, pelo algoritmo da Problem Table
(Kemp §3.9.1, pp. 95-96). Nunca lança: entrada recusada vira resultado inviável.

Os nove passos do livro, na ordem, estão marcados no corpo.
"""
function problem_table(streams, dt_min::Real)
    # Passo 1 — o ΔTmin é escolha de quem chama. Aqui só se confere que é utilizável.
    queixas = validate_streams(streams, dt_min)
    isempty(queixas) || return pinch_infeasible(join(queixas, " "); dt_min)

    dt = float(dt_min)

    # Passo 2 — deslocar. Guarda-se (lo, hi, mcp, quente) por segmento: a partir daqui
    # ninguém mais olha temperatura real, e é isso que impede um segundo deslocamento.
    desl = NTuple{4,Any}[]
    for s in streams, seg in s.segments
        s_in, s_out = shifted_temperatures(seg, dt)
        push!(desl, (min(s_in, s_out), max(s_in, s_out), seg.mcp, is_hot(seg)))
    end

    # Passos 3 e 4 — listar as fronteiras e ordenar em ordem DECRESCENTE.
    fronteiras = sort!(unique!([t for d in desl for t in (d[1], d[2])]); rev = true)
    n = length(fronteiras) - 1

    # Passos 5 e 6 — CP líquido e calor líquido de cada intervalo.
    intervalos = Vector{TemperatureInterval}(undef, n)
    for i in 1:n
        topo, base = fronteiras[i], fronteiras[i + 1]
        cp = 0.0
        for (lo, hi, mcp, quente) in desl
            # As fronteiras SAEM das pontas dos segmentos, então um segmento ou cobre o
            # intervalo inteiro ou não toca o seu interior. Não há caso parcial.
            lo <= base && hi >= topo && (cp += quente ? mcp : -mcp)
        end
        intervalos[i] = TemperatureInterval(topo, base, cp, cp * (topo - base))
    end

    # Passo 7 — cascata a partir de zero no topo. O nó `k` está na fronteira `k`.
    infactivel = Vector{Float64}(undef, n + 1)
    infactivel[1] = 0.0
    for i in 1:n
        infactivel[i + 1] = infactivel[i] + intervalos[i].dh
    end

    # Passo 8 — o fluxo mais negativo (ou zero) vira utilidade quente no topo.
    minimo = minimum(infactivel)
    q_h = max(0.0, -minimo)
    factivel = infactivel .+ q_h

    # Passo 9 — os alvos, e o pinch onde o fluxo é nulo.
    q_c = factivel[end]

    # Zero é EXATO no nó que definiu `q_h` (`x + (-x)`), então a tolerância só serve para
    # achar pinches adicionais que chegaram a zero por outro caminho aritmético.
    escala = maximum(abs, factivel; init = 0.0)
    tol = 1e-9 * max(1.0, escala)

    # Só nós INTERIORES. O nó 1 vale QHmin e o último vale QCmin; zero neles significa
    # "esta ponta não precisa de utilidade" — é a ponta livre de um problema-limiar, não
    # um pinch. Chamá-la de pinch faria um problema-limiar relatar um pinch na fronteira
    # mais quente do problema, que é exatamente onde ele não está.
    idx = [k for k in 2:n if abs(factivel[k]) <= tol]
    s_pinch = fronteiras[idx]

    return PinchResult(
        true, "", dt, intervalos, infactivel, factivel, fronteiras,
        q_h, q_c,
        s_pinch, s_pinch .+ dt / 2, s_pinch .- dt / 2,
        q_h <= tol || q_c <= tol,
    )
end

end # module PinchAnalysis
