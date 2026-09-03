@testset "Interval" begin
    @test Interval(3.0, 1.0) == Interval(1.0, 3.0)        # ordena na construção
    @test FPSOSiz.corners(Interval(1.0, 3.0)) == (1.0, 3.0)
    @test FPSOSiz.corners(Interval(2.0, 2.0)) == (2.0,)   # degenerado = escalar
    @test FPSOSiz.corners(5.0) == (5.0,)
end

@testset "construção de Case" begin
    c = Case("A", Dict(:x => 1, :y => Interval(2, 4), :z => (5, 7), :w => [8, 9]))
    @test c.values[:x] === 1.0
    @test c.values[:y] == Interval(2.0, 4.0)
    @test c.values[:z] == Interval(5.0, 7.0)             # tupla vira faixa
    @test c.values[:w] == Interval(8.0, 9.0)             # vetor de 2 também
    @test c.enabled
    @test_throws ArgumentError Case("B", Dict(:x => [1, 2, 3]))
end

@testset "expansão em casos de canto" begin
    base = Dict{Symbol,Any}(:a => 1.0, :b => 2.0)

    @testset "sem faixas: 1 caso, nome preservado" begin
        cs = CaseSet([Case("único", base)])
        @test corner_count(cs) == 1
        ex = expand(cs)
        @test length(ex) == 1
        @test ex[1][1] == "único"
        @test ex[1][2] == Dict(:a => 1.0, :b => 2.0)
    end

    @testset "duas faixas: 4 cantos, todos distintos" begin
        c = Case("C", merge(base, Dict(:a => Interval(1, 2), :b => Interval(10, 20))))
        cs = CaseSet([c])
        @test corner_count(cs) == 4
        ex = expand(cs)
        @test length(ex) == 4
        pares = Set((v[:a], v[:b]) for (_, v) in ex)
        @test pares == Set([(1.0, 10.0), (1.0, 20.0), (2.0, 10.0), (2.0, 20.0)])
        @test length(Set(first.(ex))) == 4               # nomes únicos
        @test all(n -> occursin("↓", n) || occursin("↑", n), first.(ex))
    end

    @testset "casos desativados não entram" begin
        cs = CaseSet([Case("on", base), Case("off", base; enabled = false)])
        @test corner_count(cs) == 1
        @test only(expand(cs))[1] == "on"
    end

    @testset "o teto de cantos é respeitado" begin
        muitos = Dict{Symbol,Any}(Symbol("v$i") => Interval(0, 1) for i in 1:6)
        cs = CaseSet([Case("grande", muitos)])
        @test corner_count(cs) == 64
        @test length(expand(cs; max_corners = 64)) == 64
        @test_throws ArgumentError expand(cs; max_corners = 32)
    end

    @testset "conjunto vazio" begin
        @test isempty(expand(CaseSet()))
        @test corner_count(CaseSet()) == 0
    end
end

@testset "carga de casos do TOML" begin
    cs = load_case_set("exemplo_alves_komesu.toml")
    @test length(cs.cases) == 4
    @test length(active(cs)) == 3                     # um está desativado
    @test corner_count(cs) == 1 + 1 + 8               # o terceiro tem 3 faixas

    nomes = [c.name for c in cs.cases]
    @test "Projeto (Tabela 1)" in nomes
    @test only(filter(c -> occursin("Partida", c.name), cs.cases)).enabled == false

    faixa = only(filter(c -> c.name == "Faixa de operação", cs.cases))
    @test faixa.values[:q_oil] == Interval(180.0, 260.0)
    @test faixa.values[:pressure] === 2300.0

    ex = expand(cs)
    @test length(ex) == 10
    @test all(v -> all(k -> haskey(v, k), FPSOSiz.STREAM_KEYS), last.(ex))

    @testset "dimensiona o conjunto de exemplo" begin
        env = size_envelope(Separator(), StewartArnold(), cs)
        @test env.feasible
        @test length(env.case_names) == 10
        # o caso de fim de vida (1600 m³/h de água) ou o canto de maior água governa
        @test occursin("Fim de vida", env.driver_case) ||
              occursin("q_water↑", env.driver_case)
        @test all(env.slack .>= -1e-9)
    end
end

@testset "gravar e reler um conjunto de casos" begin
    # O aceite do Sprint 4. `save_case_set` é a inversa de `case_set_from_config`, e a
    # única forma de provar isso é a ida e volta: o que sai do disco depois de gravar
    # tem de ser indistinguível do que entrou. Sem este teste, um escalar virando faixa
    # degenerada (ou o contrário) passaria despercebido até alguém reabrir o arquivo
    # meses depois e ver o número de cantos mudar.
    original = load_case_set("exemplo_alves_komesu.toml")

    mktempdir() do dir
        caminho = joinpath(dir, "ida_e_volta.toml")
        FPSOSiz.save_case_set(original, caminho; label = "Rótulo preservado")
        @test isfile(caminho)

        cfg = TOML.parsefile(caminho)
        @test FPSOSiz.config_label(cfg, "—") == "Rótulo preservado"

        volta = case_set_from_config(cfg)
        @test length(volta.cases) == length(original.cases)
        for (a, b) in zip(original.cases, volta.cases)
            @test a.name == b.name
            @test a.enabled == b.enabled
            @test a.values == b.values          # escalar continua escalar, faixa continua faixa
        end

        # e o que o motor faz com um é o que faz com o outro
        @test corner_count(volta) == corner_count(original)
        @test length(active(volta)) == length(active(original))
        @test first.(expand(volta)) == first.(expand(original))
    end
end

@testset "gravação preserva o que é frágil" begin
    mktempdir() do dir
        caminho = joinpath(dir, "frageis.toml")
        cs = CaseSet([
            # aspas, barra invertida e quebra de linha no nome: os três quebrariam o
            # arquivo se fossem escritos crus, e nome de caso vem do usuário
            Case("Aspas \" barra \\ quebra \n fim", Dict(:a => 1.0)),
            # desativado tem de continuar desativado ao reabrir
            Case("desligado", Dict(:a => 2.0); enabled = false),
            # faixa degenerada (lo == hi) e valor de muitas casas: `repr` é exato
            Case("precisão", Dict(:a => Interval(3.0, 3.0), :b => 0.1 + 0.2)),
        ])
        FPSOSiz.save_case_set(cs, caminho)
        volta = case_set_from_config(TOML.parsefile(caminho))

        @test [c.name for c in volta.cases] == [c.name for c in cs.cases]
        @test volta.cases[2].enabled == false
        @test volta.cases[3].values[:b] === 0.1 + 0.2     # bit a bit, sem arredondar
        @test volta.cases[3].values[:a] == Interval(3.0, 3.0)
        @test corner_count(volta) == corner_count(cs)     # degenerada não vira canto
    end
end

@testset "o nome do arquivo de casos é um nome, não um caminho" begin
    # `POST /api/casos/salvar` grava em disco com o nome que o navegador mandou. Sem
    # esta guarda, um nome com `..` sairia de `dir_casos()` — e o servidor escuta em
    # 127.0.0.1, onde qualquer página aberta no mesmo navegador pode postar.
    @test FPSOSiz.nome_casos_valido("meus_casos.toml")
    @test FPSOSiz.nome_casos_valido("Caso de operação 2026.toml")

    for ruim in ("../fora.toml", "..\\fora.toml", "/etc/passwd.toml", "sem_extensao",
                 "", ".toml", ".oculto.toml", "com/barra.toml", "aspas\".toml",
                 "quebra\nlinha.toml")
        @test !FPSOSiz.nome_casos_valido(ruim)
    end

    @test_throws ArgumentError FPSOSiz.case_set_path("../fora.toml")
    @test_throws ArgumentError FPSOSiz.save_case_set_named(CaseSet(), "../fora.toml")
end

@testset "listagem e resolução por nome" begin
    lista = FPSOSiz.list_case_sets()
    @test !isempty(lista)
    exemplo = only(filter(a -> a.nome == "exemplo_alves_komesu.toml", lista))
    @test exemplo.casos == 4
    @test occursin("Alves", exemplo.rotulo)
    @test isfile(exemplo.caminho)
    @test all(a -> endswith(a.nome, ".toml"), lista)
    @test length(unique(a.nome for a in lista)) == length(lista)   # sem duplicata

    @test FPSOSiz.case_set_path("exemplo_alves_komesu.toml") == exemplo.caminho
    @test FPSOSiz.case_set_path("nao_existe_em_lugar_nenhum.toml") == ""
    @test_throws ErrorException load_case_set("nao_existe_em_lugar_nenhum.toml")
end
