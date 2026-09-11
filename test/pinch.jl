"""
O núcleo da Análise Pinch: recusa de entrada, comportamento e invariantes.

O caso-ouro de Kemp mora em `golden_kemp.jl`. Aqui ficam as regras que não dependem de
fonte — as que o algoritmo tem de obedecer por construção, e que continuariam valendo se
o livro nunca tivesse sido escrito.

A regra de "uma regra de validação por teste" é levada a sério: cada `@testset` da
primeira seção viola **uma** coisa e verifica que a queixa é sobre aquela coisa. Um teste
que viola duas regras passa mesmo quando o código só pega uma delas.
"""

const Pinch = FPSOSiz.PinchAnalysis

"Correntes de Kemp — repetidas aqui porque vários testes de comportamento precisam delas."
kemp_streams() = [
    Pinch.ThermalStream("1 fria",    20, 135, 2.0),
    Pinch.ThermalStream("2 quente", 170,  60, 3.0),
    Pinch.ThermalStream("3 fria",    80, 140, 4.0),
    Pinch.ThermalStream("4 quente", 150,  30, 1.5),
]

"Uma corrente boa, para servir de companhia a uma ruim."
ok_stream(nome = "boa") = Pinch.ThermalStream(nome, 200, 100, 1.0)

# ---------------------------------------------------------------------------
# Recusa de entrada — uma regra por teste
# ---------------------------------------------------------------------------

@testset "recusa: lista de correntes vazia" begin
    msgs = Pinch.validate_streams(Pinch.ThermalStream[], 10.0)
    @test length(msgs) == 1
    @test occursin("vazia", only(msgs))

    r = Pinch.problem_table(Pinch.ThermalStream[], 10.0)
    @test !r.feasible
    @test isnan(r.q_h_min)
end

@testset "recusa: ΔTmin não positivo" begin
    for mau in (0.0, -5.0, NaN, Inf)
        msgs = Pinch.validate_streams([ok_stream()], mau)
        @test length(msgs) == 1
        @test occursin("ΔTmin", only(msgs))
    end
    # e o positivo finito passa
    @test isempty(Pinch.validate_streams([ok_stream()], 10.0))
end

@testset "recusa: mCp não positivo" begin
    for mau in (0.0, -2.0, NaN, Inf)
        s = Pinch.ThermalStream("ruim", 200, 100, mau)
        msgs = Pinch.validate_streams([s], 10.0)
        @test length(msgs) == 1
        @test occursin("mCp", only(msgs))
    end
end

@testset "recusa: segmento isotérmico, com a receita da p. 44" begin
    s = Pinch.ThermalStream("condensador", 120, 120, 5.0)
    msgs = Pinch.validate_streams([s], 10.0)
    @test length(msgs) == 1

    # A mensagem não pode ser só "recusado": tem de dizer o que fazer, e de onde vem.
    # É a diferença entre uma recusa e um diagnóstico.
    m = only(msgs)
    @test occursin("isotérmico", m)
    @test occursin("§3.1.3", m)
    @test occursin("p. 44", m)
    @test occursin("suprimento", m)

    # E o CP infinito não entra por outra porta: rejeitado, não aproximado em silêncio.
    @test !Pinch.problem_table([s, ok_stream()], 10.0).feasible
end

@testset "recusa: temperatura não numérica" begin
    for mau in (NaN, Inf, -Inf)
        s = Pinch.ThermalStream("ruim", mau, 100, 1.0)
        msgs = Pinch.validate_streams([s], 10.0)
        @test length(msgs) == 1
        @test occursin("não numérica", only(msgs))
    end
end

@testset "recusa: segmentos que mudam de direção" begin
    s = Pinch.ThermalStream("vai e volta", [
        Pinch.StreamSegment(200, 100, 1.0),   # esfria
        Pinch.StreamSegment(100, 180, 1.0),   # esquenta
    ])
    msgs = Pinch.validate_streams([s], 10.0)
    @test length(msgs) == 1
    @test occursin("direção", only(msgs))
end

@testset "recusa: segmentos não contíguos" begin
    s = Pinch.ThermalStream("com buraco", [
        Pinch.StreamSegment(200, 150, 1.0),
        Pinch.StreamSegment(140, 100, 1.0),   # o buraco de 150 a 140
    ])
    msgs = Pinch.validate_streams([s], 10.0)
    @test length(msgs) == 1
    @test occursin("contíguos", only(msgs))
end

@testset "recusa: corrente sem segmento nenhum" begin
    s = Pinch.ThermalStream("oca", Pinch.StreamSegment[])
    msgs = Pinch.validate_streams([s], 10.0)
    @test length(msgs) == 1
    @test occursin("segmento", only(msgs))
end

@testset "a recusa nunca lança — devolve resultado inviável com diagnóstico" begin
    # É o contrato do módulo inteiro: não há `case_input` aqui, logo não há fronteira
    # de tradução, logo não há exceção legítima.
    for entrada in ([ok_stream()], Pinch.ThermalStream[],
                    [Pinch.ThermalStream("x", 100, 100, 1.0)],
                    [Pinch.ThermalStream("y", 100, 50, -1.0)])
        for dt in (10.0, 0.0, -1.0, NaN)
            r = @test_nowarn Pinch.problem_table(entrada, dt)
            r.feasible || @test !isempty(r.message)
        end
    end
end

# ---------------------------------------------------------------------------
# O tipo da corrente é DERIVADO
# ---------------------------------------------------------------------------

@testset "quente ou fria sai do sinal de T_in − T_out" begin
    quente = Pinch.ThermalStream("q", 200, 100, 1.0)
    fria   = Pinch.ThermalStream("f", 100, 200, 1.0)

    @test Pinch.stream_type(quente) === :hot
    @test Pinch.stream_type(fria)   === :cold
    @test Pinch.is_hot(only(quente.segments))
    @test Pinch.is_cold(only(fria.segments))

    # Não existe campo de tipo para contradizer os números — a API não o oferece e não
    # há construtor que o aceite.
    @test fieldnames(Pinch.StreamSegment) == (:t_in, :t_out, :mcp)
    @test fieldnames(Pinch.ThermalStream) == (:name, :segments)
end

# ---------------------------------------------------------------------------
# Comportamento
# ---------------------------------------------------------------------------

@testset "corrente única quente: toda a carga vira utilidade fria" begin
    s = Pinch.ThermalStream("só quente", 200, 100, 2.0)
    r = Pinch.problem_table([s], 10.0)

    @test r.feasible
    @test r.q_h_min == 0.0
    @test r.q_c_min ≈ 200.0            # 2,0 kW/°C × 100 °C
    @test r.threshold                   # uma utilidade zerou
    @test isempty(r.t_pinch_shifted)    # e não há pinch: nada com que trocar
end

@testset "corrente única fria: toda a carga vira utilidade quente" begin
    s = Pinch.ThermalStream("só fria", 100, 200, 2.0)
    r = Pinch.problem_table([s], 10.0)

    @test r.feasible
    @test r.q_h_min ≈ 200.0
    @test r.q_c_min == 0.0
    @test r.threshold
    @test isempty(r.t_pinch_shifted)
end

@testset "problema-limiar: uma utilidade zera e o pinch some" begin
    # Kemp §3.3.2, p. 54, com as correntes do livro. O número publicado está no
    # caso-ouro; aqui verifica-se só a ESTRUTURA do desfecho.
    r = Pinch.problem_table(kemp_streams(), 3.0)

    @test r.feasible
    @test r.q_h_min == 0.0
    @test r.threshold
    @test isempty(r.t_pinch_shifted)

    # E acima do limiar volta a haver pinch, com as duas utilidades.
    r10 = Pinch.problem_table(kemp_streams(), 10.0)
    @test !r10.threshold
    @test length(r10.t_pinch_shifted) == 1
    @test r10.q_h_min > 0 && r10.q_c_min > 0
end

@testset "pinch em extremidade não é confundido com ponta livre" begin
    # Duas correntes que se tocam exatamente na ponta mais fria: o fluxo é nulo no
    # último nó, que é QCmin, e isso NÃO é um pinch — é "não precisa de utilidade fria".
    s = [Pinch.ThermalStream("q", 200, 100, 1.0),
         Pinch.ThermalStream("f",  90, 190, 1.0)]
    r = Pinch.problem_table(s, 10.0)

    @test r.feasible
    @test r.q_c_min == 0.0
    @test r.threshold
    # o nó zero está na PONTA, então não entra na lista de pinches
    @test isempty(r.t_pinch_shifted)
    @test r.cascade_feasible[end] == 0.0
end

@testset "N correntes: o algoritmo não tem número mágico de correntes" begin
    # Seis correntes, três de cada lado, sem fronteiras coincidentes.
    s = [Pinch.ThermalStream("q1", 250, 120, 1.0),
         Pinch.ThermalStream("q2", 210,  70, 2.0),
         Pinch.ThermalStream("q3", 180,  40, 1.5),
         Pinch.ThermalStream("f1",  30, 160, 2.5),
         Pinch.ThermalStream("f2",  60, 200, 1.0),
         Pinch.ThermalStream("f3",  90, 230, 0.5)]
    r = Pinch.problem_table(s, 12.0)

    @test r.feasible
    @test length(r.intervals) == length(r.boundaries) - 1
    @test length(r.cascade_feasible) == length(r.boundaries)
    @test r.q_h_min >= 0 && r.q_c_min >= 0

    cargas = Pinch.heat_loads(s)
    @test r.q_c_min - r.q_h_min ≈ cargas.hot - cargas.cold
end

# ---------------------------------------------------------------------------
# Invariantes — o que tem de valer sem consultar fonte nenhuma
# ---------------------------------------------------------------------------

@testset "invariância de segmentação: partir uma corrente não muda nada" begin
    # Uma corrente de CP constante partida em dois segmentos do MESMO CP é a mesma
    # corrente. Se o resultado mudar, o tratamento de segmentos está errado — e este
    # teste não depende de Kemp nem de número publicado nenhum.
    inteira = Pinch.ThermalStream("fria", 20, 135, 2.0)
    partida = Pinch.ThermalStream("fria", [Pinch.StreamSegment(20,  75, 2.0),
                                           Pinch.StreamSegment(75, 135, 2.0)])
    outras = [Pinch.ThermalStream("2 quente", 170, 60, 3.0),
              Pinch.ThermalStream("3 fria",    80, 140, 4.0),
              Pinch.ThermalStream("4 quente", 150,  30, 1.5)]

    a = Pinch.problem_table([inteira; outras], 10.0)
    b = Pinch.problem_table([partida; outras], 10.0)

    @test a.q_h_min ≈ b.q_h_min
    @test a.q_c_min ≈ b.q_c_min
    @test a.t_pinch_shifted ≈ b.t_pinch_shifted
    # a cascata de `b` tem um nó a mais (a fronteira de 75 °C), mas o total não muda
    @test a.cascade_infeasible[end] ≈ b.cascade_infeasible[end]
end

@testset "balanço de entalpia: QCmin − QHmin não depende de ΔTmin" begin
    # A p. 24 de Kemp usa isto como conferência, e é um invariante forte: o balanço do
    # problema inteiro é fixado pelos dados, não pela aproximação térmica escolhida.
    s = kemp_streams()
    cargas = Pinch.heat_loads(s)
    liquido = cargas.hot - cargas.cold

    for dt in (0.5, 1.0, 5.0, 10.0, 20.0, 40.0)
        r = Pinch.problem_table(s, dt)
        @test r.feasible
        @test r.q_c_min - r.q_h_min ≈ liquido
        # e é também o último nó da cascata infactível
        @test r.cascade_infeasible[end] ≈ liquido
    end
end

@testset "a cascata factível é a infactível somada de QHmin, e nunca é negativa" begin
    r = Pinch.problem_table(kemp_streams(), 10.0)
    @test r.cascade_feasible ≈ r.cascade_infeasible .+ r.q_h_min
    @test all(r.cascade_feasible .>= -1e-9)
    @test minimum(r.cascade_feasible) ≈ 0.0 atol = 1e-9
    @test r.cascade_feasible[1] ≈ r.q_h_min
    @test r.cascade_feasible[end] ≈ r.q_c_min
end

@testset "o pinch deslocado é ΔTmin/2 de cada lado das temperaturas reais" begin
    r = Pinch.problem_table(kemp_streams(), 10.0)
    @test r.t_pinch_hot  ≈ r.t_pinch_shifted .+ 5.0
    @test r.t_pinch_cold ≈ r.t_pinch_shifted .- 5.0
    # e a distância entre os dois lados é exatamente ΔTmin, que é o ponto de tudo isto
    @test all(r.t_pinch_hot .- r.t_pinch_cold .≈ 10.0)
end

@testset "o deslocamento é aplicado uma vez só" begin
    # Conferido na função que o aplica, e não por inspeção do texto: quente desce
    # ΔTmin/2, fria sobe ΔTmin/2, e nada mais no módulo mexe em temperatura.
    quente = Pinch.StreamSegment(170, 60, 3.0)
    fria   = Pinch.StreamSegment(20, 135, 2.0)

    @test Pinch.shifted_temperatures(quente, 10.0) == (165.0, 55.0)
    @test Pinch.shifted_temperatures(fria,   10.0) == (25.0, 140.0)

    # ΔTmin = 0 não desloca nada — é o limite, e serve para provar que o fator é ΔTmin/2
    # e não ΔTmin nem ΔTmin/4.
    @test Pinch.shifted_temperatures(quente, 0.0) == (170.0, 60.0)
    @test Pinch.shifted_temperatures(quente, 20.0) == (160.0, 50.0)
end

# ---------------------------------------------------------------------------
# Monotonicidade — o que sustenta `requirement = QHmin` no encaixe
# ---------------------------------------------------------------------------

@testset "QHmin é não decrescente em ΔTmin" begin
    # É a propriedade que autoriza tratar QHmin como "exigência" numa varredura sobre
    # ΔTmin: aproximar mais as curvas nunca pode custar MAIS utilidade quente. Se este
    # teste cair, o encaixe do motor está errado, e não o teste.
    for correntes in (kemp_streams(),
                      [Pinch.ThermalStream("q", 250, 120, 1.0),
                       Pinch.ThermalStream("f",  30, 160, 2.5),
                       Pinch.ThermalStream("q2", 180, 40, 1.5)])
        qs = [Pinch.problem_table(correntes, dt).q_h_min for dt in 0.1:0.1:60.0]
        @test all(diff(qs) .>= -1e-9)
        # e QCmin acompanha, porque a diferença entre os dois é fixa
        cs = [Pinch.problem_table(correntes, dt).q_c_min for dt in 0.1:0.1:60.0]
        @test all(diff(cs) .>= -1e-9)
    end
end

# ---------------------------------------------------------------------------
# Pureza — a guarda que substitui o TOML e o registro
# ---------------------------------------------------------------------------

@testset "o núcleo é puro: não cita a camada de aplicação nem a de configuração" begin
    # Guarda deliberadamente textual, como a guarda 3 de `architecture.jl`. E com a
    # mesma ressalva que ela faz: o que se proíbe é o nome USADO, não o nome CITADO.
    # O cabeçalho do módulo precisa dizer "aqui não há `ParameterSpec`" para que a
    # decisão fique registrada, e uma guarda que proibisse a frase obrigaria o arquivo a
    # ficar calado justamente sobre o que ele garante. Por isso caem fora as docstrings
    # (`\"\"\"…\"\"\"`) e os comentários, e sobra o código.
    fonte = read(joinpath(dirname(@__DIR__), "src", "analysis", "pinch.jl"), String)
    sem_doc = replace(fonte, r"\"{3}.*?\"{3}"s => "")
    codigo = join(filter(l -> !startswith(strip(l), "#"), split(sem_doc, '\n')), "\n")

    for proibido in ("ParameterSpec", "AbstractSizingMethod", "AbstractEquipment",
                     "SweepAxis", "ResultField", "StreamState", "method_config",
                     "load_config", "TOML", "include(")
        @test !occursin(proibido, codigo)
    end

    # Nenhuma constante empírica: o único literal estrutural é o `2` de ΔTmin/2, e ele
    # aparece como `/ 2`, nunca multiplicando um dado. É o espelho da guarda 3.
    for literal in ("34.5 *", "0.033 *", "42441 *")
        @test !occursin(literal, codigo)
    end

    # E o módulo carrega sozinho, sem nada do resto do pacote.
    @test isdefined(FPSOSiz, :PinchAnalysis)
    @test parentmodule(Pinch.problem_table) === Pinch
end
