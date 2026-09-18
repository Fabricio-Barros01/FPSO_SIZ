"""
A camada documental do memorial: o que ela promete e o que a mantém honesta.

Um memorial de cálculo falha de três maneiras, e nenhuma delas é ruidosa:

1. **documentando uma equação que o programa não resolve** — o revisor confere uma conta
   que não foi feita;
2. **calculando um número que o documento não explica** — aparece um valor na folha de
   resultados sem nada que diga de onde veio;
3. **carregando um número escrito à mão na camada documental** — o documento e a tela
   passam a ter duas fontes para a mesma grandeza, e divergem no primeiro caso de canto.

Os três testes abaixo fecham as três portas. A de nº 3 é fechada **estruturalmente**:
nenhum tipo de `src/memorial.jl` tem campo numérico, então não existe onde guardar um
valor calculado. É a mesma ideia do `NaN` em vez de `0.0` no `VesselConstraints` — em
vez de confiar na disciplina, torna-se impossível.
"""

# O caso de referência, com a grade default: é o que o programa dimensiona ao abrir o
# separador e clicar em Dimensionar, então é o rastro que o memorial de fato imprime.
const _VALS_SEP = FPSOSiz.default_case_values()
const _RES_SEP  = size_equipment(Separator(), StewartArnold(),
                                 stream_from_case(_VALS_SEP), _VALS_SEP)

@testset "memorial documental" begin

    @test _RES_SEP.feasible     # sem resultado não há o que documentar

    spec = FPSOSiz.memorial_spec(StewartArnold())

    @testset "o separador declara um memorial, e com a identidade do handoff" begin
        @test spec isa FPSOSiz.MemorialSpec
        @test FPSOSiz.tem_memorial(StewartArnold())
        # A sigla entra no número do documento `MC-SENAI-<SIGLA>-ENG-…`; a tabela de
        # módulos do handoff fixa SEP para o separador trifásico.
        @test spec.sigla == "SEP"
        @test !isempty(spec.equipamento)
        @test !isempty(spec.titulo)
        # As quatro seções que o handoff marca como obrigatórias não podem estar vazias:
        # um documento sem premissa, sem equação, sem verificação ou sem conclusão é o
        # gabarito em branco com o carimbo do emitente.
        @test !isempty(spec.premissas)
        @test !isempty(spec.hipoteses)
        @test !isempty(spec.equacoes)
        @test !isempty(spec.resultados)
        @test !isempty(spec.verificacoes)
        @test !isempty(spec.conclusao)
    end

    @testset "toda equação do RASTRO está documentada" begin
        documentadas = Set(e.numero for e in spec.equacoes)
        for numero in FPSOSiz.equacoes_do_rastro(_RES_SEP.trace)
            @test numero in documentadas
        end
        # As quatro divergências do método são justamente o que a Eq. 21* registra; se
        # ela sumir do rastro, o documento perde a ressalva sem nada denunciar.
        @test "Eq. 21*" in documentadas
    end

    @testset "toda equação DOCUMENTADA é resolvida ou citada" begin
        no_rastro = Set(FPSOSiz.equacoes_do_rastro(_RES_SEP.trace))
        citadas   = Set(FPSOSiz.equacoes_citadas(spec))
        for eq in spec.equacoes
            # Ou o motor a resolve (e ela ganha um valor no documento), ou algum
            # resultado da folha 04 a cita como origem. Uma equação que não caia em
            # nenhum dos dois casos é decoração num documento técnico.
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
            # A notação é MATEMÁTICA, não sintaxe de código — é a regra do handoff. O
            # que se proíbe são os operadores que só existem em programa: o produto vai
            # como `·`, e a raiz como `√` ou expoente.
            #
            # `" * "` com os espaços, e não `"*"` solto: a Eq. 21* nomeia a sua variante
            # como `(d_max*)`, e esse asterisco é anotação matemática — é justamente o
            # marcador que distingue a variante não adotada da equação publicada.
            @test !occursin(" * ", eq.notacao)
            @test !occursin("sqrt(", eq.notacao)
            @test !occursin("^0.5", eq.notacao)   # expoente com ponto decimal é código
        end
    end

    @testset "resultados e verificações casam com os campos do motor" begin
        campos = FPSOSiz.result_fields(StewartArnold(), _RES_SEP)
        rotulos = Set(f.label for f in campos)

        # Cada linha da folha de resultados tem de achar o seu valor. Sem isto o
        # documento imprime travessão numa linha que a tela mostra preenchida.
        for r in spec.resultados
            @test r.rotulo in rotulos
        end
        # E cada verificação tem de achar o campo que carrega o `status` — é de lá que
        # sai o ATENDE / NÃO ATENDE, e de lugar nenhum mais.
        for v in spec.verificacoes
            @test v.campo in rotulos
            @test !isempty(v.criterio)
        end
    end

    @testset "a verificação de esbeltez aponta para um campo que dá veredito" begin
        campos = FPSOSiz.result_fields(StewartArnold(), _RES_SEP)
        for v in spec.verificacoes
            i = findfirst(f -> f.label == v.campo, campos)
            i === nothing && continue
            # Um campo `:neutro` não aprova nem reprova nada. Pelo menos uma verificação
            # tem de apontar para um campo que DÊ veredito, senão a seção inteira sai em
            # travessão e passa por "verificado".
            v.campo == "Esbeltez SR" && @test campos[i].status in (:ok, :erro)
        end
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
        permitidos = (String, Vector{String}, Vector{FPSOSiz.PremissaDoc},
                      Vector{FPSOSiz.EquacaoDoc}, Vector{FPSOSiz.ResultadoDoc},
                      Vector{FPSOSiz.VerificacaoDoc})
        @test all(ft -> ft in permitidos, fieldtypes(FPSOSiz.MemorialSpec))
    end

    @testset "o marcador de 'não é equação' fica fora da bijeção" begin
        # `trace_selection!` carimba "—" na linha que registra o diâmetro escolhido: é
        # decisão de projeto, não equação da fonte, e a folha de fórmulas não tem o que
        # imprimir para ela.
        @test !(FPSOSiz.SEM_EQUACAO in FPSOSiz.equacoes_do_rastro(_RES_SEP.trace))
        @test any(e -> e.eq == FPSOSiz.SEM_EQUACAO, _RES_SEP.trace.entries)
    end

    @testset "quem não declara memorial devolve nothing, não um spec vazio" begin
        # Um `MemorialSpec` vazio produziria quatro folhas oficiais e nenhum conteúdo.
        # O default é `nothing` justamente para que a interface não ofereça o botão.
        for m in (StewartArnoldTwoPhase(), MoranPumpSizing(), SaariLMTD(),
                  ArnoldElectrostatic(), PinchKemp())
            spec_m = FPSOSiz.memorial_spec(m)
            @test spec_m === nothing || spec_m isa FPSOSiz.MemorialSpec
            @test FPSOSiz.tem_memorial(m) == (spec_m !== nothing)
        end
    end
end
