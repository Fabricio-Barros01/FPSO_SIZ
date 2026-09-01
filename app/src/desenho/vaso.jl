"""
Desenho do vaso em SVG: elevação (vista lateral) e seção transversal (corte A-A).

Porte direto de `views/vessel_draw.jl` da versão Makie — mesma geometria, mesmas cotas,
mesmos rótulos; troca-se `poly!`/`lines!`/`text!` por `<polygon>`/`<polyline>`/`<text>`.
Os limites de cada vista são os mesmos que o `limits!` do Makie usava, para que a
composição na tela não mude.

Uma coisa melhora na troca: no Makie o `fontsize` era em pixels e não encolhia junto com
o eixo, o que obrigava a mandar as cotas `hₒ`/`h_w` para fora do corte
(nota em `vessel_draw.jl:365`). No SVG o texto escala com o `viewBox`, então elas voltam
para o lado do desenho, onde se lêem junto com a altura que descrevem.
"""

const TRACEJADO = "6 4"
const PONTILHADO = "1.5 3"

# ---------------------------------------------------------------------------
# Elevação
# ---------------------------------------------------------------------------

"""
    svg_elevacao(g; larg) -> String

Vista lateral completa. `g` é o `NamedTuple` de [`geometry_from`](@ref); `g.ok == false`
devolve um SVG vazio com a mensagem, sem exceção.
"""
function svg_elevacao(g; larg::Real = 920.0)
    g.ok || return documento_vazio(larg, 300, "Sem resultado — dimensione primeiro.")

    hd = head_depth(g.d_m)
    # A folga inferior é maior que a do Makie (0,32 d): os rótulos dos bocais de fundo
    # ficam em −0,12 d e as cotas foram empurradas para baixo deles, senão a linha de
    # `Leff` cruza as palavras "água" e "óleo".
    t = tela_proporcional(-hd - g.d_m * 0.34, -g.d_m * 0.44,
                          g.lss_m + hd + g.d_m * 0.12, g.d_m * 1.34; larg)

    p = String[]
    zonas_elevacao!(p, t, g)
    casco_elevacao!(p, t, g)
    rotulos_zona!(p, t, g)
    internos!(p, t, g)
    bocais!(p, t, g)
    cotas!(p, t, g)

    return documento(t, join(p);
                     rotulo = "Elevação do separador, d = $(Formato.inteiro(g.d_m * 1000)) mm")
end

"As fases como faixas horizontais que acompanham os tampos — duas ou três, conforme o vaso."
function zonas_elevacao!(p, t, g)
    for c in g.camadas
        push!(p, poligono(t, hull_band(g.d_m, g.lss_m, c.y0, c.y1);
                          preenche = c.zona, opacidade = c.opacidade))
    end
    return p
end

"Contorno do casco, nível de líquido, interface óleo/água e as soldas casco/tampo."
function casco_elevacao!(p, t, g)
    # Uma linha no topo de cada faixa que a declare. A fase gasosa não declara nenhuma:
    # o topo dela é o próprio casco, desenhado logo abaixo.
    for c in g.camadas
        isempty(c.interface) && continue
        l, r = hull_profile(g.d_m, g.lss_m, c.y1)
        push!(p, segmento(t, (l, c.y1), (r, c.y1); traco = c.interface, largura = 1.8,
                          estilo = c.tracejada ? TRACEJADO : nothing))
    end

    push!(p, poligono(t, hull_band(g.d_m, g.lss_m, 0.0, g.d_m);
                      preenche = "none", traco = Formato.ACO, largura = 2.2))

    for x in (0.0, g.lss_m)
        push!(p, segmento(t, (x, 0.0), (x, g.d_m); traco = Formato.ACO,
                          largura = 0.9, estilo = PONTILHADO))
    end
    return p
end

"""
    rotulos_zona!(p, t, g)

Nomeia cada faixa dentro do desenho. Uma faixa pode ficar fina demais para caber o
rótulo — a de óleo some quando a corrente é rica em água (β pequeno) — e nesse caso o
nome vai para fora, com linha de chamada, em vez de sumir dentro de dois pixels.

O critério é a espessura da faixa, não qual fase ela é: num vaso bifásico a faixa de
líquido é metade do vaso e nunca precisa disso, e num trifásico qualquer uma das três
pode precisar.
"""
function rotulos_zona!(p, t, g)
    x_rot = g.lss_m * 0.30
    nivel = g.d_m / 2

    for c in g.camadas
        if altura(c) > g.d_m * 0.055
            push!(p, texto(t, (x_rot, meio(c)), c.nome;
                           tam = 13, cor = c.rotulo, peso = "bold"))
        else
            x = g.lss_m * 0.62
            y_alvo = nivel + g.d_m * 0.17
            push!(p, segmento(t, (x, meio(c)), (x, y_alvo); traco = c.cor, largura = 1.2))
            push!(p, marcador(t, (x, meio(c)); raio = 2.6, preenche = c.cor))
            push!(p, texto(t, (x, y_alvo), "$(c.nome) — $(Formato.num(altura(c))) m";
                           tam = 12, cor = c.cor, base = "auto", peso = "bold"))
        end
    end
    return p
end

"""
    cotas!(p, t, g)

Cotas de `d` (vertical, à esquerda), `Leff` (da entrada à placa vertedora) e `Lss`
(costura a costura). São as três grandezas que o modelo devolve — vê-las no desenho é
o que liga a tabela de resultados à geometria.
"""
function cotas!(p, t, g)
    tick = g.d_m * 0.035
    x_d = -head_depth(g.d_m) - g.d_m * 0.16

    push!(p, segmento(t, (x_d, 0.0), (x_d, g.d_m); traco = Formato.TINTA_FRACA))
    for y in (0.0, g.d_m)
        push!(p, segmento(t, (x_d - tick, y), (x_d + tick, y); traco = Formato.TINTA_FRACA))
    end
    push!(p, texto(t, (x_d - g.d_m * 0.04, g.d_m / 2),
                   "d = $(Formato.inteiro(g.d_m * 1000)) mm";
                   tam = 12, cor = Formato.TINTA_FRACA, giro = -90))

    for (i, (valor, rotulo, cor)) in enumerate((
            (g.leff_m, "Leff = $(Formato.num(g.leff_m)) m", Formato.DESTAQUE),
            (g.lss_m,  "Lss = $(Formato.num(g.lss_m)) m",   Formato.TINTA_FRACA)))
        y = -g.d_m * (i == 1 ? 0.22 : 0.33)
        push!(p, segmento(t, (0.0, y), (valor, y); traco = cor))
        for x in (0.0, valor)
            push!(p, segmento(t, (x, y - tick), (x, y + tick); traco = cor))
        end
        push!(p, texto(t, (valor / 2, y - tick), rotulo;
                       tam = 12, cor = cor, base = "hanging"))
    end
    return p
end

"""
    internos!(p, t, g)

Internos esquemáticos: defletor de entrada, extrator de névoa e a **placa vertedora**
(weir) do óleo, posicionada em `Leff` — que é justamente a distância que a Eq. 22
dimensiona. O modelo assume o vaso meio cheio e sem controladores de nível, então os
internos são representativos, não dimensionados.
"""
function internos!(p, t, g)
    nivel = g.d_m / 2

    e = g.d_m * 0.012
    push!(p, poligono(t, [(g.leff_m - e, 0.0), (g.leff_m + e, 0.0),
                          (g.leff_m + e, nivel), (g.leff_m - e, nivel)];
                      preenche = Formato.INTERNO))
    push!(p, texto(t, (g.leff_m, nivel), "placa vertedora";
                   tam = 10, cor = Formato.INTERNO, base = "auto", dy = -5))

    x, e2 = g.lss_m * 0.07, g.d_m * 0.010
    push!(p, poligono(t, [(x - e2, g.d_m * 0.50), (x + e2, g.d_m * 0.50),
                          (x + e2, g.d_m * 0.90), (x - e2, g.d_m * 0.90)];
                      preenche = Formato.INTERNO))

    x1, x2 = g.lss_m * 0.82, g.lss_m * 0.93
    y1, y2 = g.d_m * 0.70, g.d_m * 0.88
    push!(p, poligono(t, [(x1, y1), (x2, y1), (x2, y2), (x1, y2)];
                      preenche = Formato.ACO, opacidade = 0.30,
                      traco = Formato.INTERNO, largura = 1))
    push!(p, texto(t, (g.lss_m * 0.875, y2), "extrator de névoa";
                   tam = 10, cor = Formato.INTERNO, base = "auto", dy = -4))
    return p
end

"Bocais de entrada e saída, esquemáticos."
function bocais!(p, t, g)
    d, L = g.d_m, g.lss_m
    w, h = d * 0.035, d * 0.07
    caixas = ((L * 0.03, d, "entrada", d * 1.10),        # topo esquerdo
              (L * 0.97, d, "gás", d * 1.10),            # topo direito
              (L * 0.99, -h, "óleo", -d * 0.12),         # fundo direito (após a placa)
              (L * 0.05, -h, "água", -d * 0.12))         # fundo esquerdo

    for (x, y, nome, y_rot) in caixas
        push!(p, poligono(t, [(x - w, y), (x + w, y), (x + w, y + h), (x - w, y + h)];
                          preenche = "none", traco = Formato.ACO, largura = 1.6))
        push!(p, texto(t, (x, y_rot), nome; tam = 10, cor = Formato.TINTA_FRACA))
    end
    return p
end

# ---------------------------------------------------------------------------
# Seção transversal
# ---------------------------------------------------------------------------

"""
    svg_corte(g; larg) -> String

Corte A-A: as mesmas zonas, com as cotas `hₒ`, `h_w` e o nível — é aqui que β deixa de
ser um número e vira uma altura. O espaço à direita do círculo, que no Makie ficava
vazio, recebe as cotas.
"""
function svg_corte(g; larg::Real = 460.0)
    g.ok || return documento_vazio(larg, 240, "Sem resultado.")

    R = g.d_m / 2
    # A folga à direita (até 2,6 R) é a coluna das cotas — dimensionada para o rótulo
    # mais largo, "nível = 3,15 m (50 %)".
    t = tela_proporcional(-R * 1.12, -R * 0.10, R * 2.60, g.d_m * 1.06; larg)
    nivel = g.d_m / 2

    p = String[]
    for c in g.camadas
        push!(p, poligono(t, circle_band(g.d_m, c.y0, c.y1);
                          preenche = c.zona, opacidade = c.opacidade))
    end
    push!(p, poligono(t, circle_band(g.d_m, 0.0, g.d_m);
                      preenche = "none", traco = Formato.ACO, largura = 2))

    meia_corda(y) = sqrt(max(R^2 - (y - R)^2, 0.0))
    for c in g.camadas
        isempty(c.interface) && continue
        x = meia_corda(c.y1)
        push!(p, segmento(t, (-x, c.y1), (x, c.y1); traco = c.interface, largura = 1.5,
                          estilo = c.tracejada ? TRACEJADO : nothing))
    end

    # Cotas à direita, com linha de chamada do círculo até a coluna de rótulos.
    #
    # Numa corrente rica em água β é pequeno (0,03 no caso de referência): a camada de
    # óleo tem centímetros, e `hₒ` cairia exatamente em cima de `nível`. Os rótulos são
    # afastados na tela por `espalhar`, e a linha de chamada continua apontando para a
    # altura verdadeira — a cota lê-se sem ambiguidade e o desenho segue exato.
    x_cota = R * 1.20
    cotas = Tuple{Float64,String,String}[]
    for c in g.camadas
        c.nome == "GÁS" && continue          # o gás ocupa o que sobra; não se cota
        push!(cotas, (meio(c), "$(c.nome) = $(Formato.num(altura(c))) m", c.cor))
    end
    push!(cotas, (nivel, "nível = $(Formato.num(nivel)) m  (50 %)", Formato.INTERNO))
    ys_px = espalhar([paray(t, c[1]) for c in cotas], 15.0)

    for ((y, rotulo, cor), y_px) in zip(cotas, ys_px)
        x_px = parax(t, x_cota)
        a = para(t, (meia_corda(clamp(y, 0.0, g.d_m)), y))
        push!(p, string("<polyline ",
                        atrs("points" => "$(svgn(a[1])),$(svgn(a[2])) " *
                                         "$(svgn(x_px - 6)),$(svgn(y_px)) " *
                                         "$(svgn(x_px)),$(svgn(y_px))",
                             "fill" => "none", "stroke" => cor, "stroke-width" => 0.8,
                             "stroke-dasharray" => PONTILHADO), "/>"))
        push!(p, texto_px(x_px + 4, y_px, rotulo; tam = 11, cor = cor, ancora = "start"))
    end
    # β só existe onde há duas fases líquidas a repartir a metade inferior. Num vaso
    # bifásico ele é `NaN` (ver `VesselConstraints`), e escrever "β = —" seria anunciar
    # a ausência de uma grandeza que não faz parte daquele modelo.
    isfinite(g.beta) &&
        push!(p, texto(t, (x_cota, g.d_m * 0.92), "β = hₒ/d = $(Formato.num(g.beta, 4))";
                       tam = 11, cor = Formato.TINTA, ancora = "start", dx = 4,
                       peso = "bold"))

    return documento(t, join(p); rotulo = "Corte transversal A-A")
end
