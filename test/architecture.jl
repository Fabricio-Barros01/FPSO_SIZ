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
end

@testset "todo parâmetro tem rótulo, unidade e proveniência" begin
    for met in (StewartArnold(),), spec in parameters(met)
        @test !isempty(spec.label)
        @test !isempty(spec.unit)
        @test !isempty(spec.note)
        @test spec.min <= spec.default <= spec.max
    end
end

@testset "config/ está onde o código espera" begin
    @test isfile(joinpath(ROOT, "config", "stream.toml"))
    @test isfile(joinpath(ROOT, "config", "equipment", "separator",
                          "stewart_arnold.toml"))
    @test isdir(joinpath(ROOT, "config", "cases"))
end
