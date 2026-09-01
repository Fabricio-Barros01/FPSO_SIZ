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
    fecho_memorial(res) -> String

A linha que encerra o rastro de um caso, com o que ele daria dimensionado sozinho.
Separada pelo mesmo motivo que [`linha_memorial`](@ref): vai para o `.txt` e para a
tela, e os dois têm de dizer exatamente a mesma coisa.
"""
fecho_memorial(res) = res.feasible ?
    "  → d = $(Formato.inteiro(res.diameter_mm)) mm, SR = $(Formato.num(res.sr))" :
    "  → inviável isolado: $(res.message)"

"""
Blocos do memorial, na ordem do cálculo, com o nome que a tela mostra.

Os símbolos são os que `stewart_arnold.jl` carimba em cada `TraceEntry`. A ordem é a em
que o método os percorre, e não alfabética: um memorial só se lê de cima para baixo. As
letras A/B/C são as de Stewart & Arnold — as mesmas que o Sprint 5 vai reaproveitar num
vaso bifásico, que usa A e C sem o B.
"""
const BLOCOS_MEMORIAL = (:gas       => "Bloco A — capacidade de gás",
                         :settling  => "Bloco B — decantação",
                         :liquid    => "Bloco C — capacidade de líquido",
                         :selection => "Seleção do diâmetro")

"""
    exportar!(st) -> NamedTuple

Grava a varredura envelope (uma coluna por caso), o memorial de cálculo e as duas
figuras. Escreve o resultado na barra de status em vez de lançar — exportação falhando
não pode derrubar a interface.

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
        escrever_csv(csv, r, rotulo_metodo)
        escrever_memorial(memorial, r, rotulo_metodo,
                          FPSOSiz.method_reference(st.metodo))

        # Uma figura por arquivo. Concatenar dois `<svg>` num arquivo só daria dois
        # elementos-raiz, o que não é XML válido: o visualizador recusa o arquivo
        # inteiro, não só a segunda figura. Separadas, ainda vão cada uma para o ponto
        # do documento onde fazem sentido.
        g = geometry_from(r, st.d_sel, beta_atual(st))
        banda = (st.globais[:sr_min], st.globais[:sr_max])
        figuras = (
            "_vaso.svg"    => svg_elevacao(g; larg = 1100),
            "_corte.svg"   => svg_corte(g; larg = 520),
            "_leff.svg"    => svg_grafico_leff(r, st.d_sel; larg = 700, alt = 320),
            "_sr.svg"      => svg_grafico_sr(r, st.d_sel, banda, st.globais[:sr_target];
                                             larg = 700, alt = 320),
        )
        caminhos_svg = String[]
        for (sufixo, svg) in figuras
            caminho = base * sufixo
            write(caminho, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" * svg)
            push!(caminhos_svg, caminho)
        end

        arquivos = [csv, memorial, caminhos_svg...]
        st.status = "Exportado em $(dir): " * join(basename.(arquivos), ", ")
        st.status_ok = true
        return (; ok = true, arquivos, dir)
    catch err
        st.status = "Falha ao exportar: " * sprint(showerror, err)
        st.status_ok = false
        return (; ok = false, arquivos = String[], dir = "")
    end
end

"Varredura envelope: cabeçalho com o projeto escolhido e uma coluna de Leff por caso."
function escrever_csv(caminho::AbstractString, r, metodo::AbstractString)
    open(caminho, "w") do io
        println(io, "# FPSO_Siz — varredura envelope")
        println(io, "# método;", metodo)
        println(io, "# casos;", length(r.case_names))
        if r.feasible
            println(io, "# projeto;d=", Formato.inteiro(r.diameter_mm), " mm;Leff=",
                    Formato.num(r.leff_m), " m;Lss=", Formato.num(r.lss_m),
                    " m;SR=", Formato.num(r.sr))
            println(io, "# ", FPSOSiz.governing_summary(r))
        else
            println(io, "# INVIÁVEL;", r.message)
        end
        println(io)

        cabecalho = ["d (mm)", "Leff envelope (m)", "Lss (m)", "SR",
                     "governa", "caso governante", "SR na banda"]
        append!(cabecalho, ["Leff — " * n * " (m)" for n in r.case_names])
        println(io, join(cabecalho, ";"))

        for row in r.rows
            campos = [Formato.inteiro(row.d_mm), Formato.num(row.leff_m),
                      Formato.num(row.lss_m), Formato.num(row.sr),
                      row.governing === :gas ? "gás" : "líquido",
                      row.driver_case, row.sr_ok ? "sim" : "não"]
            append!(campos, [Formato.num(v) for v in row.per_case_leff])
            println(io, join(campos, ";"))
        end
    end
    return caminho
end

"Memorial: o rastro de cálculo de cada caso, equação por equação."
function escrever_memorial(caminho::AbstractString, r, metodo::AbstractString,
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
            println(io, fecho_memorial(res))
            println(io)
        end
    end
    return caminho
end
