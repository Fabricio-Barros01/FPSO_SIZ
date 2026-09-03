"""
Caso-ouro: Alves & Komesu (2025), Tabelas 1–4.

Este é **o** teste que define "correto" para o projeto. Se ele quebra, nada mais
importa. Entradas: Tabela 1. Saída esperada: Tabela 3 (varredura completa) e a
conclusão da Tabela 2 (a capacidade de gás não governa).

## O que este teste NÃO afirma

O artigo escolhe `d = 5500 mm` "por serem os valores centrais do intervalo". Pelo
critério do software — menor `|SR − sr_target|` — o ótimo da grade do artigo é
`d = 5650 mm` (SR 3,87 contra 4,19). Isso não é discordância de física: as duas linhas
estão na banda admissível e a varredura é idêntica. A escolha de 5500 no artigo é
*post-hoc*, é a única linha cujas três dimensões ficam a menos de 10 % do vaso
realmente instalado (Tabela 4) — critério que só existe porque eles tinham o vaso real
para comparar.

Portanto testamos: (a) a varredura inteira, que é a física; (b) que 5500 é admissível
com o SR publicado; (c) que a escolha automática cai dentro de um passo de grade dela.
"""

# Tabela 1 — condições de operação e propriedades dos fluidos.
# Ver config/stream.toml para a discussão de rho_water e mu_gas (colunas trocadas
# na tabela publicada).
function golden_values()
    vals = FPSOSiz.default_case_values()
    merge!(vals, Dict{Symbol,Float64}(
        :d_min => 5200.0, :d_max => 5950.0, :d_step => 150.0,   # grade do artigo
    ))
    return vals
end

# Tabela 3 — d [mm] => (Leff [m], Lss [m], SR)
const TABELA_3 = [
    (5200.0, 19.29, 25.71, 4.94),
    (5350.0, 18.22, 24.29, 4.54),
    (5500.0, 17.24, 22.98, 4.18),
    (5650.0, 16.34, 21.78, 3.86),
    (5800.0, 15.50, 20.67, 3.56),
    (5950.0, 14.73, 19.64, 3.30),
]

@testset "caso-ouro Alves & Komesu (2025)" begin
    vals = golden_values()
    res  = size_equipment(Separator(), StewartArnold(), stream_from_case(vals), vals)

    @test res.feasible
    @test res.method_id === :stewart_arnold

    @testset "Tabela 3 — varredura completa" begin
        @test length(res.sweep) == length(TABELA_3)
        for (row, (d, leff, lss, sr)) in zip(res.sweep, TABELA_3)
            @test row.x == d
            @test row.y ≈ leff rtol = 0.005      # 0,5 %
            @test der(row, :lss)  ≈ lss  rtol = 0.005
            @test der(row, :sr)     ≈ sr   rtol = 0.005
            @test row.governing === :liquid           # Eq. 23 vale, não a Eq. 15
        end
    end

    @testset "Tabela 2 — a capacidade de gás não governa" begin
        # O artigo tabula Leff_gas ≈ 0,05–0,06 m e conclui que a separação
        # líquido/líquido é a principal. Reproduzimos a ordem de grandeza e,
        # sobretudo, a conclusão.
        for row in res.sweep
            @test row.per_constraint[:gas] < 0.1
            @test row.per_constraint[:gas] < row.per_constraint[:liquid] / 100
        end
        @test res.governing === :liquid
    end

    @testset "teto de decantação não é restritivo" begin
        # O artigo observa que, sendo a gotícula de água (500 µm) maior que a de óleo
        # (200 µm), a decantação da água rege — e que o teto resultante é folgado.
        @test res.ceiling_mechanism === :water_in_oil
        @test res.ceiling > 10_000.0
        @test all(r -> r.x < res.ceiling, res.sweep)
    end

    @testset "Tabela 4 — d = 5500 mm é admissível" begin
        row = only(filter(r -> r.x == 5500.0, res.sweep))
        @test row.ok
        @test der(row, :sr) ≈ 4.18 rtol = 0.005
        @test row.y ≈ 17.24 rtol = 0.005
        @test der(row, :lss)  ≈ 22.98 rtol = 0.005
        # a escolha automática fica a no máximo um passo de grade da do artigo
        @test abs(res.x - 5500.0) <= vals[:d_step]
    end

    @testset "desvio vs. vaso instalado (Martins, 2017) < 10 %" begin
        # Tabela 4: real d = 5,30 m, Leff = 19,00 m, Lss = 21,81 m.
        row = only(filter(r -> r.x == 5500.0, res.sweep))
        @test abs(row.x / 1000 - 5.30) / 5.30 < 0.10
        @test abs(row.y - 19.00) / 19.00 < 0.10
        @test abs(der(row, :lss) - 21.81) / 21.81 < 0.10
    end

    @testset "o coeficiente 4,12e4 impresso no artigo seria reprovado" begin
        # Guarda de regressão: se alguém "corrigir" a constante para o valor impresso,
        # a Tabela 3 deixa de fechar. Ver Units.liquid_capacity_coefficient.
        c_artigo = 4.12e4
        c_nosso  = FPSOSiz.Units.liquid_capacity_coefficient()
        leff_artigo = c_artigo * (10.0 * 215.8 + 10.0 * 1025.8) / 5500.0^2
        leff_nosso  = c_nosso  * (10.0 * 215.8 + 10.0 * 1025.8) / 5500.0^2
        @test !isapprox(leff_artigo, 17.24; rtol = 0.005)   # erra ~1,9 %
        @test isapprox(leff_nosso, 17.24; rtol = 0.005)     # acerta ~0,35 %
    end

    @testset "memorial de cálculo" begin
        eqs = [e.eq for e in res.trace.entries]
        for eq in ["Eq. 11", "Eq. 13", "Eq. 14", "Eq. 16", "Eq. 17",
                   "Eq. 18", "Eq. 20", "Eq. 22", "Eq. 24"]
            @test eq in eqs
        end
        @test all(e -> isfinite(e.value), res.trace.entries)
    end

    @testset "a variante geométrica da Eq. 21 é registrada, e não decide" begin
        # β é a altura fracionária do ÓLEO; a da água é `0,5 − β`. O artigo divide as
        # duas espessuras por β. Seguimos o artigo — é o que reproduz o resultado
        # publicado, e é o propósito declarado do software — mas a variante geométrica
        # é emitida no rastro, porque a diferença NÃO é de arredondamento e o leitor do
        # memorial não teria como recalculá-la.
        entradas = Dict(e.eq => e for e in res.trace.entries)
        @test haskey(entradas, "Eq. 21")     # a publicada, que decide
        @test haskey(entradas, "Eq. 21*")    # a geométrica, que só informa

        beta = only(filter(e -> e.var == "β", res.trace.entries)).value
        publicada  = entradas["Eq. 21"].value
        geometrica = entradas["Eq. 21*"].value

        # A razão entre as duas é exatamente β/(0,5−β) — ~6,3 no caso publicado.
        @test publicada / geometrica ≈ (0.5 - beta) / beta rtol = 1e-9
        @test publicada > 6 * geometrica

        # E o que decide continua sendo a forma publicada: o teto é o da Eq. 19 e o
        # mecanismo é água em óleo, como o artigo conclui. Se algum dia a variante
        # passar a governar, este teste cai — que é o ponto.
        @test res.ceiling ≈ entradas["Eq. 19"].value
        @test res.ceiling_mechanism === :water_in_oil

        # O tamanho do que se está deixando passar: sob a leitura geométrica o teto
        # seria 3810 mm e TODA a Tabela 3 (5200–5950 mm) seria recusada.
        @test geometrica < 4000.0
        @test all(r -> r.x > geometrica, res.sweep)
    end
end
