"""
Caso-ouro da Análise Pinch: Kemp, *Pinch Analysis and Process Integration*, 2ª ed.,
Butterworth-Heinemann, 2007 (ISBN 978-0-7506-8260-2).

**A fonte traz o exemplo resolvido inteiro, e por isso este é o caso-ouro mais completo
do projeto.** Não há aqui o buraco de `golden_saari.jl`, onde Saari não publica exemplo
numérico fechado: Kemp publica as quatro correntes (Tabela 2.2, p. 21), a tabela de
intervalos com o CP líquido e o calor de cada um (Tabela 2.3, p. 22), **as duas cascatas**
(Figura 2.9, p. 23) e os alvos com a temperatura de pinch (p. 24). Todos os números abaixo
estão impressos no livro; nenhum foi recalculado para caber.

O exemplo está no **capítulo 2**, não no 3. O capítulo 3 traz o algoritmo passo a passo
(§3.9.1, pp. 95-96) e os problemas-limiar (§3.3.2, p. 54) — que dão o segundo caso-ouro.

## Os dois casos

1. **Quatro correntes a ΔTmin = 10 °C** — a cascata número a número, e os alvos
   QHmin = 20 kW, QCmin = 60 kW com pinch em 85 °C deslocada (90 °C quentes, 80 °C frias).
2. **As mesmas correntes abaixo do limiar** (§3.3.2, p. 54): *"as ∆Tmin is reduced, a
   point is reached (at 5.55 °C) where no hot utility is required; at all lower values of
   ∆Tmin, the only utility needed is 40 kW cold utility."* É um problema-limiar com número
   publicado, em vez de um construído para o teste.

## Dois errata da fonte, sem consequência para o programa

Ficam registrados pela mesma razão que os de Stewart & Arnold e os de Saari: quem for
conferir o teste contra o livro precisa saber por que dois números não são o que a página
diz.

1. **O apêndice do cap. 3 é citado com o número errado.** O §3.3 (p. 53) manda ver os
   algoritmos em *"Section 3.11"*; o apêndice é **§3.9** (p. 95). Não há §3.11 no livro.
2. **As cargas da p. 24 aparecem em kWh onde são kW.** O texto fala em *"510 and 470 kWh"*
   e *"60 and 20 kWh"* para grandezas que a própria Tabela 2.3 dá em kW — são taxas, não
   energias acumuladas. O `CP` é kW/K e a temperatura é °C: o produto é kW.

## Tolerância

0,01 °C em temperatura e 0,1 % em calor. Na prática o acordo é exato — o algoritmo é
aritmética sobre os dados, sem correlação empírica no meio — e as folgas existem para o
caso de o livro ter arredondado, que é o que acontece no "5,55 °C" do §3.3.2.
"""

const TOL_T = 0.01      # °C
const TOL_Q = 0.001     # fração — 0,1 % em calor

"Tabela 2.2, p. 21. Quatro correntes; o tipo sai do sinal de T_in − T_out, não de rótulo."
kemp_tabela_2_2() = [
    FPSOSiz.PinchAnalysis.ThermalStream("1 fria",    20, 135, 2.0),
    FPSOSiz.PinchAnalysis.ThermalStream("2 quente", 170,  60, 3.0),
    FPSOSiz.PinchAnalysis.ThermalStream("3 fria",    80, 140, 4.0),
    FPSOSiz.PinchAnalysis.ThermalStream("4 quente", 150,  30, 1.5),
]

const KP = FPSOSiz.PinchAnalysis

# ---------------------------------------------------------------------------
# Tabela 2.2 (p. 21) — as temperaturas deslocadas publicadas
# ---------------------------------------------------------------------------

@testset "Tabela 2.2 — as temperaturas deslocadas, corrente a corrente" begin
    correntes = kemp_tabela_2_2()

    # As colunas SS e ST da tabela publicada, na ordem das correntes.
    publicadas = [(25.0, 140.0),     # 1 fria:    20 → 135, sobe 5
                  (165.0, 55.0),     # 2 quente: 170 →  60, desce 5
                  (85.0, 145.0),     # 3 fria:    80 → 140, sobe 5
                  (145.0, 25.0)]     # 4 quente: 150 →  30, desce 5

    for (s, esperado) in zip(correntes, publicadas)
        obtido = KP.shifted_temperatures(only(s.segments), 10.0)
        @test obtido[1] ≈ esperado[1] atol = TOL_T
        @test obtido[2] ≈ esperado[2] atol = TOL_T
    end

    # E o tipo, que o livro dá por extenso na coluna "Stream number and type", tem de
    # sair derivado — sem ninguém informá-lo.
    @test [KP.stream_type(s) for s in correntes] == [:cold, :hot, :cold, :hot]
end

# ---------------------------------------------------------------------------
# Tabela 2.3 (p. 22) — os cinco intervalos
# ---------------------------------------------------------------------------

@testset "Tabela 2.3 — fronteiras, CP líquido e calor de cada intervalo" begin
    r = KP.problem_table(kemp_tabela_2_2(), 10.0)
    @test r.feasible

    # As seis fronteiras impressas embaixo da tabela: S1 … S6.
    @test length(r.boundaries) == 6
    for (obtido, publicado) in zip(r.boundaries, [165.0, 145.0, 140.0, 85.0, 55.0, 25.0])
        @test obtido ≈ publicado atol = TOL_T
    end

    # As três colunas numéricas da Tabela 2.3, linha a linha.
    publicada = [(20.0,  3.0,  60.0),     # 1 — excedente
                 ( 5.0,  0.5,   2.5),     # 2 — excedente
                 (55.0, -1.5, -82.5),     # 3 — déficit
                 (30.0,  2.5,  75.0),     # 4 — excedente
                 (30.0, -0.5, -15.0)]     # 5 — déficit

    @test length(r.intervals) == 5
    for (iv, (dt, cp, dh)) in zip(r.intervals, publicada)
        @test iv.s_top - iv.s_bot ≈ dt atol = TOL_T
        @test iv.cp_net ≈ cp rtol = TOL_Q
        @test iv.dh ≈ dh rtol = TOL_Q
        # a última coluna do livro, "Surplus or deficit", é o sinal de ΔH
        @test sign(iv.dh) == sign(dh)
    end
end

# ---------------------------------------------------------------------------
# Figura 2.9 (p. 23) — as duas cascatas
# ---------------------------------------------------------------------------

@testset "Figura 2.9 — as cascatas infactível e factível, nó a nó" begin
    r = KP.problem_table(kemp_tabela_2_2(), 10.0)

    # (a) infactível: parte de zero no topo e passa por −20 kW, que é o que a torna
    # termodinamicamente impossível e o que fixa QHmin.
    for (obtido, publicado) in zip(r.cascade_infeasible,
                                   [0.0, 60.0, 62.5, -20.0, 55.0, 40.0])
        @test obtido ≈ publicado rtol = TOL_Q atol = 1e-9
    end
    @test minimum(r.cascade_infeasible) ≈ -20.0 rtol = TOL_Q

    # (b) factível: os mesmos fluxos somados de 20 kW, com zero exato no pinch.
    for (obtido, publicado) in zip(r.cascade_feasible,
                                   [20.0, 80.0, 82.5, 0.0, 75.0, 60.0])
        @test obtido ≈ publicado rtol = TOL_Q atol = 1e-9
    end
end

# ---------------------------------------------------------------------------
# p. 24 — os alvos e o pinch
# ---------------------------------------------------------------------------

@testset "p. 24 — QHmin, QCmin e a posição do pinch" begin
    r = KP.problem_table(kemp_tabela_2_2(), 10.0)

    @test r.q_h_min ≈ 20.0 rtol = TOL_Q
    @test r.q_c_min ≈ 60.0 rtol = TOL_Q

    # "the position of the pinch has been located. This is at the interval boundary with
    # a shifted temperature of 85°C (i.e. hot streams at 90°C and cold at 80°C)"
    @test length(r.t_pinch_shifted) == 1
    @test only(r.t_pinch_shifted) ≈ 85.0 atol = TOL_T
    @test only(r.t_pinch_hot)     ≈ 90.0 atol = TOL_T
    @test only(r.t_pinch_cold)    ≈ 80.0 atol = TOL_T

    # Com as duas utilidades presentes, não é problema-limiar.
    @test !r.threshold
end

@testset "p. 24 — as conferências cruzadas que o próprio livro manda fazer" begin
    # "The total heat recovered by heat exchange is found by adding the heat loads for
    # all the hot streams and all the cold streams – 510 and 470 kW[h], respectively.
    # Subtracting the cold and hot utility targets (60 and 20 kW[h]) from these values
    # gives the total heat recovery, 450 kW[h], by two separate routes."
    correntes = kemp_tabela_2_2()
    r = KP.problem_table(correntes, 10.0)
    cargas = KP.heat_loads(correntes)

    @test cargas.hot  ≈ 510.0 rtol = TOL_Q
    @test cargas.cold ≈ 470.0 rtol = TOL_Q

    # A recuperação por dois caminhos independentes, como o livro pede.
    @test cargas.hot  - r.q_c_min ≈ 450.0 rtol = TOL_Q
    @test cargas.cold - r.q_h_min ≈ 450.0 rtol = TOL_Q

    # "The cold utility target minus the hot utility target should equal the bottom line
    # of the infeasible heat cascade, which is 40 kW[h]."
    @test r.q_c_min - r.q_h_min ≈ 40.0 rtol = TOL_Q
    @test r.cascade_infeasible[end] ≈ 40.0 rtol = TOL_Q
end

# ---------------------------------------------------------------------------
# §3.3.2, p. 54 — o problema-limiar
# ---------------------------------------------------------------------------

@testset "§3.3.2 — abaixo de ΔTthreshold só sobra utilidade fria, e o pinch some" begin
    correntes = kemp_tabela_2_2()

    # "at all lower values of ∆Tmin, the only utility needed is 40 kW cold utility"
    for dt in (0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 5.5)
        r = KP.problem_table(correntes, dt)
        @test r.feasible
        @test r.q_h_min ≈ 0.0 atol = 1e-9
        @test r.q_c_min ≈ 40.0 rtol = TOL_Q
        @test r.threshold
        # Sem pinch: é o que distingue um problema-limiar de um problema com pinch, e é
        # por isso que `threshold` e `t_pinch_shifted` são campos separados.
        @test isempty(r.t_pinch_shifted)
    end

    # E logo acima do limiar a utilidade quente reaparece, com pinch.
    r6 = KP.problem_table(correntes, 6.0)
    @test r6.q_h_min > 0
    @test !r6.threshold
    @test length(r6.t_pinch_shifted) == 1
end

@testset "§3.3.2 — o ΔTthreshold publicado, 5,55 °C" begin
    correntes = kemp_tabela_2_2()

    # A forma fechada do QHmin destas correntes, válida em 0 ≤ ΔTmin ≤ 10: o nó da
    # cascata que governa está na fronteira de 80 + ΔTmin/2, e vale 25 − 9·(ΔTmin/2).
    #     QHmin = max(0; 4,5·ΔTmin − 25),  com raiz em 50/9 = 5,5556 °C
    # Ela reproduz os DOIS pontos publicados — o 20 kW da p. 24 e o "5,55 °C" da p. 54 —
    # e é o que sustenta a monotonicidade analiticamente, e não por amostragem.
    fechada(dt) = max(0.0, 4.5 * dt - 25.0)

    for dt in 0.25:0.25:10.0
        @test KP.problem_table(correntes, dt).q_h_min ≈ fechada(dt) rtol = TOL_Q atol = 1e-9
    end

    limiar = 50 / 9
    @test limiar ≈ 5.55 atol = 0.01          # o valor impresso, dentro do arredondamento
    @test KP.problem_table(correntes, limiar).q_h_min ≈ 0.0 atol = 1e-9

    # No ΔTmin exato do limiar as duas coisas coexistem: a utilidade quente é zero E
    # ainda há um pinch interior. É o caso de borda que motiva os dois campos.
    r = KP.problem_table(correntes, limiar)
    @test r.threshold
    @test length(r.t_pinch_shifted) == 1
    @test only(r.t_pinch_shifted) ≈ 80.0 + limiar / 2 atol = TOL_T

    # Acima do limiar QHmin é estritamente crescente, com a inclinação de 4,5 kW/°C.
    a = KP.problem_table(correntes, 8.0).q_h_min
    b = KP.problem_table(correntes, 9.0).q_h_min
    @test b - a ≈ 4.5 rtol = TOL_Q
end
