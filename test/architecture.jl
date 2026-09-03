"""
Regras de arquitetura, verificadas mecanicamente.

O core precisa rodar headless — testes, CI e o modo lote dependem disso. Uma
dependência de GUI que entre "só para um gráfico rápido" quebra o empacotamento e o
CI sem aviso, então é barrada aqui.
"""

const ROOT = FPSOSiz.project_root()
const GUI_PKGS = ["GLMakie", "CairoMakie", "WGLMakie", "Makie", "GenieFramework",
                  "Genie", "Stipple", "StippleUI", "Blink", "Electron", "Gtk4",
                  "QML", "CImGui", "Dash"]

@testset "o core não depende de GUI" begin
    proj = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    @test proj["name"] == "FPSOSiz"

    deps = keys(get(proj, "deps", Dict()))
    for pkg in GUI_PKGS
        @test !(pkg in deps)
    end

    # Nem por import direto em src/.
    padrao = Regex("^\\s*(using|import)\\s+(" * join(GUI_PKGS, "|") * ")\\b")
    for (dir, _, files) in walkdir(joinpath(ROOT, "src")), f in files
        endswith(f, ".jl") || continue
        caminho = joinpath(dir, f)
        for (i, linha) in enumerate(eachline(caminho))
            if occursin(padrao, linha)
                @test false
                @info "import de GUI no core" arquivo = caminho linha = i conteudo = linha
            end
        end
    end
    @test true
end

@testset "os caminhos são resolvidos em runtime" begin
    # Um `const` com `@__DIR__` congela na precompilação. Num executável do
    # PackageCompiler isso aponta para o diretório da máquina que fez o build, e o
    # programa não acha o próprio `config/` no computador de quem o recebeu. Como a
    # falha só aparece depois de empacotar, ela é barrada aqui.
    for arquivo in ["config.jl"]
        codigo = read(joinpath(ROOT, "src", arquivo), String)
        sem_comentario = join(filter(l -> !startswith(strip(l), "#"),
                                     split(codigo, '\n')), "\n")
        @test !occursin(r"^\s*const\s+\w+\s*=.*@__DIR__"m, sem_comentario)
    end

    # E a resolução tem de honrar o escape que o empacotador usa.
    @test isdir(joinpath(FPSOSiz.project_root(), "config"))
    @test FPSOSiz._tem_config(ROOT)
    @test !FPSOSiz._tem_config(joinpath(ROOT, "src"))

    # `FPSOSIZ_RAIZ` só é aceito se o diretório realmente tiver `config/` — apontar
    # para lugar errado deve cair no próximo candidato, não devolver lixo.
    mktempdir() do vazio
        anterior = FPSOSiz._RAIZ[]
        try
            FPSOSiz._RAIZ[] = ""
            withenv("FPSOSIZ_RAIZ" => vazio) do
                @test FPSOSiz.project_root() != vazio
            end
        finally
            FPSOSiz._RAIZ[] = anterior
        end
    end
end

@testset "as constantes vivem no TOML, não no código" begin
    # Guarda contra a constante ser duplicada como literal dentro do .jl, o que faria
    # o TOML virar decoração. Procuramos os dígitos significativos, não o valor exato.
    sa = read(joinpath(ROOT, "src", "sizing", "separator", "stewart_arnold.jl"), String)
    codigo = join(filter(l -> !startswith(strip(l), "#"), split(sa, '\n')), "\n")
    for literal in ["42152.13", "4.2152e4", "34.5 *", "0.033 *"]
        @test !occursin(literal, codigo)
    end

    # E o TOML tem de trazer todas as constantes que o código consome.
    k = FPSOSiz.constants(FPSOSiz.load_config("equipment", "separator",
                                              "stewart_arnold.toml"))
    for c in (:eq14_coefficient, :eq17_coefficient, :eq22_coefficient,
              :lss_liquid_factor, :cd_initial, :cd_relaxation)
        @test haskey(k, c)
        @test float(k[c]) isa Float64
    end

    # Mesma guarda para o vaso bifásico: os coeficientes das Eq. 3.8b e 3.9b não podem
    # aparecer como literal dentro do .jl, senão o TOML vira decoração.
    k2 = FPSOSiz.constants(FPSOSiz.load_config("equipment", "knockout",
                                               "stewart_arnold_2f.toml"))
    for c in (:gas_capacity_coefficient, :liquid_capacity_coefficient,
              :lss_liquid_factor, :cd_initial, :cd_relaxation)
        @test haskey(k2, c)
        @test float(k2[c]) isa Float64
    end
    # O que se proíbe é o número USADO no cálculo, não citado no texto: a fórmula que
    # o memorial mostra ("42441·tr·Ql") contém o valor de propósito, para que o leitor
    # do relatório saiba o que foi multiplicado. Daí procurar o operador `*` junto — a
    # fórmula usa `·`, que não é operador nenhum em Julia.
    kn = read(joinpath(ROOT, "src", "sizing", "knockout", "two_phase.jl"), String)
    codigo_kn = join(filter(l -> !startswith(strip(l), "#"), split(kn, '\n')), "\n")
    for literal in ["42441 *", "42441.0 *", "4.2441e4", "34.5 *"]
        @test !occursin(literal, codigo_kn)
    end
end

@testset "todo parâmetro tem rótulo, unidade e proveniência" begin
    # Iterado pelo REGISTRO, não por uma lista escrita à mão: um equipamento novo entra
    # nesta guarda por registrar-se, que é a única forma de a guarda não envelhecer.
    for eq in equipments(), met in methods_for(eq)
        for spec in vcat(parameters(met), FPSOSiz.stream_parameters(met))
            @test !isempty(spec.label)
            @test !isempty(spec.unit)
            @test !isempty(spec.note)
            @test spec.min <= spec.default <= spec.max
        end
        # Os seis descritores que a FAMÍLIA DOS VASOS exige por nome — e só ela. Um
        # método registrado que não seja vaso (uma bomba, um trocador; aqui, o tratador
        # fictício de registry.jl) não tem grade de diâmetro nem esbeltez, e exigi-los
        # seria impor a forma de um vaso a todo o registro — exatamente o acoplamento
        # que os Sprints 5 e 7 desfizeram.
        #
        # A condição era um `hasmethod` sobre a assinatura de `sizing_constraints` com
        # `StreamState`. Deixou de servir no Sprint 7: `case_input` soltou a entrada da
        # `StreamState`, então um vaso pode legitimamente receber outra coisa, e um
        # não-vaso pode legitimamente receber uma `StreamState`. O supertipo é a
        # declaração explícita de quem é da família.
        if met isa FPSOSiz.AbstractVesselMethod
            chaves = Set(s.key for s in parameters(met))
            for k in (:d_min, :d_max, :d_step, :sr_min, :sr_max, :sr_target)
                @test k in chaves
            end
            # e quem usa o `lss_from` default precisa do fator no próprio TOML
            @test haskey(FPSOSiz.constants(FPSOSiz.method_config(met)),
                         :lss_liquid_factor)
        end
    end
end

@testset "config/ está onde o código espera" begin
    @test isfile(joinpath(ROOT, "config", "stream.toml"))
    @test isfile(joinpath(ROOT, "config", "equipment", "separator",
                          "stewart_arnold.toml"))
    @test isdir(joinpath(ROOT, "config", "cases"))
end

@testset "o catálogo não promete o que o core não tem" begin
    # `config/catalogo.toml` é o que o menu de abertura mostra. Um box marcado `ativo`
    # que aponte para um equipamento inexistente daria um cartão clicável levando a uma
    # tela que não monta — e a falha apareceria no navegador do usuário, não aqui.
    boxes = FPSOSiz.catalogo()
    @test !isempty(boxes)
    @test length(unique(b.id for b in boxes)) == length(boxes)   # ids únicos

    for b in boxes
        @test !isempty(b.titulo)
        @test !isempty(b.subtitulo)
        @test !isempty(b.icone)
        # id vai para a URL (/app/<id>) e para o nome de um arquivo de estado: nada de
        # separador, espaço ou acento.
        @test occursin(r"^[a-z0-9][a-z0-9-]*$", b.id)

        if b.ativo
            par = FPSOSiz.box_equipamento(b)
            @test par !== nothing                # resolve no registro
            eq, m = par
            @test FPSOSiz.method_id(eq) === Symbol(b.equipment)
            @test FPSOSiz.method_id(m) === Symbol(b.method)
            @test FPSOSiz.method_id(FPSOSiz.applies_to(m)) === FPSOSiz.method_id(eq)
        else
            # e um box pendente é obrigado a dizer por quê
            @test !isempty(b.motivo)
        end
    end

    @testset "os dois vasos prontos estão no catálogo" begin
        ativos = Set(b.equipment for b in boxes if b.ativo)
        @test "separator" in ativos
        @test "knockout" in ativos
    end

    @testset "id desconhecido não resolve" begin
        @test FPSOSiz.box_catalogo("nao-existe") === nothing
        @test FPSOSiz.box_catalogo("../etc/passwd") === nothing
    end
end
