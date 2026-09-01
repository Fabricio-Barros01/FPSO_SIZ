"""
Tradução entre o [`AppState`](@ref) e o JSON que o navegador consome.

## Por que os números atravessam como texto

O `<input>` manda `"1.025,8"` e recebe `"1.025,8"` de volta. Quem converte é
`Formato.parse_num`, do lado do Julia; quem formata é `Formato.num`, também do lado do
Julia. Assim a regra PT-BR — vírgula decimal, ponto de milhar só a partir de cinco
dígitos, travessão no lugar de `NaN` — existe **uma vez**, e não uma em Julia e outra
em JavaScript, que divergiriam no primeiro caso de canto.

A exceção é o cursor de diâmetro: `<input type=range>` é numérico por natureza, e
milímetro inteiro não tem ambiguidade de separador.

A serialização é escrita à mão, campo a campo, em vez de refletir os `struct` do core.
É mais linha de código e em troca o contrato com a tela fica visível num arquivo só —
e `governing::Symbol` precisaria de conversão de qualquer jeito.
"""

# ---------------------------------------------------------------------------
# Descritores → formulário
# ---------------------------------------------------------------------------

"Um `ParameterSpec` como a tela precisa dele."
spec_json(s::FPSOSiz.ParameterSpec) = Dict{String,Any}(
    "key"      => String(s.key),
    "label"    => s.label,
    "unit"     => s.unit,
    "default"  => Formato.num(s.default, Formato.casas_de(s)),
    "min"      => s.min,
    "max"      => s.max,
    "advanced" => s.advanced,
    "note"     => s.note,
)

"""
    esquema(st) -> Dict

Tudo que a tela precisa para **montar o formulário sozinha**: os descritores dos campos
por caso, os dos ajustes globais e os rótulos do equipamento e do método.

É a regra de `src/interfaces.jl`: a interface nunca cita um parâmetro pelo nome.
Registrar um equipamento novo no core faz a tela aparecer sem editar uma linha daqui.
"""
esquema(st::AppState) = Dict{String,Any}(
    "campos"      => [spec_json(s) for s in st.campos],
    "ajustes"     => [spec_json(s) for s in st.ajustes],
    "equipamento" => FPSOSiz.label(st.equipamento),
    "metodo"      => FPSOSiz.label(st.metodo),
    "paleta"      => Dict{String,Any}(
        "destaque" => Formato.DESTAQUE, "erro" => Formato.ERRO,
        "ok" => Formato.OK, "tinta_fraca" => Formato.TINTA_FRACA),
)

# ---------------------------------------------------------------------------
# Estado → tela
# ---------------------------------------------------------------------------

"Casas decimais de cada chave, para formatar os valores do caso."
function _casas(st::AppState)
    d = Dict{Symbol,Int}()
    for s in vcat(st.campos, st.ajustes)
        d[s.key] = Formato.casas_de(s)
    end
    return d
end

"Um caso como o formulário o edita: mín e máx já formatados."
function caso_json(c::CaseUI, casas::Dict{Symbol,Int})
    fmt(dic) = Dict{String,Any}(String(k) => Formato.num(v, get(casas, k, 2))
                                for (k, v) in dic)
    return Dict{String,Any}("id" => c.id, "name" => c.name, "enabled" => c.enabled,
                            "lo" => fmt(c.lo), "hi" => fmt(c.hi))
end

"Linha da varredura mais próxima do diâmetro selecionado."
function linha_sel(r, d)
    (r === nothing || isempty(r.rows)) && return nothing
    return argmin(row -> abs(row.d_mm - d), r.rows)
end

"""
    cartao(st) -> Dict

O cartão de resultados da coluna direita, já em texto. Mesmos oito campos da versão
Makie, na mesma ordem.
"""
function cartao(st::AppState)
    r = st.resultado
    l = linha_sel(r, st.d_sel)
    tr = "—"
    l === nothing && return Dict{String,Any}(
        "d" => tr, "leff" => tr, "lss" => tr, "sr" => tr, "sr_ok" => true,
        "volume" => tr, "governa" => tr, "caso" => tr, "teto" => tr)

    return Dict{String,Any}(
        "d"       => "$(Formato.inteiro(l.d_mm)) mm",
        "leff"    => "$(Formato.num(l.leff_m)) m",
        "lss"     => "$(Formato.num(l.lss_m)) m",
        "sr"      => "$(Formato.num(l.sr)) " * (l.sr_ok ? "✓" : "✗"),
        "sr_ok"   => l.sr_ok,
        "volume"  => "$(Formato.num(FPSOSiz.vessel_volume(l.d_mm, l.lss_m), 0)) m³",
        "governa" => l.governing === :gas ? "capacidade de gás" : "capacidade de líquido",
        "caso"    => l.driver_case,
        "teto"    => isfinite(r.d_max_mm) ? "$(Formato.inteiro(r.d_max_mm)) mm" : tr,
    )
end

"""
    tabela(st; n_linhas) -> Vector

Vizinhança do diâmetro selecionado na varredura — o mesmo recorte de nove linhas
centrado no cursor que a versão Makie mostrava. Linhas fora da grade vêm vazias, para
que a tabela não mude de altura ao chegar nas pontas.
"""
function tabela(st::AppState; n_linhas::Int = 9)
    r = st.resultado
    vazia = Dict{String,Any}("d" => "", "leff" => "", "lss" => "", "sr" => "",
                             "centro" => false, "sr_ok" => false)
    (r === nothing || isempty(r.rows)) && return [vazia for _ in 1:n_linhas]

    centro = argmin(k -> abs(r.rows[k].d_mm - st.d_sel), eachindex(r.rows))
    meio = (n_linhas + 1) ÷ 2
    linhas = Dict{String,Any}[]
    for i in 1:n_linhas
        alvo = centro - meio + i
        k = clamp(alvo, 1, length(r.rows))
        if alvo != k
            push!(linhas, vazia)
            continue
        end
        row = r.rows[k]
        push!(linhas, Dict{String,Any}(
            "d"      => Formato.inteiro(row.d_mm),
            "leff"   => Formato.num(row.leff_m),
            "lss"    => Formato.num(row.lss_m),
            "sr"     => Formato.num(row.sr),
            "centro" => k == centro,
            "sr_ok"  => row.sr_ok))
    end
    return linhas
end

"""
    desenho(st) -> Dict

Os quatro SVGs mais a legenda. É o que o cursor de diâmetro troca a cada movimento: a
varredura já está calculada, então isto é formatação, não recálculo.
"""
function desenho(st::AppState)
    r = st.resultado
    g = geometry_from(r, st.d_sel, beta_atual(st))
    banda = (st.globais[:sr_min], st.globais[:sr_max])
    return Dict{String,Any}(
        "vaso"    => svg_elevacao(g),
        "corte"   => svg_corte(g),
        "leff"    => svg_grafico_leff(r, st.d_sel),
        "sr"      => svg_grafico_sr(r, st.d_sel, banda, st.globais[:sr_target]),
        "legenda" => html_legenda_casos(r),
        "titulo"  => g.ok ?
            "Elevação — d = $(Formato.inteiro(g.d_m * 1000)) mm · " *
            "Lss = $(Formato.num(g.lss_m)) m · SR = $(Formato.num(g.sr))" :
            "Elevação — sem resultado",
    )
end

"""
    memorial(st) -> Dict

O rastro de cálculo de cada caso, agrupado por bloco — o que o painel de memorial mostra.

As linhas saem daqui **já formatadas**, por `linha_memorial` e `fecho_memorial`, que são
as mesmas funções que escrevem o `.txt` exportado. Isso não é economia de código: é a
única forma de a tela e o arquivo não divergirem. Se o JavaScript remontasse a linha do
seu jeito, os dois se afastariam no primeiro caso de canto e ninguém notaria — o
`.txt` é o que vai anexo ao relatório, e a tela é o que se confere antes de anexar.
Um teste em `smoke.jl` compara os dois linha a linha.

Não viaja em `estado`: o rastro dos dez casos de canto do exemplo de referência é grande,
e o painel é consulta, não operação. A tela pede quando o usuário abre.
"""
function memorial(st::AppState)
    r = st.resultado
    (r === nothing || isempty(r.per_case)) &&
        return Dict{String,Any}("casos" => Dict{String,Any}[], "governante" => "")

    casos = Dict{String,Any}[]
    for (nome, res) in zip(r.case_names, r.per_case)
        blocos = Dict{String,Any}[]
        for (id, titulo) in BLOCOS_MEMORIAL
            linhas = [linha_memorial(e) for e in FPSOSiz.block_entries(res.trace, id)]
            # Bloco vazio não vira subtítulo órfão: um método que não use um dos blocos
            # (o vaso bifásico do Sprint 5 não usa o B) simplesmente não o mostra.
            isempty(linhas) || push!(blocos, Dict{String,Any}(
                "id" => String(id), "titulo" => titulo, "linhas" => linhas))
        end
        push!(casos, Dict{String,Any}("nome" => nome, "viavel" => res.feasible,
                                      "fecho" => fecho_memorial(res), "blocos" => blocos))
    end
    return Dict{String,Any}("casos" => casos, "governante" => r.driver_case)
end

"""
    arquivos(st) -> Dict

Os conjuntos de casos disponíveis, para o seletor de arquivo, e qual está aberto.

`gravavel` distingue o que o usuário salvou do que veio de fábrica: "Salvar" por cima
de um exemplo é possível (a cópia vai para `dir_casos()` e passa a sombrear o original),
mas a tela avisa antes, porque a pessoa raramente quer isso.
"""
arquivos(st::AppState) = Dict{String,Any}(
    "arquivos" => [Dict{String,Any}("nome" => a.nome, "rotulo" => a.rotulo,
                                    "casos" => a.casos, "gravavel" => a.gravavel)
                   for a in FPSOSiz.list_case_sets()],
    "atual"    => st.arquivo,
    "rotulo"   => st.rotulo,
    "dir"      => FPSOSiz.dir_casos(),
)

"""
    estado(st; com_desenho) -> Dict

Fotografia completa do estado para a tela. `com_desenho = false` serve às respostas em
que o SVG não mudou e transmiti-lo seria desperdício.
"""
function estado(st::AppState; com_desenho::Bool = true)
    casas = _casas(st)
    r = st.resultado
    d = Dict{String,Any}(
        "arquivo"   => st.arquivo,
        "rotulo"    => st.rotulo,
        "casos"     => [caso_json(c, casas) for c in st.casos],
        "rotulos"   => nomes_menu(st),
        "sel"       => st.sel,
        "globais"   => Dict{String,Any}(String(k) => Formato.num(v, get(casas, k, 2))
                                        for (k, v) in st.globais),
        "d_sel"     => st.d_sel,
        "grade"     => grade_slider(st),
        "status"    => st.status,
        "status_ok" => st.status_ok,
        "viavel"    => r !== nothing && r.feasible,
        "cartao"    => cartao(st),
        "tabela"    => tabela(st),
    )
    com_desenho && (d["desenho"] = desenho(st))
    return d
end

# ---------------------------------------------------------------------------
# Tela → estado
# ---------------------------------------------------------------------------

"""
    aplicar!(st, payload) -> Vector{Dict}

Escreve no estado o que o formulário mandou e devolve os avisos de validação
(vazio = tudo válido). Campo ilegível ou fora da faixa do descritor é **ignorado** e
reportado: o valor anterior fica de pé. Nunca lança — entrada inválida é diagnóstico,
não exceção.

Cada aviso traz `escopo` (`"caso:3"` ou `"globais"`), `chave`, `extremo` (`"lo"`/`"hi"`)
e `msg`, para que a tela consiga apontar exatamente qual caixa recusar em vez de só
escrever a queixa na barra de status. O escopo é posicional de propósito: ele endereça a
**caixa** na tela, e a lista devolvida sai na mesma ordem em que chegou.

Já a herança de valores é por `id`, não por posição — ver [`novo_id`](@ref).
"""
function aplicar!(st::AppState, payload)
    avisos = Dict{String,Any}[]
    por_chave = Dict(s.key => s for s in vcat(st.campos, st.ajustes))

    ler = (dic, chave, escopo, extremo) -> begin
        bruto = get(dic, String(chave), nothing)
        bruto === nothing && return nothing
        spec = por_chave[chave]
        aviso = msg -> (push!(avisos, Dict{String,Any}(
                            "escopo" => escopo, "chave" => String(chave),
                            "extremo" => extremo, "msg" => msg)); nothing)

        v = Formato.parse_num(string(bruto))
        v === nothing && return aviso("$(spec.label): valor ilegível ($bruto)")
        msg = FPSOSiz.validate(spec, v)
        msg === nothing || return aviso(msg)
        return v
    end

    casos_in = get(payload, "casos", nothing)
    if casos_in !== nothing
        por_id = Dict(c.id => c for c in st.casos)
        novos = CaseUI[]
        for (i, c) in enumerate(casos_in)
            nome = strip(string(get(c, "name", "Caso $i")))
            base = CaseUI(isempty(nome) ? "Caso $i" : nome, st.campos)
            # Herda os valores do caso de mesma IDENTIDADE, para que um campo recusado
            # volte ao que estava e não ao default do descritor. Por identidade e não
            # por posição: a tela cria e remove casos por conta própria, então depois de
            # um "Remover" o índice `i` designa casos diferentes nas duas pontas, e a
            # restauração devolveria o valor do caso errado. Ver `novo_id` em state.jl.
            # Caso sem `id` é recém-criado na tela: não tem passado a herdar.
            anterior = get(por_id, string(get(c, "id", "")), nothing)
            if anterior !== nothing
                base.id = anterior.id
                merge!(base.lo, anterior.lo)
                merge!(base.hi, anterior.hi)
            end
            base.enabled = get(c, "enabled", true) === true
            escopo = "caso:$i"
            lo_in, hi_in = get(c, "lo", Dict()), get(c, "hi", Dict())
            for s in st.campos
                v = ler(lo_in, s.key, escopo, "lo"); v === nothing || (base.lo[s.key] = v)
                w = ler(hi_in, s.key, escopo, "hi"); w === nothing || (base.hi[s.key] = w)
            end
            push!(novos, base)
        end
        isempty(novos) || (st.casos = novos)
    end

    globais_in = get(payload, "globais", nothing)
    if globais_in !== nothing
        for s in st.ajustes
            v = ler(globais_in, s.key, "globais", "lo")
            v === nothing || (st.globais[s.key] = v)
        end
    end

    sel = get(payload, "sel", nothing)
    sel isa Integer && (st.sel = clamp(sel, 1, length(st.casos)))

    return avisos
end
