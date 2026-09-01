"""
O motor de envelope — o diferencial do software.

O que precisa ser verdade:
 (a) com um caso só, o envelope tem de coincidir com o dimensionamento simples;
 (b) com N casos, o vaso escolhido tem de atender a todos, e o caso governante tem
     de ser nomeado corretamente;
 (c) faixas viram cantos;
 (d) quando não existe vaso comum, o resultado é `feasible = false` com diagnóstico —
     nunca uma exceção.
"""

base_values() = FPSOSiz.default_case_values()

@testset "(a) um caso ≡ dimensionamento simples" begin
    vals = base_values()
    single = size_equipment(Separator(), StewartArnold(), stream_from_case(vals), vals)
    env    = size_envelope(Separator(), StewartArnold(), CaseSet([Case("A", vals)]))

    @test env.feasible == single.feasible
    @test env.diameter_mm == single.diameter_mm
    @test env.leff_m ≈ single.leff_m
    @test env.lss_m ≈ single.lss_m
    @test env.sr ≈ single.sr
    @test env.governing === single.governing
    @test env.driver_case == "A"
    @test env.case_names == ["A"]
    @test only(env.slack_m) ≈ 0.0 atol = 1e-12          # sem folga: é o próprio caso
    @test length(env.rows) == length(single.sweep)
end

@testset "(b) o envelope cobre todos os casos" begin
    leve  = base_values()
    pesado = merge(base_values(), Dict(:q_water => 1600.0))   # mais água ⇒ exige mais

    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("leve", leve), Case("pesado", pesado)]))
    @test env.feasible
    @test env.driver_case == "pesado"

    # Em TODO diâmetro da grade, a envelope é o máximo entre os casos.
    for row in env.rows
        @test row.leff_m ≈ maximum(row.per_case_leff)
        @test length(row.per_case_leff) == 2
    end

    # O vaso escolhido atende cada caso individualmente: o Leff envelope é ≥ o de
    # cada caso no mesmo diâmetro.
    escolhida = only(filter(r -> r.d_mm == env.diameter_mm, env.rows))
    @test all(escolhida.per_case_leff .<= escolhida.leff_m + 1e-9)

    # Folga: zero para o caso governante, positiva para o outro.
    i_gov = findfirst(==(env.driver_case), env.case_names)
    @test env.slack_m[i_gov] ≈ 0.0 atol = 1e-9
    @test all(env.slack_m .>= -1e-9)
    @test any(env.slack_m .> 0)

    # É mais exigente que o caso leve sozinho.
    so_leve = size_envelope(Separator(), StewartArnold(), CaseSet([Case("leve", leve)]))
    @test env.leff_m > so_leve.leff_m
end

@testset "(b') o caso governante pode mudar de restrição" begin
    # Um caso rico em líquido (governado pela Eq. 22) e outro com gás muito alto
    # (governado pela Eq. 14). A envelope tem de escolher o certo em cada diâmetro.
    liquido = base_values()
    gas     = merge(base_values(), Dict(:q_gas => 4587.3 * 400, :q_water => 50.0,
                                        :q_oil => 20.0))

    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("líquido", liquido), Case("gás", gas)]))
    @test env.feasible

    # Existem diâmetros governados por cada um dos dois casos.
    drivers = Set(r.driver_case for r in env.rows)
    @test "gás" in drivers
    @test length(drivers) == 2

    # Onde o caso "gás" governa, a restrição governante é a de gás.
    for row in env.rows
        row.driver_case == "gás" && @test row.governing === :gas
    end
end

@testset "(c) faixas viram cantos e o pior canto governa" begin
    vals = merge(base_values(), Dict{Symbol,Any}(
        :q_water => Interval(1025.8, 1600.0),
        :pressure => Interval(2300.0, 2600.0),
    ))
    cs  = CaseSet([Case("faixa", vals)])
    @test corner_count(cs) == 4

    env = size_envelope(Separator(), StewartArnold(), cs)
    @test env.feasible
    @test length(env.case_names) == 4
    @test length(unique(env.case_names)) == 4
    @test all(r -> length(r.per_case_leff) == 4, env.rows)

    # O canto governante é o de maior vazão de água (Eq. 22 é crescente em Qw).
    @test occursin("q_water↑", env.driver_case)

    # E o envelope coincide com dimensionar só o pior canto.
    pior = merge(base_values(), Dict(:q_water => 1600.0, :pressure => 2600.0))
    ref  = size_envelope(Separator(), StewartArnold(), CaseSet([Case("pior", pior)]))
    @test env.diameter_mm == ref.diameter_mm
    @test env.leff_m ≈ ref.leff_m
end

@testset "(d) inviabilidade é estado, não exceção" begin
    @testset "conjunto vazio" begin
        r = size_envelope(Separator(), StewartArnold(), CaseSet())
        @test !r.feasible
        @test occursin("Nenhum caso ativo", r.message)
    end

    @testset "esbeltez fora da banda em toda a grade" begin
        # Grade presa em diâmetros pequenos, com as vazões do caso-ouro: o vaso fica
        # longo e magro demais (SR ≫ 5). O teto de decantação (16,5 m) não interfere,
        # então o diagnóstico tem de apontar a esbeltez.
        vals = merge(base_values(), Dict(:d_min => 3000.0, :d_max => 3300.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("magro", vals)]))
        @test !r.feasible
        @test occursin("esbeltez", r.message)
        # o culpado é a banda de SR, não o teto de decantação (que a mensagem só
        # menciona como contexto, informando a faixa de SR abaixo dele)
        @test !occursin("respeita o teto", r.message)
        @test occursin("banda", r.message)
        @test !isempty(r.rows)                    # a varredura fica disponível p/ a GUI
    end

    @testset "teto de decantação impede toda a grade" begin
        # Vazões minúsculas ⇒ pouca água ⇒ β maior ⇒ d_max pequeno, abaixo da grade.
        vals = merge(base_values(), Dict(:q_oil => 1.0, :q_water => 1.0,
                                         :d_min => 7000.0, :d_max => 8000.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("teto", vals)]))
        @test !r.feasible
        @test occursin("decantação", r.message)
        @test occursin("água em óleo", r.message) # nomeia o mecanismo
    end

    @testset "óleo mais denso que a água" begin
        vals = merge(base_values(), Dict(:rho_oil => 1100.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("denso", vals)]))
        @test !r.feasible
        @test occursin("ΔSG", r.message)
        @test occursin("denso", r.message)        # nomeia o caso culpado
    end

    @testset "entrada de corrente faltando" begin
        r = size_envelope(Separator(), StewartArnold(),
                          CaseSet([Case("incompleto", Dict(:q_oil => 100.0))]))
        @test !r.feasible
        @test occursin("incompleto", r.message)
    end

    @testset "estouro do teto de cantos" begin
        muitos = merge(base_values(),
                       Dict{Symbol,Any}(k => Interval(1.0, 2.0) for k in
                                        (:q_oil, :q_water, :q_gas, :mu_oil, :mu_water)))
        r = size_envelope(Separator(), StewartArnold(),
                          CaseSet([Case("explosivo", muitos)]); max_corners = 8)
        @test !r.feasible
        @test occursin("casos de canto", r.message)
        @test occursin("32", r.message)           # diz quantos seriam
        @test occursin("8", r.message)            # e qual era o limite
    end
end

@testset "resumo de governança" begin
    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("A", base_values())]))
    s = governing_summary(env)
    @test occursin("capacidade de líquido", s)
    @test occursin("A", s)
    @test occursin("decantação", s)
end
