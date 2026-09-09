"""
Tratador eletrostático — Stewart & Arnold (2008), §4.7 a §4.9.6.

**Não há caso-ouro.** O livro não traz exemplo resolvido de tratador, e o volume que
trataria do campo elétrico (*Emulsions and Oil Treating*) não está em `References/`.
Por isso este arquivo não se chama `golden_*`: o que ele amarra são as **três relações
internas da fonte** que permitem decidir qual coeficiente impresso é o certo, mais a
geometria, que é exata, mais o comportamento do método.

A verificação mais forte que este box tem é a de que os coeficientes se conferem
mutuamente: o livro imprime a mesma equação em quatro lugares e em duas unidades, e as
quatro só fecham com um dos dois valores impressos. É isso que os primeiros três
testsets fazem.
"""

const K_TRATADOR = FPSOSiz.constants(FPSOSiz.method_config(ArnoldElectrostatic()))
const IN_MM = FPSOSiz.Units.INCH_M * 1000

@testset "o coeficiente de decantação: 0,033, e não os 0,0033 da Eq. 4.5b" begin
    # O livro imprime a MESMA equação com dois valores, num fator de 10:
    #   Eq. (4.5b)      h_o = 0,0033·(tr)o·ΔSG·d_m²/µ
    #   §4.9.3 passo 3  h_o = 0,033 ·(tr)o·ΔSG·d_m²/µ
    # Três conferências independentes apontam para 0,033.
    c = float(K_TRATADOR[:settling_coefficient])
    @test c == 0.033

    @testset "1. fecha com a Eq. 4.6b do próprio livro" begin
        # Eq. (4.6b): para d_m = 500 µm, (h_o)max = 8250·(tr)o·ΔSG/µ.
        @test c * 500^2 ≈ 8250.0
        @test 0.0033 * 500^2 ≈ 825.0        # dez vezes menos — não é a Eq. 4.6b
    end

    @testset "2. fecha com a conversão exata da forma de campo" begin
        # Eq. (4.6a): (h_o)max = 320·(tr)o·ΔSG/µ, com h em polegadas.
        @test isapprox(320 * IN_MM, c * 500^2; rtol = 0.02)      # 8128 vs 8250: 1,5 %
        @test !isapprox(320 * IN_MM, 0.0033 * 500^2; rtol = 0.5) # 8128 vs 825
        # e a forma geral de campo, Eq. (4.5a)
        @test isapprox(0.00128 * 500^2, 320.0; rtol = 1e-9)
    end

    @testset "3. é o mesmo que o separador trifásico já usava" begin
        # Desde o Sprint 1, por Alves & Komesu — que reproduzem este livro. A fonte
        # primária confirma o valor e denuncia a própria errata.
        k_sep = FPSOSiz.constants(FPSOSiz.method_config(StewartArnold()))
        @test float(k_sep[:eq17_coefficient]) == c
    end
end

@testset "a Eq. 4.9b tem erro de digitação: 1520 deveria ser 1320" begin
    c = float(K_TRATADOR[:settling_coefficient])
    # A Eq. (4.9b) imprime (h_w)max = 1520·(tr)w·ΔSG/µ_w para d_m = 200 µm.
    # A forma geral com 0,033 dá:
    @test c * 200^2 ≈ 1320.0
    # E a conversão exata da Eq. (4.9a) de campo (51,2 in) dá:
    exato = 51.2 * IN_MM                                  # ≈ 1300,5 mm
    @test isapprox(exato, 1320.0; rtol = 0.02)            # 1,5 %
    @test !isapprox(exato, 1520.0; rtol = 0.05)           # 17 % — fora de qualquer
    # e a forma geral de campo é consistente com a especializada
    @test isapprox(0.00128 * 200^2, 51.2; rtol = 1e-9)
end

@testset "o coeficiente de retenção fecha com a forma de vaso meio cheio" begin
    c = float(K_TRATADOR[:retention_coefficient])
    @test c == 21000.0
    # Eq. (4.15b) com α = 0,5 tem de reproduzir a Eq. (4.4b), d²Leff = 4,2×10⁴·(...).
    @test c / 0.5 ≈ 42000.0
    # A conversão exata da forma de campo (1,42) dá 42152 — 0,36 % acima do publicado.
    # Não é contradição interna, então segue-se o publicado; o contraste deliberado é
    # com a Eq. 22 do trifásico, cujo impresso erra 1,9 % contra a tabela do artigo.
    exato = FPSOSiz.Units.liquid_capacity_coefficient()
    @test isapprox(c / 0.5, exato; rtol = 0.005)
    @test !isapprox(4.12e4, exato; rtol = 0.005)
end

@testset "Eq. 4.17 — a altura do segmento circular é geometria exata" begin
    @testset "os extremos" begin
        @test segment_height_fraction(0.0) == 0.0
        @test segment_height_fraction(1.0) == 1.0
        @test isapprox(segment_height_fraction(0.5), 0.5; atol = 1e-9)
    end

    @testset "é a inversa da área do segmento" begin
        # A área fracionária de um segmento de altura relativa b:
        #   a(b) = (1/π)·[acos(1−2b) − (1−2b)·√(4b(1−b))]
        area(b) = (acos(1 - 2b) - (1 - 2b) * sqrt(max(4b * (1 - b), 0.0))) / π
        for a in 0.02:0.03:0.98
            @test isapprox(area(segment_height_fraction(a)), a; atol = 1e-9)
        end
    end

    @testset "é monótona, e simétrica em torno do meio" begin
        hs = [segment_height_fraction(a) for a in 0.0:0.05:1.0]
        @test issorted(hs)
        for a in 0.05:0.05:0.45
            @test isapprox(segment_height_fraction(a) +
                           segment_height_fraction(1 - a), 1.0; atol = 1e-8)
        end
    end

    @testset "β do vaso meio cheio continua sendo 0,5 − h_w/d" begin
        # A Figura 3 do trifásico é um caso particular desta geometria; refatorá-la não
        # pode ter movido nenhum dos pontos que `test/beta.jl` fixa.
        for a in (0.1, 0.25, 0.4131)
            @test beta_coefficient(a) ≈ 0.5 - segment_height_fraction(a)
        end
    end
end

# ---------------------------------------------------------------------------
# O método
# ---------------------------------------------------------------------------

tratador_defaults() =
    merge(defaults(FPSOSiz.stream_parameters(ArnoldElectrostatic())),
          defaults(parameters(ArnoldElectrostatic())))

@testset "o tratador dimensiona, e sem bloco de gás" begin
    vals = tratador_defaults()
    entrada = FPSOSiz.case_input(ArnoldElectrostatic(), vals)
    ok, cons, tr = FPSOSiz.sizing_constraints(
        ArnoldElectrostatic(), entrada,
        with_defaults(parameters(ArnoldElectrostatic()), vals), K_TRATADOR)
    @test ok

    @testset "d·Leff de gás é ZERO, não NaN" begin
        # Zero é a exigência honesta de um vaso sem fase gasosa. NaN contaminaria o
        # `max` do motor e faria a envelope inteira sumir.
        @test cons.d_leff_gas == 0.0
        @test isfinite(cons.d2_leff) && cons.d2_leff > 0
        # e por isso o líquido governa em todo diâmetro
        for d in (900.0, 3000.0, 6000.0)
            @test FPSOSiz.governing_of(ArnoldElectrostatic(), d, cons) === :liquid
            @test FPSOSiz.requirement(ArnoldElectrostatic(), d, cons) ≈ cons.d2_leff / d^2
        end
    end

    @testset "o memorial não tem Bloco A, nem promete um" begin
        @test isempty(FPSOSiz.block_entries(tr, :gas))
        titulos = [t for (_, t) in FPSOSiz.trace_blocks(ArnoldElectrostatic())]
        @test !any(t -> occursin("gás", lowercase(t)), titulos)
        @test length(titulos) == 3
        # e `per_constraint` não devolve uma curva de zeros rotulada ":gas"
        pc = FPSOSiz.per_constraint(ArnoldElectrostatic(), 3000.0, cons)
        @test keys(pc) == Set([:liquid])
    end

    @testset "a seção transversal é de vaso CHEIO — duas faixas, sem gás" begin
        # O defeito que este testset fixa: `VesselConstraints.beta` guarda aqui a altura
        # do óleo num vaso CHEIO (β_o = β_l − β_w, com β_l = 1), e não num vaso meio
        # cheio. Quem herdasse o `cross_section` da família recebia
        #   água = 0,5 − 0,8965 = −0,3965  →  camada de altura NEGATIVA
        #   gás  = 0,5                     →  metade de gás num vaso sem fase gasosa
        # e o desenho saía com a faixa de água invertida sob um céu de gás inventado.
        faixas = FPSOSiz.cross_section(ArnoldElectrostatic(), cons)

        @test length(faixas) == 2
        @test [l.fase for l in faixas] == [:water, :oil]      # água embaixo
        @test !any(l -> l.fase === :gas, faixas)
        @test all(l -> l.fracao > 0, faixas)                  # nenhuma altura negativa
        @test sum(l.fracao for l in faixas) ≈ 1.0             # ocupam a seção inteira

        # β_w = 1 − β_o: as duas fases repartem a seção toda (Eq. 4.17 com α = 1)
        @test faixas[1].fracao ≈ 1 - cons.beta
        @test faixas[2].fracao ≈ cons.beta

        @testset "e o β daqui passa de 0,5, que é o que quebrava a dedução" begin
            @test cons.beta > 0.5
            @test 0.5 - cons.beta < 0        # a conta que a família faria
        end

        @testset "α = 1 é o que põe as duas faixas na seção inteira" begin
            # Se α deixasse de ser 1, β_l deixaria de ser 1 e sobraria fase gasosa —
            # que este método não dimensiona. É a mesma razão que mantém α constante.
            @test segment_height_fraction(
                float(K_TRATADOR[:liquid_area_fraction])) == 1.0
        end
    end

    @testset "as entradas de gás somem do formulário" begin
        chaves = Set(s.key for s in FPSOSiz.stream_parameters(ArnoldElectrostatic()))
        for k in (:q_gas, :rho_gas, :mu_gas, :z, :pressure, :temperature)
            @test !(k in chaves)
        end
        for k in (:q_oil, :q_water, :rho_oil, :rho_water, :mu_oil, :mu_water)
            @test k in chaves
        end
    end

    res = size_equipment(ElectrostaticTreater(), ArnoldElectrostatic(), entrada, vals)
    @test res.feasible
    @test vals[:sr_min] <= res.derivados[:sr] <= vals[:sr_max]

    @testset "Lss é o MAIOR dos dois candidatos — §4.9.1" begin
        d, leff = res.x, res.y
        @test res.derivados[:lss] ≈ max(leff + d / 1000,
                                        float(K_TRATADOR[:lss_liquid_factor]) * leff)
        @test res.derivados[:lss] >= leff + d / 1000
        @test res.derivados[:lss] >= 4 / 3 * leff
    end

    @testset "o memorial cita §4.9.2 para a esbeltez, e não a Eq. 24 do artigo" begin
        sel = FPSOSiz.block_entries(res.trace, :selection)
        sr = only(filter(e -> e.var == "SR", sel))
        @test sr.eq == "§4.9.2"
        @test sr.eq != "Eq. 24"
        # e cada vaso cita a sua fonte
        @test slenderness_equation(StewartArnold()) == "Eq. 24"
        @test slenderness_equation(StewartArnoldTwoPhase()) == "§3.8.5"
    end
end

@testset "o campo elétrico é operativo, não decorativo" begin
    # A premissa central do box é `dm_water`, e ela entra pelo QUADRADO (Stokes). Se ela
    # não mudasse o resultado, o box seria um decantador com outro nome.
    base = tratador_defaults()

    tratado = size_equipment(ElectrostaticTreater(), ArnoldElectrostatic(),
                             FPSOSiz.case_input(ArnoldElectrostatic(), base), base)
    @test tratado.feasible

    sem_campo = merge(base, Dict(:dm_water => K_TRATADOR[:untreated_droplet_um]))
    cru = size_equipment(ElectrostaticTreater(), ArnoldElectrostatic(),
                         FPSOSiz.case_input(ArnoldElectrostatic(), sem_campo), sem_campo)

    @testset "sem coalescência, o teto de decantação despenca" begin
        @test cru.ceiling < tratado.ceiling
        # o teto vai com d_m²: 1000 µm contra 500 µm são 4×
        @test isapprox(tratado.ceiling / cru.ceiling, 4.0; rtol = 1e-6)
    end

    @testset "e o mesmo serviço deixa de caber no vaso" begin
        @test !cru.feasible
        @test occursin("decanta", lowercase(cru.message))
    end

    @testset "o ganho aparece no memorial, quantificado" begin
        entrada = FPSOSiz.case_input(ArnoldElectrostatic(), base)
        _, _, tr = FPSOSiz.sizing_constraints(
            ArnoldElectrostatic(), entrada,
            with_defaults(parameters(ArnoldElectrostatic()), base), K_TRATADOR)
        ganho = only(filter(e -> e.var == "ganho do campo",
                            FPSOSiz.block_entries(tr, :settling)))
        @test ganho.value ≈ 4.0
        # e a linha diz que é hipótese, não correlação — é a única defesa contra o
        # número ser lido como se viesse da fonte
        @test occursin("hipótese", ganho.formula)
    end
end

@testset "vaso cheio: α = 1 é constante, e não campo de formulário" begin
    # Com α < 1 existiria fase gasosa, e com ela o bloco A (Eq. 4.14b), que este método
    # não avalia. Expor α convidaria a receber um número dimensionado ignorando uma
    # restrição que se aplica — em silêncio.
    @test float(K_TRATADOR[:liquid_area_fraction]) == 1.0
    chaves = Set(s.key for s in parameters(ArnoldElectrostatic()))
    @test !(:liquid_area_fraction in chaves)
    @test !(:alpha in chaves)
end

@testset "óleo mais denso que a água é recusado com mensagem" begin
    vals = merge(tratador_defaults(), Dict(:rho_oil => 1050.0, :rho_water => 1000.0))
    res = size_equipment(ElectrostaticTreater(), ArnoldElectrostatic(),
                         FPSOSiz.case_input(ArnoldElectrostatic(), vals), vals)
    @test !res.feasible
    @test occursin("ΔSG", res.message) || occursin("densidade", lowercase(res.message))
end
