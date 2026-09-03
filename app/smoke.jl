"""
Teste de fumaça da interface.

    julia --project=app app/smoke.jl

Cobre o que o teste do core não alcança: `test/architecture.jl` garante que o core não
importa GUI; este garante que a interface não quebra ao montar, e que o servidor
responde de verdade. Roda headless — é onde o `create_app` é construído.

## Por que ele sobe um servidor em vez de só chamar as funções

Lição herdada do projeto anterior, e cara: o core exporta `label` e `parameters`, o
Genie exporta `label` também. Com `using` nos dois o nome fica ambíguo e o Julia lança
`UndefVarError` **no instante em que a linha roda** — dentro do handler. Um teste que
só faz `HTTP.get("/")` e confere status 200 passa com o formulário chegando vazio ao
usuário. Por isso aqui se exercita o ciclo inteiro: requisição, handler, resposta, e o
conteúdo da resposta.
"""

using Test
using HTTP
using JSON3

using FPSOSizApp
const A = FPSOSizApp

import FPSOSiz

# As figuras e o CSV vão para um diretório temporário: um teste não pode sujar a pasta
# de saída do usuário, e precisa de um lugar previsível para conferir o que gravou.
const TEMP_SAIDA = mktempdir(; prefix = "fpso_siz_smoke_")
ENV["FPSOSIZ_SAIDA"] = TEMP_SAIDA
FPSOSiz._SAIDA[] = ""

# O mesmo para os conjuntos de casos, e por um motivo a mais: sem o desvio, "Salvar"
# gravaria dentro de `config/cases/` do repositório — o teste passaria e deixaria um
# arquivo versionado para trás. Com `FPSOSIZ_CASOS` apontando para um temporário, os
# exemplos de fábrica continuam visíveis (`dirs_casos()` procura nos dois) e o que o
# teste escreve morre com ele.
const TEMP_CASOS = mktempdir(; prefix = "fpso_siz_casos_")
ENV["FPSOSIZ_CASOS"] = TEMP_CASOS
FPSOSiz._CASOS[] = ""

"""
    valor_cartao(st, rotulo) -> String

Um campo do cartão pelo RÓTULO, e não por uma chave fixa.

O cartão deixou de ser oito chaves com nome de vaso (`"d"`, `"sr"`, `"teto"`) e passou a
ser a lista que `result_fields` declara. Procurar pelo rótulo é o que o usuário faz na
tela, e é o que continua funcionando quando o método muda os campos.
"""
valor_cartao(st, rotulo) =
    something(findfirst(c -> occursin(rotulo, c["rotulo"]), A.cartao(st)),
              0) == 0 ? "" :
    A.cartao(st)[findfirst(c -> occursin(rotulo, c["rotulo"]), A.cartao(st))]["valor"]

"O SVG de uma figura pelo id — `\"vaso\"`, `\"corte\"`, `\"envelope\"`, `\"banda\"`."
function svg_figura(st, id)
    f = findfirst(f -> f["id"] == id, A.desenho(st)["figuras"])
    return f === nothing ? "" : A.desenho(st)["figuras"][f]["svg"]
end

"O mesmo, sobre o JSON que a rota devolve."
function svg_figura_json(d, id)
    for f in d.figuras
        f.id == id && return f.svg
    end
    return ""
end

"Um campo do cartão sobre o JSON que a rota devolve."
function valor_cartao_json(d, rotulo)
    for c in d.cartao
        occursin(rotulo, c.rotulo) && return c.valor
    end
    return ""
end

@testset "fumaça da interface" begin

    @testset "estado inicial" begin
        st = A.AppState()
        @test !isempty(st.casos)
        @test !isempty(st.campos)
        @test length(st.ajustes) == length(FPSOSiz.global_keys(st.metodo))
        # todo campo editável tem valor nos dois extremos
        for c in st.casos, s in st.campos
            @test haskey(c.lo, s.key)
            @test haskey(c.hi, s.key)
        end
        # as chaves globais NÃO são editáveis por caso
        @test all(k -> !(k in [s.key for s in st.campos]),
                  FPSOSiz.global_keys(st.metodo))
    end

    @testset "dimensiona e desenha" begin
        st = A.AppState()
        A.dimensionar!(st)
        @test st.resultado !== nothing
        @test st.resultado.feasible
        @test st.status_ok
        @test st.d_sel == st.resultado.x

        g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
        for svg in (A.svg_elevacao(g), A.svg_corte(g),
                    A.svg_grafico_envelope(st.resultado, st.d_sel),
                    A.svg_grafico_banda(st.resultado, st.d_sel, :sr, (3.0, 5.0), 4.0))
            @test startswith(svg, "<svg")
            @test endswith(svg, "</svg>")
            # Um SVG malformado é recusado inteiro pelo navegador, em silêncio: a
            # figura simplesmente não aparece. Contar as tags fecha esse buraco.
            @test count("<", svg) == count(">", svg)
        end
    end

    @testset "geometria do desenho acompanha o resultado" begin
        st = A.AppState(); A.dimensionar!(st)
        r = st.resultado
        g = A.geometry_from(r, st.d_sel, A.beta_atual(st))
        @test g.ok
        @test g.d_m ≈ r.x / 1000
        @test g.lss_m ≈ FPSOSiz.der(r, :lss)
        @test g.sr ≈ FPSOSiz.der(r, :sr)

        # as camadas fecham no vaso meio cheio
        hw, ho, nivel = A.layer_heights(g.d_m, g.beta)
        @test hw + ho ≈ nivel
        @test nivel ≈ g.d_m / 2
        @test hw >= 0 && ho >= 0

        # o casco é fechado e simétrico nos tampos
        l0, r0 = A.hull_profile(g.d_m, g.lss_m, g.d_m / 2)
        @test l0 ≈ -A.head_depth(g.d_m)
        @test r0 ≈ g.lss_m + A.head_depth(g.d_m)
        @test A.hull_profile(g.d_m, g.lss_m, 0.0)[1] ≈ 0.0 atol = 1e-9
        @test length(A.hull_band(g.d_m, g.lss_m, 0.0, g.d_m)) == 80
    end

    @testset "mexer no cursor não quebra nada" begin
        st = A.AppState(); A.dimensionar!(st)
        for row in st.resultado.rows
            st.d_sel = row.x
            g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
            @test g.ok
            @test isfinite(g.lss_m) && g.lss_m > 0
            @test startswith(A.svg_elevacao(g), "<svg")
        end
    end

    @testset "trocar de caso reescreve o formulário" begin
        st = A.AppState(); A.dimensionar!(st)
        n = length(st.casos)
        @test n >= 2
        for i in 1:n
            st.sel = i
            @test A.caso_atual(st).name == st.casos[i].name
        end
    end

    @testset "estado inviável não derruba a tela" begin
        st = A.AppState()
        # óleo mais denso que a água em todos os casos ⇒ sem separação gravitacional
        for c in st.casos
            c.lo[:rho_oil] = c.hi[:rho_oil] = 1200.0
        end
        A.dimensionar!(st)
        @test !st.status_ok
        @test occursin("ΔSG", st.status)

        g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
        @test !g.ok                                  # desenha vazio, sem exceção
        @test startswith(A.svg_elevacao(g), "<svg")  # e ainda produz documento válido
        @test valor_cartao(st, "Diâmetro") == "—"
        @test length(A.tabela(st)["linhas"]) == 9

        # E a figura vazia diz o que houve TAMBÉM para quem não a enxerga. Ela saía com
        # `role="img"` e `aria-label=""`, que é o pior dos dois mundos: o leitor de tela
        # anuncia "gráfico sem nome" e para de ler os `<text>` de dentro — e é justamente
        # no estado inviável que o `<text>` de dentro é a única explicação na tela.
        vazio = A.documento_vazio(400, 200, "sem resultado")
        @test occursin("aria-label=\"sem resultado\"", vazio)
        @test !occursin("aria-label=\"\"", vazio)
        # Sem mensagem não há nome, e sem nome não há `role="img"`: assim o conteúdo do
        # SVG volta a ser alcançável em vez de ficar escondido atrás de um nome vazio.
        sem_nome = A.documento_vazio(400, 200)
        @test !occursin("aria-label", sem_nome)
        @test !occursin("role=\"img\"", sem_nome)
    end

    @testset "o programa não promete só separadores" begin
        # `USO` (a saída de `--ajuda`) e o banner do terminal diziam "separadores
        # trifásicos horizontais / Stewart & Arnold (2008)" desde o Sprint 0, quando era
        # verdade. Desde o menu do Sprint 6 são seis aplicações, e a citação do método é
        # por equipamento — ela vive em `method_reference` e sai no memorial.
        @test !occursin("separador", lowercase(A.LEMA))
        @test !occursin("separador", lowercase(A.USO))
        @test !occursin("Stewart", A.USO)
        # O banner do terminal, o `--ajuda` e o subtítulo do menu diziam três coisas
        # diferentes sobre o que o programa faz; agora os dois primeiros são o mesmo texto.
        @test occursin(A.LEMA, A.USO)

        # E o `<title>` é escapado como o JSON de `__INICIAL__` já era: os dois vêm de
        # TOML que o usuário edita, e um `</title>` ali encerraria o elemento no meio do
        # cabeçalho do documento.
        html = A.pagina(; titulo = "a<b>c", corpo = "menu.html",
                        scripts = String[], dados = nothing)
        @test occursin("<title>a&lt;b&gt;c</title>", html)
    end

    @testset "nenhum caso ativo" begin
        st = A.AppState()
        for c in st.casos
            c.enabled = false
        end
        A.dimensionar!(st)
        @test !st.status_ok
        @test st.resultado === nothing
        @test startswith(svg_figura(st, "vaso"), "<svg")
    end

    @testset "formatação PT-BR" begin
        @test A.Formato.num(17.243) == "17,24"
        @test A.Formato.num(NaN) == "—"
        @test A.Formato.inteiro(6300) == "6300"          # sem separador até 5 dígitos
        @test A.Formato.inteiro(16508) == "16.508"
        @test A.Formato.parse_num("17,24") ≈ 17.24       # vírgula decimal
        @test A.Formato.parse_num("17.24") ≈ 17.24       # ponto decimal também
        @test A.Formato.parse_num("1.025,8") ≈ 1025.8    # com separador de milhar
        @test A.Formato.parse_num("abc") === nothing
        @test A.Formato.parse_num("") === nothing
        # O SVG não lê vírgula: coordenada tem de sair com ponto, sempre.
        @test A.svgn(17.25) == "17.25"
        @test !occursin(',', A.svgn(1025.8))
    end

    @testset "a paleta do CSS não divergiu da do Julia" begin
        # `app.css` não tem como importar Julia, então a duplicação é vigiada aqui.
        css = read(joinpath(A.dir_publico(), "app.css"), String)
        for (var, cor) in ("--destaque" => A.Formato.DESTAQUE,
                           "--erro"     => A.Formato.ERRO,
                           "--ok"       => A.Formato.OK,
                           "--tinta"    => A.Formato.TINTA,
                           "--linha"    => A.Formato.LINHA,
                           "--fundo"    => A.Formato.FUNDO,
                           "--gas"      => A.Formato.GAS,
                           "--oleo"     => A.Formato.OLEO_ZONA,
                           "--agua"     => A.Formato.AGUA_ZONA)
            @test occursin(Regex("\\Q$var\\E:\\s*\\Q$cor\\E\\s*;"), css)
        end
    end

    @testset "o JavaScript e o HTML falam dos mesmos elementos" begin
        # `document.getElementById` devolve `null` para id inexistente, e o
        # `addEventListener` seguinte lança — o que aborta a montagem inteira da tela.
        # O sintoma é a página servida com status 200 e parada em "Carregando…",
        # exatamente a classe de falha que este arquivo existe para pegar. Renomear um
        # id no HTML e esquecer o JS (ou o contrário) é barato demais para depender de
        # alguém abrir o navegador.
        publico = A.dir_publico()
        casca = read(joinpath(publico, "casca.html"), String)

        # Uma página é a casca MAIS o seu corpo, servida com o seu script. Desde o
        # Sprint 6 são duas — o menu e a tela de dimensionamento —, então o par fixo
        # (index.html, app.js) virou uma lista de pares.
        for (corpo, script) in (("index.html", "app.js"), ("menu.html", "menu.js"))
            html = casca * read(joinpath(publico, corpo), String)
            js   = read(joinpath(publico, script), String)

            ids_html = Set(m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", html))
            ids_js   = Set(m.captures[1] for m in eachmatch(r"\bq\(\"([^\"]+)\"\)", js))

            @test !isempty(ids_js)
            @test isempty(setdiff(ids_js, ids_html))   # JS pede id que o HTML não tem
            @test isempty(setdiff(ids_html, ids_js))   # HTML declara id que ninguém usa
        end

        # E as classes que o Julia emite na legenda têm de existir na folha de estilo.
        css = read(joinpath(publico, "app.css"), String)
        for classe in ("legenda-casos", "legenda-fases", "amostra",
                       "governa", "marca", "nome", "resto")
            @test occursin("." * classe, css)
        end
    end

    @testset "o aquecimento bate nas rotas que existem" begin
        # `app/precompile/aquecimento.jl` exercita o ciclo HTTP no build — é a parte
        # cara de compilar, e é o que faz o executável abrir rápido. Ele está envolto
        # num `try` que degrada para `@warn`, então uma rota errada ali NÃO quebra o
        # build: só devolve um binário lento, com um aviso no meio de mil linhas de
        # compilação. Foi o que aconteceu no Sprint 6, quando as rotas ganharam o
        # prefixo do box e o aquecimento continuou pedindo `/api/dimensionar`.
        aquecimento = read(joinpath(dirname(A.dir_publico()), "precompile",
                                    "aquecimento.jl"), String)
        ativos = Set(b.id for b in FPSOSiz.catalogo() if b.ativo)
        for m in eachmatch(r"/api/([a-z0-9-]+)", aquecimento)
            @test m.captures[1] == "parar" || m.captures[1] in ativos
        end
        # e ele tem de bater em ao menos uma rota de box, senão o teste acima passa
        # vazio e não prova nada
        @test occursin(r"/api/[a-z0-9-]+-\d", aquecimento)
    end

    @testset "a tela não cita nenhuma grandeza pelo nome" begin
        # O aceite do Sprint 7. A regra de src/interfaces.jl — a interface nunca cita um
        # PARÂMETRO pelo nome — passou a valer também para as GRANDEZAS: `index.html`
        # tinha oito `<dt>` ("Comprimento efetivo Leff", "Esbeltez SR", "Teto de
        # decantação"), quatro `<th>` e uma legenda de fases escritos à mão, e `app.js`
        # gravava em oito `id` fixos. Nada disso dava erro num equipamento que não fosse
        # vaso — dava campo vazio e legenda mentirosa, que é pior.
        #
        # Prova de que era real: a legenda de fases prometia "água" também no vaso
        # BIFÁSICO, que não tem fase aquosa. Estava errada desde o Sprint 5 e ninguém viu,
        # porque quem a escrevia era o HTML e o HTML não sabia de qual vaso se tratava.
        publico = A.dir_publico()

        # Comentários são a documentação do arquivo e PODEM citar o que quiserem — é
        # onde a decisão fica registrada. O que não pode citar é o que o usuário lê.
        sem_comentario_html(t) = replace(t, r"<!--.*?-->"s => "")
        sem_comentario_js(t)   = replace(replace(t, r"/\*.*?\*/"s => ""), r"//[^\n]*" => "")

        html = sem_comentario_html(read(joinpath(publico, "index.html"), String))
        js   = sem_comentario_js(read(joinpath(publico, "app.js"), String))

        # A asserção devolve as palavras ENCONTRADAS, e não o arquivo inteiro: um
        # `@test !occursin(…)` que falha imprime a página toda no terminal.
        visivel = lowercase(html) * lowercase(js)
        proibidas = ("leff", "lss", "sbeltez", "decanta", "óleo", "água",
                     "gás", "vaso", "diâmetro")
        @test filter(p -> occursin(p, visivel), proibidas) == ()
    end

    @testset "o app.js é JavaScript válido" begin
        # Um erro de sintaxe no app.js não produz sinal nenhum do lado do Julia: o
        # arquivo é servido como texto, com status 200, e o navegador o descarta
        # inteiro. O sintoma é a tela parada em "Carregando…" — a mesma classe de falha
        # que o cross-check de ids existe para pegar, e que ele não alcança.
        #
        # O `node` entra só como verificador de sintaxe (`--check` não executa nada), e
        # está no flake.nix por isso. Onde ele não existe o teste se pula, para que
        # `build/bootstrap.sh` continue rodando numa máquina sem Node.
        node = Sys.which("node")
        if node === nothing
            @info "node ausente: verificação de sintaxe do app.js pulada"
            @test true
        else
            for nome in ("app.js", "menu.js", "icones.js")
                js = joinpath(A.dir_publico(), nome)
                @test success(pipeline(`$node --check $js`;
                                       stdout = devnull, stderr = devnull))
            end
        end
    end

    @testset "a tela continua operável por leitor de tela" begin
        # Nenhuma destas falhas produz status ≠ 200 nem exceção: a tela abre bonita e é
        # inoperável para quem não a enxerga. Como o formulário nasce em JavaScript, não
        # há HTML para inspecionar — o que dá para vigiar é a presença das construções
        # que produzem a semântica. É a mesma estratégia da paleta e dos ids.
        publico = A.dir_publico()
        html = read(joinpath(publico, "casca.html"), String) *
               read(joinpath(publico, "index.html"), String)
        js   = read(joinpath(publico, "app.js"), String)
        css  = read(joinpath(publico, "app.css"), String)

        # A barra de status é o único retorno de "Dimensionar" e de campo recusado.
        # Sem região viva, o leitor de tela não anuncia nada ao usuário. Ela vive na
        # casca desde o Sprint 6, e por isso serve as duas páginas.
        @test occursin(r"id=\"status\"[^>]*role=\"status\"", html)
        @test occursin(r"id=\"status\"[^>]*aria-live=\"polite\"", html)

        # Todo <select> da tela precisa de nome acessível — por `<label for>` quando
        # há um rótulo visível ao lado, por `aria-label` quando não há.
        for id in ("sel-arquivo", "sel-caso", "sel-memorial")
            @test occursin(Regex("<label[^>]*for=\"$id\"|id=\"$id\"[^>]*aria-label="),
                           html)
        end

        # As duas tabelas de formulário são layout, não dado tabular.
        for id in ("form-campos", "form-ajustes")
            @test occursin(Regex("id=\"$id\"[^>]*role=\"presentation\""), html)
        end

        # Cada uma das ~50 caixas geradas precisa de nome acessível próprio: são duas
        # por rótulo, e sem isto ambas são anunciadas como "caixa de edição, em branco".
        @test occursin("aria-label", js)
        @test occursin("aria-describedby", js)
        # Campo recusado não pode se distinguir só pela cor da borda.
        @test occursin("aria-invalid", js)
        @test occursin(".erro-campo", css)
        # E `aria-invalid` tem de ser REMOVIDO quando válido, nunca escrito como
        # "false" — que faz o leitor anunciar "inválido: falso" em cada campo.
        @test occursin("removeAttribute(\"aria-invalid\")", js)
        @test !occursin("aria-invalid\", \"false\"", js)

        # O cursor é um <input type=range> sobre o ÍNDICE da grade (a grade não tem passo
        # constante — ver `aplicarGrade`), e é o `value` que o leitor de tela anuncia.
        # Sem `aria-valuetext` ele lia "3 de 12" em vez de "5550 mm": justamente o número
        # que a pessoa precisa ouvir era o único que ela não ouvia.
        @test occursin("aria-valuetext", js)

        # O foco de teclado não pode ser marcado só pela cor da borda — é a mesma regra
        # que vale para campo recusado, e ela valia para todo campo do formulário. A
        # proibição sozinha passaria com o foco simplesmente removido, então exige-se
        # também a regra que o repõe.
        @test !occursin(r"input:focus\s*\{[^}]*outline:\s*none"s, css)
        @test occursin(r"input:focus-visible[^{]*\{[^}]*outline:\s*\d"s, css)
        # O cartão do menu tinha `outline: none` na MESMA regra do `:hover`: percorrer os
        # seis cartões por Tab não mostrava qual deles o Enter abriria.
        @test occursin(r"a\.box:focus-visible\s*\{[^}]*outline:\s*\d"s, css)

        # O menu trata os DOIS eventos, como a tela de dimensionamento: `error` não pega
        # promessa rejeitada, e `sair()` é `async`.
        menu_js = read(joinpath(publico, "menu.js"), String)
        @test occursin("unhandledrejection", menu_js)
        @test occursin("addEventListener(\"error\"", menu_js)
    end

    @testset "a tela não perde o que o usuário fez" begin
        # Quatro defeitos de uma família só: a tela e o servidor deixam de se
        # corresponder, ou o trabalho some, e NADA denuncia. Nenhum deles produz status
        # ≠ 200 — o que dá para vigiar é a presença das construções que os corrigem, que
        # é a mesma estratégia do testset acima.
        publico = A.dir_publico()
        js = read(joinpath(publico, "app.js"), String)

        # (1) Campo recusado em caso que não está à vista. O servidor valida TODOS os
        # casos; a tela mostra um. Os avisos dos outros eram descartados na hora, e os do
        # caso à vista morriam na primeira troca de caso — a barra dizia "3 campo(s)
        # recusado(s)" e não havia nada marcado em lugar nenhum.
        @test occursin("avisosPendentes", js)
        @test occursin("function aplicarAvisos()", js)
        @test occursin("function casosComAviso()", js)
        # e `escreverCaso` REPÕE as marcas depois de limpar as caixas
        corpo_escrever = match(r"function escreverCaso\(\).*?\n\}"s, js)
        @test corpo_escrever !== nothing
        @test occursin("aplicarAvisos()", corpo_escrever.match)

        # (2) O escopo do aviso é POSICIONAL ("caso:3"). Criar ou remover caso o
        # desendereça — a mesma armadilha da herança por posição do Sprint 3.
        for f in ("function novoCaso(", "function removerCaso(")
            corpo = match(Regex(replace(f, "(" => "\\(") * ".*?\\n\\}", "s"), js)
            @test corpo !== nothing && occursin("esquecerAvisos()", corpo.match)
        end

        # (3) Fechar a aba com edição pendente descartava o estudo em silêncio, enquanto
        # Abrir e Voltar ao menu já perguntavam desde o Sprint 3.
        @test occursin("beforeunload", js)
        # …e não pergunta duas vezes numa saída que a pessoa já confirmou.
        @test occursin("saindoDeProposito", js)

        # (4) `ocupado` travava só os cinco botões que disparam requisição. O que EDITA
        # `casos` ficava vivo, e o `aplicarEstado` da resposta em voo o sobrescrevia.
        controles = match(r"const CONTROLES = \[.*?\];"s, js)
        @test controles !== nothing
        for id in ("btn-novo", "btn-duplicar", "btn-remover",
                   "sel-arquivo", "sel-caso", "slider-d")
            @test occursin(id, controles.match)
        end

        # (5) `pedir` parseava JSON antes de olhar o tipo: uma página de erro do servidor
        # virava "Sem conexão com o servidor", que é falso e manda procurar no lugar
        # errado.
        corpo_pedir = match(r"async function pedir\(.*?\n\}"s, js)
        @test corpo_pedir !== nothing
        @test occursin("content-type", corpo_pedir.match)
    end

    @testset "validação recusa o campo e preserva o valor" begin
        st = A.AppState(); A.dimensionar!(st)
        antes = A.caso_atual(st).lo[:q_oil]

        avisos = A.aplicar!(st, Dict("casos" => [Dict(
            "name" => "Teste", "enabled" => true,
            "lo" => Dict("q_oil" => "abacaxi"), "hi" => Dict())]))
        @test length(avisos) == 1
        @test avisos[1]["chave"] == "q_oil"
        @test avisos[1]["extremo"] == "lo"
        @test occursin("ilegível", avisos[1]["msg"])
        @test st.casos[1].lo[:q_oil] == antes    # o valor anterior fica de pé

        # fora da faixa do descritor também é recusado, com a mensagem do core
        avisos = A.aplicar!(st, Dict("casos" => [Dict(
            "name" => "Teste", "enabled" => true,
            "lo" => Dict("q_oil" => "999999"), "hi" => Dict())]))
        @test length(avisos) == 1
        @test occursin("acima do máximo", avisos[1]["msg"])

        # O aviso pode ser de um caso que NÃO está à vista — e é o caso comum, porque o
        # servidor valida o conjunto inteiro enquanto a tela mostra um caso por vez. É a
        # prova de que a situação existe: sem ela, o tratamento do lado do JavaScript
        # (`avisosPendentes`, o `⚠` no seletor) seria conserto de problema imaginado.
        caso = i -> Dict("name" => "Caso $i", "enabled" => true,
                         "lo" => Dict("q_oil" => i == 3 ? "abacaxi" : "200"),
                         "hi" => Dict())
        avisos = A.aplicar!(st, Dict("casos" => [caso(1), caso(2), caso(3)], "sel" => 1))
        @test length(avisos) == 1
        @test avisos[1]["escopo"] == "caso:3"      # e o selecionado é o 1
        @test st.sel == 1
    end

    @testset "remover um caso não embaralha os valores dos outros" begin
        # A regressão que este teste fixa: `aplicar!` restaura o valor anterior de um
        # campo recusado, e antes fazia isso pela POSIÇÃO no vetor. Como a tela cria e
        # remove casos sozinha, depois de um "Remover" a posição `i` designava casos
        # diferentes nas duas pontas — e o valor do caso REMOVIDO reaparecia dentro do
        # caso seguinte, entrando no envelope sem nenhum aviso que o denunciasse.
        st = A.AppState()
        @test length(st.casos) >= 3

        a, b, c = st.casos[1], st.casos[2], st.casos[3]
        @test allunique([a.id, b.id, c.id])
        # os três precisam ser distinguíveis pelo valor, senão o teste não prova nada
        a.lo[:q_oil], b.lo[:q_oil], c.lo[:q_oil] = 1000.0, 2000.0, 3000.0

        # a tela remove o do meio e manda [a, c] — com `id`, como o navegador faz
        envia(x, q_oil) = Dict("id" => x.id, "name" => x.name, "enabled" => true,
                               "lo" => Dict("q_oil" => q_oil), "hi" => Dict())
        avisos = A.aplicar!(st, Dict("casos" => [envia(a, "1000"),
                                                 envia(c, "abacaxi")]))

        @test length(avisos) == 1
        @test avisos[1]["escopo"] == "caso:2"        # endereça a CAIXA, que é posicional
        @test length(st.casos) == 2
        @test st.casos[2].id == c.id                 # e a identidade sobreviveu
        # o valor recusado voltou ao de `c` (3000), não ao do removido `b` (2000)
        @test st.casos[2].lo[:q_oil] == 3000.0
    end

    @testset "caso sem id é novo, e não herda de ninguém" begin
        # É como "+ Novo" e "Duplicar" chegam: o navegador não inventa identidade, o
        # servidor atribui. Um caso novo não tem passado do qual restaurar valor.
        st = A.AppState()
        antes = length(st.casos)
        ids_antes = Set(c.id for c in st.casos)

        A.aplicar!(st, Dict("casos" => vcat(
            [Dict("id" => c.id, "name" => c.name, "enabled" => true,
                  "lo" => Dict(), "hi" => Dict()) for c in st.casos],
            [Dict("name" => "Recém-nascido", "enabled" => true,
                  "lo" => Dict("q_oil" => "1234"), "hi" => Dict("q_oil" => "1234"))])))

        @test length(st.casos) == antes + 1
        novo = st.casos[end]
        @test novo.name == "Recém-nascido"
        @test novo.lo[:q_oil] == 1234.0
        @test !(novo.id in ids_antes)                # identidade própria
        @test allunique([c.id for c in st.casos])
    end

    @testset "exportação" begin
        st = A.AppState(); A.dimensionar!(st)
        r = A.exportar!(st)
        @test r.ok
        @test st.status_ok
        @test r.dir == TEMP_SAIDA

        arquivos = readdir(TEMP_SAIDA)
        for sufixo in ("_varredura.csv", "_memorial.txt",
                       "_vaso.svg", "_corte.svg", "_leff.svg", "_sr.svg")
            @test any(f -> endswith(f, sufixo), arquivos)
        end

        # Uma figura por arquivo, e cada arquivo com UM elemento-raiz. Dois `<svg>`
        # num arquivo só não é XML válido, e o visualizador recusa o arquivo inteiro
        # em silêncio — foi assim que a primeira versão da exportação quebrou.
        for f in filter(f -> endswith(f, ".svg"), arquivos)
            texto = read(joinpath(TEMP_SAIDA, f), String)
            @test startswith(texto, "<?xml")
            @test count("<svg", texto) == 1
            @test count("</svg>", texto) == 1
        end

        csv = joinpath(TEMP_SAIDA,
                       last(sort(filter(f -> endswith(f, "_varredura.csv"), arquivos))))
        linhas = readlines(csv)
        @test any(l -> startswith(l, "d (mm);"), linhas)
        # As colunas do CSV são as MESMAS que a tabela da tela declara, mais três
        # fixas (governa, caso governante, admissível) e uma por caso.
        cab = only(filter(l -> startswith(l, "d (mm);"), linhas))
        n_cols = length(FPSOSiz.sweep_columns(st.metodo))
        @test length(split(cab, ';')) == n_cols + 3 + length(st.resultado.case_names)
        @test split(cab, ';')[1:n_cols] ==
              [c.label for c in FPSOSiz.sweep_columns(st.metodo)]

        # o memorial traz o rastro de cálculo de cada caso
        memorial = read(joinpath(TEMP_SAIDA,
                        last(sort(filter(f -> endswith(f, "_memorial.txt"), arquivos)))),
                        String)
        @test occursin("memorial de cálculo", memorial)
        @test occursin("Eq. 22", memorial)
    end

    @testset "o memorial da tela é o mesmo do arquivo exportado" begin
        # O aceite do Sprint 3. A tela e o `.txt` compartilham `linha_memorial` e
        # `fecho_memorial` — este teste é o que impede que alguém "melhore" um dos dois
        # lados isoladamente. O `.txt` é o que vai anexo ao relatório; a tela é o que se
        # confere antes de anexar. Divergirem seria pior do que qualquer um estar errado.
        st = A.AppState(); A.dimensionar!(st)
        m = A.memorial(st)
        r = A.exportar!(st)
        @test r.ok

        arquivo = only(filter(f -> endswith(f, "_memorial.txt"), r.arquivos))
        linhas_txt = Set(split(read(arquivo, String), '\n'))

        @test length(m["casos"]) == length(st.resultado.case_names)
        @test m["governante"] == st.resultado.driver_case

        for (i, caso) in enumerate(m["casos"])
            @test caso["nome"] == st.resultado.case_names[i]
            @test "CASO: " * caso["nome"] in linhas_txt
            @test !isempty(caso["blocos"])

            # toda linha que a tela mostra está, IDÊNTICA, no arquivo
            for bloco in caso["blocos"], linha in bloco["linhas"]
                @test linha in linhas_txt
            end
            @test caso["fecho"] in linhas_txt

            # e o contrário: nenhuma entrada do rastro ficou de fora da tela
            na_tela = sum(length(b["linhas"]) for b in caso["blocos"])
            @test na_tela == length(st.resultado.per_case[i].trace.entries)
        end

        # os blocos saem na ordem do cálculo, não na ordem em que o Dict os guardou
        ordem = [String(id) for (id, _) in
                 A.blocos_memorial(st.metodo, first(st.resultado.per_case).trace)]
        for caso in m["casos"]
            vistos = [b["id"] for b in caso["blocos"]]
            @test vistos == filter(in(vistos), ordem)
        end
    end

    @testset "as colunas do memorial não estouram" begin
        # `linha_memorial` alinha em larguras fixas (rpad de 10, 10, 24, 16, 8). Um
        # rótulo mais longo que a sua coluna não quebra nada visível do lado do Julia:
        # ele apenas cola no campo seguinte, e o memorial — que vai ANEXO ao relatório —
        # sai com uma linha ilegível no meio de trinta legíveis. Foi o que aconteceu ao
        # acrescentar a variante geométrica da Eq. 21 ("d_max (óleo em água, geom.)",
        # 27 caracteres numa coluna de 24).
        st = A.AppState(); A.dimensionar!(st)
        larguras = ("block" => 10, "eq" => 10, "var" => 24, "unit" => 8)

        for res in st.resultado.per_case, e in res.trace.entries
            for (campo, largura) in larguras
                texto = string(getfield(e, Symbol(campo)))
                @test textwidth(texto) < largura     # `<`, não `<=`: sobra o separador
            end
            # e o valor formatado também tem de caber
            @test textwidth(A.Formato.num(e.value, 5)) < 16

            # a conferência de fato: nenhuma coluna encosta na seguinte
            linha = A.linha_memorial(e)
            @test !occursin(r"\S{25,}", linha[1:min(end, 60)])
        end
    end

    @testset "memorial sem resultado não quebra" begin
        # Mesmo contrato do resto da tela: ausência de resultado é estado, não exceção.
        st = A.AppState()
        for c in st.casos
            c.enabled = false
        end
        A.dimensionar!(st)
        @test st.resultado === nothing
        m = A.memorial(st)
        @test isempty(m["casos"])
        @test m["governante"] == ""
    end

    @testset "abrir e salvar conjuntos de casos" begin
        # O aceite do Sprint 4 do lado da interface. O de dentro do core (a ida e volta
        # do TOML) está em `test/cases.jl`; aqui o que se prova é que o caminho
        # tela → arquivo → tela não perde nada pelo meio.
        st = A.AppState()
        @test st.arquivo == "exemplo_alves_komesu.toml"
        @test occursin("Alves", st.rotulo)
        n = length(st.casos)

        A.caso_atual(st).name = "Renomeado na tela"
        r = A.salvar_casos!(st, "smoke_salvo.toml"; rotulo = "Salvo pelo teste")
        @test r.ok
        @test dirname(r.caminho) == TEMP_CASOS
        @test st.arquivo == "smoke_salvo.toml"
        @test st.status_ok

        # Os ajustes de grade e a banda de SR são decisão de projeto, não dado de
        # corrente: gravá-los seria gravar o que a leitura descarta — um arquivo que
        # parece guardar mais do que guarda.
        texto = read(r.caminho, String)
        for k in FPSOSiz.global_keys(st.metodo)
            @test !occursin(string(k), texto)
        end

        lista = A.arquivos(st)
        @test lista["atual"] == "smoke_salvo.toml"
        @test lista["dir"] == TEMP_CASOS
        salvo = only(filter(a -> a["nome"] == "smoke_salvo.toml", lista["arquivos"]))
        @test salvo["rotulo"] == "Salvo pelo teste"
        @test salvo["gravavel"]
        @test salvo["casos"] == n
        # o exemplo de fábrica continua na lista, marcado como não gravável
        fabrica = only(filter(a -> a["nome"] == "exemplo_alves_komesu.toml",
                              lista["arquivos"]))
        @test !fabrica["gravavel"]

        outro = A.AppState()
        @test A.abrir_casos!(outro, "smoke_salvo.toml")
        @test outro.arquivo == "smoke_salvo.toml"
        @test outro.resultado !== nothing            # abrir redimensiona
        @test length(outro.casos) == n
        for (a, b) in zip(st.casos, outro.casos)
            @test a.name == b.name
            @test a.enabled == b.enabled
            @test a.lo == b.lo                       # valor a valor, sem arredondar
            @test a.hi == b.hi
        end
        @test outro.casos[1].name == "Renomeado na tela"
        # o caso desativado do exemplo continua desativado depois da ida e volta
        @test any(c -> !c.enabled, outro.casos)
    end

    @testset "salvar recusa nome que não é nome de arquivo" begin
        # O nome vem do navegador e vira caminho em disco. `..` tem de morrer aqui.
        st = A.AppState()
        for ruim in ("../fuga.toml", "/tmp/fuga.toml", "sem_extensao", "")
            r = A.salvar_casos!(st, ruim)
            @test !r.ok
            @test !st.status_ok
            @test occursin("inválido", st.status)
        end
        @test !isfile(joinpath(dirname(TEMP_CASOS), "fuga.toml"))
        @test !isfile("/tmp/fuga.toml")
    end

    @testset "arquivo de casos ilegível vira mensagem, não exceção" begin
        # Este arquivo é editável à mão — é o ponto dele. Então ele vai ser quebrado à
        # mão, e o programa tem de abrir mesmo assim, dizendo o que houve.
        quebrado = joinpath(TEMP_CASOS, "quebrado.toml")
        write(quebrado, "isto [não é TOML\n")

        st = A.AppState(; case_file = "quebrado.toml")
        @test length(st.casos) == 1                  # cai para um caso em branco
        @test !st.status_ok
        @test occursin("Não consegui abrir", st.status)
        @test st.arquivo == ""                       # nada aberto, então nada a salvar por cima

        A.dimensionar!(st)                           # e a tela segue operável
        @test startswith(svg_figura(st, "vaso"), "<svg")

        # A listagem mostra o arquivo quebrado em vez de escondê-lo: sumir com ele
        # esconderia justamente o arquivo que a pessoa acabou de editar e quebrar.
        entrada = only(filter(a -> a["nome"] == "quebrado.toml",
                              A.arquivos(st)["arquivos"]))
        @test occursin("ilegível", entrada["rotulo"])

        rm(quebrado)
    end

    @testset "abrir que falha não deixa na tela o resultado do conjunto anterior" begin
        # A tela mostra desenho, cartão, grade e memorial derivados de `st.resultado`.
        # Se um "Abrir" que falhou trocasse os casos e deixasse o resultado velho de pé,
        # a pessoa leria números de um vaso que a tela já não tem como explicar — e nada
        # na barra de status diria que os dois lados deixaram de se corresponder.
        st = A.AppState()
        A.dimensionar!(st)
        @test length(st.resultado.case_names) == 10        # 4 casos → 10 cantos

        @test !A.abrir_casos!(st, "nao_existe_de_jeito_nenhum.toml")
        @test length(st.casos) == 1
        @test !st.status_ok
        @test occursin("Não consegui abrir", st.status)    # a queixa sobrevive
        # e o resultado passou a ser o do caso em branco, não o dos dez cantos
        @test st.resultado === nothing || length(st.resultado.case_names) == 1
        @test length(A.tabela(st)["linhas"]) == 9
        @test startswith(svg_figura(st, "vaso"), "<svg")
    end

    @testset "o vaso bifásico atravessa a interface inteira" begin
        # O aceite do Sprint 5 do lado da tela: o segundo equipamento tem de desenhar,
        # cotar e memorializar sem uma linha de `app/` citar o nome dele.
        U = FPSOSiz.Units
        lb_ft3 = U.LB_KG / U.CUFT_M3
        st = A.AppState(; case_file = "nao_existe_de_proposito.toml",
                          equipamento = FPSOSiz.KnockoutDrum(),
                          metodo = FPSOSiz.StewartArnoldTwoPhase())

        # O formulário encolhe sozinho: 8 de corrente (sem as três de água e sem a
        # viscosidade do líquido) + 2 do método. Nenhum campo escrito à mão em `app/`.
        @test length(st.campos) == 10
        chaves = Set(s.key for s in st.campos)
        for ausente in (:q_water, :rho_water, :mu_water, :mu_oil)
            @test !(ausente in chaves)
        end
        @test :tr_liquid in chaves

        # Exemplo 3.2 do livro, em SI
        c = A.caso_atual(st)
        for (k, v) in (:q_gas => 10e6 * U.CUFT_M3 / 24,
                       :q_oil => 2000 * U.BARREL_M3 / 24,
                       :rho_oil => 51.5 * lb_ft3, :rho_gas => 3.71 * lb_ft3,
                       :mu_gas => 0.013, :pressure => 1000 * U.PSI_KPA,
                       :temperature => (60 - 32) * 5 / 9, :z => 0.84)
            c.lo[k] = c.hi[k] = v
        end
        A.dimensionar!(st)
        @test st.status_ok

        # o livro escolhe 36 in (914 mm) por 10 ft (3,05 m), SR 3,2
        @test abs(st.resultado.x - 914.4) <= 150.0
        @test 3.0 <= FPSOSiz.der(st.resultado, :sr) <= 4.0
        @test valor_cartao(st, "Teto") == "—"      # sem teto de decantação

        @testset "o desenho tem DUAS camadas, e nenhum NaN" begin
            # Com `beta = NaN`, deduzir três camadas de β daria `h_w = NaN·d` nas
            # coordenadas — e um SVG com NaN num atributo é descartado pelo navegador
            # em silêncio: a figura some, com status 200 e sem erro em lugar nenhum.
            @test isnan(A.beta_atual(st))
            g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
            @test [cam.nome for cam in g.camadas] == ["LÍQUIDO", "GÁS"]
            @test g.camadas[1].y1 ≈ g.d_m / 2      # meio cheio, como o trifásico

            for svg in (A.svg_elevacao(g), A.svg_corte(g))
                @test startswith(svg, "<svg")
                @test count("<", svg) == count(">", svg)
                @test !occursin("NaN", svg)
                @test !occursin("Sem resultado", svg)   # desenhou de verdade
            end
            # β não é anunciado onde não existe
            @test !occursin("β = hₒ/d", A.svg_corte(g))
        end

        @testset "o memorial não ganha um Bloco B vazio" begin
            blocos = A.memorial(st)["casos"][1]["blocos"]
            titulos = [b["titulo"] for b in blocos]
            @test any(t -> occursin("Bloco A", t), titulos)
            @test any(t -> occursin("Bloco C", t), titulos)
            @test !any(t -> occursin("Bloco B", t), titulos)
            # e cita a fonte DELE, não o artigo sobre trifásicos
            @test occursin("Eq. 3.8b", join(blocos[1]["linhas"], "\n"))
        end

        @testset "exportar carrega o método e a referência certos" begin
            r = A.exportar!(st)
            @test r.ok
            txt = read(only(filter(f -> endswith(f, "_memorial.txt"), r.arquivos)), String)
            @test occursin("bifásico", txt)
            @test occursin("Gas-Liquid and Liquid-Liquid Separators", txt)
            @test !occursin("Alves & Komesu", txt)     # essa é a fonte do OUTRO vaso
        end

        @testset "nem as figuras chamam este vaso de separador" begin
            # O guarda do Sprint 7 ("a tela não cita nenhuma grandeza pelo nome") lê
            # `index.html` e `app.js` — e não alcança o que o JULIA GERA para dentro da
            # tela. Passava por ele o `aria-label` de `svg_elevacao`, que dizia "Elevação
            # do separador" nos DOIS vasos: `svg_elevacao` serve os dois, e o rótulo era
            # literal. Quem enxerga a figura não notava; quem depende do leitor de tela
            # ouvia o knockout bifásico ser anunciado como separador.
            #
            # A asserção é sobre a SAÍDA, e não sobre o texto do arquivo: é o que o
            # usuário recebe, e vale para qualquer figura que um método venha a declarar.
            for f in A.figuras(st)
                @test !occursin("separador", lowercase(f["svg"]))
                @test !occursin("separador", lowercase(f["titulo"]))
                @test !occursin("separador", lowercase(f["legenda"]))
            end
            # E o `role="img"` só existe quando há nome: um SVG com `aria-label=""` é
            # anunciado como gráfico sem nome E esconde os `<text>` de dentro.
            for f in A.figuras(st)
                @test !occursin("aria-label=\"\"", f["svg"])
            end
        end
    end

    @testset "o trifásico continua com três camadas e com β" begin
        st = A.AppState(); A.dimensionar!(st)
        g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
        @test [cam.nome for cam in g.camadas] == ["ÁGUA", "ÓLEO", "GÁS"]
        @test isfinite(A.beta_atual(st))
        @test occursin("β = hₒ/d", A.svg_corte(g))
        # as camadas fecham no vaso meio cheio
        @test g.camadas[2].y1 ≈ g.d_m / 2
        @test g.camadas[1].y0 ≈ 0.0
        @test g.camadas[end].y1 ≈ g.d_m
    end

    @testset "sem resultado, β é NaN — não um número plausível" begin
        # O valor anterior aqui era 0,25: um β de aparência correta que produzia um
        # desenho errado sem nada denunciar.
        st = A.AppState()
        @test st.cons_gov === nothing
        @test isnan(A.beta_atual(st))
        for c in st.casos
            c.enabled = false
        end
        A.dimensionar!(st)
        @test st.cons_gov === nothing
        @test isnan(A.beta_atual(st))
    end

    # -----------------------------------------------------------------------
    # O servidor de verdade
    # -----------------------------------------------------------------------

    @testset "o servidor responde e os handlers rodam" begin
        A.reiniciar_estado!()
        porta = A.porta_livre(0)
        @async A.servir(; porta, abrir = false, bloquear = false)

        base = "http://127.0.0.1:$porta"
        pronto = false
        for _ in 1:120                       # a primeira compilação demora
            try
                HTTP.get(base; retry = false, status_exception = false)
                pronto = true
                break
            catch
                sleep(0.5)
            end
        end
        @test pronto

        r = HTTP.get(base)
        html = String(r.body)
        @test r.status == 200
        # Marcador: distingue "é a nossa página" de "veio alguma coisa com status 200".
        @test occursin("fpso-siz-genie", html)
        # E o estado tem de vir embutido — senão a tela abre vazia e só o navegador vê.
        @test occursin("window.__INICIAL__", html)

        for (caminho, tipo) in ("/app.css" => "css", "/app.js" => "javascript",
                                "/senai-cetiqt.webp" => "webp")
            resp = HTTP.get(base * caminho; status_exception = false)
            @test resp.status == 200
            @test !isempty(resp.body)
            # O tipo importa tanto quanto o status: servida como octet-stream, a folha
            # de estilo é ignorada pelo navegador e a logo não aparece — com 200 nos dois.
            @test occursin(tipo, lowercase(HTTP.header(resp, "Content-Type", "")))
        end

        # Arquivo inexistente: `serve_static_file` consulta o diretório-fonte do Genie
        # antes de desistir (ver a nota no topo de server.jl). No executável esse
        # caminho não existe; o que não pode é virar exceção em vez de 404.
        faltando = HTTP.get("$base/nao-existe.js"; status_exception = false)
        @test faltando.status == 404

        esq = JSON3.read(String(HTTP.get("$base/api/separador-3f/esquema").body))
        @test length(esq.campos) > 10
        @test length(esq.ajustes) == length(FPSOSiz.global_keys(FPSOSiz.StewartArnold()))
        # nenhum descritor pode chegar à tela sem rótulo e unidade
        @test all(c -> !isempty(c.label) && !isempty(c.unit), esq.campos)

        @testset "a aplicação abre EM BRANCO" begin
            # Até o Sprint 5 o programa abria já com o caso do artigo carregado e
            # dimensionado, sem que ninguém tivesse pedido nem uma coisa nem outra.
            vazio = JSON3.read(String(HTTP.get("$base/api/separador-3f/estado").body))
            @test vazio.arquivo == ""
            @test length(vazio.casos) == 1
            @test valor_cartao_json(vazio, "Diâmetro") == "—"   # nada dimensionado
        end

        # É abrir o arquivo que traz os quatro casos do artigo — e é por este caminho
        # que a pessoa chega ao exemplo agora.
        ab0 = JSON3.read(String(HTTP.post("$base/api/separador-3f/casos/abrir";
            body = """{"arquivo":"exemplo_alves_komesu.toml"}""").body))
        @test ab0.arquivo == "exemplo_alves_komesu.toml"
        @test length(ab0.casos) == 4

        d = JSON3.read(String(HTTP.post("$base/api/separador-3f/dimensionar"; body = "{}").body))
        @test d.status_ok
        @test d.viavel
        # O caso de referência de config/cases/: quatro casos, dez cantos.
        @test valor_cartao_json(d, "Diâmetro") == "6300 mm"
        @test valor_cartao_json(d, "Leff") == "18,59 m"
        @test valor_cartao_json(d, "Caso governante") == "Fim de vida"
        @test startswith(svg_figura_json(d.desenho, "vaso"), "<svg")
        @test !isempty(d.grade)

        # mover o cursor troca a seleção sem redimensionar. É POST porque a rota
        # escreve `st.d_sel`, que é o diâmetro que a exportação desenha.
        x = JSON3.read(String(HTTP.post("$base/api/separador-3f/desenho";
                                        body = """{"d":"5500"}""").body))
        @test x.d_sel == 5500
        @test valor_cartao_json(x, "Diâmetro") != valor_cartao_json(d, "Diâmetro")
        @test startswith(svg_figura_json(x.desenho, "vaso"), "<svg")

        # E o verbo antigo não pode continuar servindo por acidente: um GET que
        # respondesse 200 aqui seria a porta que este POST existe para fechar.
        @test HTTP.get("$base/api/separador-3f/desenho?d=5500"; status_exception = false).status != 200

        # O memorial atravessando o handler — é aqui que um `using` ambíguo apareceria.
        # Antes do POST inválido logo abaixo, que troca o conjunto de casos inteiro.
        mem = JSON3.read(String(HTTP.get("$base/api/separador-3f/memorial").body))
        @test length(mem.casos) == 10          # o caso de referência: 4 casos → 10 cantos
        @test mem.governante == "Fim de vida"
        @test !isempty(mem.casos[1].blocos)
        @test occursin("Eq.", mem.casos[1].blocos[1].linhas[1])

        # --- conjuntos de casos ------------------------------------------
        lista = JSON3.read(String(HTTP.get("$base/api/separador-3f/casos/arquivos").body))
        @test any(a -> a.nome == "exemplo_alves_komesu.toml", lista.arquivos)
        @test lista.dir == TEMP_CASOS

        sv = JSON3.read(String(HTTP.post("$base/api/separador-3f/casos/salvar";
            body = """{"arquivo":"smoke_rota.toml","rotulo":"Pela rota"}""").body))
        @test sv.ok
        @test sv.arquivo == "smoke_rota.toml"
        @test isfile(joinpath(TEMP_CASOS, "smoke_rota.toml"))
        @test any(a -> a.nome == "smoke_rota.toml", sv.lista.arquivos)

        ab = JSON3.read(String(HTTP.post("$base/api/separador-3f/casos/abrir";
            body = """{"arquivo":"smoke_rota.toml"}""").body))
        @test ab.arquivo == "smoke_rota.toml"
        @test ab.status_ok
        @test length(ab.casos) == 4
        @test ab.viavel                       # abrir redimensiona, não só recarrega

        # Nome que sai da pasta: recusado, e com 200 — é erro do usuário, não do
        # transporte, então vira mensagem na barra como todo o resto.
        mau = JSON3.read(String(HTTP.post("$base/api/separador-3f/casos/salvar";
            body = """{"arquivo":"../fuga_rota.toml"}""").body))
        @test !mau.ok
        @test !isfile(joinpath(dirname(TEMP_CASOS), "fuga_rota.toml"))

        # Arquivo inexistente: mensagem, não 500.
        faltoso = HTTP.post("$base/api/separador-3f/casos/abrir";
            body = """{"arquivo":"nao_existe_mesmo.toml"}""", status_exception = false)
        @test faltoso.status == 200
        @test !JSON3.read(String(faltoso.body)).status_ok

        # Origem alheia nas rotas que escrevem. O servidor escuta em 127.0.0.1: um
        # `<form>` numa página qualquer posta para cá sem preflight de CORS, e o
        # `Origin` é o que separa isso de um clique na janela do programa.
        for (rota, corpo) in ("/api/separador-3f/casos/salvar" => """{"arquivo":"invasor.toml"}""",
                              "/api/separador-3f/casos/abrir"  => """{"arquivo":"smoke_rota.toml"}""",
                              "/api/separador-3f/exportar"     => "{}")
            alheia = HTTP.post(base * rota, ["Origin" => "http://exemplo.invalido"];
                               body = corpo, status_exception = false)
            @test alheia.status == 403
        end
        @test !isfile(joinpath(TEMP_CASOS, "invasor.toml"))

        # A origem da própria janela passa...
        propria = HTTP.post("$base/api/separador-3f/casos/salvar",
                            ["Origin" => "http://127.0.0.1:$porta"];
                            body = """{"arquivo":"smoke_rota.toml","rotulo":"Pela rota"}""",
                            status_exception = false)
        @test propria.status == 200

        # ...e leitura não é afetada: um GET não muda nada de qualquer forma.
        @test HTTP.get("$base/api/separador-3f/casos/arquivos",
                       ["Origin" => "http://exemplo.invalido"];
                       status_exception = false).status == 200

        # entrada inválida vira aviso em português, não erro 500
        ruim = JSON3.read(String(HTTP.post("$base/api/separador-3f/dimensionar";
            body = """{"casos":[{"name":"X","enabled":true,
                       "lo":{"q_oil":"não é número"},"hi":{}}]}""").body))
        @test haskey(ruim, :avisos)
        @test occursin("ilegível", ruim.avisos[1].msg)

        expo = JSON3.read(String(HTTP.post("$base/api/separador-3f/exportar"; body = "{}").body))
        @test expo.ok
        @test length(expo.arquivos) == 6

        # --- o menu e o roteamento por box -------------------------------
        @testset "o menu de abertura" begin
            menu = HTTP.get(base; status_exception = false)
            @test menu.status == 200
            html = String(menu.body)
            @test occursin("fpso-siz-genie", html)          # veio da nossa casca
            @test occursin("grade-boxes", html)

            # A grade nasce do catálogo injetado, não de HTML escrito à mão.
            m = match(r"window\.__INICIAL__ = (.*?);</script>", html)
            @test m !== nothing
            boxes = JSON3.read(m.captures[1]).boxes
            @test length(boxes) == length(FPSOSiz.catalogo())
            @test count(b -> b.ativo, boxes) >= 2
            # todo box pendente diz por quê — um cartão morto sem explicação é pior
            # que um cartão ausente
            @test all(b -> b.ativo || !isempty(b.motivo), boxes)

            for nome in ("/menu.js", "/icones.js")
                @test HTTP.get(base * nome; status_exception = false).status == 200
            end
        end

        @testset "cada box ativo serve a sua aplicação" begin
            for b in filter(x -> x.ativo, FPSOSiz.catalogo())
                r = HTTP.get("$base/app/$(b.id)"; status_exception = false)
                @test r.status == 200
                h = String(r.body)
                @test occursin("fpso-siz-genie", h)
                d = JSON3.read(match(r"window\.__INICIAL__ = (.*?);</script>",
                                     h).captures[1])
                @test d.box == b.id
                # o formulário vem do método daquele box, não de uma lista fixa
                @test !isempty(d.esquema.campos)
                @test d.esquema.equipamento ==
                      FPSOSiz.label(FPSOSiz.box_equipamento(b)[1])
            end
        end

        @testset "id de box que não serve não é servido" begin
            # O id vem da URL. Um inventado, um pendente e um caminho relativo têm de
            # morrer antes de tocar no estado.
            for id in ("nao-existe", "bomba-centrifuga", "..")
                @test HTTP.get("$base/app/$id"; status_exception = false).status == 404
                @test HTTP.get("$base/api/$id/estado";
                               status_exception = false).status == 404
            end
        end

        @testset "os estados dos boxes não se misturam" begin
            # O separador já foi dimensionado acima, com o exemplo do artigo aberto.
            e3 = JSON3.read(String(HTTP.get("$base/api/separador-3f/estado").body))
            @test e3.viavel

            # O bifásico, nunca tocado, continua em branco.
            e2 = JSON3.read(String(HTTP.get("$base/api/knockout-2f/estado").body))
            @test valor_cartao_json(e2, "Diâmetro") == "—"
            @test length(e2.casos) == 1
            # e o formulário dele é o dele: 8 de corrente + 2 do método
            esq2 = JSON3.read(String(HTTP.get("$base/api/knockout-2f/esquema").body))
            @test length(esq2.campos) == 10
            @test !any(c -> c.key == "q_water", esq2.campos)

            # Dimensionar o bifásico não mexe no separador.
            HTTP.post("$base/api/knockout-2f/casos/abrir";
                      body = """{"arquivo":"exemplo_knockout.toml"}""")
            d2 = JSON3.read(String(HTTP.post("$base/api/knockout-2f/dimensionar";
                                             body = "{}").body))
            @test d2.status_ok
            @test valor_cartao_json(d2, "Diâmetro") == "900 mm"   # Exemplo 3.2 do livro
            @test valor_cartao_json(d2, "Teto") == "—"            # sem teto de decantação

            # O invariante é "não mudou", e não "é tal arquivo": testsets anteriores
            # neste mesmo servidor já abriram e salvaram outros conjuntos no separador.
            depois = JSON3.read(String(HTTP.get("$base/api/separador-3f/estado").body))
            @test valor_cartao_json(depois, "Diâmetro") ==
                  valor_cartao_json(e3, "Diâmetro")
            @test depois.arquivo == e3.arquivo
            @test length(depois.casos) == length(e3.casos)
        end

        @testset "cada box só enxerga os arquivos do seu equipamento" begin
            l3 = JSON3.read(String(HTTP.get("$base/api/separador-3f/casos/arquivos").body))
            l2 = JSON3.read(String(HTTP.get("$base/api/knockout-2f/casos/arquivos").body))
            n3 = [a.nome for a in l3.arquivos]
            n2 = [a.nome for a in l2.arquivos]
            @test "exemplo_alves_komesu.toml" in n3
            @test !("exemplo_alves_komesu.toml" in n2)
            @test "exemplo_knockout.toml" in n2
            @test !("exemplo_knockout.toml" in n3)

            # E abrir à força um arquivo do outro equipamento é RECUSADO, não
            # preenchido com defaults em silêncio.
            r = JSON3.read(String(HTTP.post("$base/api/knockout-2f/casos/abrir";
                body = """{"arquivo":"exemplo_alves_komesu.toml"}""").body))
            @test !r.status_ok
            @test occursin("outro equipamento", r.status)
        end

        try
            A.Genie.down()
        catch
        end
    end
end

rm(TEMP_SAIDA; recursive = true, force = true)
rm(TEMP_CASOS; recursive = true, force = true)
