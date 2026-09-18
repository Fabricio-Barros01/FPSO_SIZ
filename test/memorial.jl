"""
A camada documental do memorial: o que ela promete e o que a mantém honesta.

Um memorial de cálculo falha de três maneiras, e nenhuma delas é ruidosa:

1. **documentando uma equação que o programa não resolve** — o revisor confere uma conta
   que não foi feita;
2. **calculando um número que o documento não explica** — aparece um valor na folha de
   resultados sem nada que diga de onde veio;
3. **carregando um número escrito à mão na camada documental** — o documento e a tela
   passam a ter duas fontes para a mesma grandeza, e divergem no primeiro caso de canto.

Os testes abaixo fecham as três portas. A de nº 3 é fechada **estruturalmente**: nenhum
tipo de `src/memorial.jl` tem campo numérico, então não existe onde guardar um valor
calculado. É a mesma ideia do `NaN` em vez de `0.0` no `VesselConstraints` — em vez de
confiar na disciplina, torna-se impossível.

# Por que este arquivo é dirigido por tabela

Porque a alternativa envelhece. Escrito método a método, um `memorial_spec` novo entra no
programa sem teste nenhum até que alguém se lembre de copiar o bloco — e o que este
arquivo verifica é justamente o tipo de erro que ninguém vê ao escrever a spec (uma
equação documentada que o motor não resolve, uma verificação apontando para um campo que
não existe mais).

`METODOS_COM_MEMORIAL` sai do REGISTRO, filtrado por quem declara spec. Registrar um
método com memorial é entrar nesta bateria; não há como escapar dela por omissão.
"""

"""
    _valores(m) -> Dict

Os defaults de corrente e de método, que é o caso que o programa dimensiona ao abrir a
tela e clicar em Dimensionar — logo, o rastro que o memorial de fato imprime.
"""
const _CASO_EXEMPLO = Dict{Symbol,String}(
    # A Análise Pinch descreve uma REDE: as correntes são um grupo repetível, e os
    # defaults dos descritores não descrevem nenhuma ("o caso não descreve nenhuma
    # corrente: não há rede a integrar"). O caso de referência é o exemplo do livro.
    :pinch_kemp => "exemplo_pinch_kemp.toml")

function _valores(m)
    arq = get(_CASO_EXEMPLO, FPSOSiz.method_id(m), "")
    isempty(arq) || return merge(
        FPSOSiz.defaults(FPSOSiz.parameters(m)),
        Dict{Symbol,Any}(first(FPSOSiz.expand(FPSOSiz.load_case_set(arq);
                                              max_corners = 8))[2]))
    return merge(FPSOSiz.defaults(FPSOSiz.stream_parameters(m)),
                 FPSOSiz.defaults(FPSOSiz.parameters(m)))
end

"""
    _dimensiona(m) -> SizingResult

Roda o método pelo caminho genérico do contrato — `case_input` → `size_equipment` —, sem
citar nenhuma grandeza. É o que permite a bateria abaixo valer para qualquer método que
venha a declarar um memorial.
"""
function _dimensiona(m)
    vals = _valores(m)
    return FPSOSiz.size_equipment(FPSOSiz.applies_to(m), m,
                                  FPSOSiz.case_input(m, vals), vals)
end

"Os métodos do registro que declaram memorial documental."
const METODOS_COM_MEMORIAL = [m for eq in FPSOSiz.equipments()
                                for m in FPSOSiz.methods_for(eq)
                                if FPSOSiz.memorial_spec(m) !== nothing]

@testset "memorial documental" begin

    @testset "a bateria não está vazia" begin
        # Uma guarda que passa por não ter o que verificar é pior que uma que falha.
        @test length(METODOS_COM_MEMORIAL) >= 2
        @test FPSOSiz.tem_memorial(StewartArnold())
        @test FPSOSiz.tem_memorial(StewartArnoldTwoPhase())
    end

    @testset "a camada documental não guarda número — estruturalmente" begin
        # Nenhum campo numérico em nenhum dos descritores: não há ONDE escrever um valor
        # calculado. É o que garante que todo número do documento venha do `CalcTrace` ou
        # do `ResultField`, e não de alguém que digitou 5650 aqui.
        so_texto(T) = all(ft -> ft === String, fieldtypes(T))
        @test so_texto(FPSOSiz.PremissaDoc)
        @test so_texto(FPSOSiz.VariavelDoc)
        @test so_texto(FPSOSiz.ResultadoDoc)
        @test so_texto(FPSOSiz.VerificacaoDoc)

        # `EquacaoDoc` tem o vetor de variáveis; o resto é texto.
        @test all(ft -> ft === String || ft === Vector{FPSOSiz.VariavelDoc},
                  fieldtypes(FPSOSiz.EquacaoDoc))

        # E o `MemorialSpec` só agrega os anteriores.
        permitidos = (String, Symbol, Vector{String}, Vector{FPSOSiz.PremissaDoc},
                      Vector{FPSOSiz.EquacaoDoc}, Vector{FPSOSiz.ResultadoDoc},
                      Vector{FPSOSiz.VerificacaoDoc})
        @test all(ft -> ft in permitidos, fieldtypes(FPSOSiz.MemorialSpec))

        # E a afirmação central, sobre TODOS os tipos de uma vez: nenhum campo é
        # numérico. `natureza` é `Symbol` — diz que TIPO de documento é, não quanto vale
        # nada —, e a lista acima a admite sem abrir a porta para um Float64.
        for T in (FPSOSiz.PremissaDoc, FPSOSiz.VariavelDoc, FPSOSiz.ResultadoDoc,
                  FPSOSiz.VerificacaoDoc, FPSOSiz.EquacaoDoc, FPSOSiz.MemorialSpec)
            @test !any(ft -> ft <: Number, fieldtypes(T))
        end
    end

    # -----------------------------------------------------------------------
    # A bateria, uma vez por método que declare memorial
    # -----------------------------------------------------------------------
    for m in METODOS_COM_MEMORIAL
        spec = FPSOSiz.memorial_spec(m)
        res  = _dimensiona(m)

        @testset "$(FPSOSiz.method_id(m))" begin

            @test res.feasible          # sem resultado não há o que documentar

            @testset "identidade do documento" begin
                # A sigla entra no número `MC-SENAI-<SIGLA>-ENG-…`, e o handoff de design
                # fixa uma por módulo. Três letras maiúsculas, sem exceção.
                @test occursin(r"^[A-Z]{3}$", spec.sigla)
                @test !isempty(spec.equipamento)
                @test !isempty(spec.titulo)
                # As seções que o handoff marca como obrigatórias não podem estar vazias:
                # um documento sem premissa, sem equação, sem verificação ou sem conclusão
                # é o gabarito em branco com o carimbo do emitente.
                @test !isempty(spec.premissas)
                @test !isempty(spec.hipoteses)
                @test !isempty(spec.equacoes)
                @test !isempty(spec.resultados)
                @test !isempty(spec.verificacoes)
                @test !isempty(spec.conclusao)
            end

            @testset "toda equação do RASTRO está documentada" begin
                documentadas = Set(e.numero for e in spec.equacoes)
                for numero in FPSOSiz.equacoes_do_rastro(res.trace)
                    @test numero in documentadas
                end
            end

            @testset "toda equação DOCUMENTADA é resolvida ou citada" begin
                no_rastro = Set(FPSOSiz.equacoes_do_rastro(res.trace))
                citadas   = Set(FPSOSiz.equacoes_citadas(spec))
                for eq in spec.equacoes
                    # Ou o motor a resolve (e ela ganha um valor no documento), ou algum
                    # resultado da folha 04 a cita como origem. Uma equação que não caia
                    # em nenhum dos dois é decoração num documento técnico.
                    @test (eq.numero in no_rastro) || (eq.numero in citadas)
                end
            end

            @testset "nenhuma equação documentada duas vezes" begin
                numeros = [e.numero for e in spec.equacoes]
                @test length(numeros) == length(unique(numeros))
            end

            @testset "toda equação tem notação, referência e variáveis" begin
                for eq in spec.equacoes
                    @test !isempty(eq.notacao)
                    @test !isempty(eq.referencia)
                    @test !isempty(eq.variaveis)
                    for v in eq.variaveis
                        @test !isempty(v.simbolo)
                        @test !isempty(v.descricao)
                    end
                    # A notação é MATEMÁTICA, não sintaxe de código — é a regra do
                    # handoff. O que se proíbe são os operadores que só existem em
                    # programa: o produto vai como `·`, e a raiz como `√` ou expoente.
                    #
                    # `" * "` com os espaços, e não `"*"` solto: a Eq. 21* do separador
                    # nomeia a sua variante como `(d_max*)`, e esse asterisco é anotação
                    # matemática — é o marcador que distingue a variante não adotada da
                    # equação publicada.
                    @test !occursin(" * ", eq.notacao)
                    @test !occursin("sqrt(", eq.notacao)
                    @test !occursin("^0.5", eq.notacao)
                end
            end

            @testset "resultados e verificações casam com os campos do motor" begin
                campos = FPSOSiz.result_fields(m, res)
                rotulos = Set(f.label for f in campos)
                # Cada linha da folha de resultados tem de achar o seu valor. Sem isto o
                # documento imprime travessão numa linha que a tela mostra preenchida.
                for r in spec.resultados
                    @test r.rotulo in rotulos
                end
                for v in spec.verificacoes
                    @test v.campo in rotulos
                    @test !isempty(v.criterio)
                end
            end

            @testset "TODA verificação dá veredito" begin
                campos = FPSOSiz.result_fields(m, res)
                for v in spec.verificacoes
                    i = findfirst(f -> f.label == v.campo, campos)
                    @test i !== nothing
                    # Um campo `:neutro` não aprova nem reprova nada, e o documento
                    # imprime travessão. Numa linha de VERIFICAÇÃO isso é pior que
                    # ausência: num documento assinado, passa por verificada.
                    #
                    # É também o que impede declarar uma verificação que o equipamento
                    # não faz — o vaso bifásico não tem teto de decantação, e por isso
                    # não declara essa verificação em vez de declará-la em travessão.
                    @test campos[i].status in (:ok, :erro)
                end
            end

            @testset "toda citação cabe na coluna do memorial em texto" begin
                # `linha_memorial`, em app/src/report.jl, alinha a coluna de equação em
                # 10 caracteres. Uma citação mais longa cola na coluna seguinte do `.txt`
                # que vai anexo ao relatório — e foi exatamente o que aconteceu ao
                # documentar o vaso bifásico com `"Eq. 3.10b / 3.11"` (16). A guarda de
                # larguras do smoke pegou; esta aqui pega antes, no core, e diz por quê.
                for e in res.trace.entries
                    @test textwidth(e.eq) < 10
                end
            end

            @testset "o marcador de 'não é equação' fica fora da bijeção" begin
                # `trace_selection!` carimba "—" na linha que registra o diâmetro
                # escolhido: é decisão de projeto, não equação da fonte, e a folha de
                # fórmulas não tem o que imprimir para ela.
                @test !(FPSOSiz.SEM_EQUACAO in FPSOSiz.equacoes_do_rastro(res.trace))
            end
        end
    end

    # -----------------------------------------------------------------------
    # O que é específico de um método, e não cabe na bateria genérica
    # -----------------------------------------------------------------------

    @testset "separador trifásico — as ressalvas da fonte chegam ao documento" begin
        spec = FPSOSiz.memorial_spec(StewartArnold())
        res  = _dimensiona(StewartArnold())
        @test spec.sigla == "SEP"
        # A Eq. 21* é a variante geométrica NÃO adotada, calculada e registrada só para
        # que a divergência apareça no documento que vai assinado, em vez de viver no
        # comentário do código. Se sumir do rastro, o memorial perde a ressalva.
        @test "Eq. 21*" in Set(e.numero for e in spec.equacoes)
        @test !isempty(FPSOSiz.entradas_do_rastro(res.trace, "Eq. 21*"))
        # E o teto de decantação é verificado — este vaso TEM um.
        @test any(v -> occursin("teto", lowercase(v.descricao)), spec.verificacoes)
    end

    @testset "vaso bifásico — não promete a verificação que não faz" begin
        spec = FPSOSiz.memorial_spec(StewartArnoldTwoPhase())
        res  = _dimensiona(StewartArnoldTwoPhase())
        @test spec.sigla == "VKO"
        # Sem bloco B não há teto de diâmetro. O campo existe no cartão (a família o
        # declara) mas sai em travessão, e por isso NÃO pode virar verificação.
        @test !isfinite(res.ceiling)
        @test !any(v -> occursin("teto", lowercase(v.descricao)), spec.verificacoes)
        @test !any(r -> occursin("Teto", r.rotulo), spec.resultados)
        # E a numeração é a do LIVRO, não a do artigo sobre trifásicos.
        numeros = Set(e.numero for e in spec.equacoes)
        @test "Eq. 3.8b" in numeros
        @test !("Eq. 14" in numeros)
    end

    @testset "o Lss deixa rastro, e pela equação do bloco que governa" begin
        res = _dimensiona(StewartArnold())
        # Sem isto o `Lss` era o único resultado sem passo intermediário: a folha de
        # fórmulas mostrava as Eq. 15 e 23 com notação e referência, e travessão no
        # valor. Ver `lss_trace`.
        eq_gov, _ = FPSOSiz.lss_trace(StewartArnold(), res.governing)
        linhas = FPSOSiz.entradas_do_rastro(res.trace, eq_gov)
        @test length(linhas) == 1
        @test only(linhas).var == "Lss"
        @test only(linhas).value ≈ FPSOSiz.der(res, :lss)
        @test only(linhas).unit == "m"
        # As duas regras são numeradas, e cada uma pela sua: gás pela Eq. 15, líquido
        # pela Eq. 23. Citar só uma mandaria conferir a errada em metade dos casos.
        @test FPSOSiz.lss_trace(StewartArnold(), :gas)[1]    == "Eq. 15"
        @test FPSOSiz.lss_trace(StewartArnold(), :liquid)[1] == "Eq. 23"
        # E a que NÃO governou não deixa linha — não se registra conta que não se fez.
        eq_outra = res.governing === :gas ? "Eq. 23" : "Eq. 15"
        @test isempty(FPSOSiz.entradas_do_rastro(res.trace, eq_outra))

        # No bifásico a regra é OUTRA — o maior das duas —, então a citação é dupla e
        # vale sempre, governando quem governar.
        r2 = _dimensiona(StewartArnoldTwoPhase())
        @test FPSOSiz.lss_trace(StewartArnoldTwoPhase(), r2.governing)[1] == "§3.8.4"
        @test !isempty(FPSOSiz.entradas_do_rastro(r2.trace, "§3.8.4"))
        # E cabe na coluna de 10 do memorial `.txt` — ver o teste de larguras no smoke.
        @test textwidth("§3.8.4") < 10
    end

    @testset "quem não declara memorial devolve nothing, não um spec vazio" begin
        # Um `MemorialSpec` vazio produziria quatro folhas oficiais e nenhum conteúdo.
        # O default é `nothing` justamente para que a interface não ofereça o botão.
        for eq in FPSOSiz.equipments(), m in FPSOSiz.methods_for(eq)
            s = FPSOSiz.memorial_spec(m)
            @test s === nothing || s isa FPSOSiz.MemorialSpec
            @test FPSOSiz.tem_memorial(m) == (s !== nothing)
        end
    end
end
