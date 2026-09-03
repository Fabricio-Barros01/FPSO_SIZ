#
# aquecimento.jl — `precompile_execution_file` do PackageCompiler.
#
# O PackageCompiler roda este arquivo durante o build e grava no sysimage tudo o que
# for compilado aqui. É por isso que o executável abre em menos de um segundo em vez de
# gastar meio minuto compilando o HTTP e o Genie na primeira requisição do usuário.
#
# A regra para o que entra: **o caminho que o usuário percorre no primeiro minuto**.
# Abrir a tela, dimensionar, arrastar o cursor, exportar. Exercitar mais do que isso
# só engorda o sysimage.
#
# Nada aqui pode derrubar o build: uma porta ocupada na máquina de CI não é motivo para
# não haver programa. Por isso o `try` externo — o pior caso é um executável que demora
# mais para abrir, não um build que falha.

using FPSOSizApp
using HTTP
using JSON3

import FPSOSiz

const A = FPSOSizApp

try
    # Sem tocar na pasta de saída de quem estiver compilando.
    mktempdir() do tmp
        withenv("FPSOSIZ_SAIDA" => tmp) do
            FPSOSiz._SAIDA[] = ""

            # --- o núcleo do que a tela faz
            st = A.AppState()
            A.dimensionar!(st)
            g = A.geometry_from(st.resultado, st.d_sel, A.beta_atual(st))
            A.svg_elevacao(g)
            A.svg_corte(g)
            A.svg_grafico_envelope(st.resultado, st.d_sel)
            A.svg_grafico_banda(st.resultado, st.d_sel, :sr, (3.0, 5.0), 4.0)
            A.html_legenda_casos(st.resultado)
            # `figuras` e `figuras_grandes` despacham no método e chamam os quatro
            # desenhos: aquecê-las cobre o caminho da tela e o da exportação.
            A.figuras(st); A.figuras_grandes(st)
            A.esquema(st); A.estado(st); A.cartao(st); A.tabela(st); A.desenho(st)
            A.aplicar!(st, Dict{String,Any}("sel" => 1))
            A.exportar!(st)

            # --- e o ciclo HTTP inteiro, que é a parte cara de compilar
            A.reiniciar_estado!()
            porta = A.porta_livre(0)
            @async A.servir(; porta, abrir = false, bloquear = false)

            base = "http://127.0.0.1:$porta"
            for _ in 1:60
                try
                    HTTP.get(base; retry = false, status_exception = false)
                    break
                catch
                    sleep(0.25)
                end
            end

            # As rotas com estado são prefixadas pelo box desde o Sprint 6
            # (`/api/<box>/…`). Sem o prefixo elas respondiam 404, o `JSON3.read`
            # lançava e o aquecimento HTTP inteiro — que é a parte cara de compilar —
            # caía no `catch` lá embaixo, com um aviso que ninguém leu. O executável
            # continuava correto e abria devagar, que é exatamente o problema que este
            # arquivo existe para evitar.
            api = "$base/api/separador-3f"

            HTTP.get(base; status_exception = false)
            HTTP.get("$base/app.css"; status_exception = false)
            HTTP.get("$base/menu.js"; status_exception = false)
            HTTP.get("$base/app/separador-3f"; status_exception = false)
            HTTP.get("$api/esquema"; status_exception = false)
            r = HTTP.post("$api/dimensionar"; body = "{}", status_exception = false)
            r.status == 200 || error("aquecimento: /dimensionar devolveu $(r.status)")
            JSON3.read(String(r.body), Dict{String,Any})
            HTTP.post("$api/desenho"; body = """{"d":"5500"}""",
                      status_exception = false)
            HTTP.get("$api/memorial"; status_exception = false)
            HTTP.get("$api/casos/arquivos"; status_exception = false)
            HTTP.post("$api/exportar"; body = "{}", status_exception = false)

            try
                A.Genie.down()
            catch
            end
            A.reiniciar_estado!()
        end
    end

    # --- e o modo lote, que é o caminho de quem roda sem navegador
    mktempdir() do tmp
        withenv("FPSOSIZ_SAIDA" => tmp) do
            FPSOSiz._SAIDA[] = ""
            A.modo_lote()
        end
    end
catch err
    @warn "aquecimento incompleto — o executável funciona, só abre mais devagar" exception = err
end

# O memoizado do diretório de saída não pode viajar para dentro do sysimage apontando
# para um `mktempdir` que não existirá mais.
FPSOSiz._SAIDA[] = ""
FPSOSiz._RAIZ[] = ""
