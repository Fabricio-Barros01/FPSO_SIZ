"""
β é geometria pura (ver src/sizing/separator/beta.jl). Estes testes amarram a
implementação analítica à Figura 3 de Stewart & Arnold (2008).
"""

@testset "β — extremos físicos" begin
    # Sem água, o óleo ocupa toda a metade inferior: h_o = d/2.
    @test beta_coefficient(0.0) ≈ 0.5
    # Água ocupando toda a metade inferior: não sobra óleo.
    @test beta_coefficient(0.5) ≈ 0.0 atol = 1e-12
    # Fora do domínio, trunca nos extremos em vez de extrapolar.
    @test beta_coefficient(-0.1) ≈ 0.5
    @test beta_coefficient(0.7) ≈ 0.0
end

@testset "β — pontos lidos da Figura 3" begin
    # Valores conferidos contra a curva publicada (eixo vertical invertido:
    # 0,0 no topo, 0,5 na base).
    @test beta_coefficient(0.10) ≈ 0.3435 atol = 2e-3
    @test beta_coefficient(0.25) ≈ 0.2020 atol = 2e-3
    @test beta_coefficient(0.40) ≈ 0.0805 atol = 2e-3
end

@testset "β — monotonicidade e continuidade" begin
    xs = range(0.0, 0.5; length = 501)
    bs = beta_coefficient.(xs)
    @test issorted(bs; rev = true)                       # estritamente decrescente
    @test all(0.0 .<= bs .<= 0.5)
    @test maximum(abs.(diff(bs))) < 0.02                 # sem saltos
end

@testset "β — coerência com a área do segmento" begin
    # Reconstrói Aw/A a partir de β e confere que fecha: a camada de água tem
    # altura h_w = (0,5 − β)·d, e sua área deve valer (Aw/A)·A.
    for f in (0.05, 0.15, 0.3, 0.45)
        β = beta_coefficient(f)
        u = 2 * (0.5 - β)                                # u = h_w/R
        @test FPSOSiz._segment_area(u) / π ≈ f atol = 1e-6
    end
end

@testset "Eq. 18 — fração da área ocupada pela água" begin
    # Caso-ouro: Qo = 215,8, Qw = 1025,8 m³/h, tr = 10 min nas duas fases.
    @test water_area_fraction(215.8, 1025.8, 10.0, 10.0) ≈ 0.41310 atol = 1e-5

    # Sem água, fração nula; com só água, tende ao teto de 0,5.
    @test water_area_fraction(100.0, 0.0, 10.0, 10.0) ≈ 0.0
    @test water_area_fraction(0.0, 100.0, 10.0, 10.0) ≈ 0.5
    # Vazões nulas não devem gerar divisão por zero.
    @test water_area_fraction(0.0, 0.0, 10.0, 10.0) ≈ 0.0
end
