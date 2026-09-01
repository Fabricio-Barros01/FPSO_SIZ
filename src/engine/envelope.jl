"""
Motor de envelope multi-caso — o diferencial do software.

Dado um [`CaseSet`](@ref) com N correntes (e entradas dadas como faixa), entrega **um
único vaso** que atende a todos, e diz qual caso governa cada restrição.

## Por que envelopar em `Leff(d)` e não nos dados de entrada

O caminho ingênuo seria pegar o máximo de cada vazão, o mínimo de cada viscosidade
etc., e dimensionar uma vez. Isso só é válido se todas as restrições forem monótonas em
cada entrada isoladamente — e não são: o bloco de decantação depende da razão `Aw/A`
(Eq. 18), que é uma razão entre vazões, e de β, que é não-linear. O pior caso pode
estar num canto misto.

Envelopar a curva `Leff(d)` é correto por construção: para cada diâmetro da grade,
calcula-se o `Leff` exigido por **cada** caso e toma-se o máximo. O vaso resultante
satisfaz todos os casos em todos os diâmetros, sem hipótese de monotonicidade.

    Leff_env(d) = max_c  max( Leff_gás(d, c), Leff_líq(d, c) )
    d_adm       = min_c  d_max(c)
    Lss(d), SR(d) pela relação do bloco que governa no caso governante

E produz de graça o gráfico que comunica o método: uma curva fina por caso e a
envelope em negrito por cima de todas.
"""

"""
    size_envelope(eq, m, cases::CaseSet; max_corners = 256) -> EnvelopeResult

Dimensiona um vaso único que atende a todos os casos ativos de `cases`.

Cada caso é um dicionário com as chaves de corrente ([`STREAM_KEYS`](@ref)) e os
parâmetros do método; qualquer uma pode ser um [`Interval`](@ref), que é expandido em
casos de canto antes do cálculo.

A grade de diâmetros é a união conservadora das grades pedidas pelos casos: menor
`d_min`, maior `d_max`, menor passo.

## Genérico sobre o equipamento, de propósito

A assinatura aceita qualquer `AbstractEquipment`/`AbstractSizingMethod`, e o corpo não
cita nenhum dos dois: tudo o que ele pede ao método são as três coisas do contrato de
`src/sizing/constraints.jl` — [`sizing_constraints`](@ref), [`method_config`](@ref) e
[`lss_from`](@ref).

Isto não era assim. Até o Sprint 5 a função era declarada sobre `::Separator,
::StewartArnold` e o corpo lia o TOML do separador, montava um vetor de
`SeparatorConstraints` e chamava `separator_constraints`. O efeito prático é que um
segundo equipamento registrado ganharia formulário e dimensionamento de caso único e
**perderia o multi-caso** — o diferencial do software — sem que nada denunciasse a
perda: nenhum erro, nenhum teste vermelho, só um método que a tela não conseguiria
oferecer. `test/envelope.jl` prova a genericidade com um método declarado fora de
`src/`, que não tem física nenhuma.
"""
function size_envelope(eq::AbstractEquipment, m::AbstractSizingMethod, cases::CaseSet;
                       max_corners::Int = 256)
    # Par incoerente é erro de programação, não de dado — mas com dois equipamentos no
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
    conss    = VesselConstraints[]
    per_case = SizingResult[]
    params   = Dict{Symbol,Float64}[]

    for (name, vals) in expanded
        stream = try
            # só as entradas que ESTE método consome: ver `stream_keys`
            stream_from_case(vals; required = stream_keys(m))
        catch err
            err isa ArgumentError &&
                return infeasible_envelope("Caso '$name': $(sprint(showerror, err))")
            rethrow()
        end
        p = with_defaults(specs, vals)
        ok, cons, _ = sizing_constraints(m, stream, p, k)
        ok || return infeasible_envelope("Caso '$name': $cons"; case_names = names)

        push!(names, name)
        push!(conss, cons)
        push!(params, p)
        push!(per_case, size_equipment(eq, m, stream, vals))
    end

    # Grade comum: união conservadora das grades pedidas.
    d_lo   = minimum(p[:d_min]  for p in params)
    d_hi   = maximum(p[:d_max]  for p in params)
    d_step = minimum(p[:d_step] for p in params)
    grid   = collect(d_lo:d_step:d_hi)
    isempty(grid) && return infeasible_envelope(
        "Grade de diâmetros vazia (d_min = $d_lo, d_max = $d_hi, passo = $d_step).";
        case_names = names, per_case)

    # Banda de esbeltez: INTERSEÇÃO, ao contrário da grade logo acima.
    #
    # A assimetria é deliberada e vale a pena explicar, porque as duas linhas parecem
    # fazer a mesma coisa e fazem o oposto. A grade é onde se PROCURA: uni-la (menor
    # d_min, maior d_max) só amplia a busca, e ampliar busca não perde solução. A banda
    # é o que se ACEITA: uni-la afrouxaria a exigência. Com um caso pedindo SR ∈ [3, 5] e
    # outro [3,5 , 4,5], a união aceitaria um vaso com SR = 3,2 — que viola o segundo
    # caso, e o vaso é um só. A interseção é a única leitura em que "atende a todos os
    # casos" continua verdadeira.
    sr_min = maximum(p[:sr_min] for p in params)
    sr_max = minimum(p[:sr_max] for p in params)
    sr_min <= sr_max || return infeasible_envelope(
        "As bandas de esbeltez pedidas pelos casos não se cruzam: o mais exigente pede " *
        "SR ≥ $(sr_min) e outro pede SR ≤ $(sr_max). Como o vaso é um só, não há " *
        "esbeltez que atenda a todos.";
        case_names = names, per_case, d_max_mm = minimum(c.d_max_mm for c in conss))

    # `sr_target` é PREFERÊNCIA, não restrição: é o alvo do desempate entre diâmetros
    # já admissíveis. Por isso a média, e não um extremo — nenhum caso tem direito de
    # veto sobre o gosto dos outros. Depois de fixado, é preso à banda, senão um alvo
    # fora dela empurraria a escolha sempre para a mesma ponta.
    sr_target = clamp(sum(p[:sr_target] for p in params) / length(params),
                      sr_min, sr_max)

    # Teto de decantação: o mais restritivo entre os casos.
    i_dmax     = argmin(c.d_max_mm for c in conss)
    d_max_env  = conss[i_dmax].d_max_mm
    d_max_case = names[i_dmax]

    rows = EnvelopeRow[]
    for d in grid
        per_case_leff = [max(c.d_leff_gas / d, c.d2_leff / d^2) for c in conss]
        leff, idx = findmax(per_case_leff)
        gov = conss[idx].d_leff_gas / d > conss[idx].d2_leff / d^2 ? :gas : :liquid
        lss = lss_from(m, d, leff, gov, k)
        sr  = lss / (d / 1000.0)
        push!(rows, EnvelopeRow(d, leff, lss, sr, gov, names[idx], per_case_leff,
                                sr_min <= sr <= sr_max))
    end

    admissible = filter(r -> r.d_mm <= d_max_env && r.sr_ok, rows)

    if isempty(admissible)
        as_sweep = [SweepRow(r.d_mm, NaN, NaN, r.leff_m, r.lss_m, r.sr, r.governing,
                             r.sr_ok) for r in rows]
        msg = selection_diagnosis(as_sweep, d_max_env, conss[i_dmax].mechanism,
                                  sr_min, sr_max)
        return infeasible_envelope(
            "Não há vaso que atenda simultaneamente aos $(length(names)) casos. " * msg;
            case_names = names, rows, per_case, d_max_mm = d_max_env,
            d_max_case)
    end

    best  = argmin(r -> abs(r.sr - sr_target), admissible)
    slack = [best.leff_m - l for l in best.per_case_leff]

    return EnvelopeResult(true, "", best.d_mm, best.leff_m, best.lss_m, best.sr,
                          vessel_volume(best.d_mm, best.lss_m), best.governing,
                          best.driver_case, d_max_env, d_max_case, names, rows,
                          slack, per_case)
end

"""
    governing_summary(r::EnvelopeResult) -> String

Resumo em uma linha de quem governa o quê — o que a coluna de resultados da GUI e o
relatório exibem.
"""
function governing_summary(r::EnvelopeResult)
    r.feasible || return r.message
    what = r.governing === :gas ? "capacidade de gás" : "capacidade de líquido"
    return "Governa: $what, pelo caso '$(r.driver_case)'. " *
           "Teto de decantação: $(round(Int, r.d_max_mm)) mm, " *
           "imposto pelo caso '$(r.d_max_case)'."
end
