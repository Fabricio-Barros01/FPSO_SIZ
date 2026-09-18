"""
O servidor HTTP.

## Genie como biblioteca, não como framework

Só se usa daqui o roteador, o servidor e o servidor de arquivos estáticos. Nada de
`Genie.loadapp()`, de estrutura MVC, de Stipple e — principalmente — **nada de
`Genie.Assets`**.

O motivo é empacotamento, e é concreto: `Genie/src/Assets.jl:282` resolve os arquivos
do próprio Genie com `joinpath(@__DIR__, "..", path)`, e o Stipple resolve os dele com
`Base.pkgdir(Genie)`. O `PackageCompiler.create_app` embarca o *código* dos pacotes no
sysimage, mas **não** copia os diretórios-fonte deles: no computador de quem recebe o
programa esses caminhos apontam para o `~/.julia/packages/...` da máquina que fez o
build, que não existe. A página viria quebrada, sem erro no servidor.

Servindo só `public/` — nosso, copiado para dentro do bundle, com o caminho resolvido
em runtime por [`dir_publico`](@ref) — **nenhum arquivo que a tela pede vem de um
caminho de pacote**: `Genie.Router.serve_static_file` acha tudo no document root e lê do
disco com `read(f, String)`.

Uma ressalva, para que a afirmação acima não seja lida como mais forte do que é: quando
o arquivo **não** está no document root, o mesmo `serve_static_file` ainda consulta
`Genie.Router.bundles_path()` antes de desistir, e essa função é literalmente
`joinpath(@__DIR__, "..", "files", "static")` (`Genie/src/Router.jl:1140`) — o
diretório-fonte do Genie na máquina que fez o build. No executável esse caminho não
existe, então o efeito é 404 em vez de 404: o pior caso é nenhum. Vale saber que o
caminho é consultado, e um teste em `smoke.jl` fixa que pedir um arquivo inexistente
devolve 404 limpo, sem exceção no servidor.

## Um estado só, sob trava

Isto é um aplicativo de mesa que fala HTTP com `127.0.0.1`, não um servidor
multi-inquilino: há **um** [`AppState`](@ref) no processo, protegido por um
`ReentrantLock` porque o HTTP.jl atende requisições em tarefas concorrentes.
Consequência a conhecer: duas abas abertas compartilham o mesmo estado, como duas
janelas do mesmo editor sobre o mesmo arquivo.
"""

"""
Um [`AppState`](@ref) por box do catálogo, criado sob demanda.

Era um `Ref` único quando havia uma aplicação só. Com o menu há várias, e um `Ref`
faria abrir o vaso bifásico descartar o estudo aberto no separador — sem aviso, porque
o servidor não teria como saber que aquilo era trabalho de outra tela. Um dicionário
por box faz "voltar ao menu e entrar noutro" ser o que a pessoa espera: nada se perde.
"""
const ESTADO = Dict{Symbol,AppState}()
const TRAVA = ReentrantLock()

"""
Arquivo de casos aberto na partida, quando dado por `--caso`.

Vazio é o normal: o programa abre **em branco** e quem carrega exemplo ou estudo é a
barra de arquivo da tela. `--caso` continua existindo porque o modo lote depende dele e
porque quem já sabe o que quer não deve precisar de dois cliques.
"""
const ARQUIVO_CASOS = Ref{String}("")

"Porta em que o servidor subiu, para a conferência de origem. `0` = ainda não subiu."
const PORTA = Ref{Int}(0)

"""
    estado_atual(box) -> AppState

O estado daquele box, criado na primeira chamada. Sempre com a [`TRAVA`](@ref) na mão.

**Não dimensiona na criação.** Até o Sprint 5 o programa abria com o caso do artigo já
carregado e já dimensionado; ninguém tinha pedido nem uma coisa nem outra. Agora a tela
abre com um caso nos defaults dos descritores e o cartão em travessão, esperando
"Dimensionar" — salvo quando `--caso` diz explicitamente o que abrir.
"""
function estado_atual(box::FPSOSiz.BoxCatalogo)
    chave = Symbol(box.id)
    haskey(ESTADO, chave) && return ESTADO[chave]

    par = FPSOSiz.box_equipamento(box)
    par === nothing && error("o box '$(box.id)' não resolve num equipamento do registro")
    eq, m = par

    st = AppState(; case_file = ARQUIVO_CASOS[], equipamento = eq, metodo = m)
    if !isempty(ARQUIVO_CASOS[])
        # Só quem pediu um arquivo pela linha de comando é dimensionado na abertura. A
        # queixa de um `--caso` inexistente tem de sobreviver ao `dimensionar!`.
        redimensionar_sem_perder_queixa!(st)
    end
    ESTADO[chave] = st
    return st
end

"Zera os estados — usado pelos testes, que precisam de um começo limpo por caso."
reiniciar_estado!() = empty!(ESTADO)

"""
    dir_publico() -> String

Onde vivem `index.html`, `app.css` e `app.js`. Resolvido em runtime pelo mesmo motivo
que `FPSOSiz.project_root()`: no app compilado o `@__DIR__` seria o da máquina de build.

Ordem: `FPSOSIZ_PUBLIC` → `<raiz>/public` (layout do bundle) → `app/public` (dev).
"""
function dir_publico()
    env = get(ENV, "FPSOSIZ_PUBLIC", "")
    isempty(env) || return normpath(env)
    empacotado = joinpath(FPSOSiz.project_root(), "public")
    isdir(empacotado) && return empacotado
    return normpath(joinpath(@__DIR__, "..", "public"))
end

# ---------------------------------------------------------------------------
# Respostas
# ---------------------------------------------------------------------------

"Resposta JSON. Serializamos com JSON3 direto para ter um parser só no programa."
resposta_json(x; status::Int = 200) = HTTP.Response(
    status, ["Content-Type" => "application/json; charset=utf-8"];
    body = JSON3.write(x))

"Corpo da requisição já como `Dict{String,Any}`; corpo vazio ou ilegível vira dicionário vazio."
function corpo_json()
    bruto = try
        Genie.Requests.rawpayload()
    catch
        ""
    end
    isempty(strip(bruto)) && return Dict{String,Any}()
    return try
        JSON3.read(bruto, Dict{String,Any})
    catch
        Dict{String,Any}()
    end
end

"""
    mesma_origem() -> Bool

Verdadeiro quando a requisição **não** veio de outra origem.

Por que isto existe num programa de mesa: o servidor escuta em `127.0.0.1`, e qualquer
página aberta no mesmo navegador pode postar contra ele. Um `fetch` com
`Content-Type: application/json` seria barrado pelo próprio navegador (o preflight de
CORS não teria resposta), mas um `<form method=post>` para `text/plain` **não** é
preflightado — e [`corpo_json`](@ref) lê o corpo cru, sem olhar o tipo. As rotas que
escrevem em disco com um nome vindo do cliente (`/api/casos/salvar`) e a que encerra o
programa (`/api/parar`) não podem depender disso.

A regra é a canônica: rejeita-se apenas quando o cabeçalho `Origin` **está presente e
diverge**. Ausente é o caso normal de um cliente que não é navegador — `curl`, o
`smoke.jl`, o modo lote — e de navegações de mesma origem que não o enviam; tratá-lo
como hostil quebraria todos eles sem fechar nada.
"""
function mesma_origem()
    origem = try
        Genie.Requests.findheader("Origin", nothing)
    catch
        nothing
    end
    (origem === nothing || isempty(origem)) && return true
    p = PORTA[]
    return origem in ("http://127.0.0.1:$p", "http://localhost:$p",
                      "http://[::1]:$p")
end

"Resposta padrão para requisição de outra origem."
recusa_origem() = resposta_json(
    Dict("erro" => "origem não permitida",
         "status" => "Requisição recusada: veio de outra página. " *
                     "Use a janela do próprio FPSO_Siz.",
         "status_ok" => false); status = 403)

"""
    box_da_rota() -> BoxCatalogo | nothing

O box que a rota `/api/:box/…` nomeia, validado contra o catálogo.

`nothing` quando o id não existe, não está ativo, ou não resolve num par do registro —
os três casos em que servir a aplicação seria servir uma tela que não monta.
"""
function box_da_rota()
    id = try
        string(Genie.Router.params(:box, ""))
    catch
        ""
    end
    isempty(id) && return nothing
    b = FPSOSiz.box_catalogo(id)
    (b === nothing || !b.ativo) && return nothing
    FPSOSiz.box_equipamento(b) === nothing && return nothing
    return b
end

"""
    protegido(f) -> resposta

Roda `f(st)` com a trava tomada e transforma qualquer exceção em JSON de erro. Uma
falha inesperada tem de virar mensagem na barra de status, não uma aba em branco —
é o mesmo contrato do core: inviabilidade é estado, não exceção.
"""
function protegido(f::Function; conferir_origem::Bool = false)
    conferir_origem && !mesma_origem() && return recusa_origem()

    # O box vem da URL, então nunca se confia nele: `box_catalogo` só devolve algo para
    # um id que o catálogo declara, e `box_equipamento` só para um que resolva no
    # registro. Id inventado morre aqui, com 404, sem tocar em `ESTADO`.
    box = box_da_rota()
    box === nothing && return resposta_json(
        Dict("erro" => "aplicação desconhecida",
             "status" => "Essa aplicação não existe. Volte ao menu.",
             "status_ok" => false); status = 404)

    return lock(TRAVA) do
        try
            f(estado_atual(box))
        catch err
            @error "falha ao atender a requisição" exception = (err, catch_backtrace())
            resposta_json(Dict("erro" => sprint(showerror, err),
                               "status" => "Erro interno: " * sprint(showerror, err),
                               "status_ok" => false); status = 500)
        end
    end
end

"Marca em `casca.html` onde o estado inicial é injetado."
const MARCA_INICIAL = "<!--ESTADO-INICIAL-->"

"Lê um arquivo de `public/`, com erro claro se faltar."
function ler_publico(nome::AbstractString)
    caminho = joinpath(dir_publico(), nome)
    isfile(caminho) || error("arquivo da interface não encontrado: $caminho")
    return read(caminho, String)
end

"""
    pagina(; titulo, corpo, scripts, dados) -> String

Monta uma página a partir de `casca.html`: o cabeçalho do documento, a barra de status
e a tag do script vivem lá uma vez, e cada página traz só o seu corpo.

`dados` é injetado em `window.__INICIAL__`. Sem isso a página abriria vazia e só se
preencheria depois de dois `fetch`, o que num aplicativo de mesa é um piscar de tela
sem motivo: o servidor é o mesmo processo e o dado já está na memória.

`</script>` dentro do JSON encerraria o bloco no meio, e o HTML não interpreta escapes
dentro de `<script>` — a barra invertida antes da barra é a única defesa. Nome de caso e
rótulo de box vêm de TOML que o usuário edita, então o risco é real, não teórico.
"""
function pagina(; titulo::AbstractString, corpo::AbstractString,
                  scripts::Vector{String}, dados = nothing)
    html = ler_publico("casca.html")
    # O título vem de `box.titulo`, que é `config/catalogo.toml` — o MESMO arquivo que a
    # nota abaixo classifica como editado pelo usuário. O JSON já era escapado e o título
    # não era: um `</title>` ali encerraria o elemento no meio do cabeçalho.
    html = replace(html, "<!--TITULO-->" => escapa(titulo))
    html = replace(html, "<!--CORPO-->" => ler_publico(corpo))
    html = replace(html, "<!--SCRIPT-->" =>
                   join(["<script src=\"/$s\"></script>" for s in scripts], "\n"))

    injecao = if dados === nothing
        ""
    else
        seguro = replace(JSON3.write(dados), "</" => "<\\/")
        "<script>window.__INICIAL__ = $seguro;</script>"
    end
    return replace(html, MARCA_INICIAL => injecao)
end

"A página de uma aplicação de dimensionamento de vaso."
pagina_inicial(st::AppState, box::FPSOSiz.BoxCatalogo) = pagina(;
    titulo  = "$(box.titulo) — FPSO_Siz",
    corpo   = "index.html",
    scripts = ["app.js"],
    dados   = Dict("box" => box.id, "titulo" => box.titulo,
                   "esquema" => esquema(st), "estado" => estado(st)))

"""
    _e_dinamico(box) -> Bool

Se este box é o do simulador dinâmico (Song 2023). Ele resolve no registro como qualquer
outro (por isso o catálogo o aceita como `ativo`), mas serve por um caminho próprio — sem
`AppState`, sem `dimensionar!` —, porque simula no tempo em vez de dimensionar um vaso.
"""
_e_dinamico(box::FPSOSiz.BoxCatalogo) = box.method == "song_dinamico"

"A página da tela dinâmica. Não constrói `AppState`: os campos vêm do `ParameterSpec` e a
simulação corre por `/api/:box/simular`."
pagina_dinamica(box::FPSOSiz.BoxCatalogo) = pagina(;
    titulo  = "$(box.titulo) — FPSO_Siz",
    corpo   = "dinamico.html",
    scripts = ["dinamico.js"],
    dados   = dados_dinamico(box))

"O menu de abertura. O catálogo é dado — ver `config/catalogo.toml`."
pagina_menu() = pagina(;
    titulo  = "FPSO_Siz — dimensionamento de equipamentos",
    corpo   = "menu.html",
    scripts = ["icones.js", "menu.js"],
    dados   = Dict("boxes" => [Dict("id" => b.id, "titulo" => b.titulo,
                                    "subtitulo" => b.subtitulo, "icone" => b.icone,
                                    "ativo" => b.ativo, "motivo" => b.motivo)
                               for b in FPSOSiz.catalogo()]))

"""
    _pagina_recusa(motivo) -> String

A página que a rota do memorial devolve quando não há documento a emitir.

Existe porque o memorial é servido como PÁGINA: uma falha ali não pode virar JSON (o
navegador baixaria um arquivo) nem uma aba em branco. O motivo aparece escrito, com o
caminho de volta — é o mesmo contrato do resto do programa, onde inviabilidade é
mensagem e não exceção.
"""
_pagina_recusa(motivo::AbstractString) = string(
    "<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">",
    "<title>Memorial de cálculo — não emitido</title></head>",
    "<body style=\"font:14px system-ui;padding:32px;max-width:60ch;line-height:1.5\">",
    "<h1 style=\"font-size:18px\">Memorial de cálculo não emitido</h1><p>",
    escapa(motivo), "</p><p><a href=\"/\">Voltar ao menu</a></p></body></html>")

"""
    meta_da_consulta() -> Dict{String,String}

Os metadados do documento que vierem na consulta da rota — `?cliente=…&projeto=…`.

Cliente, unidade, executor e o sequencial do documento **não** são coisas que o programa
calcule ou guarde; sem isto eles saem como `A DEFINIR`, que é a resposta honesta (ver
`DocMeta`). Esta função é a porta para quem quiser preenchê-los sem que o programa
invente nada.

Defensiva de propósito: se a versão do Genie expuser os parâmetros de consulta sob outra
chave, o `catch` devolve vazio e o documento sai com os defaults — um memorial com
`A DEFINIR` no cliente é utilizável; uma rota que responde 500 por causa do nome de um
campo opcional não é.
"""
function meta_da_consulta()
    aceitas = ("cliente", "projeto", "unidade", "executor", "seq", "rev")
    bruto = try
        p = Genie.Router.params()
        get(p, :GET, get(p, :query, Dict{Symbol,Any}()))
    catch
        Dict{Symbol,Any}()
    end
    out = Dict{String,String}()
    for (k, v) in bruto
        chave = String(k)
        chave in aceitas || continue
        # Limitado em tamanho: o valor vai para dentro do bloco de título, que tem
        # largura fixa, e um texto de 10 kB vindo da URL viraria uma folha ilegível.
        out[chave] = String(first(strip(string(v)), 120))
    end
    return out
end

# ---------------------------------------------------------------------------
# Rotas
# ---------------------------------------------------------------------------

"""
    rotas!() -> nothing

Registra as rotas. Idempotente: o Genie substitui a rota de mesmo caminho, então
chamar de novo (o smoke test chama) não duplica nada.
"""
function rotas!()
    html(corpo) = HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"];
                               body = corpo)

    # A raiz é o MENU, não uma tela de dimensionamento. Até o Sprint 5 o programa abria
    # já com o caso do artigo carregado e dimensionado, sem que ninguém tivesse pedido
    # nem uma coisa nem outra — e sem caminho para o segundo equipamento.
    Genie.Router.route("/") do
        try
            html(pagina_menu())
        catch err
            @error "falha ao montar o menu" exception = (err, catch_backtrace())
            HTTP.Response(500, ["Content-Type" => "text/plain; charset=utf-8"];
                          body = "Falha ao montar o menu: " * sprint(showerror, err))
        end
    end

    Genie.Router.route("/app/:box") do
        box = box_da_rota()
        box === nothing && return HTTP.Response(
            404, ["Content-Type" => "text/html; charset=utf-8"];
            body = "<p style=\"padding:24px;font:14px system-ui\">Essa aplicação não " *
                   "existe. <a href=\"/\">Voltar ao menu</a></p>")
        # O box dinâmico desvia do fluxo de dimensionamento: página própria, sem AppState.
        _e_dinamico(box) && return html(pagina_dinamica(box))
        lock(TRAVA) do
            try
                html(pagina_inicial(estado_atual(box), box))
            catch err
                @error "falha ao montar a aplicação" exception = (err, catch_backtrace())
                HTTP.Response(500, ["Content-Type" => "text/plain; charset=utf-8"];
                              body = "Falha ao montar a tela: " * sprint(showerror, err))
            end
        end
    end

    # O memorial de cálculo DOCUMENTAL — as folhas A4 imprimíveis.
    #
    # É `/app/...`, e não `/api/...`, porque devolve uma PÁGINA, não JSON: o usuário abre
    # noutra aba e manda imprimir. A rota `/api/:box/memorial`, logo abaixo, continua
    # servindo o rastro de cálculo que o painel da tela mostra — são dois artefatos
    # diferentes sobre o mesmo cálculo, e nenhum dos dois recalcula nada.
    #
    # Não usa `protegido`: aquele caminho responde em JSON, e uma falha aqui tem de virar
    # uma página legível em vez de um objeto que o navegador baixaria como arquivo.
    Genie.Router.route("/app/:box/memorial") do
        box = box_da_rota()
        box === nothing && return HTTP.Response(
            404, ["Content-Type" => "text/html; charset=utf-8"];
            body = _pagina_recusa("Essa aplicação não existe."))
        # O box dinâmico monitora no tempo; não dimensiona equipamento nenhum, e por isso
        # não tem memorial de dimensionamento a emitir. Ver `_e_dinamico`.
        _e_dinamico(box) && return HTTP.Response(
            404, ["Content-Type" => "text/html; charset=utf-8"];
            body = _pagina_recusa("O simulador dinâmico não dimensiona um equipamento, " *
                                  "então não emite memorial de dimensionamento."))
        lock(TRAVA) do
            try
                html(memorial_documento(estado_atual(box);
                                        meta_extra = meta_da_consulta()))
            catch err
                @error "falha ao emitir o memorial" exception = (err, catch_backtrace())
                HTTP.Response(500, ["Content-Type" => "text/html; charset=utf-8"];
                              body = _pagina_recusa(sprint(showerror, err)))
            end
        end
    end

    Genie.Router.route("/api/:box/esquema") do
        protegido(st -> resposta_json(esquema(st)))
    end

    Genie.Router.route("/api/:box/estado") do
        protegido(st -> resposta_json(estado(st)))
    end

    # GET de verdade: só lê. O rastro fica fora de `/api/estado` porque é grande e o
    # painel é consulta — a tela pede quando o usuário abre o memorial.
    Genie.Router.route("/api/:box/memorial") do
        protegido(st -> resposta_json(memorial(st)))
    end

    Genie.Router.route("/api/:box/dimensionar"; method = Genie.Router.POST) do
        protegido() do st
            erros = aplicar!(st, corpo_json())
            dimensionar!(st)
            resp = estado(st)
            # A validação não impede o dimensionamento: os campos recusados mantêm o
            # valor anterior. Mas o usuário precisa saber quais foram.
            isempty(erros) || (resp["avisos"] = erros)
            resposta_json(resp)
        end
    end

    # POST, não GET, porque a rota **escreve**: ela move `st.d_sel`, que é o diâmetro
    # que o botão Exportar desenha. Um GET é idempotente por contrato — o navegador pode
    # reemiti-lo por bfcache ou prefetch — e um reenvio silencioso mudaria o arquivo
    # gravado. O verbo agora diz a verdade sobre o efeito.
    Genie.Router.route("/api/:box/desenho"; method = Genie.Router.POST) do
        protegido() do st
            d = Formato.parse_num(string(get(corpo_json(), "d", "")))
            d === nothing || (st.d_sel = d)
            resposta_json(Dict{String,Any}("d_sel" => st.d_sel,
                                           "desenho" => desenho(st),
                                           "cartao" => cartao(st),
                                           "tabela" => tabela(st)))
        end
    end

    # --- a tela dinâmica (Song 2023): simular no tempo ---------------------
    #
    # NÃO usa `protegido`: aquele caminho constrói um `AppState` e dimensiona, e o box
    # dinâmico não faz nem uma coisa nem outra. Valida o box à mão, roda a simulação (pura
    # nos valores do formulário) e devolve os painéis de série temporal já em SVG.
    # Inviabilidade (CFL) volta como `ok = false`, nunca como exceção.
    Genie.Router.route("/api/:box/simular"; method = Genie.Router.POST) do
        box = box_da_rota()
        (box === nothing || !_e_dinamico(box)) && return resposta_json(
            Dict("erro" => "aplicação desconhecida",
                 "status" => "Essa aplicação não existe. Volte ao menu.",
                 "status_ok" => false); status = 404)
        try
            corpo = corpo_json()
            valores = valores_do_corpo(corpo)
            malha_fechada = get(corpo, "malha_fechada", true) == true
            r = FPSOSiz.simular_dinamico(valores; malha_fechada)
            resposta_json(resultado_dinamico(r, valores; malha_fechada))
        catch err
            @error "falha ao simular" exception = (err, catch_backtrace())
            resposta_json(Dict("ok" => false, "graficos" => String[],
                "resumo" => Dict{String,Any}(),
                "status" => "Erro na simulação: " * sprint(showerror, err),
                "status_ok" => false); status = 500)
        end
    end

    # --- conjuntos de casos: abrir, salvar, listar -------------------------
    #
    # GET só lê o diretório; os dois POST escrevem (um troca o estado inteiro, o outro
    # grava um arquivo com nome vindo do cliente) e por isso conferem a origem.

    Genie.Router.route("/api/:box/casos/arquivos") do
        protegido(st -> resposta_json(arquivos(st)))
    end

    Genie.Router.route("/api/:box/casos/abrir"; method = Genie.Router.POST) do
        protegido(; conferir_origem = true) do st
            nome = string(get(corpo_json(), "arquivo", ""))
            abrir_casos!(st, nome)
            # Sempre 200 com o estado completo: arquivo ilegível é diagnóstico na barra
            # de status, não erro de transporte — o mesmo contrato do resto da tela.
            resp = estado(st)
            resp["lista"] = arquivos(st)
            resposta_json(resp)
        end
    end

    Genie.Router.route("/api/:box/casos/salvar"; method = Genie.Router.POST) do
        protegido(; conferir_origem = true) do st
            corpo = corpo_json()
            # O que se grava é o que está NA TELA, não o que o servidor tinha da última
            # vez que se dimensionou: o usuário edita uma vazão e clica em Salvar sem
            # passar por Dimensionar, e esperaria — com razão — o valor novo no arquivo.
            avisos = aplicar!(st, corpo)
            r = salvar_casos!(st, string(get(corpo, "arquivo", ""));
                              rotulo = string(get(corpo, "rotulo", "")))
            resp = Dict{String,Any}("ok" => r.ok, "caminho" => r.caminho,
                                    "arquivo" => st.arquivo,
                                    "status" => st.status, "status_ok" => st.status_ok,
                                    "lista" => arquivos(st))
            isempty(avisos) || (resp["avisos"] = avisos)
            resposta_json(resp)
        end
    end

    Genie.Router.route("/api/:box/exportar"; method = Genie.Router.POST) do
        protegido(; conferir_origem = true) do st
            r = exportar!(st)
            resposta_json(Dict{String,Any}("ok" => r.ok, "dir" => r.dir,
                                           "arquivos" => basename.(r.arquivos),
                                           "status" => st.status,
                                           "status_ok" => st.status_ok))
        end
    end

    Genie.Router.route("/api/parar"; method = Genie.Router.POST) do
        mesma_origem() || return recusa_origem()
        # Responde primeiro, desce depois: sem o atraso o navegador recebe uma conexão
        # cortada e mostra erro de rede em vez da mensagem de despedida.
        @async begin
            sleep(0.4)
            try
                Genie.down()
            catch
            end
        end
        resposta_json(Dict("ok" => true))
    end

    return nothing
end

# ---------------------------------------------------------------------------
# Subida
# ---------------------------------------------------------------------------

"""
    porta_livre(preferida) -> Int

Devolve `preferida` se estiver livre; senão pede uma efêmera ao sistema. Duas cópias do
programa abertas ao mesmo tempo não podem brigar pela porta — a segunda escolhe outra
e abre o navegador nela.
"""
function porta_livre(preferida::Int = 8000)
    for p in (preferida, 0)
        try
            s = Sockets.listen(Sockets.localhost, p)
            porta = Int(Sockets.getsockname(s)[2])
            close(s)
            return porta
        catch
            continue
        end
    end
    return preferida
end

"""
    abrir_navegador(url) -> Bool

Abre o navegador padrão do sistema. Falha não é erro: numa sessão sem ambiente gráfico
(SSH, container) o certo é seguir servindo e deixar a URL impressa no terminal.
"""
function abrir_navegador(url::AbstractString)
    cmd = Sys.iswindows() ? `cmd /c start "" $url` :
          Sys.isapple()   ? `open $url` : `xdg-open $url`
    try
        run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
        return true
    catch
        return false
    end
end

"""
    servir(; porta, abrir, bloquear) -> Int

Configura o Genie e sobe o servidor. Com `bloquear = true` (o padrão) a função não
retorna enquanto o servidor estiver no ar — sem isso o processo terminaria e o usuário
veria o navegador abrir numa página morta.
"""
function servir(; porta::Int = 8000, abrir::Bool = true, bloquear::Bool = true)
    publico = dir_publico()
    isdir(publico) || error("não encontrei os arquivos da interface em: $publico")

    # `prod` desliga o recarregamento automático de código do Genie; `manual` impede o
    # Revise (dependência dura do Genie 6) de sair varrendo arquivos que, num
    # executável compilado, não existem.
    get!(ENV, "GENIE_ENV", "prod")
    get!(ENV, "JULIA_REVISE", "manual")

    Genie.config.server_document_root = publico
    Genie.config.websockets_server = false
    Genie.config.run_as_server = bloquear
    Genie.config.log_level = Logging.Warn

    rotas!()

    p = porta_livre(porta)
    PORTA[] = p                       # `mesma_origem` compara contra ela
    url = "http://127.0.0.1:$p"
    println()
    # `LEMA` e não uma frase própria: o banner do terminal, o `--ajuda` e o subtítulo do
    # menu diziam três coisas diferentes sobre o que o programa faz, e duas delas
    # prometiam só separadores. Ver a nota de `LEMA` em FPSOSizApp.jl.
    println(LEMA)
    println("Interface no ar:  ", url)
    println("Saída (CSV, memorial, SVG): ", FPSOSiz.dir_saida())
    println("Conjuntos de casos:          ", FPSOSiz.dir_casos())
    println("Para encerrar: feche esta janela ou pressione Ctrl+C.")
    println()

    abrir && !abrir_navegador(url) &&
        println("Não consegui abrir o navegador. Abra o endereço acima à mão.")

    Genie.up(p, "127.0.0.1"; async = !bloquear, open_browser = false, ws_port = nothing)
    return p
end
