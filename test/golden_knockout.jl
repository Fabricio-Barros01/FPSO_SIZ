"""
Caso-ouro do vaso bifásico: Stewart & Arnold (2008), Exemplo 3.2 e Tabela 3.4.

É o **segundo** caso-ouro do projeto, e o primeiro vindo da fonte primária em vez do
artigo que a reproduz. Vale mais do que um teste a mais: o trifásico prova que o
software reproduz Alves & Komesu, e este prova que reproduz Stewart & Arnold — que é
o que Alves & Komesu por sua vez reproduzem.

## O exemplo é em unidades de campo; o software é SI

Os dados de entrada são convertidos aqui, uma vez, com as constantes de `Units`. As
saídas são comparadas contra a Tabela 3.4 convertida. O par de coeficientes do livro
(420 em campo, 34,5 em SI; 1/0,7 e 42441) não é exatamente equivalente — os valores SI
são arredondados na publicação —, então a tolerância é de 2 %, não de 0,5 %.

## Dois errata da fonte, encontrados ao reproduzi-la

1. **O `dLeff` impresso no Exemplo 3.2 está errado.** O texto diz `55,04 in·ft`. Com os
   próprios dados do exemplo, a Eq. 3.8a dá `420 × 4,368 × 0,021724 = 39,85`. As sete
   linhas da Tabela 3.4 conferem com **39,85** (erro < 6 %) e erram 38 % contra 55,04.
   O texto está errado e a tabela certa.

2. **A coluna `Lss` da Tabela 3.4 não usa a Eq. 3.10b.** A nota de rodapé diz
   "Lss = Leff + 2.5 governs", e de fato `6,6 + 2,5 = 9,1`, `4,9 + 2,5 = 7,4`,
   `3,7 + 2,5 = 6,2` — as três linhas batem com uma folga **constante de 2,5 ft**, não
   com `d/12` (que daria 3,0, 3,5 e 4,0 ft). A Eq. 3.10b do próprio livro é `Leff + d/12`.
   Por isso este teste amarra as duas colunas de `Leff`, que são física pura, e **não**
   as de `Lss` e `SR`, que dependem dessa folga inconsistente.
"""

# ---------------------------------------------------------------------------
# Exemplo 3.2 — dados em unidades de campo, convertidos para SI
# ---------------------------------------------------------------------------
const LB_FT3_KG_M3 = FPSOSiz.Units.LB_KG / FPSOSiz.Units.CUFT_M3

function knockout_golden_values()
    Dict{Symbol,Float64}(
        # 10 MMscfd
        :q_gas       => 10e6 * FPSOSiz.Units.CUFT_M3 / 24,
        # 2000 BOPD
        :q_oil       => 2000 * FPSOSiz.Units.BARREL_M3 / 24,
        # ρl = 51,5 lb/ft³ (40 °API), ρg = 3,71 lb/ft³ (SG 0,6 a 1000 psia, 60 °F)
        :rho_oil     => 51.5 * LB_FT3_KG_M3,
        :rho_gas     => 3.71 * LB_FT3_KG_M3,
        :mu_gas      => 0.013,
        :pressure    => 1000 * FPSOSiz.Units.PSI_KPA,
        :temperature => (60 - 32) * 5 / 9,
        :z           => 0.84,
        # parâmetros do método
        :dm_gas      => 140.0,
        :tr_liquid   => 3.0,
        # a grade do exemplo: 16 a 48 in, de 6 em 6
        :d_min       => 16 * 25.4,
        :d_max       => 48 * 25.4,
        :d_step      => 6 * 25.4,
    )
end

# Tabela 3.4 — d [in] => (Leff_gás [ft], Leff_líquido [ft])
const TABELA_3_4 = [
    (16.0, 2.5, 33.5),
    (20.0, 2.0, 21.4),
    (24.0, 1.7, 14.9),
    (30.0, 1.3,  9.5),
    (36.0, 1.1,  6.6),
    (42.0, 0.9,  4.9),
    (48.0, 0.8,  3.7),
]

@testset "caso-ouro Stewart & Arnold (2008) — vaso bifásico" begin
    vals = knockout_golden_values()
    m, eq = StewartArnoldTwoPhase(), KnockoutDrum()
    s = stream_from_case(vals; required = FPSOSiz.stream_keys(m))
    k = FPSOSiz.constants(FPSOSiz.method_config(m))
    p = with_defaults(parameters(m), vals)

    ok, cons, tr = FPSOSiz.sizing_constraints(m, s, p, k)
    @test ok

    @testset "não há teto de decantação — o bloco B não existe neste vaso" begin
        @test cons.d_max_mm == Inf
        @test cons.mechanism === :none
        @test isnan(cons.beta)              # geometria de três camadas não se aplica
        @test isnan(cons.aw_over_a)
        # e o rastro não tem bloco de decantação nenhum
        @test isempty(FPSOSiz.block_entries(tr, :settling))
        @test !isempty(FPSOSiz.block_entries(tr, :gas))
        @test !isempty(FPSOSiz.block_entries(tr, :liquid))
    end

    @testset "o coeficiente de arrasto converge no valor do livro" begin
        # O Exemplo 3.1 itera à mão e para em C_D = 0,854 ("OK"); o ponto fixo é 0,851.
        # Nossa iteração é sub-relaxada e vai até a convergência de verdade.
        cd = only(filter(e -> e.var == "C_D", tr.entries)).value
        @test cd ≈ 0.851 rtol = 0.02
    end

    @testset "Tabela 3.4 — a coluna de líquido (Eq. 3.9b)" begin
        # Esta coluna fecha apertado: o coeficiente SI publicado (42441) e o de campo
        # (1/0,7 → 42406) diferem 0,08 %, e a tabela traz três algarismos.
        pe = FPSOSiz.Units.FOOT_M
        for (d_in, _, leff_liq_ft) in TABELA_3_4
            @test cons.d2_leff / (d_in * 25.4)^2 ≈ leff_liq_ft * pe rtol = 0.02
        end
    end

    @testset "Tabela 3.4 — a coluna de gás, e o erratum do Exemplo 3.2" begin
        # Comparar esta coluna linha a linha com tolerância relativa é comparar com o
        # arredondamento da publicação: ela é dada com UMA casa em pés, e em d = 42 in
        # meia casa já vale 5,6 %. O que a tabela de fato fixa é um número só — o
        # `d·Leff` — e é contra ele que se testa.
        const_livro = 39.85          # Eq. 3.8a com os dados do Exemplo 3.2
        for (d_in, leff_gas_ft, _) in TABELA_3_4
            # a tabela é consistente com 39,85...
            @test round(const_livro / d_in, digits = 1) == leff_gas_ft
            # ...e não com os 55,04 que o texto do exemplo imprime
            @test round(55.04 / d_in, digits = 1) != leff_gas_ft
        end

        # E o nosso, em SI, fica a 1,3 % do valor de campo. A maior parte disso é o
        # próprio livro: ver o teste do coeficiente logo abaixo.
        @test cons.d_leff_gas / (25.4 * FPSOSiz.Units.FOOT_M) ≈ const_livro rtol = 0.015
    end

    @testset "o 34,5 do livro está 0,87 % acima do equivalente exato do 420" begin
        # Terceiro achado da revisão de fontes, da mesma família do 4,12×10⁴ do artigo,
        # mas benigno: o par de coeficientes do livro (420 em campo, 34,5 em SI) não é
        # exatamente equivalente. Convertendo o 420:
        #   34,5_equiv = (25,4·0,3048) · 420 · 1,8 · [24/(10⁶·0,0283168)] · 6,894757
        U = FPSOSiz.Units
        exato = (25.4 * U.FOOT_M) * 420 * 1.8 * (24 / (1e6 * U.CUFT_M3)) * U.PSI_KPA
        @test exato ≈ 34.202 rtol = 1e-3
        @test 34.5 / exato ≈ 1.0087 rtol = 1e-3

        # Usamos o 34,5 publicado, e não o derivado: 0,87 % não muda vaso nenhum, e o
        # critério do projeto é seguir a fonte salvo quando ela se contradiz — o que
        # aqui não acontece (as duas formas concordam a menos de 1 %). Contraste com a
        # Eq. 22 do artigo, onde o valor impresso erra 1,9 % contra a tabela do próprio
        # artigo, e por isso é derivado. Ver config/equipment/knockout/.
        @test FPSOSiz.constants(FPSOSiz.method_config(m))[:gas_capacity_coefficient] == 34.5
    end

    @testset "o bloco de gás é O MESMO do trifásico" begin
        # A Eq. 3.8b do livro e a Eq. 14 do artigo são a mesma equação. Se algum dia os
        # dois caminhos divergirem, é porque alguém duplicou a física — que é o que
        # `gas_capacity.jl` existe para impedir.
        tr3 = FPSOSiz.CalcTrace()
        ok3, dleff3, _ = FPSOSiz.gas_capacity_dleff(
            s, p[:dm_gas], 34.5, 0.34, 0.5, tr3; eqs = FPSOSiz.EQS_GAS_ALVES)
        @test ok3
        @test dleff3 ≈ cons.d_leff_gas       # bit a bit: é a mesma função
        # e o que muda é só a citação no memorial
        @test [e.eq for e in FPSOSiz.block_entries(tr, :gas)] !=
              [e.eq for e in FPSOSiz.block_entries(tr3, :gas)]
        @test "Eq. 3.8b" in [e.eq for e in FPSOSiz.block_entries(tr, :gas)]
        @test "Eq. 14"   in [e.eq for e in FPSOSiz.block_entries(tr3, :gas)]
    end

    @testset "Lss pela regra do livro: o maior dos dois" begin
        # §3.8.4: "the larger of the following". No trifásico o artigo usa a relação do
        # bloco que governa — a diferença está documentada na nota 4 de stewart_arnold.jl.
        for d_mm in (400.0, 900.0, 1200.0)
            leff = 2.0
            esperado = max(leff + d_mm / 1000, (4 / 3) * leff)
            @test FPSOSiz.lss_from(m, d_mm, leff, :liquid, k) ≈ esperado
            @test FPSOSiz.lss_from(m, d_mm, leff, :gas, k)    ≈ esperado
        end
        # e o trifásico continua com a regra do artigo, que depende de quem governa
        k3 = FPSOSiz.constants(FPSOSiz.method_config(StewartArnold()))
        @test FPSOSiz.lss_from(StewartArnold(), 5950.0, 14.73, :liquid, k3) ≈
              (4 / 3) * 14.73
    end

    @testset "dimensiona, e o resultado é coerente com a tabela" begin
        res = size_equipment(eq, m, s, vals)
        @test res.feasible
        @test res.method_id === :stewart_arnold_2f
        @test 3.0 <= der(res, :sr) <= 4.0                  # banda §3.8.5, mais estreita que a do 3φ
        @test res.governing === :liquid             # como no exemplo do livro
        # o exemplo escolhe 36 in (914 mm); a escolha automática fica perto
        @test abs(res.x - 36 * 25.4) <= 2 * vals[:d_step]
        @test isinf(res.ceiling)
    end

    @testset "o resumo não inventa um teto que não existe" begin
        # `governing_summary` fazia `round(Int, r.ceiling)` incondicionalmente e
        # lançava `InexactError` com teto `Inf` — o resumo assumia que todo vaso
        # tem teto de decantação. Só o segundo equipamento revelou isso.
        env = size_envelope(eq, m, CaseSet([Case("único", vals)]))
        @test env.feasible
        @test isinf(env.ceiling)
        resumo = governing_summary(m, env)              # não lança
        @test occursin("Governa", resumo)
        @test !occursin("Teto de decantação", resumo)   # cala-se em vez de inventar

        # e o trifásico, que tem teto, continua dizendo qual é
        vals3 = FPSOSiz.default_case_values()
        env3 = size_envelope(Separator(), StewartArnold(), CaseSet([Case("t", vals3)]))
        @test env3.feasible
        @test occursin("Teto de decantação", governing_summary(StewartArnold(), env3))
    end

    @testset "multi-caso: o motor de envelope serve o vaso novo sem mudança" begin
        # A invariante do Sprint 5. O envelope foi generalizado ANTES de este vaso
        # existir, e não sabe que ele existe.
        dobro = merge(vals, Dict(:q_oil => 2 * vals[:q_oil]))
        env = size_envelope(eq, m, CaseSet([Case("normal", vals), Case("dobro", dobro)]))
        @test env.feasible
        @test env.driver_case == "dobro"
        @test isinf(env.ceiling)
        @test all(env.slack .>= -1e-9)
        for row in env.rows
            @test row.y ≈ maximum(row.per_case_y)
        end
    end
end
