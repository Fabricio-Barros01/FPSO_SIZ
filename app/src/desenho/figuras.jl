"""
Quais figuras cada equipamento mostra, e onde.

O desenho de um vaso não serve a uma bomba, e o de uma bomba não serve a um trocador —
mas os três precisam do mesmo enquadramento: uma figura grande, uma pequena ao lado da
legenda de fases, e a faixa de gráficos embaixo. Então a tela declara **áreas**, e cada
método declara o que põe em cada uma.

| área | o vaso põe | a bomba põe | o trocador põe |
|---|---|---|---|
| `principal` | elevação com as cotas | esquema hidráulico da linha | corte do casco |
| `secundaria` | seção transversal | — | — |
| `grafico` | `Leff × d` e `SR × d` | `H × DN` e `v × DN` | `L × N` e `v × N` |

As figuras chegam à tela como uma **lista**, não como quatro `id` fixos: `index.html`
trazia `fig-vaso`, `fig-corte`, `fig-leff` e `fig-sr` escritos à mão, o que fixava
tanto a quantidade quanto o assunto. Um método que só tenha dois gráficos não deixa dois
buracos, e um que tenha três não precisa de HTML novo.

O fallback genérico desenha só o gráfico de envelope. É pouco, mas é o gráfico que
comunica o multi-caso — e é o que um equipamento novo ganha **sem escrever nada aqui**,
que é o ponto.
"""

"""
Uma figura: onde vai, como se chama, o SVG e a legenda que a acompanha.

`legenda` é HTML e quase sempre vazia. A exceção é a seção transversal do vaso, cujas
três amostras de cor (gás, óleo, água) não fazem sentido sozinhas — e não fazem sentido
nenhum numa bomba, que é por que elas deixaram de estar escritas em `index.html`.
"""
function figura(id, area, titulo, svg; legenda::AbstractString = "",
                modelo3d = nothing)
    f = Dict{String,Any}("id" => String(id), "area" => String(area),
                         "titulo" => String(titulo), "svg" => svg,
                         "legenda" => legenda)
    modelo3d === nothing || (f["modelo3d"] = modelo3d)
    return f
end

"""
    modelo_3d(m) -> String

Qual modelo o visor 3D constrói para este método — `""` quando não há nenhum.

Despacha no método, como [`figuras`](@ref) logo abaixo, e pela mesma razão: quem sabe
que um casco horizontal meio cheio com placa vertedora é um separador trifásico é o
método, não a tela. O visor recebe o nome e constrói; `app.js` nunca o escreve.

O default é `""`, e é o que faz um equipamento sem modelo continuar mostrando só a
figura SVG em vez de montar um visor vazio. Os três vasos da família Stewart & Arnold
têm modelo; a bomba e o trocador têm arquivo no handoff mas ainda não foram conferidos
contra o desenho deles, então seguem sem — prometer um 3D que ninguém validou é pior que
não oferecê-lo.
"""
modelo_3d(::FPSOSiz.AbstractSizingMethod) = ""
modelo_3d(::FPSOSiz.StewartArnold) = "separador"
modelo_3d(::FPSOSiz.StewartArnoldTwoPhase) = "knockout"
modelo_3d(::FPSOSiz.ArnoldElectrostatic) = "tratador"
modelo_3d(::FPSOSiz.MoranPumpSizing) = "bomba"
modelo_3d(::FPSOSiz.SaariLMTD) = "trocador"

"""
    atributos_3d(m, g, camadas) -> Dict | nothing

Os atributos que o visor 3D lê, **todos derivados do que o motor calculou**: o diâmetro,
o comprimento entre costuras, o comprimento efetivo (onde fica a placa vertedora), o β
da interface líquido-líquido e a fração de enchimento.

`nivel` sai das [`FPSOSiz.PhaseLayer`](@ref) que o método declara em `cross_section` — é
1 menos a fração de gás —, e não de um `0,5` escrito aqui. Era exatamente essa dedução
("vaso meio cheio") que punha metade de céu de gás num tratador cheio de líquido, e que
`cross_section` nasceu para corrigir; repeti-la no visor 3D reintroduziria o defeito em
três dimensões.

`nothing` sem resultado viável: o visor não monta e a figura SVG (que já sabe se
desenhar vazia) fica no lugar.
"""
function atributos_3d(m::FPSOSiz.AbstractSizingMethod, g, camadas)
    nome = modelo_3d(m)
    (isempty(nome) || !g.ok) && return nothing
    gasosa = sum(c.fracao for c in camadas if c.fase === :gas; init = 0.0)
    return Dict{String,Any}(
        "modelo" => nome,
        # Chaves minúsculas porque viram ATRIBUTO de elemento HTML, que é
        # case-insensitive e chega em minúsculas do outro lado.
        "atributos" => Dict{String,Any}(
            "d"     => g.d_m,
            "lss"   => g.lss_m,
            "leff"  => g.leff_m,
            "beta"  => isfinite(g.beta) ? g.beta : 0.0,
            "nivel" => clamp(1.0 - gasosa, 0.0, 1.0),
            "fases" => isempty(camadas) ? "false" : "true"))
end

"""
    modelo3d_de(m, atributos) -> Dict | nothing

O envelope que o visor 3D recebe, para os métodos que **não** são vaso: a bomba e o
trocador não têm `geometry_from`, `PhaseLayer` nem β, então [`atributos_3d`](@ref) não
os serve.

`nothing` quando o método não declara modelo, e é assim que a bomba e o trocador ficavam
até aqui: prometer um 3D que ninguém conferiu contra a elevação é pior que não oferecê-lo.

O que os liberou foi a conferência, e ela é simples de enunciar: **o 3D lê exatamente as
mesmas grandezas que a elevação SVG desenha**, do mesmo ponto do cursor. Na bomba é o DN
(`svg_linha_bomba(d, dn, h)`); no trocador são os tubos por passe, o comprimento e o
número de passes (`svg_trocador(d, l, passes)`). Nenhum dos dois recalcula nada, que é a
mesma regra do vaso — e é ela que impede o 3D e a elevação de mostrarem equipamentos
diferentes.
"""
function modelo3d_de(m::FPSOSiz.AbstractSizingMethod, atributos::AbstractDict)
    nome = modelo_3d(m)
    isempty(nome) && return nothing
    return Dict{String,Any}("modelo" => nome,
                            "atributos" => Dict{String,Any}(atributos))
end

"""
    legenda_fases(g) -> String

As amostras de cor das fases presentes no corte. Duas num vaso bifásico, três num
trifásico — as mesmas [`Camada`](@ref) que o desenho usou, então a legenda não pode
prometer uma fase que a figura não mostra.
"""
function legenda_fases(g)
    g.ok && !isempty(g.camadas) || return ""
    # A cor da amostra é a MESMA do desenho, opacidade inclusive: uma legenda com cor
    # aproximada é pior que nenhuma, porque convida a comparar e erra a comparação.
    itens = [string("<li><span class=\"amostra\" style=\"background:", escapa(c.zona),
                    ";opacity:", svgn(c.opacidade), "\"></span>",
                    escapa(lowercase(c.nome)), "</li>")
             for c in Iterators.reverse(g.camadas)]
    return string("<ul class=\"legenda-fases\">", join(itens), "</ul>")
end

"""
    figuras(st; larg_extra) -> Vector{Dict}

As figuras deste equipamento, na ordem em que a tela as coloca. Despacha no método:
quem sabe o que se está dimensionando é ele.
"""
figuras(st::AppState) = figuras(st.metodo, st)

"""
    figuras(m, st) -> Vector{Dict}

Fallback para um método que ainda não declarou desenho próprio: o gráfico de envelope,
que existe para qualquer eixo, e nada mais. Sem esquema inventado — uma figura genérica
de "equipamento" seria decoração, e decoração num relatório técnico é ruído.
"""
function figuras(m::FPSOSiz.AbstractSizingMethod, st::AppState)
    eixo = FPSOSiz.sweep_axis(m, st.globais)
    # O rótulo do eixo y sai de `requirement_spec`, e não de uma string vazia: o gráfico
    # sem ele mostra uma curva sem dizer de quê.
    rot, un = FPSOSiz.requirement_spec(m)
    return [figura("envelope", "grafico", "Exigência por caso, e a envelope",
                   svg_grafico_envelope(st.resultado, st.d_sel;
                                        titulo = "Exigência por caso, e a envelope",
                                        xlabel = "$(eixo.label) ($(eixo.unit))",
                                        ylabel = isempty(un) ? rot : "$rot ($un)"))]
end

"""
    _linha_cursor(st) -> (derivados, x, y)

O ponto que o cursor aponta, ou vazio quando não há varredura. Existe porque as três
famílias de figura precisam do mesmo recorte, e cada uma o obteria de um jeito.
"""
function _linha_cursor(st::AppState)
    r = st.resultado
    l = linha_sel(r, st.d_sel)
    l === nothing && return (Dict{Symbol,Float64}(), NaN, NaN)
    return (l.derivados, l.x, l.y)
end

"""
    figuras(m::MoranPumpSizing, st) -> Vector{Dict}

As três da bomba: o esquema da linha com as cotas, a envelope de carga e a banda de
velocidade.

O segundo gráfico é `svg_grafico_banda` com `:v` no lugar de `:sr` — a mesma função que
o vaso usa para a esbeltez, que é o que o Sprint 7 a soltou da grandeza para permitir.
"""
function figuras(m::FPSOSiz.MoranPumpSizing, st::AppState; larg_principal = 900.0)
    d, x, y = _linha_cursor(st)
    banda = (st.globais[:v_min], st.globais[:v_max])
    alvo = (banda[1] + banda[2]) / 2
    return [
        # O 3D lê o MESMO DN que a elevação cota — ver `modelo3d_de`.
        figura("linha", "principal", _titulo_bomba(x, y),
               svg_linha_bomba(d, x, y; larg = larg_principal);
               modelo3d = isfinite(x) ? modelo3d_de(m, Dict("dn" => x)) : nothing),
        figura("envelope", "grafico", "", svg_grafico_envelope(
            st.resultado, st.d_sel;
            titulo = "Carga do sistema exigida por caso, e a envelope",
            xlabel = "diâmetro nominal DN (mm)", ylabel = "H (m)")),
        figura("banda", "grafico", "", svg_grafico_banda(
            st.resultado, st.d_sel, :v, banda, alvo;
            titulo = "Velocidade na linha e a banda recomendada",
            xlabel = "diâmetro nominal DN (mm)", ylabel = "v (m/s)")),
    ]
end

_titulo_bomba(x, y) = isfinite(x) ?
    "Linha de recalque — DN = $(Formato.inteiro(x)) mm · H = $(Formato.num(y)) m" :
    "Linha de recalque — sem resultado"

"""
    figuras(m::SaariLMTD, st) -> Vector{Dict}

As três do trocador: o corte do casco, a envelope de comprimento de tubo e a banda de
velocidade no tubo.
"""
function figuras(m::FPSOSiz.SaariLMTD, st::AppState; larg_principal = 900.0)
    d, x, y = _linha_cursor(st)
    banda = (st.globais[:v_min], st.globais[:v_max])
    passes = clamp(round(Int, get(d, :passes, 1.0)), 1, 2)
    return [
        # As mesmas três grandezas do corte SVG: tubos por passe, comprimento e passes.
        # A chave é `n-tubos` com hífen porque vira ATRIBUTO de elemento HTML.
        figura("trocador", "principal", _titulo_trocador(x, y),
               svg_trocador(d, y, passes; larg = larg_principal);
               modelo3d = isfinite(x) && isfinite(y) ?
                          modelo3d_de(m, Dict("n-tubos" => x, "l" => y,
                                              "passes" => passes)) : nothing),
        figura("envelope", "grafico", "", svg_grafico_envelope(
            st.resultado, st.d_sel;
            titulo = "Comprimento de tubo exigido por caso, e a envelope",
            xlabel = "tubos por passe", ylabel = "L (m)")),
        figura("banda", "grafico", "", svg_grafico_banda(
            st.resultado, st.d_sel, :v, banda, (banda[1] + banda[2]) / 2;
            titulo = "Velocidade no tubo e a banda da Tabela 3.1",
            xlabel = "tubos por passe", ylabel = "v (m/s)")),
    ]
end

_titulo_trocador(x, y) = isfinite(x) ?
    "Casco-e-tubos — $(Formato.inteiro(x)) tubos/passe · L = $(Formato.num(y)) m" :
    "Casco-e-tubos — sem resultado"

"""
    figuras(m::AbstractVesselMethod, st) -> Vector{Dict}

As quatro do vaso: elevação, seção transversal e os dois gráficos.

A banda do segundo gráfico vem de `st.globais`, que são os ajustes que o usuário
controla — e não de constantes daqui. Se ele apertar a banda, o sombreado acompanha.
"""
function figuras(m::FPSOSiz.AbstractVesselMethod, st::AppState)
    camadas = camadas_atual(st)
    g = geometry_from(st.resultado, st.d_sel, camadas, beta_atual(st))
    banda = (st.globais[:sr_min], st.globais[:sr_max])
    return [
        # A elevação SVG continua sendo a figura — é ela que carrega as COTAS, e é ela
        # que vai para o memorial impresso. O modelo 3D viaja ao lado, como melhoria
        # progressiva: a tela monta o visor quando o navegador tem WebGL e fica com o
        # SVG quando não tem. Nenhum dos dois é recalculado — os dois leem a mesma
        # geometria de `geometry_from`.
        figura("vaso", "principal", titulo_elevacao(g), svg_elevacao(g);
               modelo3d = atributos_3d(m, g, camadas)),
        figura("corte", "secundaria", "Seção transversal", svg_corte(g);
               legenda = legenda_fases(g)),
        figura("envelope", "grafico", "", svg_grafico_envelope(
            st.resultado, st.d_sel;
            titulo = "Comprimento efetivo exigido por caso, e a envelope",
            xlabel = "diâmetro d (mm)", ylabel = "Leff (m)")),
        figura("banda", "grafico", "", svg_grafico_banda(
            st.resultado, st.d_sel, :sr, banda, st.globais[:sr_target];
            titulo = "Esbeltez e a banda recomendada por Stewart & Arnold",
            xlabel = "diâmetro d (mm)", ylabel = "esbeltez SR = Lss/d")),
    ]
end

"Título da elevação, com as três medidas que ela mostra."
titulo_elevacao(g) = g.ok ?
    "Elevação — d = $(Formato.inteiro(g.d_m * 1000)) mm · " *
    "Lss = $(Formato.num(g.lss_m)) m · SR = $(Formato.num(g.sr))" :
    "Elevação — sem resultado"

"""
    figuras_exportadas(st) -> Vector{Pair{String,String}}

As mesmas figuras, em tamanho de relatório, com o sufixo de arquivo de cada uma.

Uma figura por arquivo. Concatenar dois `<svg>` num arquivo só daria dois elementos-raiz,
o que não é XML válido: o visualizador recusa o arquivo inteiro, não só a segunda figura.
"""
figuras_exportadas(st::AppState) =
    [("_" * f["id"] * ".svg") => f["svg"] for f in figuras_grandes(st)]

"As figuras redesenhadas em largura de relatório."
figuras_grandes(st::AppState) = figuras_grandes(st.metodo, st)

figuras_grandes(m::FPSOSiz.AbstractSizingMethod, st::AppState) = figuras(m, st)

# Os dois esquemas nascem em largura de tela; para o relatório eles só crescem — a
# geometria é fixa e a escala é do `viewBox`, então não há o que redesenhar.
figuras_grandes(m::FPSOSiz.MoranPumpSizing, st::AppState) =
    figuras(m, st; larg_principal = 1100.0)
figuras_grandes(m::FPSOSiz.SaariLMTD, st::AppState) =
    figuras(m, st; larg_principal = 1100.0)

function figuras_grandes(m::FPSOSiz.AbstractVesselMethod, st::AppState)
    g = geometry_from(st.resultado, st.d_sel, camadas_atual(st), beta_atual(st))
    banda = (st.globais[:sr_min], st.globais[:sr_max])
    return [
        figura("vaso", "principal", titulo_elevacao(g), svg_elevacao(g; larg = 1100)),
        figura("corte", "secundaria", "Seção transversal", svg_corte(g; larg = 520);
               legenda = legenda_fases(g)),
        figura("leff", "grafico", "", svg_grafico_envelope(
            st.resultado, st.d_sel; larg = 700, alt = 320,
            titulo = "Comprimento efetivo exigido por caso, e a envelope",
            xlabel = "diâmetro d (mm)", ylabel = "Leff (m)")),
        figura("sr", "grafico", "", svg_grafico_banda(
            st.resultado, st.d_sel, :sr, banda, st.globais[:sr_target];
            larg = 700, alt = 320,
            titulo = "Esbeltez e a banda recomendada por Stewart & Arnold",
            xlabel = "diâmetro d (mm)", ylabel = "esbeltez SR = Lss/d")),
    ]
end
