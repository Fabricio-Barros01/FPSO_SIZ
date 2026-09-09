"""
Motor de envelope multi-caso — o diferencial do software.

Dado um [`CaseSet`](@ref) com N correntes (e entradas dadas como faixa), entrega **um
único equipamento** que atende a todos, e diz qual caso governa cada restrição.

## Por que envelopar a curva de exigência e não os dados de entrada

O caminho ingênuo seria pegar o máximo de cada vazão, o mínimo de cada viscosidade
etc., e dimensionar uma vez. Isso só é válido se todas as restrições forem monótonas em
cada entrada isoladamente — e não são: no separador o bloco de decantação depende da
razão `Aw/A` (Eq. 18), que é uma razão entre vazões, e de β, que é não-linear. O pior
caso pode estar num canto misto.

Envelopar a curva `y(x)` é correto por construção: para cada ponto da grade, calcula-se
o que **cada** caso exige e toma-se o máximo. O equipamento resultante satisfaz todos os
casos em todos os pontos, sem hipótese de monotonicidade.

    y_env(x) = max_c  requirement(m, x, cons_c)
    x_adm    = min_c  ceiling_of(m, cons_c)

E produz de graça o gráfico que comunica o método: uma curva fina por caso e a envelope
em negrito por cima de todas.

## Genérico sobre o equipamento **e sobre a grandeza**

O corpo não cita diâmetro, `Leff` nem esbeltez: tudo o que ele pede ao método são os
hooks de `src/engine/contract.jl`. Isso não era assim. Até o Sprint 5 a função era
declarada sobre `::Separator, ::StewartArnold`; o Sprint 6 a soltou do equipamento, e
este sprint a soltou da grandeza. O efeito prático de não fazer isto seria que um
equipamento que não fosse vaso ganharia formulário e caso único e **perderia o
multi-caso** — o diferencial do software — sem que nada denunciasse a perda.

`test/envelope.jl` prova as duas genericidades com métodos declarados fora de `src/`:
um vaso fictício sem física, e um equipamento que não é vaso nenhum.
"""

"""
    size_envelope(eq, m, cases::CaseSet; max_corners = 256) -> EnvelopeResult

Dimensiona um equipamento único que atende a todos os casos ativos de `cases`.

Cada caso é um dicionário com as entradas que [`case_input`](@ref) do método consome e
os parâmetros dele; qualquer uma pode ser um [`Interval`](@ref), que é expandido em
casos de canto antes do cálculo.
"""
function size_envelope(eq::AbstractEquipment, m::AbstractSizingMethod, cases::CaseSet;
                       max_corners::Int = 256)
    # Par incoerente é erro de programação, não de dado — mas com vários equipamentos no
    # registro ele passa a ser possível, e silenciosamente produziria números do método
    # errado para o equipamento mostrado na tela.
    method_id(applies_to(m)) === method_id(eq) || return infeasible_envelope(
        "O método '$(label(m))' não se aplica a '$(label(eq))'.")

    specs = parameters(m)
    k     = constants(method_config(m))

    expanded = try
        expand(cases; max_corners)
    catch err
        err isa ArgumentError && return infeasible_envelope(sprint(showerror, err))
        rethrow()
    end
    isempty(expanded) && return infeasible_envelope(
        "Nenhum caso ativo. Adicione ao menos uma corrente.")

    names    = String[]
    conss    = Any[]
    per_case = SizingResult[]
    params   = Dict{Symbol,Float64}[]

    for (name, vals) in expanded
        entrada = try
            # só as entradas que ESTE método consome: ver `case_input` e `stream_keys`
            case_input(m, vals)
        catch err
            err isa ArgumentError &&
                return infeasible_envelope("Caso '$name': $(sprint(showerror, err))")
            rethrow()
        end
        p = with_defaults(specs, vals)
        ok, cons, _ = sizing_constraints(m, entrada, p, k)
        ok || return infeasible_envelope("Caso '$name': $cons"; case_names = names)

        push!(names, name)
        push!(conss, cons)
        push!(params, p)
        push!(per_case, size_equipment(eq, m, entrada, vals))
    end

    # Uma grade e uma banda para N casos — o equipamento é um só. A regra é do método:
    # ver `envelope_params`, e a assimetria grade-união × banda-interseção documentada lá.
    ok_p, p_env = envelope_params(m, params)
    ok_p || return infeasible_envelope(p_env; case_names = names, per_case,
                                       ceiling = _menor_teto(m, conss)[1])

    eixo = sweep_axis(m, p_env)
    isempty(eixo.values) && return infeasible_envelope(
        "Grade de $(eixo.label) vazia.";  case_names = names, per_case)

    # Teto: o mais restritivo entre os casos.
    teto, i_teto = _menor_teto(m, conss)
    mecan = conss[i_teto] isa VesselConstraints ? conss[i_teto].mechanism : :none

    rows = EnvelopeRow[]
    for x in eixo.values
        per_case_y = [requirement(m, x, c) for c in conss]
        y, idx = findmax(per_case_y)
        gov = governing_of(m, x, conss[idx])
        d   = derived(m, x, y, gov, conss[idx], k, p_env)
        # A admissibilidade tem três camadas, e as três são necessárias: o teto (o
        # menor entre os casos, já resolvido acima), o que CADA caso aceita em `x` — a
        # banda de velocidade de uma linha é por vazão, e a vazão é do caso — e o que o
        # conjunto aceita, que só o governante sabe dizer. Ver `case_admissible`.
        ok = x <= teto && all(c -> case_admissible(m, x, c, p_env), conss) &&
             admissible(m, x, d, p_env)
        push!(rows, EnvelopeRow(x, y, d, gov, names[idx], per_case_y, ok))
    end

    admissivel = filter(r -> r.ok, rows)

    if isempty(admissivel)
        msg = selection_message(m, rows, teto, p_env; mechanism = mecan) *
              _sem_intersecao(m, eixo, conss, names, p_env)
        return infeasible_envelope(
            "Não há equipamento que atenda simultaneamente aos $(length(names)) " *
            "casos. " * msg;
            case_names = names, rows, per_case, ceiling = teto,
            ceiling_case = names[i_teto], ceiling_mechanism = mecan)
    end

    best  = argmin(r -> objective(m, r.x, r.derivados, p_env), admissivel)
    slack = [best.y - v for v in best.per_case_y]

    return EnvelopeResult(true, "", best.x, best.y, best.derivados, best.governing,
                          best.driver_case, teto, names[i_teto], mecan, names, rows,
                          slack, per_case)
end

"""
    _sem_intersecao(m, eixo, conss, names, p) -> String

A frase que só o motor pode escrever: **cada caso, sozinho, tem solução, e elas não se
cruzam.**

Existe porque [`selection_message`](@ref) não alcança esse diagnóstico. Ela recebe as
linhas da varredura, e os derivados de cada linha vêm do caso **governante** — o de maior
exigência naquele ponto. Quando a recusa vem de outro caso (uma vazão menor que deixa a
velocidade cair abaixo do piso, um teto de decantação mais baixo), o método olha para os
números do governante, não vê nada de errado com eles, e escreve uma frase que não
corresponde ao que houve. Foi exatamente o que aconteceu com a primeira versão do exemplo
de bomba: a mensagem acusava cavitação com folga de NPSH de +26 m.

O motor tem a informação que falta — as restrições de todos os casos — e a pergunta é
genérica: as duas camadas que variam por caso são o teto e [`case_admissible`](@ref).
Devolve string vazia quando não é esse o problema, para não acrescentar ruído ao
diagnóstico que o método já deu.
"""
function _sem_intersecao(m::AbstractSizingMethod, eixo::SweepAxis, conss, names,
                         p::AbstractDict)
    length(conss) >= 2 || return ""
    aceitos = [[x for x in eixo.values
                if x <= ceiling_of(m, c) && case_admissible(m, x, c, p)] for c in conss]
    any(isempty, aceitos) && return ""          # há caso sem solução: outro problema
    isempty(intersect(aceitos...)) || return ""  # cruzam-se: outro problema

    faixas = [string("'", n, "' aceita ", _faixa_texto(s), " ", eixo.unit)
              for (n, s) in zip(names, aceitos)]
    return " Isolado, cada caso tem $(eixo.label) admissível, mas as faixas não se " *
           "cruzam: " * join(faixas, "; ") * ". Como o equipamento é um só, amplie a " *
           "banda, ou trate os casos em equipamentos separados."
end

_faixa_texto(s) = length(s) == 1 ? string(round(only(s), digits = 2)) :
                  string(round(minimum(s), digits = 2), "–",
                         round(maximum(s), digits = 2))

"O menor teto entre os casos, e o índice do caso que o impôs."
function _menor_teto(m::AbstractSizingMethod, conss)
    isempty(conss) && return (Inf, 0)
    tetos = [ceiling_of(m, c) for c in conss]
    i = argmin(tetos)
    return (tetos[i], i)
end

"""
    governing_summary(m, r::EnvelopeResult) -> String

Resumo em uma linha de quem governa o quê — o que a coluna de resultados da GUI e o
relatório exibem.

Recebe o método porque só ele sabe chamar `:gas` de "capacidade de gás" e `:atrito` de
"perda de carga". O motor carimba o símbolo; a tradução é de quem o carimbou.
"""
function governing_summary(m::AbstractSizingMethod, r::EnvelopeResult)
    r.feasible || return r.message
    resumo = "Governa: $(governing_label(m, r.governing)), " *
             "pelo caso '$(r.driver_case)'."

    # Nem todo equipamento tem teto: um vaso bifásico não tem duas fases líquidas a
    # separar, e `ceiling` vale `Inf` por direito. Sem teto, cala-se em vez de inventar
    # um número — o `round(Int, Inf)` que estava aqui lançava `InexactError`.
    isfinite(r.ceiling) || return resumo
    return resumo * " Teto de decantação: $(round(Int, r.ceiling)) mm, " *
                    "imposto pelo caso '$(r.ceiling_case)'."
end
