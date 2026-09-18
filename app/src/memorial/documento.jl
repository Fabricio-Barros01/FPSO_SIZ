"""
A infraestrutura documental do memorial de cálculo: a folha A4, o bloco de título, o
quadro de revisões, a paginação e a resolução de tokens.

**Compartilhada por todos os equipamentos.** O que muda de um para o outro é o
[`FPSOSiz.MemorialSpec`](@ref) — a sigla, o título, as equações, as verificações —, e
nada disto aqui sabe qual equipamento está sendo documentado. É a mesma divisão que o
resto do programa já faz: o método declara, a interface desenha.

## Geometria: o que se reproduz do handoff e o que não

A referência (`MC-SENAI-SEP-ENG-001-0.xlsx`) é uma planilha, e o handoff descreve como
reproduzi-la **numa planilha**: larguras de coluna em caracteres, alturas de linha em
pontos, mesclagens, e o ajuste `fitToWidth`/`fitToHeight` que encolhe a folha inteira
para caber numa página (69 % numa aba, 66 % noutra).

O caminho escolhido neste projeto é HTML → impressão do navegador → PDF, e aí não há
planilha para escalar. O que se reproduz, porque é o que sustenta o documento:

* **A grade de 28 colunas** (`A`…`AB`), com as larguras relativas exatas do handoff. É
  ela que põe cada campo do bloco de título e cada coluna de tabela na mesma banda da
  referência — `A:J` para o parâmetro, `K:N` para o símbolo, `O:S` para o valor, e assim
  por diante;
* **A geometria da página**: A4 retrato, margens 0,7 pol à esquerda, 0,3 à direita, 0,4
  em cima e embaixo; uma folha = uma página impressa;
* **O bloco de título em todas as folhas** e o quadro de revisões só na de rosto;
* **A tipografia**: Arial em tudo, Times New Roman itálico nas equações, e os corpos que
  o handoff tabela (5 pt para rótulo, 7 pt para cabeçalho de tabela, 7,5 pt para dado,
  8,5 pt para barra de seção, 9 pt para campo do bloco de título, 11 pt para o título);
* **As bordas**: contorno e divisões estruturais `medium`, grade de tabela `thin`, sem
  preenchimento de fundo colorido.

O que **não** se reproduz é a escala global da planilha: os corpos de texto acima são
usados como tamanhos impressos diretos. Aplicar 69 % sobre eles daria 6,2 pt num
documento de engenharia que se lê em papel.

## Paginação

A regra do handoff, e ela é dura: nada fora da faixa de conteúdo, um bloco nunca é
partido entre folhas, e ao estourar abre-se outra folha do mesmo tipo — repetindo o
bloco de título, incrementando o número da folha e acrescentando `(cont.)` ao título da
seção. [`paginar`](@ref) é quem faz isso, e as folhas de fórmulas são o caso real: são
dezoito equações, e quatro cabem por folha.

O total de folhas só se conhece no fim, então ele é gravado numa segunda passagem — o
que o handoff também prescreve, e pela mesma razão.
"""

# ---------------------------------------------------------------------------
# A grade de 28 colunas
# ---------------------------------------------------------------------------

"""
Larguras das colunas `A`…`AB`, em caracteres, exatamente como o handoff as tabela
(soma ≈ 118,7). Viram `fr` no `grid-template-columns`, o que preserva as proporções
qualquer que seja a largura impressa.

As colunas `S`, `T` e `U` ocultas da planilha de referência já estão removidas aqui —
é a própria observação do handoff.
"""
const COLUNAS = [3.00, 3.00, 3.00, 2.29, 3.00, 2.86, 3.28, 3.00, 3.57, 1.86, 3.00,
                 3.00, 2.57, 2.86, 3.00, 2.71, 3.28, 2.00, 14.14, 9.57, 7.43, 8.57,
                 8.72, 3.00, 4.57, 3.00, 2.14, 6.29]

"Os nomes das 28 colunas, na ordem — para converter uma banda `\"A:J\"` em índices."
const NOMES_COLUNAS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                       "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
                       "AA", "AB"]

"""
    banda(spec) -> (inicio, fim)

Converte uma banda de colunas do handoff (`"A:J"`, `"W"`) nos índices 1-based da grade.

Existe para que as tabelas do memorial citem as **mesmas bandas** que o handoff
tabela, em vez de números mágicos: `"O:S"` é a coluna VALOR da folha 02 lá e aqui.
Banda desconhecida é erro de programação — o documento sairia com a coluna no lugar
errado e nada denunciaria.
"""
function banda(spec::AbstractString)
    partes = split(spec, ':')
    idx = map(partes) do p
        i = findfirst(==(strip(String(p))), NOMES_COLUNAS)
        i === nothing && error("banda de coluna desconhecida no memorial: '$spec'")
        return i
    end
    return length(idx) == 1 ? (idx[1], idx[1]) : (idx[1], idx[2])
end

"""
    celula(spec, conteudo; classe, linha) -> String

Uma célula que ocupa a banda `spec` da grade de 28 colunas.

`linha` é a linha (ou a faixa de linhas) do gabarito, e existe para o bloco de título:
lá a marca do emitente ocupa as linhas 1–5 e o título do documento as 6–7, e sem posição
explícita o posicionamento automático da grade os empilharia na ordem em que aparecem no
HTML — que não é a ordem em que estão na folha. Nas tabelas ela é omitida de propósito:
ali as linhas se sucedem, e é o automático que se quer.
"""
function celula(spec::AbstractString, conteudo::AbstractString;
                classe::AbstractString = "", linha = nothing)
    i, j = banda(spec)
    cls = isempty(classe) ? "" : " class=\"$classe\""
    pos = "grid-column:$i/$(j + 1)"
    if linha !== nothing
        a, b = linha isa Tuple ? linha : (linha, linha)
        pos *= ";grid-row:$a/$(b + 1)"
    end
    return "<div$cls style=\"$pos\">$conteudo</div>"
end

# ---------------------------------------------------------------------------
# Metadados e tokens
# ---------------------------------------------------------------------------

"""
Os metadados do documento — o que o bloco de título imprime.

`cliente`, `unidade` e `executor` não são dados que o programa calcula nem que ele
guarde em lugar nenhum, e por isso entram com `"A DEFINIR"`. Preenchê-los com um nome
plausível seria escrever no documento uma informação que ninguém informou — a mesma
classe de defeito que o `NaN` em vez de `0.0` evita no core. Quem quiser preenchê-los
passa-os na consulta da rota (ver [`meta_da_consulta`](@ref)).

`projeto` é a exceção, e por um bom motivo: o programa **tem** essa informação — é o
rótulo do conjunto de casos aberto, que o usuário nomeou.
"""
struct DocMeta
    sigla::String
    sequencial::String
    revisao::String
    titulo::String
    equipamento::String
    cliente::String
    projeto::String
    unidade::String
    executor::String
    data::String
end

"O valor que substitui o que o programa não tem como saber."
const A_DEFINIR = "A DEFINIR"

"""
    numero_documento(meta) -> String

`MC-SENAI-<SIGLA>-ENG-<sequencial>-<revisão>` — a convenção do handoff.
"""
numero_documento(m::DocMeta) =
    "MC-SENAI-$(m.sigla)-ENG-$(m.sequencial)-$(m.revisao)"

"Título completo do documento, como o handoff o compõe."
titulo_documento(m::DocMeta) = "MEMÓRIA DE CÁLCULO – $(m.titulo)"

"""
    tokens(meta, folha, folhas) -> Dict{String,String}

A tabela de tokens do handoff. Os valores saem **já escapados**, porque vão direto para
o HTML e vêm de TOML que o usuário edita (o rótulo do conjunto de casos) e da consulta
da rota.
"""
tokens(m::DocMeta, folha::Integer, folhas) = Dict{String,String}(
    "doc.numero"       => escapa(numero_documento(m)),
    "doc.titulo"       => escapa(titulo_documento(m)),
    "doc.revisao"      => escapa(m.revisao),
    "doc.folha"        => escapa(string(folha)),
    "doc.folhas"       => escapa(string(folhas)),
    "doc.data"         => escapa(m.data),
    "doc.executor"     => escapa(m.executor),
    "projeto.cliente"  => escapa(m.cliente),
    "projeto.nome"     => escapa(m.projeto),
    "projeto.unidade"  => escapa(m.unidade),
    "equipamento.rotulo" => escapa(m.equipamento),
    "modulo.rotulo"    => escapa(m.sigla),
)

"""
    resolver(texto, tab) -> String

Substitui os `{{token}}` do gabarito pelos valores de `tab`.

**Token não resolvido é erro**, não célula vazia — a regra está no handoff e a razão é
que uma célula vazia num memorial assinado passa por "não se aplica" em vez de por
"faltou preencher". Vale para token desconhecido e para token que sobrou: os dois viram
`error`, e a rota transforma em mensagem na tela em vez de servir um documento furado.
"""
function resolver(texto::AbstractString, tab::AbstractDict)
    out = replace(texto, r"\{\{([a-z_]+(?:\.[a-z_]+)?)\}\}" => s -> begin
        chave = strip(String(s), ['{', '}'])
        haskey(tab, chave) ||
            error("memorial: token não resolvido no documento — '{{$chave}}'")
        return tab[chave]
    end)
    m = match(r"\{\{[^}]*\}\}", out)
    m === nothing ||
        error("memorial: token não resolvido no documento — '$(m.match)'")
    return out
end

# ---------------------------------------------------------------------------
# O bloco de título — repetido em TODAS as folhas
# ---------------------------------------------------------------------------

"""
    bloco_titulo(css) -> String

O bloco de título (linhas 1–8 do handoff), em gabarito com tokens: o mesmo HTML serve a
todas as folhas, e o que muda entre elas — o número da folha e o total — entra por
[`resolver`](@ref).

Uma função só, chamada ao abrir cada folha, como o handoff manda. Escrever o bloco em
cada folha seria oito oportunidades de a revisão de uma delas divergir das outras.

`css` chega aqui pela **marca do emitente**, e por nada mais: ela é o único recurso
externo do documento, e no arquivo exportado precisa vir embutida — ver
[`marca_emitente`](@ref).
"""
function bloco_titulo(css::Symbol = :link)
    partes = String[]
    push!(partes, "<header class=\"bloco-titulo\">")

    # Marca do emitente (linhas 1–5) e o nome (linha 8), na banda A:F. As linhas 6–7
    # ficam reservadas à marca do cliente, e por isso vazias — é o que o handoff manda.
    push!(partes, celula("A:F", marca_emitente(css);
        classe = "marca", linha = (1, 5)))
    push!(partes, celula("A:F", "SENAI CETIQT"; classe = "emitente", linha = 8))

    # Faixa do título do documento, número e revisão — linhas 1–2.
    push!(partes, celula("G:O", "MEMÓRIA DE CÁLCULO";
                         classe = "faixa-titulo", linha = (1, 2)))
    push!(partes, celula("P", "Nº."; classe = "rotulo-min", linha = (1, 2)))
    push!(partes, celula("Q:W", "{{doc.numero}}";
                         classe = "campo-numero", linha = (1, 2)))
    push!(partes, celula("Y", "Rev."; classe = "rotulo-min", linha = (1, 2)))
    push!(partes, celula("Z:AB", "{{doc.revisao}}";
                         classe = "campo-revisao", linha = (1, 2)))

    # Cliente / folha — linha 3.
    push!(partes, celula("G:I", "CLIENTE:"; classe = "rotulo-min", linha = 3))
    push!(partes, celula("J:W", "{{projeto.cliente}}"; classe = "campo", linha = 3))
    push!(partes, celula("X:Y", "FOLHA:"; classe = "rotulo-min", linha = 3))
    push!(partes, celula("Z", "{{doc.folha}}"; classe = "campo", linha = 3))
    push!(partes, celula("AA", "de"; classe = "rotulo-min", linha = 3))
    push!(partes, celula("AB", "{{doc.folhas}}"; classe = "campo", linha = 3))

    # Projeto / escala — linha 4.
    push!(partes, celula("G:I", "PROJETO:"; classe = "rotulo-min", linha = 4))
    push!(partes, celula("J:W", "{{projeto.nome}}"; classe = "campo", linha = 4))
    push!(partes, celula("X:Y", "ESC:"; classe = "rotulo-min", linha = 4))
    push!(partes, celula("Z:AB", "SEM ESCALA"; classe = "campo-escala", linha = 4))

    # Unidade — linha 5.
    push!(partes, celula("G:I", "UNIDADE:"; classe = "rotulo-min", linha = 5))
    push!(partes, celula("J:W", "{{projeto.unidade}}"; classe = "campo", linha = 5))

    # Título do documento — linhas 6–7, duas linhas de texto.
    push!(partes, celula("G:H", "TÍTULO:"; classe = "rotulo-min", linha = (6, 7)))
    push!(partes, celula("I:AB", "{{doc.titulo}}";
                         classe = "campo-titulo", linha = (6, 7)))

    # Arquivo — linha 8.
    push!(partes, celula("J:AB", "{{doc.numero}}";
                         classe = "campo-arquivo", linha = 8))

    push!(partes, "</header>")
    return join(partes)
end

"""
    quadro_revisoes() -> String

O quadro de revisões (linhas 73–79), **só na folha de rosto**. Nas demais folhas esse
espaço fica livre para conteúdo e sobra apenas a nota de propriedade.

A revisão corrente é a única linha preenchida; as quatro seguintes ficam em branco para
as futuras, que é como um quadro de revisões funciona. Executor, revisor e aprovador
saem em `A DEFINIR` pela razão de [`DocMeta`](@ref): aprovação é assinatura de gente, e
o programa não tem como carimbá-la.
"""
function quadro_revisoes()
    cab = [("A:B", "Rev."), ("C:R", "DESCRIÇÃO"), ("S", "EXECUTOR"), ("T", "DATA EXEC."),
           ("U", "REVISOR"), ("V", "DATA REV."), ("W:Z", "APROVAÇÃO"),
           ("AA:AB", "DATA APROV.")]
    # Revisor e aprovação saem EM BRANCO, e não com `A DEFINIR`.
    #
    # Não é a mesma coisa que o cliente ou a unidade do bloco de título, onde o dado
    # existe e ninguém o informou. Aqui o dado não existe: esta é a emissão inicial, ela
    # ainda não foi revisada nem aprovada, e um quadro de revisões com os campos de
    # assinatura vazios é exatamente o que ele deve mostrar. Escrever `A DEFINIR` numa
    # linha de aprovação sugere pendência de preenchimento onde o que há é pendência de
    # REVISÃO — e, de quebra, não cabe na coluna.
    linha_atual = [("A:B", "{{doc.revisao}}"),
                   ("C:R", "EMISSÃO INICIAL — GERADA POR FPSO_Siz"),
                   ("S", "{{doc.executor}}"), ("T", "{{doc.data}}"),
                   ("U", "&nbsp;"), ("V", "&nbsp;"),
                   ("W:Z", "&nbsp;"), ("AA:AB", "&nbsp;")]

    partes = String["<section class=\"quadro-revisoes\">"]
    for (b, t) in cab
        push!(partes, celula(b, t; classe = "rev-cab"))
    end
    for (b, t) in linha_atual
        push!(partes, celula(b, t; classe = "rev-atual"))
    end
    # Quatro linhas em branco para as revisões futuras — linhas 75–78 do handoff.
    for _ in 1:4, (b, _) in cab
        push!(partes, celula(b, "&nbsp;"; classe = "rev-vazia"))
    end
    push!(partes, "</section>")
    return join(partes)
end

"A nota de propriedade da linha 79 — em todas as folhas."
nota_propriedade() =
    "<footer class=\"nota-propriedade\">AS INFORMAÇÕES DESTE DOCUMENTO SÃO " *
    "PROPRIEDADE DO SENAI CETIQT, SENDO PROIBIDA A UTILIZAÇÃO FORA DA SUA " *
    "FINALIDADE.</footer>"

# ---------------------------------------------------------------------------
# A folha
# ---------------------------------------------------------------------------

"""
Uma folha do memorial, antes de saber o seu próprio número.

`conteudo` é o HTML da faixa de conteúdo; `revisoes` diz se esta folha leva o quadro de
revisões (só a de rosto leva).

`tokens` diz se o conteúdo desta folha passa por [`resolver`](@ref). O bloco de título e
o quadro de revisões passam **sempre**; o conteúdo, quase sempre — a folha de rosto usa
`{{doc.numero}}` e `{{projeto.nome}}` nas suas próprias células.

A exceção é a folha de figuras, e ela tem motivo concreto: ali o conteúdo é o SVG que a
tela desenha, e dentro dele vão os **nomes dos casos**, que o usuário escolhe. Um caso
batizado de `{{x}}` faria o resolvedor recusar a emissão do documento inteiro por conta
de um nome de caso — a regra de "token não resolvido é erro" existe para proteger o
gabarito, não para dar ao nome de um caso o poder de impedir a impressão.
"""
struct Folha
    conteudo::String
    revisoes::Bool
    tokens::Bool
end

Folha(conteudo::AbstractString; revisoes::Bool = false, tokens::Bool = true) =
    Folha(String(conteudo), revisoes, tokens)

"""
    barra_secao(texto; cont) -> String

A barra de seção do handoff: Arial 8,5 pt negrito, com bordas superior e inferior.
`cont = true` acrescenta o `(cont.)` que a regra de paginação exige de toda seção que
atravessa folhas.
"""
barra_secao(texto::AbstractString; cont::Bool = false) =
    "<h2 class=\"barra-secao\">" * escapa(texto) * (cont ? " (cont.)" : "") * "</h2>"

"""
    tabela_doc(colunas, linhas) -> String

Uma tabela do memorial na grade de 28 colunas. `colunas` é um vetor de
`(banda, cabeçalho, alinhamento)`; `linhas`, um vetor de vetores de células **já
escapadas ou já em HTML**.

A grade é a mesma das demais folhas, e é isso que faz a coluna VALOR da folha 02 e a
coluna VALOR da folha 04 caírem no mesmo lugar da página — que é o que se espera de um
documento, e o que uma tabela HTML comum não daria.

`_doc` no nome porque `tabela` já é a tabela de varredura da TELA, em `api.jl`. As duas
teriam aridades diferentes e conviveriam como métodos da mesma função, mas "tabela" no
meio deste arquivo passaria a significar duas coisas conforme os argumentos — e quem
lesse `tabela(cols, linhas)` procuraria a varredura.
"""
function tabela_doc(colunas, linhas)
    partes = String["<div class=\"tabela\">"]
    # Cabeçalho SÓ quando há cabeçalho. Os quadros de duas colunas da folha de fórmulas
    # (rótulo / valor) não têm nenhum, e emitir a linha assim mesmo punha uma faixa
    # vazia de 13,5 pt acima de cada "REFERÊNCIA DA EQUAÇÃO" — que se lê como célula que
    # alguém esqueceu de preencher, exatamente o que este documento não pode ter.
    if any(!isempty(cab) for (_, cab, _) in colunas)
        for (b, cab, al) in colunas
            push!(partes, celula(b, escapa(cab); classe = "th al-$al"))
        end
    end
    for linha in linhas
        for ((b, _, al), valor) in zip(colunas, linha)
            push!(partes, celula(b, valor; classe = "td al-$al"))
        end
    end
    push!(partes, "</div>")
    return join(partes)
end

"""
    paginar(itens, por_folha) -> Vector{Vector}

Reparte os itens em folhas de no máximo `por_folha`, sem partir nenhum.

É a regra do handoff aplicada ao único lugar onde ela morde de verdade: a folha de
fórmulas do separador trifásico tem dezoito equações, e um bloco de equação — barra de
seção, faixa da equação, `ONDE:`, definição das variáveis, referência e validade — não
se parte entre páginas sem ficar ilegível.
"""
paginar(itens, por_folha::Integer) =
    [itens[i:min(i + por_folha - 1, length(itens))]
     for i in 1:por_folha:length(itens)]

"""
    paginar_por_custo(itens, custo, orcamento) -> Vector{Vector}

Reparte os itens em folhas por **altura estimada**, e não por contagem fixa.

É o que o handoff prescreve — *"contar linhas antes de escrever; ao estourar a faixa de
conteúdo, abrir nova planilha"* — e é preciso porque os blocos de equação não têm todos
a mesma altura: o da Eq. 9–11 define duas variáveis e o da Eq. 22 define sete, e a
diferença entre eles é maior que o que sobra no pé da folha.

Com contagem fixa de quatro por folha o quarto bloco era cortado pela borda inferior:
a folha saía com "VALIDADE / CONDIÇÃO" pela metade e sem o valor calculado, que é
justamente o elo que a folha existe para mostrar. Um item sozinho maior que o orçamento
ganha a sua própria folha em vez de sumir.
"""
function paginar_por_custo(itens, custo, orcamento::Real)
    folhas, atual, soma = Vector{eltype(itens)}[], eltype(itens)[], 0.0
    for it in itens
        c = custo(it)
        if !isempty(atual) && soma + c > orcamento
            push!(folhas, atual)
            atual, soma = eltype(itens)[], 0.0
        end
        push!(atual, it)
        soma += c
    end
    isempty(atual) || push!(folhas, atual)
    return folhas
end

# ---------------------------------------------------------------------------
# O documento
# ---------------------------------------------------------------------------

"""
    documento_html(meta, folhas; titulo_pagina) -> String

Monta o documento completo: o gabarito de cada folha, o bloco de título repetido, o
quadro de revisões na primeira e a numeração `folha X de Y` resolvida na segunda
passagem — o total só se conhece depois de montar todas, que é o que o handoff prescreve.

Sai um HTML **imprimível e sem script nenhum**. Imprimir esta página no navegador
(Ctrl+P → Salvar como PDF) produz o documento paginado, uma folha por página.

## `css`: de onde vem a folha de estilo

* `:link` (o default) — `<link rel="stylesheet" href="/memorial.css">`. É o da **rota**:
  o arquivo é servido do mesmo `public/` de sempre, o navegador o guarda em cache entre
  as folhas, e editá-lo em desenvolvimento não exige regerar o documento.
* `:embutido` — o conteúdo de `memorial.css` dentro de um `<style>`. É o da
  **exportação**: o arquivo gravado em `saida/` tem de abrir por duplo clique, com o
  programa fechado, e um `href="/memorial.css"` ali não resolve para nada — o documento
  abriria sem uma borda, sem a grade e sem a paginação, que é o mesmo que não abrir.

## `editavel`: por que o documento se deixa escrever

O que o programa não tem como saber — cliente, unidade, quem executou — sai `A DEFINIR`,
nunca num nome plausível. A consulta preenche esses campos quando quem gera os conhece
(`?cliente=…&executor=…`), mas quem imprime nem sempre é quem gera.

Com `editavel = true` cada folha recebe `contenteditable`, e o campo se preenche na tela
antes de imprimir — que é o que o protótipo do handoff faz
(`References/memorial-de-calculo-editavel.html`). Não há script: `contenteditable` é do
navegador, a edição vive na aba e **não volta para o programa**. É deliberado — um
memorial editado à mão não é o memorial que o motor calculou, e gravá-lo de volta
apagaria a distinção entre o que foi computado e o que foi digitado.
"""
function documento_html(meta::DocMeta, folhas::Vector{Folha};
                        titulo_pagina::AbstractString = "",
                        css::Symbol = :link,
                        editavel::Bool = true)
    total = length(folhas)
    corpo = String[]
    for (i, f) in enumerate(folhas)
        tab = tokens(meta, i, total)
        # O gabarito (bloco de título e quadro de revisões) é resolvido SEMPRE; o
        # conteúdo, só quando a folha o pede — ver a nota de `Folha` sobre as figuras.
        # `contenteditable` vai na FOLHA, e não no `<body>`: assim a barra de tela
        # continua fora da edição (ninguém apaga o próprio botão de imprimir sem querer),
        # e cada folha é uma região de edição independente.
        edicao = editavel ? " contenteditable=\"true\" spellcheck=\"false\"" : ""
        push!(corpo, string(
            "<article class=\"folha\"", edicao, ">",
            resolver(bloco_titulo(css), tab),
            "<main class=\"conteudo\">",
            f.tokens ? resolver(f.conteudo, tab) : f.conteudo,
            "</main>",
            f.revisoes ? resolver(quadro_revisoes(), tab) : "",
            nota_propriedade(), "</article>"))
    end

    titulo = isempty(titulo_pagina) ? numero_documento(meta) : titulo_pagina
    return string(
        "<!doctype html>\n<html lang=\"pt-BR\">\n<head>\n",
        "<meta charset=\"utf-8\">\n",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
        "<title>", escapa(titulo), "</title>\n",
        folha_de_estilo(css), "\n",
        "</head>\n<body>\n",
        # A barra não é impressa (`@media print` a esconde): é só o atalho para quem
        # abriu o documento na tela e quer o PDF, mais a instrução de edição — sem ela
        # nada na página denuncia que os campos se deixam escrever.
        "<div class=\"barra-tela\">",
        "<button type=\"button\" onclick=\"window.print()\">Imprimir / salvar em PDF</button>",
        editavel ? "<span>Clique em qualquer campo para corrigi-lo antes de imprimir.</span>" : "",
        "<span>", escapa(numero_documento(meta)), " — ", escapa(string(total)),
        " folhas</span>", "</div>\n",
        join(corpo, "\n"), "\n</body>\n</html>\n")
end

"""
    marca_emitente(modo) -> String

A marca do SENAI CETIQT do bloco de título.

Pela rota (`:link`) é `/senai-cetiqt.webp`, servida do `public/`. No documento exportado
(`:embutido`) o caminho absoluto não resolve para nada — o arquivo é aberto por duplo
clique, de `saida/`, e o navegador procuraria a marca na raiz do disco. Então ela vai
**dentro do HTML**, como `data:` URI.

O handoff põe a marca na primeira célula de **todas** as folhas, então ela entra uma vez
por folha: ~20 kB em base64 cada, e um separador de doze folhas passa de 124 kB a 365 kB.
A repetição é do gabarito, não desta função — o bloco de título inteiro se repete, e é
essa repetição que faz cada folha ser um documento completo se destacada das outras.

Daria para gravar a imagem uma vez só, numa regra `content:` do CSS embutido. Não se faz:
`content:` sobre `<img>` é substituição de renderização, e apostar a marca de um documento
assinado nela — na impressão, que é onde o arquivo é usado — troca 240 kB por um risco.
Num arquivo escrito em disco uma vez, os 240 kB não custam nada.

Marca ausente do `public/` não derruba a exportação: o documento sai com o texto
alternativo, que é o que o `<img>` já faria. Um memorial sem logotipo ainda é o
memorial; uma exportação que falha inteira por causa dele, não.
"""
function marca_emitente(modo::Symbol)
    modo === :link && return "<img src=\"/senai-cetiqt.webp\" alt=\"SENAI CETIQT\">"

    caminho = joinpath(dir_publico(), "senai-cetiqt.webp")
    isfile(caminho) || return "<img alt=\"SENAI CETIQT\">"
    dados = base64encode(read(caminho))
    return "<img src=\"data:image/webp;base64,$dados\" alt=\"SENAI CETIQT\">"
end

"""
    folha_de_estilo(modo) -> String

O `<link>` da rota ou o `<style>` embutido da exportação — ver `css` em
[`documento_html`](@ref).

O CSS embutido é lido de `dir_publico()`, que é a **mesma** origem que o servidor usa
para servi-lo. É a propriedade que importa: não há uma segunda cópia do estilo a
divergir, e o arquivo exportado imprime exatamente como a rota.
"""
function folha_de_estilo(modo::Symbol)
    modo === :link && return "<link rel=\"stylesheet\" href=\"/memorial.css\">"
    if modo === :embutido
        caminho = joinpath(dir_publico(), "memorial.css")
        isfile(caminho) ||
            error("memorial.css não encontrado em $(caminho): o documento exportado " *
                  "sairia sem borda, sem grade e sem paginação.")
        return string("<style>\n", read(caminho, String), "\n</style>")
    end
    throw(ArgumentError("modo de folha de estilo desconhecido: $modo (use :link ou :embutido)"))
end
