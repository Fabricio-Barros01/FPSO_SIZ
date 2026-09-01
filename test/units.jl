using FPSOSiz.Units

@testset "conversões" begin
    @test m3h_to_m3s(3600.0) ≈ 1.0
    @test m3s_to_m3h(1.0) ≈ 3600.0
    @test cp_to_pas(1.0) ≈ 1e-3
    @test pas_to_cp(1e-3) ≈ 1.0
    @test kpa_to_pa(2300.0) ≈ 2.3e6
    @test celsius_to_kelvin(28.0) ≈ 301.15

    # ida e volta
    for x in (0.1, 1.0, 1234.5)
        @test m3s_to_m3h(m3h_to_m3s(x)) ≈ x
        @test pas_to_cp(cp_to_pas(x)) ≈ x
        @test kelvin_to_celsius(celsius_to_kelvin(x)) ≈ x
        @test m_to_mm(mm_to_m(x)) ≈ x
    end
end

@testset "grau API (Eq. 12)" begin
    # Tabela 1: 32 °API. A Eq. 12 dá 865,4 kg/m³; a tabela lista 863 (medido).
    @test api_to_density(32.0) ≈ 865.4 rtol = 1e-3
    @test density_to_api(api_to_density(32.0)) ≈ 32.0
    @test api_to_density(10.0) ≈ 1000.0 rtol = 1e-6   # 10 °API ≡ água, por definição
    @test specific_gravity(863.0) ≈ 0.863
end

@testset "coeficiente da Eq. 22 vem da derivação, não de um literal" begin
    c = liquid_capacity_coefficient()

    # 1) É o que a conversão de unidades manda, a partir do 1,42 de Stewart & Arnold
    #    em unidades de campo (d[in], Leff[ft], tr[min], Q[BPD]).
    lhs = 25.4^2 * 0.3048          # mm²·m por in²·ft
    rhs = 24.0 / 0.158987294928    # BPD por m³/h
    @test c ≈ lhs * 1.42 * rhs
    @test c ≈ 4.2152e4 rtol = 1e-4

    # 2) O TOML carrega exatamente este valor — a constante do código e o dado de
    #    configuração não podem divergir silenciosamente.
    k = FPSOSiz.constants(FPSOSiz.load_config("equipment", "separator",
                                              "stewart_arnold.toml"))
    @test float(k[:eq22_coefficient]) ≈ c rtol = 1e-9

    # 3) É materialmente diferente do 4,12e4 impresso no artigo.
    @test !isapprox(c, 4.12e4; rtol = 0.005)
    @test abs(c - 4.12e4) / 4.12e4 > 0.02      # ~2,3 %
end

@testset "field_units é o único conversor" begin
    vals = FPSOSiz.default_case_values()
    fu = field_units(stream_from_case(vals))
    @test fu.q_o ≈ vals[:q_oil]
    @test fu.q_w ≈ vals[:q_water]
    @test fu.q_g ≈ vals[:q_gas]
    @test fu.mu_o ≈ vals[:mu_oil]
    @test fu.mu_g ≈ vals[:mu_gas]
    @test fu.p_kpa ≈ vals[:pressure]
    @test fu.t_k ≈ celsius_to_kelvin(vals[:temperature])
    @test fu.sg_o ≈ vals[:rho_oil] / 1000
    @test fu.sg_w ≈ vals[:rho_water] / 1000
end
