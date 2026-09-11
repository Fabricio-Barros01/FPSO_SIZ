"""
O **encaixe** da Análise Pinch: o descritor repetível, a fronteira de tradução e as duas
restrições duras que a Rota 2 tinha de preservar.

Não há física aqui. O algoritmo está em `test/pinch.jl` e os números publicados em
`test/golden_kemp.jl`; o que se verifica neste arquivo é que a rede chega ao motor
inteira, volta para o disco inteira, e não faz o programa explodir em cantos pelo
caminho.

As duas restrições duras, escritas antes dos testes para que se saiba o que se está
protegendo:

1. **A guarda de proveniência tem de ALCANÇAR os campos de corrente.** Foi a razão de o
   grupo ser um atributo de `ParameterSpec` e não um tipo irmão: `architecture.jl:112`
   itera `Vector{ParameterSpec}`, e um tipo novo sairia da cobertura sem que a guarda
   ficasse vermelha. Guarda que fica verde verificando menos é o pior desfecho possível,
   então aqui se assere que ela verifica mais, e não se supõe.

2. **A contagem de cantos não pode crescer com o número de correntes.** `cases.jl:85`
   recusa acima de 256, e três campos por corrente com mín ≠ máx estourariam o limite
   com seis correntes. Uma rede de N correntes é UM problema de pinch, não 2^N deles.
"""

const PM = FPSOSiz.PinchAnalysis

metodo_pinch() = FPSOSiz.PinchKemp()
alvo_pinch()   = FPSOSiz.PinchTarget()

"As quatro correntes da Tabela 2.2 de Kemp (p. 21), como o formulário as guarda."
function valores_kemp(; dt_alvo = 10.0)
    m = metodo_pinch()
    vals = Dict{Symbol,Any}()
    # Os globais entram pelos defaults do descritor, como `to_case` faz na tela.
    for s in FPSOSiz.parameters(m)
        FPSOSiz.in_group(s) || (vals[s.key] = s.default)
    end
    vals[:dt_min_alvo] = dt_alvo
    for (i, (t_in, t_out, mcp)) in enumerate(((20.0, 135.0, 2.0), (170.0, 60.0, 3.0),
                                              (80.0, 140.0, 4.0), (150.0, 30.0, 1.5)))
        vals[FPSOSiz.instance_key(:corrente, i, :t_in)]  = t_in
        vals[FPSOSiz.instance_key(:corrente, i, :t_out)] = t_out
        vals[FPSOSiz.instance_key(:corrente, i, :mcp)]   = mcp
    end
    return vals
end

# ---------------------------------------------------------------------------
# O descritor repetível
# ---------------------------------------------------------------------------

@testset "o molde declara o grupo; a instância o carrega e sabe quem é" begin
    m = metodo_pinch()
    moldes = filter(FPSOSiz.in_group, FPSOSiz.parameters(m))
    @test length(moldes) == 3
    @test all(FPSOSiz.is_template, moldes)
    @test all(s -> s.group === :corrente, moldes)
    @test Set(s.key for s in moldes) == Set((:t_in, :t_out, :mcp))

    inst = FPSOSiz.group_instance(first(moldes), 3; prefixo = "Corrente")
    @test inst.key === :corrente_3_t_in
    @test inst.group === :corrente          # continua sendo campo de grupo…
    @test inst.instance == 3                # …mas já não é molde
    @test !FPSOSiz.is_template(inst)
    @test startswith(inst.label, "Corrente 3 — ")
    # o que veio do TOML atravessa intacto
    @test inst.unit == first(moldes).unit
    @test inst.note == first(moldes).note
    @test (inst.min, inst.default, inst.max) ==
          (first(moldes).min, first(moldes).default, first(moldes).max)
end

@testset "expandir uma instância é erro, e lança em vez de inventar chave" begin
    m = metodo_pinch()
    molde = first(filter(FPSOSiz.in_group, FPSOSiz.parameters(m)))
    inst = FPSOSiz.group_instance(molde, 1; prefixo = "Corrente")
    # :corrente_1_corrente_1_t_in seria uma chave que nenhum caso tem, e sumiria do
    # formulário sem nada denunciar.
    @test_throws ArgumentError FPSOSiz.group_instance(inst, 2)
    @test_throws ArgumentError FPSOSiz.group_instance(molde, 0)
    # e um campo avulso nunca é expandível
    avulso = first(filter(s -> !FPSOSiz.in_group(s), FPSOSiz.parameters(m)))
    @test_throws ArgumentError FPSOSiz.group_instance(avulso, 1)
end

@testset "instance_key é a única convenção de nome, e é reversível por leitura" begin
    @test FPSOSiz.instance_key(:corrente, 1, :t_in) === :corrente_1_t_in
    @test FPSOSiz.instance_key(:corrente, 12, :mcp) === :corrente_12_mcp
    # duas instâncias diferentes nunca colidem
    todas = [FPSOSiz.instance_key(:corrente, i, k)
             for i in 1:12, k in (:t_in, :t_out, :mcp)]
    @test length(unique(todas)) == length(todas)
end

@testset "o TOML recusa parâmetro órfão e grupo com faixa impossível" begin
    # group que não tem [[group]] correspondente
    @test_throws ErrorException FPSOSiz.parameter_specs(Dict(
        "parameter" => [Dict("key" => "x", "label" => "X", "unit" => "–",
                             "default" => 1.0, "min" => 0.0, "max" => 2.0,
                             "group" => "nao_existe")]))
    # min > max
    @test_throws ErrorException FPSOSiz.group_specs(Dict(
        "group" => [Dict("key" => "g", "label" => "G", "min" => 5, "max" => 2)]))
    # min < 1
    @test_throws ErrorException FPSOSiz.group_specs(Dict(
        "group" => [Dict("key" => "g", "label" => "G", "min" => 0, "max" => 2)]))
end

@testset "os cinco métodos que não têm grupo continuam sem nenhum" begin
    # O atributo é retrocompatível por construção, e isto o prova pelo REGISTRO: um
    # método que nunca ouviu falar de grupo tem de sair daqui com :none em tudo.
    for eq in equipments(), met in methods_for(eq)
        met isa FPSOSiz.PinchKemp && continue
        @test isempty(FPSOSiz.parameter_groups(met))
        for s in vcat(parameters(met), FPSOSiz.stream_parameters(met))
            @test s.group === :none
            @test s.instance == 0
            @test !FPSOSiz.single_box(s)
        end
    end
end

# ---------------------------------------------------------------------------
# Restrição dura 1 — a guarda de proveniência ALCANÇA os campos de corrente
# ---------------------------------------------------------------------------

@testset "a guarda 4 alcança os campos de corrente" begin
    # Esta é a asserção que o atributo existe para permitir, e ela é escrita como a
    # guarda 4 é escrita — iterando o REGISTRO —, para que a prova não dependa de o
    # método Pinch ser citado pelo nome em architecture.jl.
    cobertos = FPSOSiz.ParameterSpec[]
    for eq in equipments(), met in methods_for(eq)
        append!(cobertos, vcat(parameters(met), FPSOSiz.stream_parameters(met)))
    end

    de_corrente = filter(FPSOSiz.in_group, cobertos)

    # 1. Os campos de corrente ESTÃO dentro do que a guarda 4 percorre. Se o grupo
    #    tivesse virado um tipo irmão, esta linha daria zero — e a guarda 4 continuaria
    #    verde, verificando três campos a menos e sem dizer nada.
    @test length(de_corrente) == 3
    @test all(s -> s.group === :corrente, de_corrente)

    # 2. E o que a guarda 4 verifica de fato vale para eles, um por um, com o mesmo
    #    conjunto de asserções de architecture.jl:113-116.
    for spec in de_corrente
        @test !isempty(spec.label)
        @test !isempty(spec.unit)
        @test !isempty(spec.note)
        @test spec.min <= spec.default <= spec.max
    end

    # 3. E a proveniência é proveniência: cita a fonte, não é texto de enfeite.
    for spec in de_corrente
        @test occursin("Tabela 2.2", spec.note)
        @test occursin("p. 21", spec.note)
    end
end

@testset "os ajustes de ΔTmin citam as páginas que os decidem" begin
    m = metodo_pinch()
    por_chave = Dict(s.key => s for s in parameters(m))
    # §3.7.3, p. 82 — o valor adotado, com as duas ressalvas que a página faz
    alvo = por_chave[:dt_min_alvo]
    @test alvo.default == 10.0
    @test occursin("§3.7.3", alvo.note)
    @test occursin("p. 82", alvo.note)
    @test occursin("2–3 K", alvo.note)                   # criogenia, em K e não em °C
    @test occursin("U", alvo.note)                       # o motivo do ΔTmin alto
    # §3.7.2, p. 82 — a faixa do ótimo achatado é a grade
    @test por_chave[:dt_min_min].default == 5.0
    @test por_chave[:dt_min_max].default == 50.0
    for k in (:dt_min_min, :dt_min_max)
        @test occursin("§3.7.2", por_chave[k].note)
    end
    # e os quatro são decisão de projeto, não dado de corrente
    @test Set(FPSOSiz.global_keys(m)) ==
          Set((:dt_min_min, :dt_min_max, :dt_min_step, :dt_min_alvo))
end

# ---------------------------------------------------------------------------
# Restrição dura 2 — a contagem de cantos não cresce com as correntes
# ---------------------------------------------------------------------------

@testset "corner_count não cresce com o número de correntes" begin
    m = metodo_pinch()
    anterior = 0
    for n in 2:12
        vals = Dict{Symbol,Any}()
        for s in parameters(m)
            FPSOSiz.in_group(s) || (vals[s.key] = s.default)
        end
        for i in 1:n, k in (:t_in, :t_out, :mcp)
            vals[FPSOSiz.instance_key(:corrente, i, k)] = i * 10.0 + Float64(length(String(k)))
        end
        c = FPSOSiz.Case("rede de $n", vals)
        @test FPSOSiz.corner_count(c) == 1
        @test isempty(FPSOSiz.interval_keys(c))
        n > 2 && @test FPSOSiz.corner_count(c) == anterior
        anterior = FPSOSiz.corner_count(c)
    end

    # A prova de que o limite é real, e não folgado: se os campos de corrente pudessem
    # ser faixa, seis correntes já estourariam o teto de `expand`. É por isso que
    # `single_box` existe.
    vals = Dict{Symbol,Any}()
    for i in 1:6, k in (:t_in, :t_out, :mcp)
        vals[FPSOSiz.instance_key(:corrente, i, k)] = FPSOSiz.Interval(10.0, 20.0)
    end
    hipotetico = FPSOSiz.Case("se fossem faixas", vals)
    @test FPSOSiz.corner_count(hipotetico) == 2^18
    @test_throws ArgumentError FPSOSiz.expand(FPSOSiz.CaseSet([hipotetico]))

    # E os três moldes declaram uma caixa só, que é o que impede o caso acima.
    @test all(FPSOSiz.single_box, filter(FPSOSiz.in_group, parameters(m)))
end

# ---------------------------------------------------------------------------
# A fronteira de tradução
# ---------------------------------------------------------------------------

@testset "case_input converte as instâncias em Vector{ThermalStream}" begin
    correntes = FPSOSiz.case_input(metodo_pinch(), valores_kemp())
    @test correntes isa Vector{PM.ThermalStream}
    @test length(correntes) == 4
    @test [PM.stream_type(s) for s in correntes] == [:cold, :hot, :cold, :hot]
    # os números da Tabela 2.2, na ordem das instâncias
    @test [only(s.segments).t_in  for s in correntes] == [20.0, 170.0, 80.0, 150.0]
    @test [only(s.segments).t_out for s in correntes] == [135.0, 60.0, 140.0, 30.0]
    @test [only(s.segments).mcp   for s in correntes] == [2.0, 3.0, 4.0, 1.5]
    # o nome é sintetizado do índice, e é o que as mensagens de recusa citam
    @test [s.name for s in correntes] == ["Corrente $i" for i in 1:4]
end

@testset "case_input lança — e só ele lança, e só como fronteira" begin
    m = metodo_pinch()

    # instância pela metade: recusada, não completada com o default do descritor
    meia = valores_kemp()
    delete!(meia, :corrente_3_mcp)
    err = try; FPSOSiz.case_input(m, meia); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("pela metade", sprint(showerror, err))
    @test occursin("corrente_3_mcp", sprint(showerror, err))

    # rede vazia
    vazia = Dict{Symbol,Any}(:dt_min_alvo => 10.0)
    @test_throws ArgumentError FPSOSiz.case_input(m, vazia)

    # buraco no meio NÃO é erro: 1, 2 e 4 descrevem três correntes, e a 3 simplesmente
    # não existe. É o que `instancias_dos_valores` e o arquivo de casos permitem.
    com_buraco = valores_kemp()
    for k in (:t_in, :t_out, :mcp)
        delete!(com_buraco, FPSOSiz.instance_key(:corrente, 3, k))
    end
    @test length(FPSOSiz.case_input(m, com_buraco)) == 3
end

@testset "o motor converte a exceção da fronteira em inviabilidade" begin
    # `envelope.jl:61` e `:76-79` são os dois `try` que existem para isto. A recusa tem
    # de chegar ao usuário como mensagem com o NOME do caso, nunca como exceção.
    m, eq = metodo_pinch(), alvo_pinch()
    meia = valores_kemp()
    delete!(meia, :corrente_2_t_out)
    cs = FPSOSiz.CaseSet([FPSOSiz.Case("cenário incompleto", meia)])

    r = FPSOSiz.size_envelope(eq, m, cs)
    @test !r.feasible
    @test occursin("cenário incompleto", r.message)
    @test occursin("pela metade", r.message)
    @test isnan(r.x)
end

@testset "corrente inválida vira mensagem de sizing_constraints, não exceção" begin
    # O outro idioma de falha: `sizing_constraints` devolve (ok, msg, tr). Um segmento
    # isotérmico é dado ruim, não fronteira, e a receita da p. 44 tem de vir junto.
    m, eq = metodo_pinch(), alvo_pinch()
    vals = valores_kemp()
    vals[:corrente_1_t_out] = vals[:corrente_1_t_in]
    r = FPSOSiz.size_envelope(eq, m, FPSOSiz.CaseSet([FPSOSiz.Case("isotérmica", vals)]))
    @test !r.feasible
    @test occursin("isotérmico", r.message)
    @test occursin("p. 44", r.message)
end

# ---------------------------------------------------------------------------
# O contrato preenchido: o que o motor pede, o método responde
# ---------------------------------------------------------------------------

@testset "o método está registrado e o par equipamento↔método fecha" begin
    m, eq = metodo_pinch(), alvo_pinch()
    @test FPSOSiz.method_id(eq) === :pinch
    @test FPSOSiz.method_id(m) === :pinch_kemp
    @test FPSOSiz.method_id(FPSOSiz.applies_to(m)) === FPSOSiz.method_id(eq)
    @test FPSOSiz.sizing_method(:pinch, :pinch_kemp) !== nothing
    @test FPSOSiz.equipment(:pinch) !== nothing
    # não é vaso, e não pode passar por um
    @test !(m isa FPSOSiz.AbstractVesselMethod)
    # não contribui campo de corrente de óleo/água/gás
    @test FPSOSiz.stream_keys(m) == ()
    @test isempty(FPSOSiz.stream_parameters(m))
    # a fonte que o memorial cita
    @test occursin("Kemp", FPSOSiz.method_reference(m))
    @test occursin("§3.9.1", FPSOSiz.method_reference(m))
end

@testset "o eixo é o ΔTmin, e a exigência é o QHmin" begin
    m = metodo_pinch()
    p = FPSOSiz.with_defaults(parameters(m), Dict{Symbol,Float64}())
    eixo = FPSOSiz.sweep_axis(m, p)
    @test eixo.key === :dt_min
    @test eixo.unit == "°C"
    @test first(eixo.values) == 5.0 && last(eixo.values) == 50.0
    @test p[:dt_min_alvo] in eixo.values     # o alvo é atingível pela grade

    correntes = FPSOSiz.case_input(m, valores_kemp())
    ok, cons, _ = FPSOSiz.sizing_constraints(m, correntes, p, Dict{Symbol,Any}())
    @test ok

    # `requirement` é exatamente o QHmin do núcleo puro — nenhuma física reimplementada
    for dt in (5.0, 10.0, 20.0, 50.0)
        @test FPSOSiz.requirement(m, dt, cons) == PM.problem_table(correntes, dt).q_h_min
    end
    # e é não-decrescente, que é o que autoriza chamá-la de exigência
    qs = [FPSOSiz.requirement(m, x, cons) for x in eixo.values]
    @test all(diff(qs) .>= -1e-9)

    # nenhum ponto da grade é inadmissível: não há critério a citar para recusar um
    @test all(x -> FPSOSiz.case_admissible(m, x, cons, p), eixo.values)
    @test FPSOSiz.ceiling_of(m, cons) == Inf
end

@testset "o dimensionamento reproduz os números publicados, pelo motor" begin
    # `golden_kemp.jl` já prova o algoritmo. O que se prova AQUI é que o encaixe não
    # perde nem desloca nada pelo caminho: o mesmo resultado, saindo por `size_envelope`.
    m, eq = metodo_pinch(), alvo_pinch()
    cs = FPSOSiz.CaseSet([FPSOSiz.Case("Tabela 2.2", valores_kemp())])
    @test FPSOSiz.corner_count(cs) == 1

    r = FPSOSiz.size_envelope(eq, m, cs)
    @test r.feasible
    @test r.x == 10.0                                  # o ΔTmin declarado
    @test r.y ≈ 20.0                                   # QHmin, p. 24
    @test FPSOSiz.der(r, :qcmin) ≈ 60.0                # QCmin, p. 24
    @test FPSOSiz.der(r, :t_pinch_deslocada) ≈ 85.0
    @test FPSOSiz.der(r, :t_pinch_quente) ≈ 90.0
    @test FPSOSiz.der(r, :t_pinch_fria) ≈ 80.0
    @test FPSOSiz.der(r, :n_pinch) == 1.0
    @test FPSOSiz.der(r, :threshold) == 0.0
    @test FPSOSiz.der(r, :n_correntes) == 4.0
    @test FPSOSiz.der(r, :n_quentes) == 2.0 && FPSOSiz.der(r, :n_frias) == 2.0
    # o balanço de entalpia da p. 24, que não depende de ΔTmin nenhum
    @test FPSOSiz.der(r, :qcmin) - r.y ≈
          FPSOSiz.der(r, :q_hot) - FPSOSiz.der(r, :q_cold)
    @test FPSOSiz.der(r, :recuperacao) ≈ FPSOSiz.der(r, :q_hot) - FPSOSiz.der(r, :qcmin)
end

@testset "o problema-limiar do §3.3.2 chega ao cartão dizendo o que é" begin
    # Abaixo de 5,55 °C nenhuma utilidade quente é exigida, e não há mais pinch. O
    # cartão não pode mostrar um travessão calado — tem de dizer por quê.
    m, eq = metodo_pinch(), alvo_pinch()
    vals = valores_kemp(; dt_alvo = 5.0)
    vals[:dt_min_min] = 1.0
    r = FPSOSiz.size_envelope(eq, m, FPSOSiz.CaseSet([FPSOSiz.Case("limiar", vals)]))
    @test r.feasible
    @test r.x == 5.0
    @test r.y ≈ 0.0                                    # QHmin zerou
    @test FPSOSiz.der(r, :threshold) == 1.0
    @test FPSOSiz.der(r, :n_pinch) == 0.0
    @test isnan(FPSOSiz.der(r, :t_pinch_deslocada))

    campos = FPSOSiz.result_fields(m, r)
    situacao = only(filter(f -> f.label == "Situação do pinch", campos))
    @test situacao.value == "sem pinch (problema-limiar)"
end

@testset "o envelope toma o pior cenário, e diz qual é" begin
    m, eq = metodo_pinch(), alvo_pinch()
    # Dois cenários da MESMA rede: no segundo, a corrente quente 2 entrega menos calor.
    magro = valores_kemp()
    magro[:corrente_2_mcp] = 1.0
    cs = FPSOSiz.CaseSet([FPSOSiz.Case("nominal", valores_kemp()),
                          FPSOSiz.Case("quente fraca", magro)])
    r = FPSOSiz.size_envelope(eq, m, cs)
    @test r.feasible
    # menos calor quente disponível é MAIS utilidade quente exigida
    @test r.driver_case == "quente fraca"
    @test r.y > 20.0
    @test length(r.slack) == 2
    @test minimum(r.slack) ≈ 0.0                  # o governante tem folga zero
    @test FPSOSiz.governing_label(m, r.governing) == "utilidade quente (QHmin)"
end

@testset "o cartão diz o que a tela NÃO faz, e o texto vem do Julia" begin
    # Regra B2 antecipada: o aviso de escopo é texto de domínio, logo não pode estar
    # escrito no HTML. Aqui se fixa que ele existe e que sai de `result_fields`.
    m, eq = metodo_pinch(), alvo_pinch()
    r = FPSOSiz.size_envelope(eq, m,
            FPSOSiz.CaseSet([FPSOSiz.Case("Tabela 2.2", valores_kemp())]))
    campos = FPSOSiz.result_fields(m, r)
    aviso = first(campos).value
    @test aviso isa String
    @test occursin("NÃO dimensiona", aviso)
    @test occursin("NÃO sintetiza", aviso)
    # e as colunas da varredura também são declaradas, não escritas na tela
    cols = FPSOSiz.sweep_columns(m)
    @test [c.key for c in cols] == [:x, :y, :qcmin, :recuperacao, :t_pinch_deslocada]
    @test all(c -> !isempty(c.label), cols)
end

@testset "o memorial carrega o balanço de entalpia como conferência" begin
    m, eq = metodo_pinch(), alvo_pinch()
    r = FPSOSiz.size_equipment(eq, m, FPSOSiz.case_input(m, valores_kemp()),
                               valores_kemp())
    @test r.feasible
    blocos = FPSOSiz.trace_block_order(r.trace)
    @test :correntes in blocos
    @test :selection in blocos
    # uma linha por corrente, mais as duas somas
    @test length(FPSOSiz.block_entries(r.trace, :correntes)) == 6
    fecho = FPSOSiz.block_entries(r.trace, :selection)
    balanco = only(filter(e -> e.var == "QCmin − QHmin", fecho))
    @test balanco.value ≈ 40.0                        # 660 − 620, e também 60 − 20
    @test occursin("p. 24", balanco.eq) || occursin("balanço", balanco.formula)
end
