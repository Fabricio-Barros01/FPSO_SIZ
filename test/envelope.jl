"""
O motor de envelope — o diferencial do software.

O que precisa ser verdade:
 (a) com um caso só, o envelope tem de coincidir com o dimensionamento simples;
 (b) com N casos, o vaso escolhido tem de atender a todos, e o caso governante tem
     de ser nomeado corretamente;
 (c) faixas viram cantos;
 (d) quando não existe vaso comum, o resultado é `feasible = false` com diagnóstico —
     nunca uma exceção.
"""

base_values() = FPSOSiz.default_case_values()

@testset "(a) um caso ≡ dimensionamento simples" begin
    vals = base_values()
    single = size_equipment(Separator(), StewartArnold(), stream_from_case(vals), vals)
    env    = size_envelope(Separator(), StewartArnold(), CaseSet([Case("A", vals)]))

    @test env.feasible == single.feasible
    @test env.x == single.x
    @test env.y ≈ single.y
    @test der(env, :lss) ≈ der(single, :lss)
    @test der(env, :sr) ≈ der(single, :sr)
    @test env.governing === single.governing
    @test env.driver_case == "A"
    @test env.case_names == ["A"]
    @test only(env.slack) ≈ 0.0 atol = 1e-12          # sem folga: é o próprio caso
    @test length(env.rows) == length(single.sweep)
end

@testset "(b) o envelope cobre todos os casos" begin
    leve  = base_values()
    pesado = merge(base_values(), Dict(:q_water => 1600.0))   # mais água ⇒ exige mais

    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("leve", leve), Case("pesado", pesado)]))
    @test env.feasible
    @test env.driver_case == "pesado"

    # Em TODO diâmetro da grade, a envelope é o máximo entre os casos.
    for row in env.rows
        @test row.y ≈ maximum(row.per_case_y)
        @test length(row.per_case_y) == 2
    end

    # O vaso escolhido atende cada caso individualmente: o Leff envelope é ≥ o de
    # cada caso no mesmo diâmetro.
    escolhida = only(filter(r -> r.x == env.x, env.rows))
    @test all(escolhida.per_case_y .<= escolhida.y + 1e-9)

    # Folga: zero para o caso governante, positiva para o outro.
    i_gov = findfirst(==(env.driver_case), env.case_names)
    @test env.slack[i_gov] ≈ 0.0 atol = 1e-9
    @test all(env.slack .>= -1e-9)
    @test any(env.slack .> 0)

    # É mais exigente que o caso leve sozinho.
    so_leve = size_envelope(Separator(), StewartArnold(), CaseSet([Case("leve", leve)]))
    @test env.y > so_leve.y
end

@testset "(b') o caso governante pode mudar de restrição" begin
    # Um caso rico em líquido (governado pela Eq. 22) e outro com gás muito alto
    # (governado pela Eq. 14). A envelope tem de escolher o certo em cada diâmetro.
    liquido = base_values()
    gas     = merge(base_values(), Dict(:q_gas => 4587.3 * 400, :q_water => 50.0,
                                        :q_oil => 20.0))

    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("líquido", liquido), Case("gás", gas)]))
    @test env.feasible

    # Existem diâmetros governados por cada um dos dois casos.
    drivers = Set(r.driver_case for r in env.rows)
    @test "gás" in drivers
    @test length(drivers) == 2

    # Onde o caso "gás" governa, a restrição governante é a de gás.
    for row in env.rows
        row.driver_case == "gás" && @test row.governing === :gas
    end
end

@testset "(c) faixas viram cantos e o pior canto governa" begin
    vals = merge(base_values(), Dict{Symbol,Any}(
        :q_water => Interval(1025.8, 1600.0),
        :pressure => Interval(2300.0, 2600.0),
    ))
    cs  = CaseSet([Case("faixa", vals)])
    @test corner_count(cs) == 4

    env = size_envelope(Separator(), StewartArnold(), cs)
    @test env.feasible
    @test length(env.case_names) == 4
    @test length(unique(env.case_names)) == 4
    @test all(r -> length(r.per_case_y) == 4, env.rows)

    # O canto governante é o de maior vazão de água (Eq. 22 é crescente em Qw).
    @test occursin("q_water↑", env.driver_case)

    # E o envelope coincide com dimensionar só o pior canto.
    pior = merge(base_values(), Dict(:q_water => 1600.0, :pressure => 2600.0))
    ref  = size_envelope(Separator(), StewartArnold(), CaseSet([Case("pior", pior)]))
    @test env.x == ref.x
    @test env.y ≈ ref.y
end

@testset "(d) inviabilidade é estado, não exceção" begin
    @testset "conjunto vazio" begin
        r = size_envelope(Separator(), StewartArnold(), CaseSet())
        @test !r.feasible
        @test occursin("Nenhum caso ativo", r.message)
    end

    @testset "esbeltez fora da banda em toda a grade" begin
        # Grade presa em diâmetros pequenos, com as vazões do caso-ouro: o vaso fica
        # longo e magro demais (SR ≫ 5). O teto de decantação (16,5 m) não interfere,
        # então o diagnóstico tem de apontar a esbeltez.
        vals = merge(base_values(), Dict(:d_min => 3000.0, :d_max => 3300.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("magro", vals)]))
        @test !r.feasible
        @test occursin("esbeltez", r.message)
        # o culpado é a banda de SR, não o teto de decantação (que a mensagem só
        # menciona como contexto, informando a faixa de SR abaixo dele)
        @test !occursin("respeita o teto", r.message)
        @test occursin("banda", r.message)
        @test !isempty(r.rows)                    # a varredura fica disponível p/ a GUI
    end

    @testset "teto de decantação impede toda a grade" begin
        # Vazões minúsculas ⇒ pouca água ⇒ β maior ⇒ d_max pequeno, abaixo da grade.
        vals = merge(base_values(), Dict(:q_oil => 1.0, :q_water => 1.0,
                                         :d_min => 7000.0, :d_max => 8000.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("teto", vals)]))
        @test !r.feasible
        @test occursin("decantação", r.message)
        @test occursin("água em óleo", r.message) # nomeia o mecanismo
    end

    @testset "óleo mais denso que a água" begin
        vals = merge(base_values(), Dict(:rho_oil => 1100.0))
        r = size_envelope(Separator(), StewartArnold(), CaseSet([Case("denso", vals)]))
        @test !r.feasible
        @test occursin("ΔSG", r.message)
        @test occursin("denso", r.message)        # nomeia o caso culpado
    end

    @testset "entrada de corrente faltando" begin
        r = size_envelope(Separator(), StewartArnold(),
                          CaseSet([Case("incompleto", Dict(:q_oil => 100.0))]))
        @test !r.feasible
        @test occursin("incompleto", r.message)
    end

    @testset "estouro do teto de cantos" begin
        muitos = merge(base_values(),
                       Dict{Symbol,Any}(k => Interval(1.0, 2.0) for k in
                                        (:q_oil, :q_water, :q_gas, :mu_oil, :mu_water)))
        r = size_envelope(Separator(), StewartArnold(),
                          CaseSet([Case("explosivo", muitos)]); max_corners = 8)
        @test !r.feasible
        @test occursin("casos de canto", r.message)
        @test occursin("32", r.message)           # diz quantos seriam
        @test occursin("8", r.message)            # e qual era o limite
    end
end

@testset "resumo de governança" begin
    env = size_envelope(Separator(), StewartArnold(),
                        CaseSet([Case("A", base_values())]))
    s = governing_summary(StewartArnold(), env)
    @test occursin("capacidade de líquido", s)
    @test occursin("A", s)
    @test occursin("decantação", s)
end

# ---------------------------------------------------------------------------
# A genericidade do motor, provada por um vaso que não existe
# ---------------------------------------------------------------------------
#
# Até o Sprint 5 `size_envelope` era declarada sobre `::Separator, ::StewartArnold` e o
# corpo lia o TOML do separador. Um segundo equipamento ganharia formulário e caso
# único e PERDERIA o multi-caso, sem erro e sem teste vermelho — só um método que a
# tela não conseguiria oferecer.
#
# Este vaso fake é a guarda contra a regressão. Ele não tem física: as restrições são
# proporcionais às vazões, com um fator por parâmetro. É de propósito — o que se está
# testando é o MOTOR, e um teste que precisasse da física de um segundo vaso real só
# poderia existir depois de escrevê-la.

struct VasoFake <: AbstractEquipment end
FPSOSiz.method_id(::VasoFake) = :vaso_fake
FPSOSiz.label(::VasoFake) = "Vaso Fake (sem física)"

struct MetodoVasoFake <: AbstractVesselMethod end
FPSOSiz.method_id(::MetodoVasoFake) = :metodo_vaso_fake
FPSOSiz.label(::MetodoVasoFake) = "Método de mentira"
FPSOSiz.applies_to(::MetodoVasoFake) = VasoFake()

# Os seis descritores que o motor exige por nome (grade e banda de SR), mais os dois
# fatores próprios. Ver o cabeçalho de src/sizing/constraints.jl.
FPSOSiz.parameters(::MetodoVasoFake) = [
    ParameterSpec(:d_min,      "Diâmetro mínimo",  "mm", 1000.0, 500.0, 9000.0, false, "fake"),
    ParameterSpec(:d_max,      "Diâmetro máximo",  "mm", 6000.0, 500.0, 9000.0, false, "fake"),
    ParameterSpec(:d_step,     "Passo",            "mm",  100.0,  10.0, 1000.0, false, "fake"),
    ParameterSpec(:sr_min,     "SR mínimo",        "–",     3.0,   1.0,   10.0, false, "fake"),
    ParameterSpec(:sr_max,     "SR máximo",        "–",     5.0,   1.0,   10.0, false, "fake"),
    ParameterSpec(:sr_target,  "SR alvo",          "–",     4.0,   1.0,   10.0, false, "fake"),
    ParameterSpec(:fator_gas,  "Fator de gás",     "–",   1.0e4,   1.0,   1e9,  true,  "fake"),
    ParameterSpec(:fator_liq,  "Fator de líquido", "–",   2.4e8,   1.0,   1e12, true,  "fake"),
]

# Nenhum arquivo em disco: `method_config` só precisa devolver algo de que `constants`
# saiba tirar o bloco. É o que prova que o motor lê o TOML DO MÉTODO que recebeu, e não
# o do separador.
FPSOSiz.method_config(::MetodoVasoFake) =
    Dict{String,Any}("constants" => Dict{String,Any}("lss_liquid_factor" => 1.25))

function FPSOSiz.sizing_constraints(m::MetodoVasoFake, s::StreamState,
                                    p::AbstractDict, k::AbstractDict)
    tr = FPSOSiz.CalcTrace()
    q_liq = s.oil.volumetric_flow + s.water.volumetric_flow
    d_leff_gas = p[:fator_gas] * s.gas.volumetric_flow
    d2_leff    = p[:fator_liq] * q_liq
    FPSOSiz.trace!(tr, :gas,    "—", "d·Leff",  "fator·Qg", d_leff_gas, "mm·m")
    FPSOSiz.trace!(tr, :liquid, "—", "d²·Leff", "fator·Ql", d2_leff, "mm²·m")
    # Construtor de dois argumentos: sem teto de decantação (Inf) e sem geometria de
    # três camadas (NaN) — o caminho que o vaso bifásico do Sprint 5 vai percorrer.
    return (true, VesselConstraints(d_leff_gas, d2_leff), tr)
end

FPSOSiz.size_equipment(eq::VasoFake, m::MetodoVasoFake, s::StreamState,
                       params::AbstractDict) = FPSOSiz.size_vessel(eq, m, s, params)

@testset "o motor de envelope é genérico sobre o equipamento" begin
    register!(VasoFake())
    register!(MetodoVasoFake())

    base = defaults(FPSOSiz.stream_parameters())
    dobro = merge(base, Dict(:q_oil   => 2 * base[:q_oil],
                             :q_water => 2 * base[:q_water]))

    @testset "dimensiona um equipamento que o motor nunca viu" begin
        env = size_envelope(VasoFake(), MetodoVasoFake(), CaseSet([Case("único", base)]))
        @test env.feasible
        @test isfinite(env.x)
        # o resultado por caso carrega o id do método FAKE — o motor não substituiu
        # o método recebido pelo do separador em nenhum ponto do caminho
        @test env.per_case[1].method_id === :metodo_vaso_fake
        @test 3.0 <= der(env, :sr) <= 5.0
        # sem teto de decantação: é o caminho `d_max_mm = Inf` do VesselConstraints
        @test env.ceiling == Inf
        @test length(env.per_case) == 1
        @test env.per_case[1].feasible
        # `lss_from` default, com o fator vindo do `method_config` DO MÉTODO (1,25) —
        # se o motor tivesse lido o TOML do separador, este número não fecharia
        @test der(env, :lss) ≈ 1.25 * env.y
    end

    @testset "multi-caso: a envelope cobre todos, e o maior governa" begin
        cs = CaseSet([Case("normal", base), Case("dobro", dobro)])
        env = size_envelope(VasoFake(), MetodoVasoFake(), cs)
        @test env.feasible
        @test length(env.case_names) == 2
        @test env.driver_case == "dobro"          # o dobro de líquido exige mais Leff
        @test env.governing === :liquid

        # A propriedade que define o motor: em TODO diâmetro da grade, o Leff envelope
        # é o máximo dos Leff de cada caso. É isto que torna o vaso resultante válido
        # para os dois sem hipótese de monotonicidade.
        for row in env.rows
            @test row.y ≈ maximum(row.per_case_y)
        end
        @test all(env.slack .>= -1e-9)          # nenhum caso fica de fora
    end

    @testset "um caso mais exigente não encolhe o vaso" begin
        so  = size_envelope(VasoFake(), MetodoVasoFake(), CaseSet([Case("n", base)]))
        com = size_envelope(VasoFake(), MetodoVasoFake(),
                            CaseSet([Case("n", base), Case("d", dobro)]))
        @test com.feasible && so.feasible
        @test com.y >= so.y
        @test der(com, :volume) >= der(so, :volume)
    end

    @testset "par equipamento/método incoerente é recusado" begin
        # Com dois equipamentos no registro este engano passa a ser possível, e sem a
        # guarda ele produziria números do método errado sob o rótulo do outro.
        env = size_envelope(Separator(), MetodoVasoFake(), CaseSet([Case("x", base)]))
        @test !env.feasible
        @test occursin("não se aplica", env.message)
    end

    @testset "o separador atravessa o mesmo caminho genérico" begin
        # A generalização não pode ter aberto um desvio só para o separador: o
        # equipamento real e o fake saem os dois do registro, pelas mesmas funções.
        for eq in equipments(), met in methods_for(eq)
            met isa MetodoVasoFake || met isa StewartArnold || continue
            @test FPSOSiz.method_config(met) isa AbstractDict
            k = FPSOSiz.constants(FPSOSiz.method_config(met))
            @test haskey(k, :lss_liquid_factor)
            # `lss_from` responde para os dois, e o ramo do gás não usa o fator
            @test FPSOSiz.lss_from(met, 3000.0, 10.0, :gas, k) ≈ 13.0
            @test FPSOSiz.lss_from(met, 3000.0, 10.0, :liquid, k) ≈
                  10.0 * float(k[:lss_liquid_factor])
        end
    end
end

@testset "a banda de esbeltez é interseção, não união" begin
    # A grade de diâmetros é união (procurar mais largo não perde solução); a banda de
    # aceitação é interseção (aceitar mais largo afrouxa a exigência). As duas linhas
    # são vizinhas em envelope.jl e fazem o oposto — daí o teste.
    base = defaults(FPSOSiz.stream_parameters())
    largo   = merge(base, Dict(:sr_min => 3.0, :sr_max => 5.0))
    estreito = merge(base, Dict(:sr_min => 3.5, :sr_max => 4.0))

    @testset "o caso mais exigente manda" begin
        env = size_envelope(VasoFake(), MetodoVasoFake(),
                            CaseSet([Case("largo", largo), Case("estreito", estreito)]))
        @test env.feasible
        # Sob a união, [3,0 , 5,0] seria aceito e um vaso com SR = 3,2 passaria —
        # violando o caso "estreito", que pediu SR ≥ 3,5. O vaso é um só.
        @test 3.5 <= der(env, :sr) <= 4.0
        @test all(r -> !r.ok || 3.5 <= der(r, :sr) <= 4.0, env.rows)
    end

    @testset "bandas que não se cruzam viram diagnóstico, não vaso" begin
        baixo = merge(base, Dict(:sr_min => 2.0, :sr_max => 3.0))
        alto  = merge(base, Dict(:sr_min => 4.5, :sr_max => 6.0))
        env = size_envelope(VasoFake(), MetodoVasoFake(),
                            CaseSet([Case("baixo", baixo), Case("alto", alto)]))
        @test !env.feasible
        @test occursin("não se cruzam", env.message)
        # inviabilidade é estado retornado, com os nomes preservados para a tela
        @test env.case_names == ["baixo", "alto"]
    end

    @testset "o alvo de SR é preso à banda" begin
        # `sr_target` é preferência, não restrição: é a média entre casos. Mas uma média
        # que caia fora da banda comum empurraria o desempate sempre para a mesma ponta.
        fora = merge(base, Dict(:sr_min => 3.0, :sr_max => 3.5, :sr_target => 5.0))
        env = size_envelope(VasoFake(), MetodoVasoFake(), CaseSet([Case("fora", fora)]))
        @test env.feasible
        @test 3.0 <= der(env, :sr) <= 3.5
    end
end

# ---------------------------------------------------------------------------
# A genericidade sobre a GRANDEZA, provada por algo que não é vaso
# ---------------------------------------------------------------------------
#
# O `VasoFake` acima prova que o motor não conhece o equipamento. Não prova que ele não
# conhece a grandeza: até o Sprint 6 o corpo do laço dizia `max(d_leff_gas/d, d2_leff/d²)`,
# a linha da varredura se chamava `d_mm` e o resultado tinha `lss_m` e `sr`. Um vaso
# fictício atravessava isso sem reclamar justamente por ser vaso.
#
# Esta linha de recalque fictícia não é: o eixo é diâmetro nominal de tubulação, a
# grandeza envelopada é carga do sistema, a banda é de velocidade, não há teto e o
# critério de escolha é o menor DN. Se algum dia alguém reintroduzir esbeltez no motor,
# é aqui que quebra — e é aqui que a bomba do Sprint 8 vai encaixar.

struct LinhaFake <: AbstractEquipment end
FPSOSiz.method_id(::LinhaFake) = :linha_fake
FPSOSiz.label(::LinhaFake) = "Linha de recalque (sem física)"

# Note o supertipo: `AbstractSizingMethod`, e NÃO `AbstractVesselMethod`. Nenhum dos
# defaults da família dos vasos vale aqui.
struct MetodoLinhaFake <: AbstractSizingMethod end
FPSOSiz.method_id(::MetodoLinhaFake) = :metodo_linha_fake
FPSOSiz.label(::MetodoLinhaFake) = "Método de linha de mentira"
FPSOSiz.applies_to(::MetodoLinhaFake) = LinhaFake()

FPSOSiz.parameters(::MetodoLinhaFake) = [
    ParameterSpec(:dn_min, "DN mínimo",  "mm",  50.0, 25.0, 600.0, false, "fake"),
    ParameterSpec(:dn_max, "DN máximo",  "mm", 400.0, 25.0, 600.0, false, "fake"),
    ParameterSpec(:dn_step, "Passo",     "mm",  25.0,  5.0, 100.0, false, "fake"),
    ParameterSpec(:v_max,  "Velocidade máxima", "m/s", 1.5, 0.5, 5.0, false, "fake"),
    ParameterSpec(:fator,  "Fator de atrito agregado", "–", 1.0e10, 1.0, 1e14, true, "fake"),
]

FPSOSiz.method_config(::MetodoLinhaFake) = Dict{String,Any}("constants" => Dict{String,Any}())

# A entrada NÃO é uma `StreamState`: este equipamento não tem óleo, água nem gás. É o
# hook `case_input` fazendo o que existe para fazer.
struct EntradaLinha
    q::Float64          # vazão, m³/h
    h_est::Float64      # carga estática, m
    comprimento::Float64
end

function FPSOSiz.case_input(::MetodoLinhaFake, vals::AbstractDict)
    faltando = [k for k in (:q, :h_est, :comprimento) if !haskey(vals, k)]
    isempty(faltando) || throw(ArgumentError("entradas ausentes: $(join(faltando, ", "))"))
    return EntradaLinha(float(vals[:q]), float(vals[:h_est]), float(vals[:comprimento]))
end

# As restrições que não dependem do DN: a carga estática e o agregado de atrito.
function FPSOSiz.sizing_constraints(::MetodoLinhaFake, e::EntradaLinha,
                                    p::AbstractDict, k::AbstractDict)
    tr = FPSOSiz.CalcTrace()
    atrito = p[:fator] * e.comprimento * e.q^2
    FPSOSiz.trace!(tr, :estatica, "—", "h_est", "cota do reservatório", e.h_est, "m")
    FPSOSiz.trace!(tr, :atrito, "—", "K", "fator·L·Q²", atrito, "m·mm⁵")
    return (true, (h_est = e.h_est, atrito = atrito, q = e.q), tr)
end

# `hf ∝ L·Q²/D⁵`, que é a forma de Darcy-Weisbach — nenhum `Leff`, nenhum `d²·Leff`.
FPSOSiz.requirement(::MetodoLinhaFake, dn::Real, c) = c.h_est + c.atrito / dn^5
FPSOSiz.governing_of(::MetodoLinhaFake, dn::Real, c) =
    c.atrito / dn^5 > c.h_est ? :atrito : :estatica

FPSOSiz.sweep_axis(::MetodoLinhaFake, p::AbstractDict) =
    SweepAxis(:dn, "diâmetro nominal", "mm", collect(p[:dn_min]:p[:dn_step]:p[:dn_max]))

function FPSOSiz.derived(::MetodoLinhaFake, dn::Real, y::Real, gov::Symbol, c,
                         k::AbstractDict, p::AbstractDict)
    area = π * (dn / 1000)^2 / 4
    return Dict{Symbol,Float64}(:v => c.q / 3600 / area, :carga => y)
end

FPSOSiz.admissible(::MetodoLinhaFake, dn::Real, d::AbstractDict, p::AbstractDict) =
    d[:v] <= p[:v_max]

# O menor DN admissível é o mais barato — critério que não tem alvo nem distância.
FPSOSiz.objective(::MetodoLinhaFake, dn::Real, d::AbstractDict, p::AbstractDict) = dn

function FPSOSiz.envelope_params(::MetodoLinhaFake, params::Vector{<:AbstractDict})
    return (true, Dict{Symbol,Float64}(
        :dn_min  => minimum(p[:dn_min] for p in params),
        :dn_max  => maximum(p[:dn_max] for p in params),
        :dn_step => minimum(p[:dn_step] for p in params),
        :v_max   => minimum(p[:v_max] for p in params),      # interseção, como a banda
        :fator   => maximum(p[:fator] for p in params)))
end

FPSOSiz.selection_message(::MetodoLinhaFake, rows, teto::Real, p::AbstractDict;
                          mechanism::Symbol = :none) =
    "Nenhum DN da grade mantém a velocidade abaixo de $(p[:v_max]) m/s."

FPSOSiz.governing_label(::MetodoLinhaFake, g::Symbol) =
    g === :atrito ? "perda por atrito" : g === :estatica ? "carga estática" : String(g)

FPSOSiz.result_fields(m::MetodoLinhaFake, r) = ResultField[
    ResultField("Diâmetro nominal", r.feasible ? r.x : NaN; unit = "mm", digits = 0,
                highlight = true),
    ResultField("Carga do sistema", r.feasible ? r.y : NaN; unit = "m"),
    ResultField("Velocidade", der(r, :v); unit = "m/s"),
    ResultField("Termo governante",
                r.feasible ? FPSOSiz.governing_label(m, r.governing) : "—"),
]

FPSOSiz.sweep_columns(::MetodoLinhaFake) = [
    SweepColumn("DN (mm)", :x; digits = 0),
    SweepColumn("H (m)",   :y),
    SweepColumn("v (m/s)", :v),
]

FPSOSiz.size_equipment(eq::LinhaFake, m::MetodoLinhaFake, e, params::AbstractDict) =
    FPSOSiz.size_single(eq, m, e, params)

@testset "o motor de envelope é genérico sobre a grandeza" begin
    register!(LinhaFake())
    register!(MetodoLinhaFake())

    base = Dict{Symbol,Any}(:q => 100.0, :h_est => 12.0, :comprimento => 250.0)

    @testset "dimensiona algo que não é vaso" begin
        env = size_envelope(LinhaFake(), MetodoLinhaFake(), CaseSet([Case("único", base)]))
        @test env.feasible
        @test env.x in 50.0:25.0:400.0

        # A banda é de VELOCIDADE, e é ela que decide — não há esbeltez em lugar nenhum.
        @test der(env, :v) <= 1.5
        escolhida = only(filter(r -> r.x == env.x, env.rows))
        @test escolhida.ok
        # menor DN admissível: o anterior na grade tem de violar a banda
        anteriores = filter(r -> r.x < env.x, env.rows)
        @test !isempty(anteriores)
        @test all(!r.ok for r in anteriores)
    end

    @testset "sem teto declarado, o motor usa o default Inf" begin
        env = size_envelope(LinhaFake(), MetodoLinhaFake(), CaseSet([Case("único", base)]))
        @test isinf(env.ceiling)
        @test env.ceiling_mechanism === :none
        resumo = governing_summary(MetodoLinhaFake(), env)
        @test occursin("Governa", resumo)
        @test !occursin("Teto", resumo)
    end

    @testset "a envelope cobre os casos, sem saber o que envelopa" begin
        magro = merge(base, Dict{Symbol,Any}(:q => 60.0))
        env = size_envelope(LinhaFake(), MetodoLinhaFake(),
                            CaseSet([Case("cheio", base), Case("magro", magro)]))
        @test env.feasible
        @test env.driver_case == "cheio"                 # mais vazão, mais carga
        @test all(env.slack .>= -1e-9)
        for row in env.rows
            @test row.y ≈ maximum(row.per_case_y)
        end
    end

    @testset "a apresentação é do método, não do vaso" begin
        env = size_envelope(LinhaFake(), MetodoLinhaFake(), CaseSet([Case("único", base)]))
        rotulos = [f.label for f in FPSOSiz.result_fields(MetodoLinhaFake(), env)]
        @test "Carga do sistema" in rotulos
        @test "Velocidade" in rotulos
        @test !any(occursin("Esbeltez", r) for r in rotulos)
        @test !any(occursin("Leff", r) for r in rotulos)

        colunas = FPSOSiz.sweep_columns(MetodoLinhaFake())
        @test [c.label for c in colunas] == ["DN (mm)", "H (m)", "v (m/s)"]
        # E as colunas leem mesmo as linhas da varredura, pelas chaves que declararam.
        linha = first(env.rows)
        @test FPSOSiz.column_value(linha, colunas[1]) == linha.x
        @test FPSOSiz.column_value(linha, colunas[3]) == linha.derivados[:v]
        # Chave que o método não produz vira NaN, não zero: zero seria um número.
        @test isnan(FPSOSiz.column_value(linha, SweepColumn("SR", :sr)))
    end

    @testset "sem blocos declarados, o memorial usa a ordem de aparição" begin
        # Default de `trace_blocks`: vazio. A interface então agrupa pela ordem em que os
        # blocos apareceram no rastro, que é a ordem do cálculo — legível sem títulos.
        @test isempty(FPSOSiz.trace_blocks(MetodoLinhaFake()))
        env = size_envelope(LinhaFake(), MetodoLinhaFake(), CaseSet([Case("único", base)]))
        @test FPSOSiz.trace_block_order(first(env.per_case).trace) == [:estatica, :atrito]
    end

    @testset "entrada ausente é diagnóstico com o nome do caso, não exceção" begin
        incompleto = Dict{Symbol,Any}(:q => 100.0)      # sem h_est nem comprimento
        env = size_envelope(LinhaFake(), MetodoLinhaFake(),
                            CaseSet([Case("torto", incompleto)]))
        @test !env.feasible
        @test occursin("torto", env.message)
        @test occursin("h_est", env.message)
    end
end
