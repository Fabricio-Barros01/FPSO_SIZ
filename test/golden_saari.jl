"""
Caso-ouro do trocador: Saari, *Heat Exchanger Dimensioning* (LUT).

**A fonte não traz o exemplo que este box precisaria.** Saari é texto de aula: o único
caso numérico resolvido é o Exemplo 4.1, um trocador de tubo duplo com `U` **dado**, que
não fecha o laço `velocidade → h_i → U`. Não há Tabela 3 nem Tabela 3.4 a reproduzir.

O que dá para provar, e é o que este arquivo prova:

1. **A cadeia do Exemplo 4.1, número a número** — `q → T_c,o → ΔT_lm → A → L → n` —,
   chamando as mesmas funções que o método usa. Cobre balanço, LMTD e a conversão de
   área em comprimento de tubo, que é metade da física do box.
2. **O cruzamento LMTD ↔ ε-NTU**, que §4.1 afirma ser exato: *"essentially equivalent,
   and will yield the same results if correctly applied"*. Dado o `A` que o método LMTD
   produz, o método ε-NTU tem de devolver o **mesmo** `q`. É uma verificação forte e
   independente: os dois caminhos não compartilham nenhuma linha de código.
3. **As propriedades que o resto tem de ter por construção** — `U` entre a menor e a
   maior resistência, `F ≤ 1` e `F → 1` quando o arranjo degenera em contracorrente,
   `A` crescendo quando a incrustação cresce.

Um exemplo de literatura com o laço de `U` fechado fecharia o buraco, e está registrado
como pendência no TOML do método.

## Dois errata do Exemplo 4.1, encontrados ao reproduzi-lo

1. **A vazão de água.** O enunciado diz `0,20 kg/s`; a solução calcula
   `Ċc = 0,30 kg/s × 4200 = 1260 W/K` e segue com 1260 até o fim. Com 0,20 o `Ċc` seria
   840 W/K e `T_c,o` daria 99,3 °C — acima da entrada do óleo, o que tornaria o exemplo
   impossível. **0,30 é o valor certo**, e é com ele que as cinco linhas seguintes
   fecham.
2. **O comprimento do elemento.** A figura e o enunciado dizem 1,8 m; o texto da solução
   pede "the required number of **3.6 metre** elements" e em seguida divide por 1,8.
   **1,8 é o certo** — é o que dá os 80 elementos publicados.

Os dois são erros de digitação de enunciado, não de método: as contas do próprio texto
usam os valores certos. Ficam registrados aqui pela mesma razão que os errata de Stewart
& Arnold ficaram: quem for conferir o teste contra o livro precisa saber por que os
números não são os que estão impressos duas linhas acima.
"""

const K_TROCADOR = FPSOSiz.constants(FPSOSiz.method_config(SaariLMTD()))

# ---------------------------------------------------------------------------
# Exemplo 4.1 — tubo duplo, contracorrente
# ---------------------------------------------------------------------------

@testset "Exemplo 4.1 — a cadeia inteira" begin
    m_h, cp_h = 0.60, 2500.0        # óleo
    m_c, cp_c = 0.30, 4200.0        # água — 0,30, e não os 0,20 do enunciado
    t_hi, t_ho, t_ci = 90.0, 40.0, 10.0
    u = 200.0
    d_o = 0.0334                     # diâmetro externo do tubo interno
    l_elemento = 1.8                 # 1,8 m, e não os "3.6 metre" do texto

    c_h, c_c = m_h * cp_h, m_c * cp_c
    @test c_h ≈ 1500.0               # publicado: 1500 W/K
    @test c_c ≈ 1260.0               # publicado: 1260 W/K

    q = c_h * (t_hi - t_ho)
    @test q ≈ 75000.0                # publicado: 75000 W

    t_co = t_ci + q / c_c
    @test isapprox(t_co, 69.5; atol = 0.05)   # publicado: 69,5 °C

    # Eq. 4.7 — contracorrente
    dt1 = t_hi - t_co
    dt2 = t_ho - t_ci
    @test isapprox(dt1, 20.5; atol = 0.05)    # publicado: 20,5 °C
    @test dt2 ≈ 30.0                          # publicado: 30 °C

    dtlm = lmtd(dt1, dt2)
    @test isapprox(dtlm, 24.95; atol = 0.02)  # publicado: 24,95 °C

    a = q / (u * dtlm)
    @test isapprox(a, 15.03; rtol = 2e-3)     # publicado: 15,03 m²

    l = a / (π * d_o)
    @test isapprox(l, 143.2; rtol = 2e-3)     # publicado: 143,2 m

    n = l / l_elemento
    @test isapprox(n, 79.6; rtol = 3e-3)      # publicado: 79,6 → 80 elementos
    @test ceil(Int, n) == 80

    @testset "o arranjo em paralelo é impossível, e o sinal o denuncia" begin
        # Eq. 4.8: ΔT₂ = T_h,saída − T_c,saída = 40 − 69,5 = −29,5 °C. O exemplo usa
        # exatamente esse sinal negativo para concluir que o arranjo não fecha.
        dt2_par = t_ho - t_co
        @test dt2_par < 0
        @test isapprox(dt2_par, -29.5; atol = 0.05)
        # e `lmtd` devolve NaN em vez de um número: é o contrato de "não sei".
        @test isnan(lmtd(t_hi - t_ci, dt2_par))
    end

    @testset "o erratum da vazão: com 0,20 kg/s o exemplo seria impossível" begin
        c_errado = 0.20 * cp_c
        t_co_errado = t_ci + q / c_errado
        @test t_co_errado > t_hi      # a água sairia mais quente que o óleo entra
        @test isnan(lmtd(t_hi - t_co_errado, dt2))
    end
end

# ---------------------------------------------------------------------------
# LMTD ↔ ε-NTU: a conferência que §4.1 promete ser exata
# ---------------------------------------------------------------------------

@testset "LMTD e ε-NTU dão o mesmo resultado" begin
    # §4.1: "essentially equivalent, and will yield the same results if correctly
    # applied". Os dois caminhos não compartilham nenhuma linha de código, então a
    # coincidência é verificação de verdade, e não tautologia.
    for (c_h, c_c, t_hi, t_ci, t_ho, u) in (
            (1500.0, 1260.0, 90.0, 10.0, 40.0, 200.0),
            (4000.0, 4000.0, 120.0, 20.0, 70.0, 350.0),   # C* = 1, o limite removível
            (2000.0, 60000.0, 150.0, 25.0, 60.0, 500.0),  # C* ≈ 0, quase mudança de fase
            (900.0, 3300.0, 80.0, 15.0, 35.0, 120.0))

        q = c_h * (t_hi - t_ho)
        t_co = t_ci + q / c_c
        dtlm = lmtd(t_hi - t_co, t_ho - t_ci)
        @test isfinite(dtlm)

        # caminho 1 — LMTD: a área que entrega este q
        area = q / (u * dtlm)

        # caminho 2 — ε-NTU: o q que esta área entrega
        c_min, c_max = minmax(c_h, c_c)
        ntu = u * area / c_min
        eps = effectiveness_ntu_counterflow(ntu, c_min / c_max)
        q_ntu = eps * c_min * (t_hi - t_ci)

        @test isapprox(q_ntu, q; rtol = 1e-9)
    end

    @testset "os limites de ε-NTU" begin
        # NTU → 0: nenhuma área, nenhuma troca.
        @test effectiveness_ntu_counterflow(0.0, 0.5) ≈ 0.0
        # NTU → ∞ com C* < 1: contracorrente puro chega a ε = 1.
        @test isapprox(effectiveness_ntu_counterflow(60.0, 0.5), 1.0; rtol = 1e-6)
        # C* = 1 é o limite removível NTU/(1+NTU) — sem ele, 0/0.
        @test effectiveness_ntu_counterflow(3.0, 1.0) ≈ 3.0 / 4.0
        # e a fórmula geral converge para ele por continuidade
        @test isapprox(effectiveness_ntu_counterflow(3.0, 1.0 - 1e-9),
                       effectiveness_ntu_counterflow(3.0, 1.0); rtol = 1e-6)
        # ε cresce com NTU, sempre
        @test issorted([effectiveness_ntu_counterflow(n, 0.4) for n in 0:0.5:8])
    end
end

# ---------------------------------------------------------------------------
# ΔT médio logarítmico
# ---------------------------------------------------------------------------

@testset "ΔT_lm — Eq. 4.6" begin
    @test lmtd(30.0, 30.0) ≈ 30.0                 # §4.2.3: capacidades iguais
    @test isapprox(lmtd(30.0 + 1e-10, 30.0), 30.0; rtol = 1e-6)   # o limite é contínuo
    @test lmtd(20.5, 30.0) ≈ lmtd(30.0, 20.5)     # simétrica nos dois ΔT
    # está sempre entre os dois, e abaixo da média aritmética
    for (a, b) in ((10.0, 40.0), (5.0, 80.0), (25.0, 26.0))
        l = lmtd(a, b)
        @test min(a, b) <= l <= max(a, b)
        @test l <= (a + b) / 2
    end
    # cruzamento de temperatura não vira número
    @test isnan(lmtd(-5.0, 30.0))
    @test isnan(lmtd(30.0, 0.0))
    @test isnan(lmtd(NaN, 30.0))
end

# ---------------------------------------------------------------------------
# Fator de correção do arranjo 1-2 (Figura 4.3)
# ---------------------------------------------------------------------------

@testset "fator F do arranjo 1-2 — Figura 4.3" begin
    @testset "F ≤ 1 sempre, e sobe quando o arranjo degenera" begin
        for r in (0.2, 0.5, 1.0, 2.0, 4.0), p in (0.05, 0.2, 0.4)
            r * p < 1 || continue
            f = f_correction_1_2(p, r)
            isfinite(f) || continue
            @test 0 < f <= 1 + 1e-12
        end
        # P → 0 é troca infinitesimal: o arranjo deixa de importar e F → 1.
        @test isapprox(f_correction_1_2(1e-6, 2.0), 1.0; rtol = 1e-4)
        # e F cai à medida que se pede mais troca do mesmo arranjo
        fs = [f_correction_1_2(p, 2.0) for p in (0.05, 0.10, 0.20, 0.30)]
        @test issorted(fs; rev = true)
    end

    @testset "R = 1 é limite removível, não NaN" begin
        # O caso mais comum de todos — capacidades térmicas iguais. Sem tratamento,
        # numerador e denominador zeram juntos e o resultado é NaN, que o desenho
        # propagaria em silêncio (o β do Sprint 5, de novo).
        f1 = f_correction_1_2(0.3, 1.0)
        @test isfinite(f1)
        @test 0 < f1 < 1
        # e é contínuo em torno de 1
        @test isapprox(f_correction_1_2(0.3, 1.0 - 1e-7), f1; rtol = 1e-4)
        @test isapprox(f_correction_1_2(0.3, 1.0 + 1e-7), f1; rtol = 1e-4)
    end

    @testset "fora do domínio devolve NaN, não um número" begin
        @test isnan(f_correction_1_2(1.2, 0.5))     # P > 1 é impossível
        @test isnan(f_correction_1_2(0.9, 2.0))     # R·P > 1 idem
    end

    @testset "é simétrico entre as correntes, como §4.2.2 afirma" begin
        # "a 1-2 parallel-counterflow arrangement is in fact stream symmetric": calcular
        # com o fluido 1 ou com o 2 tem de dar o mesmo F.
        t1i, t1o, t2i = 25.0, 40.0, 110.0
        r1 = 2.654; p1 = (t1o - t1i) / (t2i - t1i)
        t2o = t2i - r1 * (t1o - t1i)
        p2 = (t2i - t2o) / (t2i - t1i)
        r2 = 1 / r1
        @test isapprox(f_correction_1_2(p1, r1), f_correction_1_2(p2, r2); rtol = 1e-9)
    end
end

# ---------------------------------------------------------------------------
# Coeficiente global — Eq. 5.7a
# ---------------------------------------------------------------------------

@testset "U das resistências em série — Eq. 5.7a" begin
    d_i, d_o, k_w = 0.01483, 0.01905, 50.0

    @testset "está entre a menor e a maior resistência" begin
        u = overall_u(6000.0, 500.0, 0.00018, 0.00035, d_i, d_o, k_w)
        # a série é dominada pela maior resistência: 1/500 = 0,002
        @test 1 / u > 0.002
        @test u < 500.0
        @test u > 0
    end

    @testset "mais incrustação é menos U" begin
        u_limpo = overall_u(6000.0, 500.0, 0.0, 0.0, d_i, d_o, k_w)
        u_sujo  = overall_u(6000.0, 500.0, 0.0005, 0.0009, d_i, d_o, k_w)
        @test u_sujo < u_limpo
    end

    @testset "a razão de áreas está lá — e é ela que se erra em silêncio" begin
        # O lado interno tem área menor, e as resistências de lá entram multiplicadas
        # por d_o/d_i. Sem esse fator o U sai maior e continua plausível.
        h_i, h_o = 6000.0, 500.0
        u = overall_u(h_i, h_o, 0.0, 0.0, d_i, d_o, k_w)
        esperado = 1 / (1 / h_o + d_o * log(d_o / d_i) / (2k_w) + (d_o / d_i) / h_i)
        @test u ≈ esperado
        # e o erro que a razão evita: sem ela, U seria ~1 % maior neste tubo
        sem_razao = 1 / (1 / h_o + d_o * log(d_o / d_i) / (2k_w) + 1 / h_i)
        @test sem_razao > u
    end

    @testset "geometria impossível não devolve número" begin
        @test isnan(overall_u(6000.0, 500.0, 0.0, 0.0, d_o, d_i, k_w))   # d_i > d_o
        @test isnan(overall_u(-1.0, 500.0, 0.0, 0.0, d_i, d_o, k_w))
    end
end

@testset "Dittus-Boelter — Eq. 6.23, na forma que Saari publica" begin
    re, pr = 5e4, 5.0
    @test nusselt_dittus_boelter(re, pr, true, K_TROCADOR) ≈ 0.024 * re^0.8 * pr^0.4
    @test nusselt_dittus_boelter(re, pr, false, K_TROCADOR) ≈ 0.026 * re^0.8 * pr^0.3
    # os quatro coeficientes moram no TOML, e são os do §6.3.1 — não os 0,023 usuais
    @test K_TROCADOR[:dittus_boelter_heating] == 0.024
    @test K_TROCADOR[:dittus_boelter_cooling] == 0.026
    # e a diferença sobre o 0,023 clássico fica dentro do erro que o próprio §6.3.1
    # declara para a correlação (-26…+7 % para água)
    @test abs(0.024 / 0.023 - 1) < 0.07
    # Nu cresce com Re e com Pr
    @test nusselt_dittus_boelter(1e5, pr, true, K_TROCADOR) >
          nusselt_dittus_boelter(1e4, pr, true, K_TROCADOR)
    @test isnan(nusselt_dittus_boelter(-1.0, pr, true, K_TROCADOR))
end

# ---------------------------------------------------------------------------
# O método inteiro
# ---------------------------------------------------------------------------

@testset "o trocador atravessa o motor genérico" begin
    vals = defaults(parameters(SaariLMTD()))
    res = size_equipment(ShellTubeExchanger(), SaariLMTD(),
                         FPSOSiz.case_input(SaariLMTD(), vals), vals)
    @test res.feasible

    @testset "respeita a banda de velocidade e os dois tetos" begin
        @test vals[:v_min] <= res.derivados[:v] <= vals[:v_max]
        @test res.derivados[:d_casco] <= vals[:d_casco_max]
        @test res.y <= vals[:l_tubo_max]
    end

    @testset "é o feixe de MENOR área entre os admissíveis" begin
        admissiveis = filter(r -> r.ok, res.sweep)
        @test !isempty(admissiveis)
        @test res.derivados[:area] ≈ minimum(r.derivados[:area] for r in admissiveis)
    end

    @testset "a área fecha por dois caminhos" begin
        d = res.derivados
        # A = q/(U·F·ΔT_lm), e L = A/(N·π·d_o) — as duas identidades do método
        @test d[:area] ≈ d[:q] / (d[:u] * d[:f] * d[:dt_lm])
        @test res.y ≈ d[:area] / (d[:n_total] * π * FPSOSiz.Units.mm_to_m(vals[:d_externo]))
    end

    @testset "mais tubos é menos velocidade, menos U e mais área" begin
        # É esta monotonicidade que faz a varredura ter conteúdo: sem o laço de U, `A`
        # seria constante e a escolha de N seria arbitrária.
        vs = [r.derivados[:v] for r in res.sweep]
        as = [r.derivados[:area] for r in res.sweep]
        us = [r.derivados[:u] for r in res.sweep]
        @test issorted(vs; rev = true)
        @test issorted(us; rev = true)
        @test issorted(as)
    end

    @testset "sem gás, sem bloco de gás — e sem 'Bloco B — decantação'" begin
        # O bloco `:casco` entrou quando Bell-Delaware passou a calcular `h_o`: antes
        # ele era um campo de formulário e não havia o que memorializar daquele lado.
        blocos = FPSOSiz.trace_block_order(res.trace)
        @test blocos == [:balanco, :tubo, :casco, :selection]
        titulos = [t for (_, t) in FPSOSiz.trace_blocks(SaariLMTD())]
        @test !any(t -> occursin("decanta", lowercase(t)), titulos)
        @test !any(t -> occursin("gás", lowercase(t)), titulos)
    end
end

# ---------------------------------------------------------------------------
# Bell-Delaware — o coeficiente do casco (Branan, cap. 2)
# ---------------------------------------------------------------------------

const KBD = FPSOSiz.constants(FPSOSiz.method_config(SaariLMTD()))[:bell_delaware]

"Uma geometria de casco plausível, para exercitar os fatores isoladamente."
function geo_teste(; d_s = 0.60, corte = 0.25, l_bc = 0.24, layout = 30,
                     n_ss = 1.0, n_t = 400.0)
    d_o = 0.01905
    p_t = 1.25 * d_o
    p_n, p_p, _ = FPSOSiz.layout_pitches(layout, p_t, KBD)
    folga = FPSOSiz.Units.mm_to_m(FPSOSiz.baffle_clearance(d_s * 1000, KBD))
    return FPSOSiz.ShellGeometry(d_s, d_s - folga, d_o, p_t, p_n, p_p,
                                 corte * d_s, l_bc, folga, 0.0008,
                                 n_t, n_ss, 0.0, 2 * d_o, layout)
end

@testset "Tabela 2-6 — os passos são geometria de rede, e são exatos" begin
    p_t = 0.0238125
    for (lay, pn, pp) in ((30, p_t, √3 / 2 * p_t),
                          (45, √2 * p_t, p_t / √2),
                          (60, √3 * p_t, p_t / 2),
                          (90, p_t, p_t))
        a, b, _ = FPSOSiz.layout_pitches(lay, p_t, KBD)
        @test a ≈ pn
        @test b ≈ pp
    end
    # Os dois limiares de troca de garganta da Eq. 2-19 são números fechados:
    # 1 + 1/√2 para o 45° e 2 + √3 para o 60°.
    @test FPSOSiz.layout_pitches(45, p_t, KBD)[3] ≈ 1 + 1 / √2
    @test FPSOSiz.layout_pitches(60, p_t, KBD)[3] ≈ 2 + √3
    # 30° e 90° não trocam de garganta: limiar zero desliga a variante.
    @test FPSOSiz.layout_pitches(30, p_t, KBD)[3] == 0.0
    @test FPSOSiz.layout_pitches(90, p_t, KBD)[3] == 0.0
end

@testset "Tabela 2-7 — a folga casco-chicana sobe em degraus com o DN" begin
    @test FPSOSiz.baffle_clearance(300.0, KBD) ≈ 2.540      # 0,100 in
    @test FPSOSiz.baffle_clearance(400.0, KBD) ≈ 3.175      # 0,125 in
    @test FPSOSiz.baffle_clearance(500.0, KBD) ≈ 3.810      # 0,150 in
    @test FPSOSiz.baffle_clearance(900.0, KBD) ≈ 4.445      # 0,175 in
    @test FPSOSiz.baffle_clearance(1200.0, KBD) ≈ 5.715     # 0,225 in
    @test FPSOSiz.baffle_clearance(2000.0, KBD) ≈ 7.620     # 0,300 in
    # e cada valor é a conversão EXATA da polegada impressa ao lado
    for (mm, pol) in ((2.540, 0.100), (3.175, 0.125), (3.810, 0.150),
                      (4.445, 0.175), (5.715, 0.225), (7.620, 0.300))
        @test isapprox(mm, pol * FPSOSiz.Units.INCH_M * 1000; rtol = 1e-9)
    end
    # é monótona: casco maior, folga maior
    dns = 200.0:100.0:2000.0
    @test issorted([FPSOSiz.baffle_clearance(d, KBD) for d in dns])
end

@testset "Eq. 2-26 — o ângulo da janela: o fator 2 que a fonte perde" begin
    # ESTE é o teste que decide a divergência 3 do TOML. A área bruta da janela É a
    # área de um segmento circular de altura lc; o projeto já tem essa geometria, exata,
    # em `_segment_area` (usada por `segment_height_fraction` desde o Sprint 1). Se as
    # duas não coincidirem, uma das duas está errada — e a do segmento é aritmética.
    for corte in (0.15, 0.20, 0.25, 0.30, 0.35, 0.45)
        g = geo_teste(; corte)
        a_sb, a_tb, a_w = FPSOSiz.leakage_areas(g)

        # área exata do segmento de altura lc, por integração do círculo
        R = g.d_s / 2
        u = g.l_c / R
        exata = R^2 * (acos(1 - u) - (1 - u) * sqrt(max(2u - u^2, 0.0)))

        # A_wg é A_w mais a área que os tubos ocupam na janela; recompomos para comparar
        c1 = g.d_s - g.d_otl
        t3 = 2 * acos(clamp((g.d_s - 2 * g.l_c) / (g.d_s - c1), -1.0, 1.0))
        f_w = (t3 - sin(t3)) / (2π)
        a_wg = a_w + π / 4 * (f_w * g.n_t) * g.d_o^2

        @test isapprox(a_wg, exata; rtol = 1e-9)

        # e a forma IMPRESSA (meio ângulo) erraria por muito — não é arredondamento
        meia = acos(clamp(1 - 2 * g.l_c / g.d_s, -1.0, 1.0))
        errada = g.d_s^2 / 8 * (meia - sin(meia))
        @test errada < exata / 3
    end

    @testset "a Eq. 2-24, ao contrário, usa o MEIO ângulo e está certa" begin
        # A_sb tem de reproduzir (2π − θ_janela)/4·Ds·d_sb, que é o arco vedado.
        g = geo_teste()
        a_sb, _, _ = FPSOSiz.leakage_areas(g)
        theta_janela = 2 * acos(clamp(1 - 2 * g.l_c / g.d_s, -1.0, 1.0))
        @test isapprox(a_sb, (2π - theta_janela) / 4 * g.d_s * g.d_sb; rtol = 1e-12)
    end
end

@testset "os cinco fatores ficam nas faixas que a fonte declara" begin
    g = geo_teste()
    a_s = FPSOSiz.crossflow_area(g, KBD)
    @test isfinite(a_s) && a_s > 0

    re = FPSOSiz.shell_reynolds(g.d_o, 15.0, 3.0e-3, a_s)
    @test isfinite(re) && re > 0

    a_sb, a_tb, a_w = FPSOSiz.leakage_areas(g)
    jc = FPSOSiz.j_baffle_cut(g, KBD)
    jl = FPSOSiz.j_leakage(a_sb, a_tb, a_w, KBD)
    jb = FPSOSiz.j_bypass(g, a_s, re, KBD)
    jr = FPSOSiz.j_laminar(re, g, KBD)

    # Branan dá a faixa de cada um em prosa; são elas que este testset fixa.
    @test 0.50 <= jc <= 1.20        # "about 0.53 ... up to 1.15"
    @test 0.30 <= jl <= 1.00        # "typically between 0.7 and 0.8"
    @test 0.50 <= jb <= 1.00        # "about 0.9 ... about 0.7"
    @test jr ≈ 1.0                  # Re > 100

    @testset "Jc = 0,55 + 0,72·Fc, e Fc cresce quando a janela encolhe" begin
        js_ = [FPSOSiz.j_baffle_cut(geo_teste(; corte = c), KBD)
               for c in (0.45, 0.35, 0.25, 0.15)]
        @test issorted(js_)                       # menos corte, mais Jc
        @test all(x -> float(KBD[:jc_a]) <= x <= float(KBD[:jc_a]) + float(KBD[:jc_b]),
                  js_)
    end

    @testset "Js = 1 quando as pontas igualam o vão central" begin
        # É o que a álgebra da Eq. 2-28 tem de devolver: Li = Lo = 1 zera a correção.
        @test FPSOSiz.j_spacing(20.0, 0.3, 0.3, 0.3, false, KBD) ≈ 1.0
        @test FPSOSiz.j_spacing(20.0, 0.3, 0.3, 0.3, true, KBD) ≈ 1.0
        # e cai quando as pontas alargam
        @test FPSOSiz.j_spacing(20.0, 0.6, 0.6, 0.3, false, KBD) < 1.0
    end

    @testset "Jb = 1 com vedação suficiente, e desconta sem ela" begin
        # z = nss/nr,cc ≥ ½ é desvio totalmente bloqueado.
        g_muita = geo_teste(; n_ss = 40.0)
        @test FPSOSiz.j_bypass(g_muita, a_s, re, KBD) == 1.0
        g_nenhuma = geo_teste(; n_ss = 0.0)
        @test FPSOSiz.j_bypass(g_nenhuma, a_s, re, KBD) <
              FPSOSiz.j_bypass(geo_teste(; n_ss = 2.0), a_s, re, KBD)
    end

    @testset "Jr só existe abaixo de Re 100, e é contínuo nas duas fronteiras" begin
        @test FPSOSiz.j_laminar(100.0, g, KBD) ≈ 1.0
        @test FPSOSiz.j_laminar(500.0, g, KBD) ≈ 1.0
        j20 = FPSOSiz.j_laminar(20.0, g, KBD)
        @test j20 < 1.0
        @test FPSOSiz.j_laminar(5.0, g, KBD) ≈ j20        # constante abaixo de 20
        # a interpolação linear entre 20 e 100 não salta nas pontas
        @test isapprox(FPSOSiz.j_laminar(20.0 + 1e-9, g, KBD), j20; atol = 1e-6)
        @test isapprox(FPSOSiz.j_laminar(100.0 - 1e-9, g, KBD), 1.0; atol = 1e-6)
        @test issorted([FPSOSiz.j_laminar(r, g, KBD) for r in 20.0:10.0:100.0])
    end
end

@testset "Eq. 2-21 — J_ideal com o expoente da Tabela 2-5" begin
    p_t, d_o = 0.0238125, 0.01905

    @testset "cai com Reynolds, em todas as faixas e os quatro layouts" begin
        for lay in (30, 45, 60, 90)
            js_ = [FPSOSiz.colburn_ideal(re, lay, p_t, d_o, KBD)
                   for re in (5.0, 50.0, 500.0, 5e3, 5e4, 5e5)]
            @test all(x -> isfinite(x) && x > 0, js_)
            @test issorted(js_; rev = true)
        end
    end

    @testset "o sinal do a2 que falta na linha 90°/Re 0-10" begin
        # A Tabela 2-5 imprime "0.667" sem menos SÓ nesta célula; as outras 19 trazem o
        # sinal. Com a2 positivo, j CRESCERIA com Re nessa faixa — o contrário do que as
        # outras quatro faixas do mesmo layout fazem, e do que a física do banco de
        # tubos manda. Fica escrito para que ninguém "corrija" de volta.
        @test float(KBD[:a2_90][1]) < 0
        @test float(KBD[:a2_90][1]) ≈ -0.667
        @test all(a -> a < 0, float.(KBD[:a2_30]))
        @test all(a -> a < 0, float.(KBD[:a2_45]))
        @test all(a -> a < 0, float.(KBD[:a2_60]))
        @test all(a -> a < 0, float.(KBD[:a2_90]))
    end

    @testset "a base do expoente é adimensional — a divergência 1" begin
        # Branan imprime 1,33/(PR/d_o) com PR já adimensional. Se fosse isso, trocar d_o
        # de metro para milímetro mudaria J_ideal — e um coeficiente que depende da
        # unidade escolhida não é correlação. A forma implementada usa p_t/d_o, e o
        # teste é justamente a invariância de escala.
        j_m  = FPSOSiz.colburn_ideal(1e4, 30, p_t, d_o, KBD)
        j_mm = FPSOSiz.colburn_ideal(1e4, 30, p_t * 1000, d_o * 1000, KBD)
        @test j_m ≈ j_mm
    end

    @testset "30° e 60° compartilham a linha da tabela" begin
        # A Tabela 2-5 repete os mesmos oito coeficientes nos dois layouts; o que os
        # separa é a Tabela 2-6 (pn e pp), não a correlação.
        @test float.(KBD[:a1_30]) == float.(KBD[:a1_60])
        @test float.(KBD[:a2_30]) == float.(KBD[:a2_60])
    end
end

@testset "h_o = h_ideal·Jc·Jl·Jb·Js·Jr, e o produto encosta nos 0,60 de Branan" begin
    g = geo_teste()
    h_o, fat, ok = FPSOSiz.bell_delaware(g, 15.0, 2100.0, 3.0e-3, 0.13,
                                         20.0, g.l_bc, g.l_bc, KBD)
    @test ok
    @test isfinite(h_o) && h_o > 0
    @test h_o ≈ fat.h_ideal * fat.jc * fat.jl * fat.jb * fat.js * fat.jr
    @test fat.produto ≈ fat.jc * fat.jl * fat.jb * fat.js * fat.jr

    # "a total correction of 0.60 may be used since this has long been used as a rule of
    # thumb" — não é alvo, é ordem de grandeza. Sair muito fora dela seria sinal de que
    # um dos cinco fatores está errado, e é a única aferição externa que este box tem.
    @test 0.35 <= fat.produto <= 0.85

    @testset "as correções só descontam: h_o < h_ideal" begin
        @test h_o < fat.h_ideal
    end

    @testset "a estrutura confere com Toledo-Velázquez et al. (2014)" begin
        # Verificação INDEPENDENTE, e só da estrutura: o paper "Delaware Method
        # Improvement for the Shell and Tubes Heat Exchanger Design" (Engineering 6,
        # 193-201) ajusta equações às curvas gráficas do Delaware original de 1963, e
        # publica a mesma forma
        #     h_cc = Ji·Cp·(W/S_m)·(k/(Cp·µ))^(2/3)·(µ/µ_w)^0,14 · Jc·Jl·Jb·Jr·Js
        # com os mesmos cinco fatores e os mesmos parâmetros de comando (Fc para Jc,
        # Fsbp e Nss/Nc para Jb, Re < 100 para Jr). NÃO se usa a correlação dele: são
        # polinômios de quarta ordem com ~70 constantes contra as ~10 fechadas de
        # Branan. O que se confere aqui é que a forma implementada é a mesma.
        pr_termo = (0.13 / (2100.0 * 3.0e-3))^(2 / 3)
        a_s = FPSOSiz.crossflow_area(g, KBD)
        re = FPSOSiz.shell_reynolds(g.d_o, 15.0, 3.0e-3, a_s)
        j = FPSOSiz.colburn_ideal(re, g.layout, g.p_t, g.d_o, KBD)
        @test fat.h_ideal ≈ j * 2100.0 * (15.0 / a_s) * pr_termo
        # o expoente 2/3 do Prandtl é o do paper e o de Branan; 1/3 seria outra coisa
        @test !isapprox(pr_termo, (0.13 / (2100.0 * 3.0e-3))^(1 / 3))
    end

    @testset "geometria impossível devolve ok = false, não um número" begin
        ruim = FPSOSiz.ShellGeometry(g.d_s, g.d_otl, g.d_o, g.p_t, 0.0, g.p_p,
                                     g.l_c, g.l_bc, g.d_sb, g.d_tb, g.n_t,
                                     g.n_ss, g.n_dp, g.w_p, g.layout)
        h, _, ok2 = FPSOSiz.bell_delaware(ruim, 15.0, 2100.0, 3.0e-3, 0.13,
                                          20.0, g.l_bc, g.l_bc, KBD)
        @test !ok2
        @test isnan(h)
    end
end

@testset "o laço de L fecha, e h_o deixa de ser constante ao longo da grade" begin
    vals = defaults(parameters(SaariLMTD()))
    res = size_equipment(ShellTubeExchanger(), SaariLMTD(),
                         FPSOSiz.case_input(SaariLMTD(), vals), vals)
    @test res.feasible

    @testset "convergiu — e o ponto escolhido carrega a prova" begin
        # `ok` é o flag do ponto fixo em L (Js ← n_b(L) ← L). Um L que não convergiu é
        # indistinguível de um que convergiu se só o número atravessar; `case_admissible`
        # recusa o ponto, então um resultado viável já é a prova de que fechou.
        admissiveis = filter(r -> r.ok, res.sweep)
        @test !isempty(admissiveis)
        d = res.derivados
        @test isfinite(d[:h_casco]) && d[:h_casco] > 0
        @test isfinite(d[:j_produto]) && 0 < d[:j_produto] < 1
        # e a identidade que fecha o laço: L = A/(N·π·d_o) com A = (U·A)/U
        @test res.y ≈ d[:area] / (d[:n_total] * π *
                                  FPSOSiz.Units.mm_to_m(vals[:d_externo]))
    end

    @testset "h_o VARIA com o número de tubos — é o que faz o cálculo valer" begin
        # Com h_casco de formulário, o coeficiente do casco era o mesmo em toda a grade
        # e a varredura só via o lado do tubo. Agora o diâmetro do feixe muda com N, e
        # com ele a área de escoamento cruzado, o Reynolds do casco e os cinco fatores.
        hs = [get(r.derivados, :h_casco, NaN) for r in res.sweep]
        @test all(isfinite, hs)
        @test length(unique(round.(hs; digits = 6))) > 1
    end

    @testset "desligar Bell-Delaware devolve o h_casco do formulário" begin
        # O caminho de saída declarado: quem não conhece a geometria de chicana informa
        # o coeficiente, como antes. É o que preserva o Exemplo 4.1, que tem U dado.
        k = deepcopy(FPSOSiz.constants(FPSOSiz.method_config(SaariLMTD())))
        k[:bell_delaware][:ativo] = false
        ok, cons, _ = FPSOSiz.sizing_constraints(
            SaariLMTD(), FPSOSiz.case_input(SaariLMTD(), vals),
            with_defaults(parameters(SaariLMTD()), vals), k)
        @test ok
        @test !cons.bd_ativo
        t = FPSOSiz._tubo(cons, 40.0)
        @test t.h_o ≈ vals[:h_casco]
        @test isnan(t.j_produto)
        @test t.ok
    end
end

@testset "cruzamento de temperatura é diagnóstico, não exceção" begin
    vals = defaults(parameters(SaariLMTD()))
    vals[:t_tubo_out] = 108.0        # a água sairia quase à entrada do óleo…
    vals[:m_tubo] = 60.0             # …e o casco não teria como sustentar isso
    res = size_equipment(ShellTubeExchanger(), SaariLMTD(),
                         FPSOSiz.case_input(SaariLMTD(), vals), vals)
    @test !res.feasible
    @test occursin("cruzamento", lowercase(res.message)) ||
          occursin("1-2", res.message)
end

@testset "faltar uma entrada do trocador é ArgumentError com o nome dela" begin
    vals = defaults(parameters(SaariLMTD()))
    delete!(vals, :cp_casco)
    err = try
        FPSOSiz.case_input(SaariLMTD(), vals); nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("cp_casco", sprint(showerror, err))
end
