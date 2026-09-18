"""
As folhas do memorial de cálculo, montadas a partir de três fontes e de mais nenhuma:

| fonte | o que ela dá | onde aparece |
|---|---|---|
| [`FPSOSiz.MemorialSpec`](@ref) | premissas, hipóteses, equações, critérios, conclusão | 02, 03, 04 |
| `ParameterSpec` + o canto governante | os dados de entrada e os seus valores | 02 |
| `CalcTrace` + `ResultField` | **todos** os números | 03, 04 |

Nenhum número é calculado aqui. Se um valor não está no rastro nem nos campos de
resultado, ele não entra no documento — o que aparece no lugar é travessão, e não um
número plausível. É a mesma decisão de `beta_atual` e de `stream_from_case`: um valor
inventado de aparência correta é pior que a ausência visível dele.

Este arquivo também não sabe o que é um separador trifásico. Trocar o `MemorialSpec`
troca o documento inteiro — é assim que os demais equipamentos entram, sem uma linha
daqui.
"""

# ---------------------------------------------------------------------------
# Formatação dos valores — uma vez só
# ---------------------------------------------------------------------------

"""
    _valor(f) -> String

O valor de um [`FPSOSiz.ResultField`](@ref) em texto, **sem** a unidade e **sem** o
✓/✗: no documento a unidade tem coluna própria e o veredito tem seção própria. A
formatação PT-BR é a de `Formato.num`, a mesma da tela — o documento e a tela não podem
arredondar diferente.
"""
_valor(f::FPSOSiz.ResultField) =
    f.value isa AbstractString ? f.value :
    isfinite(f.value) ? Formato.num(f.value, f.digits) : "—"

"""
    _situacao(f) -> String

`ATENDE` / `NÃO ATENDE` a partir do `status` que o **motor** calculou.

`:neutro` vira travessão, nunca `ATENDE`. Um campo neutro é um campo que não aprova nem
reprova nada, e carimbá-lo de aprovado seria exatamente a falha que um memorial não pode
ter: uma verificação que passa por feita sem ter sido.
"""
_situacao(f::FPSOSiz.ResultField) =
    f.status === :ok ? "ATENDE" : f.status === :erro ? "NÃO ATENDE" : "—"

"O campo de resultado cujo rótulo é `rotulo`, ou `nothing`."
function _campo(campos, rotulo::AbstractString)
    i = findfirst(f -> f.label == rotulo, campos)
    return i === nothing ? nothing : campos[i]
end

"Valor do rastro para uma equação, já formatado — travessão quando ela não foi resolvida."
function _valor_rastro(tr, numero::AbstractString)
    tr === nothing && return "—"
    es = FPSOSiz.entradas_do_rastro(tr, numero)
    isempty(es) && return "—"
    # As mesmas 5 casas do memorial em `.txt`, para que o documento e o arquivo exportado
    # não arredondem diferente o mesmo número.
    return join([string(escapa(e.var), " = ", Formato.num(e.value, 5),
                        isempty(e.unit) || e.unit == "–" ? "" : " " * escapa(e.unit))
                 for e in es], " · ")
end

"Cabeçalho numerado de seção, no formato do handoff."
secao(n::Integer, titulo::AbstractString; cont::Bool = false) =
    barra_secao("$n.  $titulo"; cont)

# ---------------------------------------------------------------------------
# Folha 01 — rosto
# ---------------------------------------------------------------------------

"""
    folha_rosto(spec, campos) -> Folha

A folha de rosto: bloco de título, identificação do objeto e o quadro de revisões.

O corpo é curto de propósito — o que a folha de rosto de um memorial faz é identificar o
documento e registrar quem o emitiu, revisou e aprovou. O resumo do resultado está aqui
porque é o que quem abre o documento procura primeiro, e sai dos **mesmos** campos que a
folha 04 tabula.

Não recebe o [`DocMeta`](@ref): os campos de identificação entram como os tokens
`{{doc.numero}}`, `{{doc.data}}` e `{{projeto.nome}}`, que [`resolver`](@ref) preenche
na montagem. Assim esta folha usa exatamente a mesma via do bloco de título, e um token
que sobre aqui quebra a emissão em vez de sair como célula vazia.
"""
function folha_rosto(spec::FPSOSiz.MemorialSpec, campos)
    destaque = filter(f -> f.highlight || f.status !== :neutro, campos)
    isempty(destaque) && (destaque = campos[1:min(3, length(campos))])

    linhas = [[escapa(f.label), escapa(_valor(f)), escapa(f.unit)] for f in destaque]

    corpo = string(
        secao(1, "IDENTIFICAÇÃO"),
        tabela_doc([("A:J", "CAMPO", "esq"), ("K:S", "CONTEÚDO", "esq"),
                    ("T:AB", "", "esq")],
                   [["Equipamento", escapa(spec.equipamento), ""],
                    ["Módulo", escapa(spec.sigla), ""],
                    ["Documento", "{{doc.numero}}", ""],
                    ["Revisão", "{{doc.revisao}}", ""],
                    ["Data de emissão", "{{doc.data}}", ""],
                    ["Projeto", "{{projeto.nome}}", ""],
                    ["Programa emissor", "FPSO_Siz", ""]]),
        secao(2, "RESUMO DO DIMENSIONAMENTO"),
        tabela_doc([("A:J", "GRANDEZA", "esq"), ("K:S", "VALOR", "dir"),
                    ("T:AB", "UNIDADE", "centro")], linhas),
        "<p class=\"aviso\">Este resumo repete, sem recalcular, os campos da folha de " *
        "resultados. O desenvolvimento completo do cálculo está nas folhas seguintes.</p>")

    return Folha(corpo; revisoes = true)
end

# ---------------------------------------------------------------------------
# Folha 02 — premissas, dados de entrada, hipóteses
# ---------------------------------------------------------------------------

"""
    folhas_premissas(spec, specs_entrada, valores) -> Vector{Folha}

Premissas de projeto e dados de entrada numa folha; hipóteses e limitações na seguinte.

São **duas** folhas, e não a única que o handoff desenha, porque o separador trifásico
tem dezessete entradas de corrente e método mais seis de decisão de projeto — contra as
treze linhas do gabarito — e quatro hipóteses que ocupam parágrafos. Partir aqui é a
regra de paginação do próprio handoff (ao estourar a faixa de conteúdo, abre-se outra
folha do mesmo tipo), e não uma licença: o que não se pode é encolher a fonte até caber
ou cortar uma hipótese.

Cada linha da tabela de entrada é um `ParameterSpec`: rótulo, a chave como símbolo, o
valor do canto governante, a unidade e a `note` — que é a proveniência que o descritor
carrega desde o Sprint 0 justamente para chegar até aqui.
"""
function folhas_premissas(spec::FPSOSiz.MemorialSpec, specs_entrada, valores)
    prem = [[escapa(p.item), escapa(p.texto), escapa(p.referencia)]
            for p in spec.premissas]

    entradas = map(specs_entrada) do s
        v = valores === nothing ? nothing : get(valores, s.key, nothing)
        texto = v === nothing ? "—" : Formato.num(v, Formato.casas_de(s))
        return [escapa(s.label), escapa(String(s.key)), escapa(texto),
                escapa(s.unit), escapa(s.note)]
    end

    f1 = Folha(string(
        secao(1, "PREMISSAS DE PROJETO"),
        tabela_doc([("A:B", "ITEM", "centro"), ("C:U", "PREMISSA DE PROJETO", "esq"),
                    ("V:AB", "REFERÊNCIA", "esq")], prem),
        secao(2, "DADOS DE ENTRADA"),
        tabela_doc([("A:J", "PARÂMETRO", "esq"), ("K:N", "SÍMBOLO", "centro"),
                    ("O:S", "VALOR", "dir"), ("T:V", "UNIDADE", "centro"),
                    ("W:AB", "FONTE", "esq")], entradas),
        valores === nothing ?
            "<p class=\"aviso\">Sem dimensionamento viável: os valores acima não " *
            "puderam ser associados a um caso governante.</p>" :
            "<p class=\"aviso\">Valores do caso governante — o cenário de operação que, " *
            "no diâmetro escolhido, impôs a maior exigência.</p>"))

    hip = string(
        secao(3, "HIPÓTESES E LIMITAÇÕES"),
        "<div class=\"hipoteses\">",
        join(["<p><b>H$i.</b> " * escapa(h) * "</p>"
              for (i, h) in enumerate(spec.hipoteses)]),
        "</div>")

    return [f1, Folha(hip)]
end

# ---------------------------------------------------------------------------
# Folha 03 — fórmulas
# ---------------------------------------------------------------------------

"""
    bloco_equacao(eq, n, tr) -> String

Um bloco da folha de fórmulas, na estrutura que o handoff fixa: barra de seção, a faixa
da equação por extenso (Times New Roman itálico), a barra `ONDE:`, a definição das
variáveis, a referência e a validade.

A linha `VALOR CALCULADO` é acréscimo a essa estrutura, e é o que transforma o gabarito
num memorial *de cálculo*: ela traz o que o motor obteve ao resolver **esta** equação,
lido do rastro. Sem ela a folha 03 seria um formulário em branco ao lado de uma folha
de resultados, e o leitor não teria como percorrer o caminho do meio — que é justamente
o que um memorial existe para mostrar.

Travessão quando a equação não foi resolvida neste caso: a variante geométrica da
Eq. 21 some quando não há água livre, e um zero ali seria um número que ninguém calculou.
"""
function bloco_equacao(eq::FPSOSiz.EquacaoDoc, n::Integer, tr)
    vars = join(["<li><span class=\"sim\">" * escapa(v.simbolo) * "</span> = " *
                 escapa(v.descricao) *
                 (isempty(v.unidade) ? "" : " (" * escapa(v.unidade) * ")") * "</li>"
                 for v in eq.variaveis])

    # `n.  Eq. 14 — Capacidade de gás`, e não `n.  EQUAÇÃO Eq. 14 — CAPACIDADE DE GÁS`:
    # o `numero` já começa com "Eq.", então o gabarito do handoff (`n. EQUAÇÃO (n) — …`)
    # sairia gaguejando. E a grandeza fica no caso em que foi escrita porque
    # `uppercase("β")` devolve `Β` — beta maiúsculo grego, que se lê como um B latino
    # e faria o bloco da Fig. 3 anunciar "COEFICIENTE B".
    return string(
        secao(n, eq.numero * " — " * eq.grandeza),
        "<div class=\"faixa-equacao\">", escapa(eq.notacao), "</div>",
        "<div class=\"barra-onde\">ONDE:</div>",
        "<ul class=\"variaveis\">", vars, "</ul>",
        tabela_doc([("A:S", "", "esq"), ("T:AB", "", "esq")],
                   [["<b>REFERÊNCIA DA EQUAÇÃO</b>", escapa(eq.referencia)],
                    ["<b>VALIDADE / CONDIÇÃO</b>",
                     isempty(eq.validade) ? "—" : escapa(eq.validade)],
                    ["<b>VALOR CALCULADO</b>", _valor_rastro(tr, eq.numero)]]))
end

"""
    folhas_formulas(spec, tr; por_folha) -> Vector{Folha}

As folhas de fórmulas, com os blocos repartidos sem partir nenhum — ver
[`paginar`](@ref). Quatro por folha é o que o protótipo do handoff mostra e o que cabe
com a definição de variáveis inteira.

A partir da segunda, o título da seção leva `(cont.)`, como a regra manda.
"""
function folhas_formulas(spec::FPSOSiz.MemorialSpec, tr; por_folha::Int = 4)
    grupos = paginar(spec.equacoes, por_folha)
    n = 0
    return map(enumerate(grupos)) do (k, grupo)
        blocos = String[]
        push!(blocos, barra_secao("DESENVOLVIMENTO DO CÁLCULO"; cont = k > 1))
        for eq in grupo
            n += 1
            push!(blocos, bloco_equacao(eq, n, tr))
        end
        return Folha(join(blocos))
    end
end

# ---------------------------------------------------------------------------
# Folha 04 — resultados, verificações, conclusão
# ---------------------------------------------------------------------------

"""
    folha_resultados(spec, campos) -> Folha

Os resultados do dimensionamento, as verificações e a conclusão.

A coluna `EQUAÇÃO` da tabela de resultados é o elo de rastreabilidade que o handoff
exige: ela amarra cada número desta folha ao bloco da folha 03 que o produziu. Quem
conferir o documento percorre o caminho inteiro sem sair dele — entrada (folha 02),
equação e intermediário (folha 03), resultado e verificação (esta).

O valor e a situação saem de `campos`, que é o **mesmo vetor** que o cartão da tela
desenha (ver `campos_resultado`). Um resultado declarado no `MemorialSpec` que não case
com nenhum campo vira travessão em vez de sumir: a linha ausente esconderia a
discordância, e o travessão a mostra.
"""
function folha_resultados(spec::FPSOSiz.MemorialSpec, campos)
    res = map(spec.resultados) do r
        f = _campo(campos, r.rotulo)
        return [escapa(r.rotulo), escapa(r.simbolo),
                f === nothing ? "—" : escapa(_valor(f)),
                f === nothing ? "—" : escapa(f.unit),
                escapa(r.equacao)]
    end

    ver = map(spec.verificacoes) do v
        f = _campo(campos, v.campo)
        sit = f === nothing ? "—" : _situacao(f)
        classe = sit == "ATENDE" ? "atende" : sit == "NÃO ATENDE" ? "nao-atende" : ""
        return [escapa(v.descricao),
                f === nothing ? "—" : escapa(_valor(f)),
                escapa(v.criterio), escapa(v.unidade),
                "<b class=\"$classe\">" * sit * "</b>"]
    end

    return Folha(string(
        secao(1, "RESULTADOS DO DIMENSIONAMENTO"),
        tabela_doc([("A:J", "GRANDEZA CALCULADA", "esq"), ("K:N", "SÍMBOLO", "centro"),
                    ("O:S", "VALOR", "dir"), ("T:V", "UNIDADE", "centro"),
                    ("W:AB", "EQUAÇÃO", "centro")], res),
        secao(2, "VERIFICAÇÕES"),
        tabela_doc([("A:J", "VERIFICAÇÃO", "esq"), ("K:N", "CALCULADO", "dir"),
                    ("O:S", "CRITÉRIO / LIMITE", "dir"), ("T:V", "UNIDADE", "centro"),
                    ("W:AB", "SITUAÇÃO", "centro")], ver),
        secao(3, "CONCLUSÃO"),
        "<div class=\"conclusao\"><p>", escapa(spec.conclusao), "</p></div>"))
end

# ---------------------------------------------------------------------------
# Folhas de figuras
# ---------------------------------------------------------------------------

"""
    folhas_figuras(figuras) -> Vector{Folha}

As figuras do equipamento, duas por folha, em continuação da folha de resultados.

São as **mesmas** SVG que a tela mostra — `figuras_grandes` —, e não um segundo desenho:
a elevação com as cotas, a seção transversal com as camadas de fase, e os dois gráficos
de varredura. Vetoriais, então imprimem na resolução da impressora em vez de na de um
bitmap.

Vazio quando o método não declara figura nenhuma; o documento simplesmente não ganha
estas folhas, em vez de ganhar páginas em branco.
"""
function folhas_figuras(figuras)
    isempty(figuras) && return Folha[]
    return map(enumerate(paginar(figuras, 2))) do (k, grupo)
        blocos = String[barra_secao("FIGURAS"; cont = k > 1)]
        for f in grupo
            titulo = isempty(f["titulo"]) ? "" :
                     "<h3 class=\"legenda-figura\">" * escapa(f["titulo"]) * "</h3>"
            push!(blocos, string("<figure class=\"figura\">", titulo,
                                 "<div class=\"svg\">", f["svg"], "</div>",
                                 f["legenda"], "</figure>"))
        end
        # `tokens = false`: o SVG carrega os nomes dos casos, que são do usuário. Ver a
        # nota de `Folha` em documento.jl.
        return Folha(join(blocos); tokens = false)
    end
end

# ---------------------------------------------------------------------------
# O documento inteiro
# ---------------------------------------------------------------------------

"""
    memorial_documento(st; meta_extra) -> String

O memorial de cálculo completo do estado atual, em HTML imprimível.

Lança quando o método não declara [`FPSOSiz.memorial_spec`](@ref) — a rota transforma
em mensagem. É de propósito: um documento de quatro folhas com o carimbo do SENAI e
nenhuma equação é pior que a recusa.

O ponto documentado é o do **cursor**, via `campos_resultado` — a mesma função que
desenha o cartão. Quem arrasta o cursor e manda imprimir recebe o documento do vaso que
está vendo, e não de outro.
"""
function memorial_documento(st::AppState; meta_extra::AbstractDict = Dict{String,String}())
    spec = FPSOSiz.memorial_spec(st.metodo)
    spec === nothing && error(
        "O método '$(FPSOSiz.label(st.metodo))' ainda não declara memorial de cálculo " *
        "documental (memorial_spec). Nada a emitir.")

    campos = campos_resultado(st)
    valores = valores_governantes(st)
    tr = rastro_governante(st)
    meta = doc_meta(st, spec; extra = meta_extra)

    folhas = Folha[]
    push!(folhas, folha_rosto(spec, campos))
    append!(folhas, folhas_premissas(spec, vcat(st.campos, st.ajustes), valores))
    append!(folhas, folhas_formulas(spec, tr))
    push!(folhas, folha_resultados(spec, campos))
    append!(folhas, folhas_figuras(figuras_grandes(st)))

    return documento_html(meta, folhas;
                          titulo_pagina = numero_documento(meta) * " — " * spec.titulo)
end

"""
    doc_meta(st, spec; extra) -> DocMeta

Os metadados do documento: o que vem do `MemorialSpec` (sigla, título), o que vem do
estado da tela (o projeto é o rótulo do conjunto de casos aberto), o que vem do relógio
(a data) e o que só quem está emitindo sabe.

`extra` são os campos que a consulta da rota pode sobrescrever. Tudo o que não for dado
fica em `A DEFINIR`, nunca num nome plausível — ver [`DocMeta`](@ref).
"""
function doc_meta(st::AppState, spec::FPSOSiz.MemorialSpec;
                  extra::AbstractDict = Dict{String,String}())
    pega(k, padrao) = begin
        v = strip(String(get(extra, k, "")))
        isempty(v) ? padrao : v
    end
    projeto = isempty(st.rotulo) ? (isempty(st.arquivo) ? A_DEFINIR : st.arquivo) :
                                   st.rotulo
    return DocMeta(
        spec.sigla,
        pega("seq", "001"),
        pega("rev", "0"),
        spec.titulo,
        spec.equipamento,
        pega("cliente", A_DEFINIR),
        pega("projeto", projeto),
        pega("unidade", A_DEFINIR),
        pega("executor", A_DEFINIR),
        Dates.format(Dates.today(), "dd/mm/yyyy"),
    )
end
