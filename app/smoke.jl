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

@testset "fumaça da interface" begin

    @testset "estado inicial" begin
        st = A.AppState()
        @test !isempty(st.casos)
        @test !isempty(st.campos)
        @test length(st.ajustes) == length(A.CHAVES_GLOBAIS)
        # todo campo editável tem valor nos dois extremos
        for c in st.casos, s in st.campos
            @test haskey(c.lo, s.key)
            @test haskey(c.hi, s.key)
        end
        # as chaves globais NÃO são editáveis por caso
        @test all(k -> !(k in [s.key for s in st.campos]), A.CHAVES_GLOBAIS)
    end

    @testset "dimensiona e desenha" begin
        st = A.AppState()
        A.dimensionar!(st)
        @test st.resultado !== nothing
        @test st.resultado.feasible
        @test st.status_ok
        @test st.d_sel == st.resultado.diameter_mm

        g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
        for svg in (A.svg_elevacao(g), A.svg_corte(g),
                    A.svg_grafico_leff(st.resultado, st.d_sel),
                    A.svg_grafico_sr(st.resultado, st.d_sel, (3.0, 5.0), 4.0))
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
        @test g.d_m ≈ r.diameter_mm / 1000
        @test g.lss_m ≈ r.lss_m
        @test g.sr ≈ r.sr

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
            st.d_sel = row.d_mm
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
        @test A.cartao(st)["d"] == "—"
        @test length(A.tabela(st)) == 9
    end

    @testset "nenhum caso ativo" begin
        st = A.AppState()
        for c in st.casos
            c.enabled = false
        end
        A.dimensionar!(st)
        @test !st.status_ok
        @test st.resultado === nothing
        @test startswith(A.desenho(st)["vaso"], "<svg")
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
        html = read(joinpath(publico, "index.html"), String)
        js   = read(joinpath(publico, "app.js"), String)

        ids_html = Set(m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", html))
        ids_js   = Set(m.captures[1] for m in eachmatch(r"\bq\(\"([^\"]+)\"\)", js))

        @test !isempty(ids_js)
        @test isempty(setdiff(ids_js, ids_html))   # JS pede id que o HTML não tem
        @test isempty(setdiff(ids_html, ids_js))   # HTML declara id que ninguém usa

        # E as classes que o Julia emite na legenda têm de existir na folha de estilo.
        css = read(joinpath(publico, "app.css"), String)
        for classe in ("legenda-casos", "amostra", "governa", "marca", "nome", "resto")
            @test occursin("." * classe, css)
        end
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
            js = joinpath(A.dir_publico(), "app.js")
            @test success(pipeline(`$node --check $js`; stdout = devnull, stderr = devnull))
        end
    end

    @testset "a tela continua operável por leitor de tela" begin
        # Nenhuma destas falhas produz status ≠ 200 nem exceção: a tela abre bonita e é
        # inoperável para quem não a enxerga. Como o formulário nasce em JavaScript, não
        # há HTML para inspecionar — o que dá para vigiar é a presença das construções
        # que produzem a semântica. É a mesma estratégia da paleta e dos ids.
        publico = A.dir_publico()
        html = read(joinpath(publico, "index.html"), String)
        js   = read(joinpath(publico, "app.js"), String)
        css  = read(joinpath(publico, "app.css"), String)

        # A barra de status é o único retorno de "Dimensionar" e de campo recusado.
        # Sem região viva, o leitor de tela não anuncia nada ao usuário.
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
        # uma coluna de Leff por caso, além das 7 fixas
        cab = only(filter(l -> startswith(l, "d (mm);"), linhas))
        @test length(split(cab, ';')) == 7 + length(st.resultado.case_names)

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
        ordem = [String(id) for (id, _) in A.BLOCOS_MEMORIAL]
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
        for k in A.CHAVES_GLOBAIS
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
        @test startswith(A.desenho(st)["vaso"], "<svg")

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
        @test length(A.tabela(st)) == 9
        @test startswith(A.desenho(st)["vaso"], "<svg")
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

        esq = JSON3.read(String(HTTP.get("$base/api/esquema").body))
        @test length(esq.campos) > 10
        @test length(esq.ajustes) == length(A.CHAVES_GLOBAIS)
        # nenhum descritor pode chegar à tela sem rótulo e unidade
        @test all(c -> !isempty(c.label) && !isempty(c.unit), esq.campos)

        d = JSON3.read(String(HTTP.post("$base/api/dimensionar"; body = "{}").body))
        @test d.status_ok
        @test d.viavel
        # O caso de referência de config/cases/: quatro casos, dez cantos.
        @test d.cartao.d == "6300 mm"
        @test d.cartao.leff == "18,59 m"
        @test d.cartao.caso == "Fim de vida"
        @test startswith(d.desenho.vaso, "<svg")
        @test !isempty(d.grade)

        # mover o cursor troca a seleção sem redimensionar. É POST porque a rota
        # escreve `st.d_sel`, que é o diâmetro que a exportação desenha.
        x = JSON3.read(String(HTTP.post("$base/api/desenho";
                                        body = """{"d":"5500"}""").body))
        @test x.d_sel == 5500
        @test x.cartao.d != d.cartao.d
        @test startswith(x.desenho.vaso, "<svg")

        # E o verbo antigo não pode continuar servindo por acidente: um GET que
        # respondesse 200 aqui seria a porta que este POST existe para fechar.
        @test HTTP.get("$base/api/desenho?d=5500"; status_exception = false).status != 200

        # O memorial atravessando o handler — é aqui que um `using` ambíguo apareceria.
        # Antes do POST inválido logo abaixo, que troca o conjunto de casos inteiro.
        mem = JSON3.read(String(HTTP.get("$base/api/memorial").body))
        @test length(mem.casos) == 10          # o caso de referência: 4 casos → 10 cantos
        @test mem.governante == "Fim de vida"
        @test !isempty(mem.casos[1].blocos)
        @test occursin("Eq.", mem.casos[1].blocos[1].linhas[1])

        # --- conjuntos de casos ------------------------------------------
        lista = JSON3.read(String(HTTP.get("$base/api/casos/arquivos").body))
        @test any(a -> a.nome == "exemplo_alves_komesu.toml", lista.arquivos)
        @test lista.dir == TEMP_CASOS

        sv = JSON3.read(String(HTTP.post("$base/api/casos/salvar";
            body = """{"arquivo":"smoke_rota.toml","rotulo":"Pela rota"}""").body))
        @test sv.ok
        @test sv.arquivo == "smoke_rota.toml"
        @test isfile(joinpath(TEMP_CASOS, "smoke_rota.toml"))
        @test any(a -> a.nome == "smoke_rota.toml", sv.lista.arquivos)

        ab = JSON3.read(String(HTTP.post("$base/api/casos/abrir";
            body = """{"arquivo":"smoke_rota.toml"}""").body))
        @test ab.arquivo == "smoke_rota.toml"
        @test ab.status_ok
        @test length(ab.casos) == 4
        @test ab.viavel                       # abrir redimensiona, não só recarrega

        # Nome que sai da pasta: recusado, e com 200 — é erro do usuário, não do
        # transporte, então vira mensagem na barra como todo o resto.
        mau = JSON3.read(String(HTTP.post("$base/api/casos/salvar";
            body = """{"arquivo":"../fuga_rota.toml"}""").body))
        @test !mau.ok
        @test !isfile(joinpath(dirname(TEMP_CASOS), "fuga_rota.toml"))

        # Arquivo inexistente: mensagem, não 500.
        faltoso = HTTP.post("$base/api/casos/abrir";
            body = """{"arquivo":"nao_existe_mesmo.toml"}""", status_exception = false)
        @test faltoso.status == 200
        @test !JSON3.read(String(faltoso.body)).status_ok

        # Origem alheia nas rotas que escrevem. O servidor escuta em 127.0.0.1: um
        # `<form>` numa página qualquer posta para cá sem preflight de CORS, e o
        # `Origin` é o que separa isso de um clique na janela do programa.
        for (rota, corpo) in ("/api/casos/salvar" => """{"arquivo":"invasor.toml"}""",
                              "/api/casos/abrir"  => """{"arquivo":"smoke_rota.toml"}""",
                              "/api/exportar"     => "{}")
            alheia = HTTP.post(base * rota, ["Origin" => "http://exemplo.invalido"];
                               body = corpo, status_exception = false)
            @test alheia.status == 403
        end
        @test !isfile(joinpath(TEMP_CASOS, "invasor.toml"))

        # A origem da própria janela passa...
        propria = HTTP.post("$base/api/casos/salvar",
                            ["Origin" => "http://127.0.0.1:$porta"];
                            body = """{"arquivo":"smoke_rota.toml","rotulo":"Pela rota"}""",
                            status_exception = false)
        @test propria.status == 200

        # ...e leitura não é afetada: um GET não muda nada de qualquer forma.
        @test HTTP.get("$base/api/casos/arquivos",
                       ["Origin" => "http://exemplo.invalido"];
                       status_exception = false).status == 200

        # entrada inválida vira aviso em português, não erro 500
        ruim = JSON3.read(String(HTTP.post("$base/api/dimensionar";
            body = """{"casos":[{"name":"X","enabled":true,
                       "lo":{"q_oil":"não é número"},"hi":{}}]}""").body))
        @test haskey(ruim, :avisos)
        @test occursin("ilegível", ruim.avisos[1].msg)

        expo = JSON3.read(String(HTTP.post("$base/api/exportar"; body = "{}").body))
        @test expo.ok
        @test length(expo.arquivos) == 6

        try
            A.Genie.down()
        catch
        end
    end
end

rm(TEMP_SAIDA; recursive = true, force = true)
rm(TEMP_CASOS; recursive = true, force = true)
