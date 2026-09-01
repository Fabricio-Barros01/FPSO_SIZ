"""
O registro é o que faz o 2º plano (bomba, tratador eletrostático, trocador com pinch,
vaso flash) entrar **por adição**: registrar no core faz a tela aparecer sem editar
uma linha de `app/`.

Este teste prova isso declarando um equipamento e um método completamente fora de
`src/`, e verificando que a GUI conseguiria montar o formulário só a partir do
registro — sem citar nenhum parâmetro pelo nome.
"""

# --- um equipamento fictício, declarado aqui, fora de src/ ------------------
struct TratadorFake <: AbstractEquipment end
FPSOSiz.method_id(::TratadorFake) = :tratador_fake
FPSOSiz.label(::TratadorFake) = "Tratador Eletrostático (fake)"

struct MetodoFake <: AbstractSizingMethod end
FPSOSiz.method_id(::MetodoFake) = :metodo_fake
FPSOSiz.label(::MetodoFake) = "Método Fake"
FPSOSiz.applies_to(::MetodoFake) = TratadorFake()
FPSOSiz.parameters(::MetodoFake) = [
    ParameterSpec(:tensao, "Tensão dos eletrodos", "kV", 20.0, 5.0, 50.0, false, "fake"),
    ParameterSpec(:gap, "Distância entre placas", "mm", 150.0, 50.0, 400.0, true, "fake"),
]

@testset "registro de equipamentos e métodos" begin
    @testset "o separador se registra sozinho no __init__" begin
        @test FPSOSiz.equipment(:separator) isa Separator
        @test any(m -> method_id(m) === :stewart_arnold, methods_for(:separator))
        @test label(Separator()) == "Separador Trifásico Horizontal"
        @test label(StewartArnold()) == "Stewart & Arnold (2008)"
    end

    @testset "extensão por adição, de fora de src/" begin
        register!(TratadorFake())
        register!(MetodoFake())

        @test FPSOSiz.equipment(:tratador_fake) isa TratadorFake
        @test any(e -> method_id(e) === :tratador_fake, equipments())

        m = FPSOSiz.sizing_method(:tratador_fake, :metodo_fake)
        @test m isa MetodoFake

        # É isto que a GUI faz: descobre o equipamento, os métodos e os campos,
        # sem conhecer nenhum nome de parâmetro.
        for eq in equipments(), met in methods_for(eq)
            @test label(eq) isa String
            @test label(met) isa String
            specs = parameters(met)
            @test !isempty(specs)
            @test all(s -> s isa ParameterSpec, specs)
            d = defaults(specs)
            @test isempty(validate(specs, d))     # os defaults são sempre válidos
        end
    end

    @testset "registrar de novo substitui, não duplica" begin
        antes = length(methods_for(:tratador_fake))
        register!(MetodoFake())
        @test length(methods_for(:tratador_fake)) == antes
    end
end

@testset "validação de parâmetros" begin
    specs = parameters(StewartArnold())
    d = defaults(specs)
    @test isempty(validate(specs, d))

    spec = only(filter(s -> s.key === :dm_water, specs))
    @test validate(spec, 500.0) === nothing
    @test occursin("abaixo do mínimo", validate(spec, 1.0))
    @test occursin("acima do máximo", validate(spec, 1e6))
    @test occursin("não numérico", validate(spec, NaN))

    msgs = validate(specs, Dict(:dm_water => 1.0, :tr_oil => 1e6))
    @test length(msgs) == 2

    @testset "with_defaults ignora chaves desconhecidas" begin
        p = with_defaults(specs, Dict(:dm_water => 300.0, :inexistente => 1.0))
        @test p[:dm_water] == 300.0
        @test p[:dm_oil] == 200.0            # veio do default
        @test !haskey(p, :inexistente)
    end
end

@testset "descritores de corrente" begin
    specs = FPSOSiz.stream_parameters()
    keys_ = Set(s.key for s in specs)
    for k in FPSOSiz.STREAM_KEYS
        @test k in keys_
    end
    @test isempty(validate(specs, defaults(specs)))
    # todo descritor traz rótulo, unidade e proveniência preenchidos
    @test all(s -> !isempty(s.label) && !isempty(s.unit) && !isempty(s.note), specs)
end

# --- um método que não é trifásico, para provar `stream_keys` -----------------
struct MetodoBifasicoFake <: AbstractSizingMethod end
FPSOSiz.method_id(::MetodoBifasicoFake) = :bifasico_fake
FPSOSiz.label(::MetodoBifasicoFake) = "Bifásico Fake"
FPSOSiz.applies_to(::MetodoBifasicoFake) = TratadorFake()
FPSOSiz.parameters(::MetodoBifasicoFake) = FPSOSiz.parameters(MetodoFake())
# Sem fase aquosa: nem vazão, nem densidade, nem viscosidade de água.
FPSOSiz.stream_keys(::MetodoBifasicoFake) =
    (:q_oil, :q_gas, :rho_oil, :rho_gas, :mu_oil, :mu_gas, :pressure, :temperature, :z)

@testset "um método declara as entradas de corrente que consome" begin
    @testset "o default continua sendo trifásico" begin
        @test FPSOSiz.stream_keys(StewartArnold()) === FPSOSiz.STREAM_KEYS
        @test length(FPSOSiz.stream_parameters(StewartArnold())) ==
              length(FPSOSiz.stream_parameters())
    end

    @testset "o formulário encolhe junto com o método" begin
        specs = FPSOSiz.stream_parameters(MetodoBifasicoFake())
        chaves = Set(s.key for s in specs)
        @test length(specs) == 9
        @test !(:q_water in chaves)
        @test !(:rho_water in chaves)
        @test !(:mu_water in chaves)
        @test :q_oil in chaves && :q_gas in chaves
        # a ordem do arquivo é preservada — o formulário não pode embaralhar
        todos = [s.key for s in FPSOSiz.stream_parameters()]
        @test [s.key for s in specs] == filter(in(chaves), todos)
    end

    @testset "a fase ausente vira NaN, não zero" begin
        # Zero é um valor POSSÍVEL (uma corrente pode ter água nula), então usá-lo como
        # "não informado" faria um resultado errado passar por válido. NaN se propaga e
        # aparece na tela. Mesma decisão de VesselConstraints.
        vals = defaults(FPSOSiz.stream_parameters())
        magro = Dict(k => v for (k, v) in vals
                     if k in FPSOSiz.stream_keys(MetodoBifasicoFake()))

        s = stream_from_case(magro; required = FPSOSiz.stream_keys(MetodoBifasicoFake()))
        @test isnan(s.water.volumetric_flow)
        @test isnan(s.water.density)
        @test isnan(s.water.viscosity)
        @test s.oil.density == vals[:rho_oil]        # o que foi declarado chega intacto
        @test s.gas.density == vals[:rho_gas]

        fu = field_units(s)
        @test isnan(fu.sg_w)                          # e contamina quem insistir em usar
        @test !isnan(fu.sg_o)
    end

    @testset "faltar uma chave que o método EXIGE continua sendo erro" begin
        vals = defaults(FPSOSiz.stream_parameters())
        sem_oleo = Dict(k => v for (k, v) in vals if k !== :q_oil)
        @test_throws ArgumentError stream_from_case(sem_oleo)
        @test_throws ArgumentError stream_from_case(
            sem_oleo; required = FPSOSiz.stream_keys(MetodoBifasicoFake()))
        # mas faltar água só é erro para quem pede água
        sem_agua = Dict(k => v for (k, v) in vals if k !== :q_water)
        @test_throws ArgumentError stream_from_case(sem_agua)
        @test stream_from_case(sem_agua;
                  required = FPSOSiz.stream_keys(MetodoBifasicoFake())) isa StreamState
    end
end
