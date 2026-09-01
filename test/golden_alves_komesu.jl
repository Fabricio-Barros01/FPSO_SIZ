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
            @test row.d_mm == d
            @test row.leff_m ≈ leff rtol = 0.005      # 0,5 %
            @test row.lss_m  ≈ lss  rtol = 0.005
            @test row.sr     ≈ sr   rtol = 0.005
            @test row.governing === :liquid           # Eq. 23 vale, não a Eq. 15
        end
    end

    @testset "Tabela 2 — a capacidade de gás não governa" begin
        # O artigo tabula Leff_gas ≈ 0,05–0,06 m e conclui que a separação
        # líquido/líquido é a principal. Reproduzimos a ordem de grandeza e,
        # sobretudo, a conclusão.
        for row in res.sweep
            @test row.leff_gas_m < 0.1
            @test row.leff_gas_m < row.leff_liquid_m / 100
        end
        @test res.governing === :liquid
    end

    @testset "teto de decantação não é restritivo" begin
        # O artigo observa que, sendo a gotícula de água (500 µm) maior que a de óleo
        # (200 µm), a decantação da água rege — e que o teto resultante é folgado.
        @test res.d_max_mechanism === :water_in_oil
        @test res.d_max_mm > 10_000.0
        @test all(r -> r.d_mm < res.d_max_mm, res.sweep)
    end

    @testset "Tabela 4 — d = 5500 mm é admissível" begin
        row = only(filter(r -> r.d_mm == 5500.0, res.sweep))
        @test row.sr_ok
        @test row.sr ≈ 4.18 rtol = 0.005
        @test row.leff_m ≈ 17.24 rtol = 0.005
        @test row.lss_m  ≈ 22.98 rtol = 0.005
        # a escolha automática fica a no máximo um passo de grade da do artigo
        @test abs(res.diameter_mm - 5500.0) <= vals[:d_step]
    end

    @testset "desvio vs. vaso instalado (Martins, 2017) < 10 %" begin
        # Tabela 4: real d = 5,30 m, Leff = 19,00 m, Lss = 21,81 m.
        row = only(filter(r -> r.d_mm == 5500.0, res.sweep))
        @test abs(row.d_mm / 1000 - 5.30) / 5.30 < 0.10
        @test abs(row.leff_m - 19.00) / 19.00 < 0.10
        @test abs(row.lss_m - 21.81) / 21.81 < 0.10
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
end
