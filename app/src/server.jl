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

const ESTADO = Ref{Union{AppState,Nothing}}(nothing)
const TRAVA = ReentrantLock()
const ARQUIVO_CASOS = Ref{String}("exemplo_alves_komesu.toml")

"Porta em que o servidor subiu, para a conferência de origem. `0` = ainda não subiu."
const PORTA = Ref{Int}(0)

"""
    estado_atual() -> AppState

O estado do processo, criado e dimensionado na primeira chamada. Sempre chamado com a
[`TRAVA`](@ref) na mão.
"""
function estado_atual()
    st = ESTADO[]
    st === nothing || return st
    st = AppState(; case_file = ARQUIVO_CASOS[])
    # `--caso arquivo_que_nao_existe.toml` tem de chegar ao usuário. Sem isto o
    # `dimensionar!` escreveria "4 caso(s) → 10 canto(s)…" por cima da queixa, e a tela
    # abriria com um caso em branco sem dizer por quê.
    redimensionar_sem_perder_queixa!(st)
    ESTADO[] = st
    return st
end

"Zera o estado — usado pelos testes, que precisam de um começo limpo por caso."
reiniciar_estado!() = (ESTADO[] = nothing)

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
    protegido(f) -> resposta

Roda `f(st)` com a trava tomada e transforma qualquer exceção em JSON de erro. Uma
falha inesperada tem de virar mensagem na barra de status, não uma aba em branco —
é o mesmo contrato do core: inviabilidade é estado, não exceção.
"""
function protegido(f::Function; conferir_origem::Bool = false)
    conferir_origem && !mesma_origem() && return recusa_origem()
    return lock(TRAVA) do
        try
            f(estado_atual())
        catch err
            @error "falha ao atender a requisição" exception = (err, catch_backtrace())
            resposta_json(Dict("erro" => sprint(showerror, err),
                               "status" => "Erro interno: " * sprint(showerror, err),
                               "status_ok" => false); status = 500)
        end
    end
end

"Marca em `index.html` onde o estado inicial é injetado."
const MARCA_INICIAL = "<!--ESTADO-INICIAL-->"

"""
    pagina_inicial(st) -> String

`index.html` com o esquema e o estado já embutidos num `<script>`.

Sem isto a página abriria vazia e só se preencheria depois de dois `fetch`, o que num
aplicativo de mesa é um piscar de tela sem motivo: o servidor é o mesmo processo, o
dado já está na memória. Injetando aqui, a primeira pintura já vem completa.

`</script>` dentro do JSON encerraria o bloco no meio; o HTML não interpreta escapes
dentro de `<script>`, então a barra invertida antes da barra é a única defesa. Nomes de
caso vêm de TOML do usuário, então o risco é real, não teórico.
"""
function pagina_inicial(st::AppState)
    html = read(joinpath(dir_publico(), "index.html"), String)
    dados = JSON3.write(Dict("esquema" => esquema(st), "estado" => estado(st)))
    seguro = replace(dados, "</" => "<\\/")
    return replace(html, MARCA_INICIAL =>
                   "<script>window.__INICIAL__ = $seguro;</script>")
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
    Genie.Router.route("/") do
        protegido(st -> HTTP.Response(
            200, ["Content-Type" => "text/html; charset=utf-8"];
            body = pagina_inicial(st)))
    end

    Genie.Router.route("/api/esquema") do
        protegido(st -> resposta_json(esquema(st)))
    end

    Genie.Router.route("/api/estado") do
        protegido(st -> resposta_json(estado(st)))
    end

    # GET de verdade: só lê. O rastro fica fora de `/api/estado` porque é grande e o
    # painel é consulta — a tela pede quando o usuário abre o memorial.
    Genie.Router.route("/api/memorial") do
        protegido(st -> resposta_json(memorial(st)))
    end

    Genie.Router.route("/api/dimensionar"; method = Genie.Router.POST) do
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
    Genie.Router.route("/api/desenho"; method = Genie.Router.POST) do
        protegido() do st
            d = Formato.parse_num(string(get(corpo_json(), "d", "")))
            d === nothing || (st.d_sel = d)
            resposta_json(Dict{String,Any}("d_sel" => st.d_sel,
                                           "desenho" => desenho(st),
                                           "cartao" => cartao(st),
                                           "tabela" => tabela(st)))
        end
    end

    # --- conjuntos de casos: abrir, salvar, listar -------------------------
    #
    # GET só lê o diretório; os dois POST escrevem (um troca o estado inteiro, o outro
    # grava um arquivo com nome vindo do cliente) e por isso conferem a origem.

    Genie.Router.route("/api/casos/arquivos") do
        protegido(st -> resposta_json(arquivos(st)))
    end

    Genie.Router.route("/api/casos/abrir"; method = Genie.Router.POST) do
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

    Genie.Router.route("/api/casos/salvar"; method = Genie.Router.POST) do
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

    Genie.Router.route("/api/exportar"; method = Genie.Router.POST) do
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
    println("FPSO_Siz — dimensionamento de separadores")
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
