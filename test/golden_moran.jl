"""
Caso-ouro da bomba: Moran, *Pump Sizing*, CEP dez/2016.

O artigo é didático e **não traz um caso resolvido de ponta a ponta** — não há tabela de
`(Q, H)` a reproduzir como a Tabela 3 de Alves & Komesu ou a 3.4 de Stewart & Arnold.
O que ele traz são dois números conferíveis, e este arquivo amarra os dois:

1. **A Tabela 3**, água a 30 °C pela Antoine: `Pv = 0,042438 bar = 4243,81 Pa`. É um
   número exato — a equação, os três coeficientes e a temperatura estão todos impressos.
2. **A leitura da Figura 3**, o nomograma: "for a 25-mm nominal-bore pipe with a flow
   velocity of 1 m/sec, the straight-run headloss is about 6 m per 100 m of pipe".
   Aproximado por declaração da própria figura ("Approximate values only"), e é assim
   que se testa.

Mais as propriedades que as equações têm de ter por construção, e que valem tanto quanto
um número publicado: Colebrook-White convergindo para o limite liso, `f` de Darcy sendo
quatro vezes o de Fanning, a perda crescendo com o quadrado da velocidade, e o par
`Δp ↔ h` fechando por `ρg`.

## Por que não há um terceiro número

Porque as equações do artigo são **imagem** dentro do PDF: o texto extraível traz a
prosa e as tabelas, não as fórmulas. As formas foram recuperadas da prosa — que nomeia
cada símbolo, sua unidade e a faixa de validade — e é justamente por isso que os dois
números publicados são importantes: são a única amarra externa que a implementação tem.
Ver o cabeçalho de `src/sizing/pump/hydraulics.jl`.
"""

const K_BOMBA = FPSOSiz.constants(FPSOSiz.method_config(MoranPumpSizing()))

@testset "Antoine — Tabela 3, água a 30 °C" begin
    # A, B, C impressos na Tabela 3, na forma do NIST com T em kelvin.
    pv = antoine_pressure(5.40221, 1838.675, -31.737, 303.15)
    @test isapprox(pv, 4243.81; rtol = 1e-4)

    # E os defaults do TOML são exatamente esses três — se alguém os trocar, o valor
    # publicado deixa de ser reproduzível e o teste tem de dizê-lo.
    p = defaults(parameters(MoranPumpSizing()))
    @test antoine_pressure(p[:antoine_a], p[:antoine_b], p[:antoine_c], 303.15) ≈ pv

    @testset "a pressão de vapor sobe com a temperatura" begin
        # Trivial de escrever e nada trivial de errar: um sinal invertido em C ou em B
        # produz uma curva decrescente que continua devolvendo números plausíveis, e o
        # NPSH sairia MAIOR quanto mais quente o líquido — o oposto da física.
        ts = 283.15:10.0:363.15
        pvs = [antoine_pressure(5.40221, 1838.675, -31.737, t) for t in ts]
        @test issorted(pvs)
        # água a 100 °C ferve a ~1 atm: a checagem de sanidade que qualquer um faz
        @test isapprox(antoine_pressure(5.40221, 1838.675, -31.737, 373.15),
                       101325.0; rtol = 0.05)
    end
end

@testset "Colebrook-White" begin
    @testset "converge, e o resultado satisfaz a própria equação" begin
        for (re, rel) in ((1e4, 1e-4), (1e5, 1e-3), (1e6, 1e-5), (5e6, 1e-2))
            f, ok = colebrook_white(re, rel)
            @test ok
            # resíduo da forma implícita: 1/√f + 2log₁₀(ε/3,7D + 2,51/(Re√f)) = 0
            r = 1 / sqrt(f) + 2 * log10(rel / 3.7 + 2.51 / (re * sqrt(f)))
            @test abs(r) < 1e-8
        end
    end

    @testset "limite liso e limite rugoso" begin
        # Tubo liso a Re alto: f cai devagar e continua dependendo de Re.
        f_liso_5, _ = colebrook_white(1e5, 0.0)
        f_liso_6, _ = colebrook_white(1e6, 0.0)
        @test f_liso_6 < f_liso_5

        # Regime plenamente rugoso: f deixa de depender de Re (von Kármán).
        f_a, _ = colebrook_white(1e7, 0.02)
        f_b, _ = colebrook_white(1e8, 0.02)
        @test isapprox(f_a, f_b; rtol = 5e-3)
        # e vale o limite explícito 1/√f = −2log₁₀(ε/3,7D)
        @test isapprox(1 / sqrt(f_a), -2 * log10(0.02 / 3.7); rtol = 5e-3)
    end

    @testset "mais rugoso é mais atrito, a mesmo Re" begin
        fs = [colebrook_white(1e5, r)[1] for r in (0.0, 1e-5, 1e-4, 1e-3, 1e-2)]
        @test issorted(fs)
    end

    @testset "Re inválido não devolve número" begin
        # `colebrook_white` sai por `(NaN, false)`, e o `false` é o ponto: um f que não
        # convergiu é indistinguível de um que convergiu se só o número atravessar.
        for re in (0.0, -1.0, NaN, Inf)
            f, ok = colebrook_white(re, 1e-4)
            @test !ok
        end
    end
end

@testset "regimes de escoamento" begin
    @testset "laminar sai por Hagen-Poiseuille, e é exato" begin
        for re in (100.0, 1000.0, 2000.0)
            f, regime, confiavel = darcy_friction(re, 1e-4, K_BOMBA)
            @test regime === :laminar
            @test confiavel
            @test f ≈ 64 / re
        end
    end

    @testset "a transição é marcada como não confiável" begin
        # Entre 2300 e 4000 usa-se Colebrook-White FORA da faixa em que o artigo a
        # declara. O número sai; o que não pode sair é a impressão de que ele vale.
        f, regime, confiavel = darcy_friction(3000.0, 1e-4, K_BOMBA)
        @test regime === :transicao
        @test !confiavel
        @test isfinite(f)
    end

    @testset "acima de 4000 é turbulento e confiável" begin
        f, regime, confiavel = darcy_friction(5e4, 1e-4, K_BOMBA)
        @test regime === :turbulento
        @test confiavel
    end

    @testset "as duas fronteiras vêm do TOML" begin
        @test K_BOMBA[:reynolds_laminar_max] == 2300.0
        @test K_BOMBA[:reynolds_turbulent_min] == 4000.0
        @test K_BOMBA[:laminar_coefficient] == 64.0
    end
end

@testset "Figura 3 — 25 mm a 1 m/s dá ~6 m por 100 m" begin
    # Água a 10 °C, que é o que o nomograma declara. Tubo de ABS (o nomograma é de um
    # fabricante de ABS), rugosidade ~0,0015 mm — praticamente liso.
    re = reynolds_pipe(999.7, 1.0, 0.025, 1.307e-3)
    f, regime, _ = darcy_friction(re, 0.0015 / 25, K_BOMBA)
    h = straight_run_head(f, 100.0, 0.025, 1.0, 9.81)

    @test regime === :turbulento
    @test 4.0 < re / 1000 < 30.0                     # ~19 000
    # "about 6" numa figura que declara "Approximate values only": 20 % é a tolerância
    # honesta para uma leitura de régua sobre escala logarítmica.
    @test isapprox(h, 6.0; rtol = 0.20)
    @test 5.0 < h < 6.5
end

@testset "Darcy-Weisbach e as perdas localizadas" begin
    @testset "a perda cresce com o quadrado da velocidade" begin
        h1 = straight_run_head(0.02, 100.0, 0.1, 1.0, 9.81)
        h2 = straight_run_head(0.02, 100.0, 0.1, 2.0, 9.81)
        @test h2 ≈ 4 * h1
        @test fittings_head(10.8, 2.0, 9.81) ≈ 4 * fittings_head(10.8, 1.0, 9.81)
    end

    @testset "a perda cresce com o comprimento, e cai com o diâmetro" begin
        @test straight_run_head(0.02, 200.0, 0.1, 1.0, 9.81) ≈
              2 * straight_run_head(0.02, 100.0, 0.1, 1.0, 9.81)
        @test straight_run_head(0.02, 100.0, 0.05, 1.0, 9.81) ≈
              2 * straight_run_head(0.02, 100.0, 0.1, 1.0, 9.81)
    end

    @testset "os k-values da Tabela 1 se somam" begin
        # Σk = válvula de controle (10,8) + retenção (1,0) + bloqueio (0,4).
        v, g = 1.5, 9.81
        @test fittings_head(10.8 + 1.0 + 0.4, v, g) ≈
              fittings_head(10.8, v, g) + fittings_head(1.0, v, g) +
              fittings_head(0.4, v, g)
        # E o default do TOML corresponde à contagem descrita no `note` — que é a
        # única forma de a proveniência de um default não apodrecer. Este teste já
        # pegou uma: o `k_recalque` nasceu 13,9 com um `note` que somava 13,8.
        # A Tabela 1 tarifa curva a cada 22,5°, então uma curva de 90° de raio longo
        # vale 4 × 0,1.
        curva90 = 4 * 0.1
        p = defaults(parameters(MoranPumpSizing()))
        @test p[:k_recalque] ≈ 10.8 + 1.0 + 0.4 + 4 * curva90
        @test p[:k_sucao] ≈ 0.5 + 0.4 + 3 * curva90
    end

    @testset "Darcy é quatro vezes Fanning" begin
        # O artigo dedica um parágrafo ao engano porque ele é silencioso: erra a perda
        # por 4× sem produzir nada absurdo na tela. Aqui a afirmação fica escrita.
        f_darcy, _ = colebrook_white(1e5, 1e-4)
        f_fanning = f_darcy / 4
        @test straight_run_head(f_darcy, 100.0, 0.1, 1.0, 9.81) ≈
              4 * (f_fanning * (100.0 / 0.1) * 1.0^2 / (2 * 9.81))
    end
end

@testset "potência de eixo" begin
    # P = ρgQH/(3,6×10⁶·η), com Q em m³/h. Conferência dimensional pelo caminho longo:
    # a potência hidráulica é ρ·g·(Q/3600)·H watts.
    rho, q, h, eta = 998.0, 100.0, 50.0, 0.7
    p_kw = FPSOSiz.Units.hydraulic_power_kw(rho, q, h, eta; g = 9.81)
    @test p_kw ≈ rho * 9.81 * (q / 3600) * h / eta / 1000
    @test isapprox(p_kw, 19.4; rtol = 0.01)

    # Rendimento menor pede mais potência; o artigo manda errar para cima.
    @test FPSOSiz.Units.hydraulic_power_kw(rho, q, h, 0.5; g = 9.81) > p_kw
end

# ---------------------------------------------------------------------------
# O método inteiro
# ---------------------------------------------------------------------------

"Os defaults do formulário da bomba: corrente reetiquetada + parâmetros do método."
bomba_defaults() = merge(defaults(FPSOSiz.stream_parameters(MoranPumpSizing())),
                         defaults(parameters(MoranPumpSizing())))

@testset "a bomba atravessa o motor genérico" begin
    vals = bomba_defaults()
    res = size_equipment(CentrifugalPump(), MoranPumpSizing(),
                         FPSOSiz.case_input(MoranPumpSizing(), vals), vals)
    @test res.feasible

    @testset "o ponto escolhido respeita a banda e o NPSH" begin
        @test vals[:v_min] <= res.derivados[:v] <= vals[:v_max]
        @test res.derivados[:folga_npsh] >= 0
    end

    @testset "é o MENOR DN admissível" begin
        admissiveis = filter(r -> r.ok, res.sweep)
        @test !isempty(admissiveis)
        @test res.x == minimum(r.x for r in admissiveis)
    end

    @testset "a carga fecha: H = h_est + h_atrito" begin
        @test res.y ≈ res.derivados[:h_est] + res.derivados[:h_atrito]
    end

    @testset "as três parcelas do memorial existem" begin
        blocos = FPSOSiz.trace_block_order(res.trace)
        @test :estatica in blocos
        @test :npsh in blocos
        @test :selection in blocos
    end

    @testset "a grade é a série comercial, não um passo constante" begin
        eixo = FPSOSiz.sweep_axis(MoranPumpSizing(), vals)
        serie = Float64.(K_BOMBA[:nominal_diameters])
        @test eixo.values ⊆ serie
        @test issorted(eixo.values)
        # Passo NÃO constante é o ponto: diâmetro de tubo é catálogo.
        passos = diff(eixo.values)
        @test length(unique(passos)) > 1
        # e a série normalizada tem o DN 125 que a Figura 3 não tem — ver o TOML
        @test 125.0 in serie
    end
end

@testset "carga estática negativa é resultado, não erro" begin
    # Recalque a pressão menor que a sucção, e descendo: o líquido escoa sozinho. Não é
    # inviabilidade — é um sifão, e a "bomba" só precisa vencer o atrito.
    vals = bomba_defaults()
    vals[:pressure] = 900.0            # sucção pressurizada
    vals[:p_recalque] = 101.3          # descarga em tanque aberto
    vals[:h_geometrica] = -5.0
    ok, cons, _ = FPSOSiz.sizing_constraints(
        MoranPumpSizing(), FPSOSiz.case_input(MoranPumpSizing(), vals),
        with_defaults(parameters(MoranPumpSizing()), vals), K_BOMBA)
    @test ok
    @test cons.h_est < 0
end

@testset "cavitação é diagnóstico, não exceção" begin
    vals = bomba_defaults()
    vals[:h_sucao] = -8.0              # bomba muito acima do nível de sucção
    vals[:temperature] = 95.0          # e água quase fervendo
    vals[:npsh_requerido] = 6.0
    res = size_equipment(CentrifugalPump(), MoranPumpSizing(),
                         FPSOSiz.case_input(MoranPumpSizing(), vals), vals)
    @test !res.feasible
    @test occursin("cavita", lowercase(res.message))
    # A varredura continua existindo: é dela que a tela desenha o diagnóstico.
    @test !isempty(res.sweep)
    @test all(r -> !r.ok, res.sweep)
end
