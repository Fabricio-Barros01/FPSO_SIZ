"""
Exportação: varredura em CSV, memorial de cálculo em texto e as figuras em SVG.

CSV em ponto-e-vírgula com vírgula decimal — é o que o Excel em português abre com
duplo clique sem passar pelo assistente de importação.

As figuras saem em SVG, e não mais em PNG: sem CairoMakie não há rasterizador no
programa, e o SVG é a mesma string que a tela mostra. Vetorial também entra melhor num
documento do que um bitmap de resolução fixa.
"""

"Carimbo de tempo para o nome do arquivo."
carimbo() = Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")

"Onde os arquivos são gravados. Resolvido pelo core, que conhece o layout do bundle."
dir_saida() = FPSOSiz.dir_saida()

"""
    linha_memorial(e) -> String

Uma linha do rastro de cálculo, em colunas fixas. Função separada porque a mesma linha
vai para o arquivo de texto e, no painel de memorial da tela, para o HTML — se cada um
formatasse do seu jeito, os dois divergiriam sem ninguém notar.
"""
linha_memorial(e) = string(rpad(String(e.block), 10), rpad(e.eq, 10),
                           rpad(e.var, 24), rpad(Formato.num(e.value, 5), 16),
                           rpad(e.unit, 8), e.formula)

"""
    fecho_memorial(m, res) -> String

A linha que encerra o rastro de um caso, com o que ele daria dimensionado sozinho.
Separada pelo mesmo motivo que [`linha_memorial`](@ref): vai para o `.txt` e para a
tela, e os dois têm de dizer exatamente a mesma coisa.

O que ela imprime são os campos que o método marcou como **destaque** e os que carregam
um sinal de aprovação — num vaso, o diâmetro e a esbeltez, que é o que estava escrito à
mão aqui. Recebe o método porque só ele sabe quais são.
"""
function fecho_memorial(m, res)
    res.feasible || return "  → inviável isolado: $(res.message)"
    campos = FPSOSiz.result_fields(m, res)
    mostra = filter(f -> f.highlight || f.status !== :neutro, campos)
    isempty(mostra) && (mostra = campos[1:min(2, length(campos))])
    return "  → " * join([_campo_curto(f) for f in mostra], ", ")
end

function _campo_curto(f::FPSOSiz.ResultField)
    v = f.value isa AbstractString ? f.value :
        isfinite(f.value) ? Formato.num(f.value, f.digits) : "—"
    return string(f.label, " = ", v, isempty(f.unit) ? "" : " " * f.unit)
end

"""
    blocos_memorial(m, tr) -> Vector{Pair{Symbol,String}}

Os blocos do memorial, na ordem do cálculo, com o título que a tela mostra.

Vem de [`FPSOSiz.trace_blocks`](@ref), declarado pelo método — era uma constante daqui
com as letras A/B/C de Stewart & Arnold, o que fazia o memorial de uma bomba prometer
"Bloco B — decantação". Um método que não declare nada cai na ordem de aparição no
rastro, que é a ordem do cálculo: legível sem títulos em português, e é o que um
equipamento novo ganha de graça.
"""
function blocos_memorial(m, tr)
    declarados = FPSOSiz.trace_blocks(m)
    isempty(declarados) || return declarados
    return [b => String(b) for b in FPSOSiz.trace_block_order(tr)]
end

"""
    exportar!(st) -> NamedTuple

Grava a varredura envelope (uma coluna por caso), o memorial de cálculo e as figuras
que o método declara. Escreve o resultado na barra de status em vez de lançar —
exportação falhando não pode derrubar a interface.

## Os dois memoriais, e por que são dois

* `_memorial.txt` — o **rastro**, em colunas de largura fixa, de TODOS os casos de canto
  do envelope. Responde "que contas o programa fez, em cada canto".
* `_memorial.html` — o **documento** de quatro folhas A4 do caso governante, com bloco de
  título, equações em simbologia e quadro de revisões. Responde "o que se assina".

São perguntas diferentes, e nenhum dos dois substitui o outro — é a mesma distinção que
`docs/validacao/08-memorial.md` §10 registra na lacuna 5.

O `.html` sai **autocontido** (`css = :embutido`): ele é gravado para ser aberto por
duplo clique, com o programa já fechado, e um `href="/memorial.css"` ali não resolveria
para nada. Sai também **editável**, que é o default do documento — quem imprime corrige
cliente e executor na tela antes do Ctrl+P.

Só sai quando o método declara `memorial_spec`. Um método sem spec não perde a
exportação por isso: o CSV, o `.txt` e as figuras saem como sempre.

Devolve `(; ok, arquivos, dir)`.
"""
function exportar!(st::AppState)
    r = st.resultado
    if r === nothing || isempty(r.rows)
        st.status = "Nada para exportar: dimensione primeiro."
        st.status_ok = false
        return (; ok = false, arquivos = String[], dir = "")
    end

    try
        dir = dir_saida()
        base = joinpath(dir, "fpso_siz_$(carimbo())")
        csv      = base * "_varredura.csv"
        memorial = base * "_memorial.txt"

        # O rótulo do método vem do estado, não de um `StewartArnold()` fixo: o CSV e o
        # memorial de um vaso bifásico têm de dizer qual método os produziu.
        rotulo_metodo = FPSOSiz.label(st.metodo)
        escrever_csv(csv, st, r, rotulo_metodo)
        escrever_memorial(memorial, st.metodo, r, rotulo_metodo,
                          FPSOSiz.method_reference(st.metodo))

        # As figuras são as que o método declara — ver `figuras_exportadas`. Uma por
        # arquivo, e cada uma vai para o ponto do documento onde faz sentido.
        caminhos_svg = String[]
        for (sufixo, svg) in figuras_exportadas(st)
            caminho = base * sufixo
            write(caminho, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" * svg)
            push!(caminhos_svg, caminho)
        end

        # O documento A4. `tem_memorial` é a mesma guarda que a rota usa para esconder o
        # link na tela: onde não há spec, não há documento a gravar — e isso não é falha.
        doc = String[]
        if FPSOSiz.tem_memorial(st.metodo)
            caminho = base * "_memorial.html"
            write(caminho, memorial_documento(st; css = :embutido))
            push!(doc, caminho)
        end

        arquivos = [csv, memorial, doc..., caminhos_svg...]
        st.status = "Exportado em $(dir): " * join(basename.(arquivos), ", ")
        st.status_ok = true
        return (; ok = true, arquivos, dir)
    catch err
        st.status = "Falha ao exportar: " * sprint(showerror, err)
        st.status_ok = false
        return (; ok = false, arquivos = String[], dir = "")
    end
end

"""
Varredura envelope: cabeçalho com o projeto escolhido e uma coluna por caso.

As colunas são as **mesmas** que a tabela da tela mostra (`FPSOSiz.sweep_columns`), e
não uma segunda lista escrita aqui: duas listas divergiriam no primeiro método novo, e
quem confere o CSV contra a tela não teria como saber qual das duas está certa.
"""
function escrever_csv(caminho::AbstractString, st::AppState, r, metodo::AbstractString)
    m = st.metodo
    cols = FPSOSiz.sweep_columns(m)
    open(caminho, "w") do io
        println(io, "# FPSO_Siz — varredura envelope")
        println(io, "# método;", metodo)
        println(io, "# casos;", length(r.case_names))
        if r.feasible
            println(io, "# projeto;",
                    join([_campo_curto(f) for f in FPSOSiz.result_fields(m, r)], ";"))
            println(io, "# ", FPSOSiz.governing_summary(m, r))
        else
            println(io, "# INVIÁVEL;", r.message)
        end
        println(io)

        cabecalho = [c.label for c in cols]
        append!(cabecalho, ["governa", "caso governante", "admissível"])
        append!(cabecalho, ["envelope — " * n for n in r.case_names])
        println(io, join(cabecalho, ";"))

        for row in r.rows
            campos = [Formato.num(FPSOSiz.column_value(row, c), c.digits) for c in cols]
            append!(campos, [FPSOSiz.governing_label(m, row.governing),
                             row.driver_case, row.ok ? "sim" : "não"])
            append!(campos, [Formato.num(v) for v in row.per_case_y])
            println(io, join(campos, ";"))
        end
    end
    return caminho
end

"Memorial: o rastro de cálculo de cada caso, equação por equação."
function escrever_memorial(caminho::AbstractString, m, r, metodo::AbstractString,
                           referencia::AbstractString = "")
    open(caminho, "w") do io
        println(io, "FPSO_Siz — memorial de cálculo")
        println(io, metodo)
        isempty(referencia) || println(io, "Referência: ", referencia)
        println(io, repeat("=", 78), "\n")
        for (nome, res) in zip(r.case_names, r.per_case)
            println(io, "CASO: ", nome)
            println(io, repeat("-", 78))
            for e in res.trace.entries
                println(io, linha_memorial(e))
            end
            println(io, fecho_memorial(m, res))
            println(io)
        end
    end
    return caminho
end
