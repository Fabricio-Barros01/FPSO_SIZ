"""
Carga dos TOML de `config/`.

Constantes e faixas ficam **fora do código**: um TOML por método, com proveniência
por linha. Isso mantém o código legível e deixa o ajuste de premissas ao alcance de
quem não vai editar Julia. Um teste garante que as constantes numéricas não estejam
duplicadas literalmente dentro do `.jl`.
"""

# ---------------------------------------------------------------------------
# Onde estão os dados — resolvido em runtime, nunca na precompilação
# ---------------------------------------------------------------------------
#
# `const RAIZ = joinpath(@__DIR__, "..")` seria mais curto e está errado para o caso
# que importa: `@__DIR__` congela quando o módulo é precompilado. Num executável gerado
# pelo PackageCompiler isso é o `~/.julia/...` da máquina que fez o build — um caminho
# que não existe no computador de quem recebe o programa. O sintoma seria "arquivo de
# configuração não encontrado" apontando para o diretório de outra pessoa.

"Memoiza [`project_root`](@ref); vazio = ainda não resolvido."
const _RAIZ = Ref{String}("")

"Memoiza [`dir_saida`](@ref)."
const _SAIDA = Ref{String}("")

"Um candidato só serve se de fato contiver `config/`."
_tem_config(dir) = !isempty(dir) && isdir(joinpath(dir, "config"))

function _descobrir_raiz()
    tentados = String[]

    # 1. Escape explícito: CI, testes e quem empacota de outro jeito.
    env = get(ENV, "FPSOSIZ_RAIZ", "")
    if !isempty(env)
        raiz = normpath(env)
        _tem_config(raiz) && return raiz
        push!(tentados, "FPSOSIZ_RAIZ=$raiz")
    end

    # 2. Aplicativo compilado: <bundle>/bin/fpso-siz procura <bundle>/share/fpso_siz.
    #    `Sys.BINDIR` é resolvido em runtime — é o que torna o bundle relocável.
    bundle = normpath(joinpath(Sys.BINDIR, "..", "share", "fpso_siz"))
    _tem_config(bundle) && return bundle
    push!(tentados, bundle)

    # 3. Desenvolvimento: dois níveis acima deste arquivo. Só se chega aqui quando 1 e 2
    #    falham, então o `@__DIR__` congelado não faz mal — no app compilado ele nunca
    #    é a resposta.
    devel = normpath(joinpath(@__DIR__, ".."))
    _tem_config(devel) && return devel
    push!(tentados, devel)

    error("""
          não encontrei o diretório `config/` do FPSO_Siz. Caminhos tentados:
          $(join("  " .* tentados, "\n"))
          Defina FPSOSIZ_RAIZ apontando para a pasta que contém `config/`.
          """)
end

"""
    project_root() -> String

Raiz dos dados do projeto: o diretório que contém `config/`.

Resolvida na primeira chamada e memoizada. Ordem: `FPSOSIZ_RAIZ` →
`<bundle>/share/fpso_siz` → dois níveis acima de `src/`. Ver a nota acima sobre por que
isto é função e não `const`.
"""
function project_root()
    isempty(_RAIZ[]) || return _RAIZ[]
    return _RAIZ[] = _descobrir_raiz()
end

"Verdadeiro se conseguirmos criar e apagar um arquivo em `dir`."
function _gravavel(dir)
    try
        isdir(dir) || mkpath(dir)
        teste = joinpath(dir, ".fpso_siz_escrita_$(getpid())")
        touch(teste)
        rm(teste; force = true)
        return true
    catch
        return false
    end
end

"Pasta pessoal onde o programa instalado guarda o que produz."
function _saida_do_usuario()
    lar = homedir()
    base = Sys.iswindows() && isdir(joinpath(lar, "Documents")) ?
           joinpath(lar, "Documents", "FPSO_Siz") : joinpath(lar, "FPSO_Siz")
    return joinpath(base, "saida")
end

"""
    dir_saida() -> String

Diretório onde CSV, memorial e figuras são gravados, criado sob demanda.

Ordem: `FPSOSIZ_SAIDA` → `saida/` na raiz do projeto, **se for gravável** → pasta
pessoal do usuário. O desvio existe porque um programa instalado em `/opt` ou em
`C:\\Program Files` não pode escrever ao lado de si mesmo; em desenvolvimento a raiz é
gravável e nada muda.
"""
function dir_saida()
    isempty(_SAIDA[]) || return _SAIDA[]

    env = get(ENV, "FPSOSIZ_SAIDA", "")
    escolhido = if !isempty(env)
        normpath(env)
    else
        local_ = joinpath(project_root(), "saida")
        _gravavel(local_) ? local_ : _saida_do_usuario()
    end

    isdir(escolhido) || mkpath(escolhido)
    return _SAIDA[] = escolhido
end

"Caminho para um arquivo dentro de `config/`."
config_path(parts...) = joinpath(project_root(), "config", parts...)

"Lê um TOML de `config/`, com erro claro se não existir."
function load_config(parts...)
    path = config_path(parts...)
    isfile(path) || error("arquivo de configuração não encontrado: $path")
    return TOML.parsefile(path)
end

"""
    parameter_specs(cfg) -> Vector{ParameterSpec}

Converte os blocos `[[parameter]]` de um TOML em descritores. Campos obrigatórios:
`key`, `label`, `unit`, `default`, `min`, `max`. Opcionais: `advanced` (false),
`note` ("").
"""
function parameter_specs(cfg::AbstractDict)
    raw = get(cfg, "parameter", Any[])
    specs = ParameterSpec[]
    for p in raw
        for f in ("key", "label", "unit", "default", "min", "max")
            haskey(p, f) || error("bloco [[parameter]] sem campo obrigatório '$f': $p")
        end
        push!(specs, ParameterSpec(
            Symbol(p["key"]),
            String(p["label"]),
            String(p["unit"]),
            float(p["default"]),
            float(p["min"]),
            float(p["max"]),
            get(p, "advanced", false),
            String(get(p, "note", "")),
        ))
    end
    return specs
end

"Lê o bloco `[constants]` como `Symbol => Float64`."
function constants(cfg::AbstractDict)
    raw = get(cfg, "constants", Dict{String,Any}())
    return Dict{Symbol,Any}(Symbol(k) => v for (k, v) in raw)
end

"Rótulo declarado no TOML, com fallback."
config_label(cfg::AbstractDict, fallback::AbstractString) = String(get(cfg, "label", fallback))

"""
    case_set_from_config(cfg) -> CaseSet

Converte os blocos `[[case]]` de um TOML em [`CaseSet`](@ref). Cada bloco tem `name`,
`enabled` (opcional, default `true`) e as entradas: um número para valor fixo, ou um
array de dois elementos `[min, max]` para faixa.
"""
function case_set_from_config(cfg::AbstractDict)
    blocos = get(cfg, "case", Any[])
    cases = Case[]
    for b in blocos
        haskey(b, "name") || error("bloco [[case]] sem 'name': $b")
        vals = Dict{Symbol,Any}()
        for (k, v) in b
            k in ("name", "enabled") && continue
            vals[Symbol(k)] = v
        end
        push!(cases, Case(b["name"], vals; enabled = get(b, "enabled", true)))
    end
    return CaseSet(cases)
end

# ---------------------------------------------------------------------------
# Conjuntos de casos: onde ficam, como se listam, como voltam para o disco
# ---------------------------------------------------------------------------
#
# Até aqui `config/cases/` era só de leitura: o programa carregava um TOML na abertura
# e o que o usuário editasse na tela morria com o processo. Para gravar de volta é
# preciso responder onde — e a resposta não pode ser `config/cases/`, porque num
# programa instalado em `/opt` ou em `C:\Program Files` essa pasta não é gravável. É o
# mesmo problema que `dir_saida()` já resolve, e a solução é a mesma: um diretório
# **do usuário**, com os arquivos de fábrica continuando visíveis ao lado.

"Memoiza [`dir_casos`](@ref)."
const _CASOS = Ref{String}("")

"Pasta pessoal onde o programa instalado guarda os conjuntos de casos do usuário."
function _casos_do_usuario()
    lar = homedir()
    base = Sys.iswindows() && isdir(joinpath(lar, "Documents")) ?
           joinpath(lar, "Documents", "FPSO_Siz") : joinpath(lar, "FPSO_Siz")
    return joinpath(base, "casos")
end

"""
    dir_casos() -> String

Diretório **gravável** onde [`save_case_set`](@ref) escreve, criado sob demanda.

Ordem: `FPSOSIZ_CASOS` → `config/cases/` do projeto, **se for gravável** → pasta
pessoal do usuário. Em desenvolvimento a raiz é gravável e tudo cai em `config/cases/`,
como antes; num programa instalado o desvio evita o erro de permissão no clique de
"Salvar".
"""
function dir_casos()
    isempty(_CASOS[]) || return _CASOS[]

    env = get(ENV, "FPSOSIZ_CASOS", "")
    escolhido = if !isempty(env)
        normpath(env)
    else
        fabrica = config_path("cases")
        _gravavel(fabrica) ? fabrica : _casos_do_usuario()
    end

    isdir(escolhido) || mkpath(escolhido)
    return _CASOS[] = escolhido
end

"""
    dirs_casos() -> Vector{String}

Onde procurar um conjunto de casos, em ordem de precedência: primeiro o diretório do
usuário, depois os arquivos de fábrica. Um arquivo salvo pelo usuário com o nome de um
exemplo **sombreia** o exemplo — é o comportamento que a pessoa espera de "Salvar".
"""
dirs_casos() = unique([dir_casos(), config_path("cases")])

"""
    nome_casos_valido(nome) -> Bool

Um nome de arquivo de casos é um **nome**, nunca um caminho.

Existe porque o nome chega do navegador, e `POST /api/casos/salvar` grava em disco com
ele: sem esta guarda, `"../../.bashrc.toml"` sairia de `dir_casos()` e escreveria onde
não devia. Não é hipótese remota — o servidor escuta em `127.0.0.1`, e qualquer página
aberta no mesmo navegador pode disparar um POST contra ele.
"""
function nome_casos_valido(nome::AbstractString)
    n = String(nome)
    isempty(n) && return false
    endswith(n, ".toml") || return false
    n == ".toml" && return false
    startswith(n, ".") && return false
    occursin("..", n) && return false
    return !any(c -> c in ('/', '\\', ':', '*', '?', '"', '<', '>', '|') || c < ' ', n)
end

"""
    case_set_path(nome) -> String

Caminho do conjunto de casos `nome`, procurado em [`dirs_casos`](@ref). Devolve `""`
quando não existe em lugar nenhum. Lança se o nome não for um nome de arquivo simples.
"""
function case_set_path(nome::AbstractString)
    nome_casos_valido(nome) ||
        throw(ArgumentError("nome de arquivo de casos inválido: $nome"))
    for d in dirs_casos()
        p = joinpath(d, nome)
        isfile(p) && return p
    end
    return ""
end

"""
    list_case_sets() -> Vector{NamedTuple}

Os conjuntos de casos disponíveis, com `nome`, `rotulo`, quantidade de `casos`,
`caminho` e se o arquivo é `gravavel`. Arquivo ilegível entra na lista com o rótulo do
erro em vez de sumir: some-lo esconderia do usuário o arquivo que ele acabou de editar
à mão e quebrou.
"""
function list_case_sets()
    vistos = Set{String}()
    out = @NamedTuple{nome::String, rotulo::String, casos::Int,
                      caminho::String, gravavel::Bool}[]
    for d in dirs_casos()
        isdir(d) || continue
        for f in sort(readdir(d))
            endswith(f, ".toml") || continue
            f in vistos && continue
            push!(vistos, f)
            caminho = joinpath(d, f)
            rotulo, n = try
                cfg = TOML.parsefile(caminho)
                config_label(cfg, f), length(get(cfg, "case", Any[]))
            catch err
                "(ilegível: " * sprint(showerror, err) * ")", 0
            end
            push!(out, (; nome = f, rotulo, casos = n, caminho,
                        gravavel = d == dir_casos()))
        end
    end
    return out
end

"Lê um conjunto de casos pelo nome, procurando em [`dirs_casos`](@ref)."
function load_case_set(name::AbstractString)
    p = case_set_path(name)
    isempty(p) && error("conjunto de casos não encontrado: $name (procurei em " *
                        join(dirs_casos(), ", ") * ")")
    return case_set_from_config(TOML.parsefile(p))
end

"""
    save_case_set(cs, caminho; label = "") -> String

Grava `cs` como TOML, **inversa exata** de [`case_set_from_config`](@ref): número para
escalar, array `[mín, máx]` para [`Interval`](@ref), `enabled = false` só quando o caso
está desativado (a leitura assume `true`). Devolve o caminho escrito.

O arquivo é escrito à mão, e não por `TOML.print`, por um motivo de uso: este é um
arquivo que a pessoa vai abrir e editar no bloco de notas. `TOML.print` ordena tudo
alfabeticamente, o que joga `name` para o meio do bloco entre `mu_water` e `pressure`;
escrevendo aqui, o nome do caso encabeça o bloco e os cabeçalhos explicam a sintaxe. Em
troca, a saída de texto (nome do caso) precisa de escape próprio — [`_toml_texto`](@ref).

Os números saem por `repr`, que é a representação **curta e de ida e volta exata** de um
`Float64`: `215.8` volta como `215.8`, sem o erro de arredondamento que um `%.6f`
introduziria a cada gravação sucessiva.
"""
function save_case_set(cs::CaseSet, caminho::AbstractString;
                       label::AbstractString = "")
    for c in cs.cases, (k, v) in c.values
        finito = v isa Interval ? isfinite(v.lo) && isfinite(v.hi) : isfinite(v)
        finito || error("valor não finito em '$(c.name)', chave '$k': $v")
    end

    mkpath(dirname(abspath(caminho)))
    open(caminho, "w") do io
        isempty(label) || println(io, "label = ", _toml_texto(label), "\n")
        println(io, """
                # Conjunto de casos do FPSO_Siz.
                #
                # Valor fixo: um número. Faixa: um array [mín, máx], que o motor expande
                # em casos de canto. `enabled = false` guarda o caso sem incluí-lo no
                # envelope. Chave omitida assume o default do descritor (config/).
                """)
        for c in cs.cases
            println(io, "[[case]]")
            println(io, "name = ", _toml_texto(c.name))
            c.enabled || println(io, "enabled = false")
            for k in sort!(collect(keys(c.values)); by = String)
                v = c.values[k]
                println(io, String(k), " = ", v isa Interval ?
                        string("[", repr(v.lo), ", ", repr(v.hi), "]") : repr(v))
            end
            println(io)
        end
    end
    return caminho
end

"Grava em [`dir_casos`](@ref) pelo nome de arquivo, validando-o antes."
function save_case_set_named(cs::CaseSet, nome::AbstractString;
                             label::AbstractString = "")
    nome_casos_valido(nome) ||
        throw(ArgumentError("nome de arquivo de casos inválido: $nome"))
    return save_case_set(cs, joinpath(dir_casos(), nome); label)
end

"""
    _toml_texto(s) -> String

`s` como string básica de TOML, com aspas e escapes. Nome de caso vem do usuário: pode
conter aspas, barra invertida ou quebra de linha, e qualquer um dos três produziria um
arquivo que não volta a ser lido.
"""
function _toml_texto(s::AbstractString)
    buf = IOBuffer()
    print(buf, '"')
    for c in s
        if c == '"'
            print(buf, "\\\"")
        elseif c == '\\'
            print(buf, "\\\\")
        elseif c == '\n'
            print(buf, "\\n")
        elseif c == '\r'
            print(buf, "\\r")
        elseif c == '\t'
            print(buf, "\\t")
        elseif c < ' ' || c == '\x7f'
            print(buf, "\\u", string(UInt16(c); base = 16, pad = 4))
        else
            print(buf, c)
        end
    end
    print(buf, '"')
    return String(take!(buf))
end
