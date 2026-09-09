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
function esquema(st::AppState)
    eixo = FPSOSiz.sweep_axis(st.metodo, st.globais)
    return Dict{String,Any}(
    "campos"      => [spec_json(s) for s in st.campos],
    "ajustes"     => [spec_json(s) for s in st.ajustes],
    "equipamento" => FPSOSiz.label(st.equipamento),
    "metodo"      => FPSOSiz.label(st.metodo),
    # O rótulo do cursor: "diâmetro (mm)" num vaso, "diâmetro nominal (mm)" numa bomba.
    # Estava escrito à mão em index.html, o que fazia a tela conhecer a grandeza.
    "eixo"        => Dict{String,Any}("label" => eixo.label, "unit" => eixo.unit),
    "paleta"      => Dict{String,Any}(
        "destaque" => Formato.DESTAQUE, "erro" => Formato.ERRO,
        "ok" => Formato.OK, "tinta_fraca" => Formato.TINTA_FRACA),
    )
end

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

"Linha da varredura mais próxima do ponto selecionado no eixo."
function linha_sel(r, x)
    (r === nothing || isempty(r.rows)) && return nothing
    return argmin(row -> abs(row.x - x), r.rows)
end

"""
    _no_cursor(r, l) -> NamedTuple

A linha do cursor vestida de resultado, para atravessar
[`FPSOSiz.result_fields`](@ref).

O cartão segue o **cursor**, não o ótimo: arrastar o controle mostra o que aquele ponto
daria. Mas `result_fields` recebe um resultado, e uma linha de varredura não tem
`feasible` nem o teto do eixo — que são do conjunto, não do ponto. Juntar os dois aqui é
mais honesto que dar a cada linha uma cópia de campos que não são dela.
"""
_no_cursor(r, l) = (; feasible = true, x = l.x, y = l.y, derivados = l.derivados,
                      governing = l.governing, driver_case = l.driver_case,
                      ceiling = r.ceiling, ok = l.ok)

"""
    cartao(st) -> Vector{Dict}

O cartão de resultados da coluna direita, já em texto.

Os campos vêm de [`FPSOSiz.result_fields`](@ref), declarados pelo método — não são mais
oito chaves fixas com nome de vaso. É a mesma regra do formulário desde o Sprint 0,
estendida ao resultado: a tela itera e desenha, sem saber que existe uma grandeza
chamada esbeltez.
"""
function cartao(st::AppState)
    r = st.resultado
    l = linha_sel(r, st.d_sel)
    alvo = l === nothing ? _vazio_para_cartao(r) : _no_cursor(r, l)
    return [campo_json(f) for f in FPSOSiz.result_fields(st.metodo, alvo)]
end

# Sem varredura ainda: o cartão precisa existir com os rótulos certos e travessão nos
# valores, senão a coluna da direita muda de altura entre "antes" e "depois" de
# dimensionar — e o rótulo é o que diz ao usuário o que ele vai receber.
_vazio_para_cartao(r) = (; feasible = false, x = NaN, y = NaN,
                           derivados = Dict{Symbol,Float64}(), governing = :none,
                           driver_case = "—", ceiling = NaN, ok = false)

"Um [`FPSOSiz.ResultField`](@ref) já formatado em PT-BR."
function campo_json(f::FPSOSiz.ResultField)
    texto = if f.value isa AbstractString
        f.value
    elseif isfinite(f.value)
        Formato.num(f.value, f.digits) * (isempty(f.unit) ? "" : " " * f.unit)
    else
        "—"
    end
    marca = f.status === :ok ? " ✓" : f.status === :erro ? " ✗" : ""
    return Dict{String,Any}("rotulo" => f.label, "valor" => texto * marca,
                            "destaque" => f.highlight, "status" => String(f.status))
end

"""
    tabela(st; n_linhas) -> Dict

Vizinhança do ponto selecionado na varredura: as colunas que o método declarou em
[`FPSOSiz.sweep_columns`](@ref) e o mesmo recorte de nove linhas centrado no cursor.

Linhas fora da grade vêm vazias, para que a tabela não mude de altura ao chegar nas
pontas — e o cabeçalho viaja junto, porque quem decide se a terceira coluna é `Lss` ou
`v` é o método.
"""
function tabela(st::AppState; n_linhas::Int = 9)
    r = st.resultado
    cols = FPSOSiz.sweep_columns(st.metodo)
    cabecalho = [c.label for c in cols]
    vazia = Dict{String,Any}("valores" => ["" for _ in cols],
                             "centro" => false, "ok" => false)

    (r === nothing || isempty(r.rows)) &&
        return Dict{String,Any}("colunas" => cabecalho,
                                "linhas" => [vazia for _ in 1:n_linhas])

    centro = argmin(k -> abs(r.rows[k].x - st.d_sel), eachindex(r.rows))
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
            "valores" => [Formato.num(FPSOSiz.column_value(row, c), c.digits)
                          for c in cols],
            "centro"  => k == centro,
            "ok"      => row.ok))
    end
    return Dict{String,Any}("colunas" => cabecalho, "linhas" => linhas)
end

"""
    desenho(st) -> Dict

As figuras deste equipamento mais a legenda de casos. É o que o cursor troca a cada
movimento: a varredura já está calculada, então isto é formatação, não recálculo.

A lista de figuras vem de [`figuras`](@ref), que despacha no método — quatro no vaso,
uma no fallback genérico, e o que a bomba do Sprint 8 declarar.
"""
desenho(st::AppState) = Dict{String,Any}(
    "figuras" => figuras(st),
    "legenda" => html_legenda_casos(
        st.resultado; unidade = FPSOSiz.requirement_spec(st.metodo)[2]))

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
        for (id, titulo) in blocos_memorial(st.metodo, res.trace)
            linhas = [linha_memorial(e) for e in FPSOSiz.block_entries(res.trace, id)]
            # Bloco vazio não vira subtítulo órfão: um método que não use um dos blocos
            # (o vaso bifásico do Sprint 5 não usa o B) simplesmente não o mostra.
            isempty(linhas) || push!(blocos, Dict{String,Any}(
                "id" => String(id), "titulo" => titulo, "linhas" => linhas))
        end
        push!(casos, Dict{String,Any}("nome" => nome, "viavel" => res.feasible,
                                      "fecho" => fecho_memorial(st.metodo, res),
                                      "blocos" => blocos))
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
function arquivos(st::AppState)
    # Só os arquivos que servem a ESTE equipamento. Listar os outros seria oferecer um
    # clique que `carregar_casos!` vai recusar — melhor não oferecer. Arquivo sem
    # `equipment` declarado aparece: é TOML escrito à mão, e não há o que conferir.
    meu = String(FPSOSiz.method_id(st.equipamento))
    lista = filter(a -> isempty(a.equipamento) || a.equipamento == meu,
                   FPSOSiz.list_case_sets())
    return _arquivos_json(st, lista)
end

_arquivos_json(st::AppState, lista) = Dict{String,Any}(
    "arquivos" => [Dict{String,Any}("nome" => a.nome, "rotulo" => a.rotulo,
                                    "casos" => a.casos, "gravavel" => a.gravavel)
                   for a in lista],
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
