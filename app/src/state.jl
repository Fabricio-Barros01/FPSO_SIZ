"""
Estado da aplicação.

Uma decisão de UX que simplifica muito a interface: **todo campo é uma faixa**, com
duas colunas `mín` e `máx`. Valores iguais significam entrada fixa. Isso elimina o
par toggle-mais-segundo-campo por linha (que dobraria a contagem de widgets e o
código de sincronização) e torna o diferencial do software visível o tempo todo —
o usuário não precisa descobrir que existe um modo faixa.

Os parâmetros de grade (`d_min`, `d_max`, `d_step`, banda de SR) são **globais**, não
por caso: são decisão de projeto, não dado de corrente. Ficam num painel separado.

## Por que não há mais `Observable`

Na versão Makie cada campo era um `Observable` e a tela era `lift` deles. No navegador
o grafo reativo é o próprio DOM: o JavaScript pede, o servidor calcula, o JavaScript
redesenha. Aqui sobra só o dado — `mutable struct` de campos simples. `dimensionar!`
tem exatamente a mesma forma de antes; o que mudou é `st.resultado[] = res` virar
`st.resultado = res`.
"""

"Contador dos identificadores de caso; ver [`novo_id`](@ref)."
const _SEQ_CASO = Ref{Int}(0)

"""
    novo_id() -> String

Identificador de um caso, único no processo.

Existe porque [`aplicar!`](@ref) precisa saber **qual** caso do estado corresponde a cada
caso que o formulário mandou, e a posição no vetor não serve para isso: a tela cria e
remove casos sozinha (botões "+ Novo", "Duplicar" e "Remover"), então depois de uma
remoção o índice `i` designa casos diferentes nas duas pontas. Como `aplicar!` restaura
o valor anterior de um campo recusado, indexar por posição faria o valor **do caso
removido** reaparecer dentro do caso seguinte — dado errado entrando no envelope sem
nenhum aviso que o denunciasse.
"""
novo_id() = string("c", _SEQ_CASO[] += 1)

"""
Um caso como a interface o edita: dois valores por chave, iguais quando é escalar.

`id` não tem significado de engenharia nenhum e nunca chega ao core — é só a costura
entre a lista da tela e a lista do servidor. Ver [`novo_id`](@ref).
"""
mutable struct CaseUI
    id::String
    name::String
    enabled::Bool
    lo::Dict{Symbol,Float64}
    hi::Dict{Symbol,Float64}
end

"Converte um `FPSOSiz.Case` do core para a forma editável."
function CaseUI(c::FPSOSiz.Case, chaves)
    lo, hi = Dict{Symbol,Float64}(), Dict{Symbol,Float64}()
    for k in chaves
        v = get(c.values, k, nothing)
        v === nothing && continue
        if v isa FPSOSiz.Interval
            lo[k], hi[k] = v.lo, v.hi
        else
            lo[k] = hi[k] = v
        end
    end
    return CaseUI(novo_id(), c.name, c.enabled, lo, hi)
end

"Caso novo, preenchido com os defaults dos descritores."
function CaseUI(nome::AbstractString, specs::Vector{FPSOSiz.ParameterSpec})
    d = Dict{Symbol,Float64}(s.key => s.default for s in specs)
    return CaseUI(novo_id(), String(nome), true, copy(d), copy(d))
end

"Cópia com identidade **própria**: duplicar um caso cria outro caso, não um apelido."
Base.copy(c::CaseUI) = CaseUI(novo_id(), c.name, c.enabled, copy(c.lo), copy(c.hi))

"""
    campos_do_metodo(metodo, instancias) -> Vector{ParameterSpec}

Os descritores **por caso**, com os grupos repetíveis já expandidos nas suas instâncias.

Um método sem grupo nenhum (os cinco primeiros) sai daqui exatamente como entrava: o
`vcat` de sempre, menos as chaves globais. Um método com grupo (a Análise Pinch) troca
cada molde por `n` campos concretos, agrupados **por instância** e não por grandeza —
"Corrente 1: entrada, saída, CP; Corrente 2: …" é a ordem em que a pessoa lê, e a
contrária ("todas as entradas, depois todas as saídas") obrigaria a contar colunas.

A tela continua sem citar um parâmetro pelo nome: quem diz que existe um grupo chamado
`:corrente`, como ele se chama em português e quantas instâncias admite é
[`FPSOSiz.parameter_groups`](@ref), e quem sintetiza a chave é
[`FPSOSiz.instance_key`](@ref) — a mesma função que `case_input` usa para ler de volta.
"""
function campos_do_metodo(metodo::FPSOSiz.AbstractSizingMethod,
                          instancias::AbstractDict{Symbol,Int})
    todos   = vcat(FPSOSiz.stream_parameters(metodo), FPSOSiz.parameters(metodo))
    globais = FPSOSiz.global_keys(metodo)
    rotulos = Dict(g.key => g.label for g in FPSOSiz.parameter_groups(metodo))

    out  = FPSOSiz.ParameterSpec[]
    feitos = Set{Symbol}()
    for s in todos
        s.key in globais && continue
        if !FPSOSiz.in_group(s)
            push!(out, s)
            continue
        end
        # O grupo inteiro é emitido de uma vez, no lugar do seu PRIMEIRO molde; os
        # demais moldes do mesmo grupo são pulados, senão ele sairia repetido uma vez
        # por grandeza.
        s.group in feitos && continue
        push!(feitos, s.group)
        moldes = filter(t -> t.group === s.group, todos)
        for i in 1:get(instancias, s.group, 0), t in moldes
            push!(out, FPSOSiz.group_instance(t, i; prefixo = get(rotulos, s.group, "")))
        end
    end
    return out
end

"Quantas instâncias de cada grupo o método admite, no piso declarado no TOML."
instancias_iniciais(metodo::FPSOSiz.AbstractSizingMethod) =
    Dict{Symbol,Int}(g.key => g.min for g in FPSOSiz.parameter_groups(metodo))

"""
    instancias_dos_valores(metodo, valores) -> Dict{Symbol,Int}

Quantas instâncias um conjunto de chaves já gravadas descreve — o **maior índice** que
aparece, preso à faixa que o TOML declara.

É o maior índice, e não a contagem: um arquivo com `corrente_1_*` e `corrente_3_*` e sem
a 2 descreve três correntes, uma delas por preencher. Contar daria duas e faria a
terceira sumir em silêncio na primeira gravação.
"""
function instancias_dos_valores(metodo::FPSOSiz.AbstractSizingMethod, valores)
    out = Dict{Symbol,Int}()
    for g in FPSOSiz.parameter_groups(metodo)
        moldes = filter(t -> t.group === g.key, FPSOSiz.parameters(metodo))
        n = 0
        for i in 1:g.max
            any(t -> FPSOSiz.instance_key(g.key, i, t.key) in valores, moldes) && (n = i)
        end
        out[g.key] = clamp(n, g.min, g.max)
    end
    return out
end

"Converte de volta para o `Case` do core, mesclando os ajustes globais."
function to_case(c::CaseUI, globais::AbstractDict)
    vals = Dict{Symbol,Any}()
    for k in keys(c.lo)
        lo, hi = c.lo[k], c.hi[k]
        vals[k] = lo == hi ? lo : FPSOSiz.Interval(lo, hi)
    end
    for (k, v) in globais
        vals[k] = v
    end
    return FPSOSiz.Case(c.name, vals; enabled = c.enabled)
end

"""
Estado global da tela. Tudo o que a interface desenha vem de algum destes campos — não
há caminho por onde a tela mostre um número que não venha do core.
"""
mutable struct AppState
    equipamento::FPSOSiz.AbstractEquipment   # de qual box esta tela é
    metodo::FPSOSiz.AbstractSizingMethod
    campos::Vector{FPSOSiz.ParameterSpec}    # editáveis por caso, grupos já expandidos
    ajustes::Vector{FPSOSiz.ParameterSpec}   # globais (grade, banda de SR)
    # Quantas instâncias de cada grupo repetível estão à vista. É da TELA, e não de cada
    # caso: a rede de correntes é uma só, e os casos são cenários de operação dela. Com
    # uma contagem por caso, o envelope compararia redes diferentes e chamaria isso de
    # "o equipamento que atende a todos". Vazio para os métodos sem grupo nenhum.
    instancias::Dict{Symbol,Int}
    casos::Vector{CaseUI}
    sel::Int
    arquivo::String                          # nome do TOML de onde os casos vieram
    rotulo::String                           # `label` declarado nesse arquivo
    globais::Dict{Symbol,Float64}
    resultado::Union{FPSOSiz.EnvelopeResult,Nothing}
    # Do caso governante; ver `beta_atual`. Sem tipo concreto de propósito: cada método
    # tem o seu objeto de restrições, e um `VesselConstraints` aqui excluiria a bomba.
    cons_gov::Any
    d_sel::Float64
    status::String
    status_ok::Bool
end

"""
    AppState(; case_file)

Monta o estado inicial. `case_file` é procurado em `FPSOSiz.dirs_casos()` — o
diretório do usuário primeiro, os exemplos de fábrica depois. Arquivo ausente ou
ilegível vira um único caso nos defaults, com a queixa na barra de status.
"""
function AppState(; case_file::AbstractString = "exemplo_alves_komesu.toml",
                    equipamento::FPSOSiz.AbstractEquipment = FPSOSiz.Separator(),
                    metodo::FPSOSiz.AbstractSizingMethod = FPSOSiz.StewartArnold())
    # Os descritores saem do MÉTODO, não de listas fixas: os de corrente por
    # `stream_parameters(metodo)` (um vaso sem fase aquosa não mostra campos de água) e
    # os do método por `parameters(metodo)`. É a regra de src/interfaces.jl — trocar de
    # equipamento troca o formulário inteiro sem uma linha de `app/` saber o nome de
    # nenhum parâmetro.
    todos   = vcat(FPSOSiz.stream_parameters(metodo), FPSOSiz.parameters(metodo))
    # Quais parâmetros são decisão de projeto (painel único) e quais são dado de
    # corrente (um por caso) é o método que diz — ver `global_keys`. Era uma tupla fixa
    # de seis chaves de vaso aqui; a bomba tem outras quatro.
    globais    = FPSOSiz.global_keys(metodo)
    instancias = instancias_iniciais(metodo)
    # Os campos por caso passam por `campos_do_metodo` para que um método com grupo
    # repetível chegue à tela já expandido. Sem grupo, a função devolve o mesmo `filter`
    # que estava escrito aqui.
    campos  = campos_do_metodo(metodo, instancias)
    ajustes = filter(s -> s.key in globais, todos)

    st = AppState(equipamento, metodo, campos, ajustes, instancias, CaseUI[], 1, "", "",
                  Dict{Symbol,Float64}(s.key => s.default for s in ajustes),
                  nothing, nothing, 0.0,
                  "Pronto. Ajuste as entradas e clique em Dimensionar.", true)
    carregar_casos!(st, case_file)
    return st
end

"""
    rotulo_casos(nome) -> String

O `label` declarado no arquivo de casos, ou o próprio nome do arquivo quando ele não
declara nenhum. Sai de [`FPSOSiz.list_case_sets`](@ref) em vez de um `TOML.parsefile`
próprio para que a tela e o seletor de arquivos mostrem exatamente o mesmo texto.
"""
function rotulo_casos(nome::AbstractString)
    for a in FPSOSiz.list_case_sets()
        a.nome == nome && return a.rotulo
    end
    return String(nome)
end

"""
    definir_instancias!(st, novas) -> nothing

Muda quantas instâncias de cada grupo estão à vista e **reexpande `st.campos`**.

Os dois andam juntos sempre, e por isso moram numa função só: `st.campos` é a lista que
`aplicar!`, `CaseUI`, `salvar_casos!` e o formulário percorrem, e uma contagem que mude
sem ela produziria uma tela com quatro correntes e um estado com três — a tela e o
servidor deixando de se corresponder, que é o defeito 4 do Sprint 7 por outro caminho.

Cada valor é preso à faixa que o TOML declara, porque a contagem chega do navegador.
"""
function definir_instancias!(st::AppState, novas::AbstractDict)
    for g in FPSOSiz.parameter_groups(st.metodo)
        haskey(novas, g.key) || continue
        st.instancias[g.key] = clamp(Int(novas[g.key]), g.min, g.max)
    end
    st.campos = campos_do_metodo(st.metodo, st.instancias)
    return nothing
end

"""
    carregar_casos!(st, nome) -> Bool

Substitui a lista de casos pelo conteúdo do arquivo `nome`. Devolve `false` — e deixa
um caso em branco no lugar, com a queixa na barra de status — quando o arquivo não
existe ou não é legível.

Não dimensiona: quem chama decide. O construtor não pode dimensionar (o `AppState`
ainda está sendo montado) e [`abrir_casos!`](@ref) precisa.

Arquivo ilegível **não** lança. É o mesmo contrato do resto da tela: um TOML que o
usuário editou à mão e quebrou tem de virar mensagem, não uma janela que não abre.
"""
function carregar_casos!(st::AppState, nome::AbstractString)
    # Um arquivo de outro equipamento é RECUSADO, não avisado. As chaves que faltam
    # entrariam com o default do descritor (o `for` logo abaixo) e o vaso sairia
    # dimensionado a partir de dados que ninguém informou — a mesma classe de falha
    # silenciosa que a herança por posição tinha no Sprint 2. Arquivo que não declara
    # equipamento nenhum é aceito: é um TOML escrito à mão, e não temos o que conferir.
    meu = String(FPSOSiz.method_id(st.equipamento))
    for a in FPSOSiz.list_case_sets()
        a.nome == nome || continue
        (isempty(a.equipamento) || a.equipamento == meu) && break
        # A recusa tem de deixar a tela USÁVEL. Sem isto, `st.casos` fica vazio — e
        # ficava: o construtor cria a lista vazia e só `carregar_casos!` a preenche.
        # Uma tela sem caso nenhum não é um estado que o resto do programa preveja
        # (`caso_atual` indexa `st.casos[1]`), e chegar nela era um `--caso` apontando
        # para o arquivo de outro equipamento. Um caso em branco é o mesmo desfecho do
        # arquivo ilegível logo abaixo, e pelo mesmo motivo.
        isempty(st.casos) && (st.casos = [CaseUI("Caso 1", st.campos)]; st.sel = 1)
        st.status = "'$nome' é um conjunto de casos de outro equipamento " *
                    "($(a.equipamento)); esta tela é de $meu. Abra-o na aplicação dele."
        st.status_ok = false
        return false
    end

    cs = try
        FPSOSiz.load_case_set(nome)
    catch err
        st.casos = [CaseUI("Caso 1", st.campos)]
        st.sel, st.arquivo, st.rotulo = 1, "", ""
        st.status = "Não consegui abrir '$nome' (" * sprint(showerror, err) *
                    "). Comecei com um caso em branco."
        st.status_ok = false
        return false
    end

    # QUANTAS instâncias o arquivo descreve vem ANTES de montar os casos: `st.campos` é
    # quem diz quais chaves um `CaseUI` guarda, e ele ainda está com a contagem da tela
    # anterior. Sem este passo, abrir um arquivo de quatro correntes numa tela de duas
    # descartaria a terceira e a quarta em silêncio — e o "Salvar" seguinte gravaria por
    # cima do arquivo original com duas.
    definir_instancias!(st, instancias_dos_valores(
        st.metodo, Set(k for c in cs.cases for k in keys(c.values))))
    chaves = [s.key for s in st.campos]

    novos = isempty(cs.cases) ? [CaseUI("Caso 1", st.campos)] :
                                [CaseUI(c, chaves) for c in cs.cases]
    # caso carregado do TOML pode omitir chaves: completa com os defaults
    for c in novos, s in st.campos
        haskey(c.lo, s.key) || (c.lo[s.key] = c.hi[s.key] = s.default)
    end

    st.casos = novos
    st.sel = 1
    st.arquivo = String(nome)
    st.rotulo = rotulo_casos(nome)
    return true
end

"""
    redimensionar_sem_perder_queixa!(st) -> nothing

Roda [`dimensionar!`](@ref) preservando na barra de status a queixa que já estava lá.

Existe para um par de exigências que se contradizem. Um arquivo que não abriu deixa a
tela com um caso em branco, e ela **precisa** ser redimensionada: sem isso o desenho, o
cartão, a grade do cursor e o memorial continuariam mostrando o resultado do conjunto
*anterior*, que já não está mais em lugar nenhum — números de um vaso que a tela não
tem mais como explicar. Mas `dimensionar!` escreve a própria mensagem por cima, e a
mensagem que interessa é a primeira: por que o arquivo não abriu.
"""
function redimensionar_sem_perder_queixa!(st::AppState)
    queixa = st.status_ok ? "" : st.status
    dimensionar!(st)
    if !isempty(queixa)
        st.status = queixa
        st.status_ok = false
    end
    return nothing
end

"""
    abrir_casos!(st, nome) -> Bool

Abre um conjunto de casos e redimensiona. O que estava na tela é **substituído** — o
aviso de que há edição não salva é da interface, que é quem sabe se houve edição.

Redimensiona nos **dois** desfechos: ver [`redimensionar_sem_perder_queixa!`](@ref).
"""
function abrir_casos!(st::AppState, nome::AbstractString)
    if carregar_casos!(st, nome)
        # A queixa que estivesse na barra é do conjunto anterior; este é outro.
        st.status, st.status_ok = "", true
        dimensionar!(st)
        st.status = "Abri '$nome' — $(length(st.casos)) caso(s). " * st.status
        return true
    end
    redimensionar_sem_perder_queixa!(st)
    return false
end

"""
    salvar_casos!(st, nome; rotulo) -> NamedTuple

Grava os casos da tela em `dir_casos()/nome`. Devolve `(; ok, caminho)`.

Os ajustes globais (grade de diâmetro, banda de SR) **não** entram no arquivo: eles são
decisão de projeto, não dado de corrente, e o leitor os descartaria de qualquer forma —
`CaseUI` só guarda as chaves de `st.campos`. Daí o dicionário vazio no lugar de
`st.globais` na chamada a [`to_case`](@ref): gravar o que não volta é como não gravar,
mas com a aparência de ter gravado.
"""
function salvar_casos!(st::AppState, nome::AbstractString;
                       rotulo::AbstractString = "")
    try
        cs = FPSOSiz.CaseSet([to_case(c, Dict{Symbol,Float64}()) for c in st.casos])
        caminho = FPSOSiz.save_case_set_named(
            cs, nome; label = rotulo,
            equipment = String(FPSOSiz.method_id(st.equipamento)))
        st.arquivo = String(nome)
        st.rotulo = String(rotulo)
        st.status = "$(length(st.casos)) caso(s) salvos em $caminho"
        st.status_ok = true
        return (; ok = true, caminho)
    catch err
        st.status = "Falha ao salvar '$nome': " * sprint(showerror, err)
        st.status_ok = false
        return (; ok = false, caminho = "")
    end
end

"O caso atualmente selecionado."
caso_atual(st::AppState) = st.casos[clamp(st.sel, 1, length(st.casos))]

"Rótulos para o seletor de casos, marcando os desativados."
nomes_menu(st::AppState) = [c.enabled ? c.name : "○ " * c.name for c in st.casos]

"""
    dimensionar!(st) -> nothing

Roda o motor de envelope sobre os casos ativos e publica o resultado. Erros viram
mensagem de status — a tela nunca cai por entrada inválida.
"""
function dimensionar!(st::AppState)
    cs = FPSOSiz.CaseSet([to_case(c, st.globais) for c in st.casos])

    if isempty(FPSOSiz.active(cs))
        st.resultado = nothing
        st.cons_gov = nothing
        st.status = "Nenhum caso ativo — ative ao menos uma corrente."
        st.status_ok = false
        return nothing
    end

    n = FPSOSiz.corner_count(cs)
    res = try
        FPSOSiz.size_envelope(st.equipamento, st.metodo, cs; max_corners = 512)
    catch err
        st.resultado = nothing
        st.cons_gov = nothing
        st.status = "Erro inesperado: " * sprint(showerror, err)
        st.status_ok = false
        return nothing
    end

    st.resultado = res
    st.cons_gov = restricoes_governantes(st, cs, res)
    st.status_ok = res.feasible
    if res.feasible
        st.d_sel = res.x
        st.status = "$(length(cs.cases)) caso(s) → $n canto(s) avaliado(s). " *
                    FPSOSiz.governing_summary(st.metodo, res)
    else
        isempty(res.rows) || (st.d_sel = cursor_inviavel(st, res.rows))
        st.status = res.message
    end
    return nothing
end

"""
    cursor_inviavel(st, rows) -> Float64

Onde pôr o cursor quando não há projeto viável — porque o desenho, os gráficos e a
tabela continuam existindo, e servem ao diagnóstico.

Num vaso é onde a esbeltez chega mais perto do alvo pedido: é o ponto de onde o usuário
enxerga o quanto faltou. `sr_target` vem dos ajustes da tela, não de um literal — a
regra do projeto é que constante de método mora em TOML. Para um método sem esbeltez,
o meio da grade, que é o palpite honesto de quem não tem critério.
"""
function cursor_inviavel(st::AppState, rows)
    alvo = get(st.globais, :sr_target, NaN)
    (isfinite(alvo) && haskey(first(rows).derivados, :sr)) ||
        return rows[(length(rows) + 1) ÷ 2].x
    return argmin(r -> abs(r.derivados[:sr] - alvo), rows).x
end

"Pontos do eixo disponíveis para o cursor, a partir do último resultado."
function grade_slider(st::AppState)
    r = st.resultado
    (r === nothing || isempty(r.rows)) &&
        return FPSOSiz.sweep_axis(st.metodo, st.globais).values
    return [row.x for row in r.rows]
end

"""
    restricoes_governantes(st, cs, res) -> restrições do método | nothing

As restrições do caso que governou o resultado — de onde saem β e a fração de área da
fase aquosa, que o desenho usa.

Calculado **uma vez por dimensionamento** e guardado em `st.cons_gov`. Antes era
recalculado dentro de `beta_atual`, que `desenho` chama e que o cursor de diâmetro
chama a cada movimento: re-expandia todos os casos e re-rodava a física inteira, laço
de convergência do arrasto incluído, dez vezes por movimento no exemplo de referência.
"""
function restricoes_governantes(st::AppState, cs, res)
    (res === nothing || !res.feasible) && return nothing
    k = FPSOSiz.constants(FPSOSiz.method_config(st.metodo))
    specs = FPSOSiz.parameters(st.metodo)
    for (nome, vals) in FPSOSiz.expand(cs; max_corners = 512)
        nome == res.driver_case || continue
        entrada = try
            FPSOSiz.case_input(st.metodo, vals)
        catch
            return nothing
        end
        ok, cons, _ = FPSOSiz.sizing_constraints(st.metodo, entrada,
                                                 FPSOSiz.with_defaults(specs, vals), k)
        return ok ? cons : nothing
    end
    return nothing
end

"""
    beta_atual(st) -> Float64

β do caso governante, para o desenho — ou `NaN` quando não há.

`NaN` e não um número plausível: o valor anterior aqui era `0.25`, que produzia um
desenho de **aparência correta e conteúdo errado** sempre que o caso governante não
fosse encontrado, sem nada que denunciasse. `NaN` faz `camadas` devolver as duas faixas
de um vaso sem interface líquido-líquido, que é a leitura honesta de "não sei onde ela
está" — e é o mesmo valor que um vaso bifásico produz de direito.
"""
beta_atual(st::AppState) =
    st.cons_gov isa FPSOSiz.VesselConstraints ? st.cons_gov.beta : NaN

"""
    camadas_atual(st) -> Vector{PhaseLayer}

Como o **método** reparte a seção transversal do caso governante — as faixas que o
desenho empilha.

É o par de [`beta_atual`](@ref) e substitui o papel que β tinha aqui. β é um
coeficiente: sozinho ele não diz quantas fases o vaso tem, e deduzir três de um número
era o que punha metade de gás num tratador cheio de líquido e uma camada de água de
altura negativa embaixo dela. Quem sabe quantas fases há é `cross_section`, despachada
pelo método.

Vazio significa "não sei repartir" — sem resultado, ou método que não declarou
repartição. O desenho mostra o casco sem fases, que é honesto.
"""
camadas_atual(st::AppState) =
    st.cons_gov === nothing ? FPSOSiz.PhaseLayer[] :
    FPSOSiz.cross_section(st.metodo, st.cons_gov)
