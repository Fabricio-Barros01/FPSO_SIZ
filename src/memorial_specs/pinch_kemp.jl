"""
A camada documental da Análise Pinch — [`memorial_spec`](@ref) para [`PinchKemp`](@ref).

**É o único memorial de `natureza = :metas` do programa, e a diferença não é cosmética.**
Os outros cinco documentam um equipamento a construir: têm diâmetro, comprimento, área,
casco. Este documenta **alvos termodinâmicos de uma rede de correntes** — a utilidade
quente mínima, a fria mínima e a temperatura de pinch —, e não há equipamento nenhum a
dimensionar. Chamar a seção de "resultados do dimensionamento" prometeria um casco que
ninguém calculou, e é por isso que o contrato ganhou `natureza`: a folha de resultados
deste documento se chama **METAS DE ENERGIA DA REDE**.

O que o módulo entrega e o que não entrega está dito no próprio cartão da tela, e
repetido na conclusão: ele **não** dimensiona trocador e **não** sintetiza a rede. A meta
é o piso termodinâmico que qualquer rede viável respeita; quem projeta a rede que o
alcança é outra tarefa, e o programa tem um box separado para dimensionar UM trocador.

# Uma verificação, e ela é genuína

O balanço de entalpia da p. 24: `QCmin − QHmin` tem de igualar `ΣQ_quente − ΣQ_frio` em
**qualquer** ΔTmin. Os dois lados vêm por rotas independentes — um da cascata de calor,
outro da soma das cargas corrente a corrente —, e é isso que faz a igualdade pegar erro
de dado e erro de cascata em vez de ser tautologia.

Ela já era **rastreada**; passou a ser **julgada** quando este memorial foi escrito, pelo
mesmo motivo que o teto de decantação do separador: um número no documento sem o critério
ao lado obriga quem confere a saber de cor qual deveria ser.
"""

function memorial_spec(::PinchKemp)
    MemorialSpec(
        sigla       = "PCH",
        equipamento = "REDE DE TROCADORES",
        titulo      = "ANÁLISE PINCH DA REDE DE TROCADORES",
        natureza    = :metas,

        premissas = [
            PremissaDoc("P1",
                "A rede é descrita por correntes com temperatura de entrada, de saída e " *
                "capacidade calorífica de fluxo constante em cada segmento.",
                "Kemp (2007), 2ª ed., §2.1.4 e Tabela 2.2, p. 21"),
            PremissaDoc("P2",
                "A diferença mínima de temperatura ΔTmin é decisão do projetista, " *
                "aplicada uniformemente a toda a rede.",
                "Kemp (2007), §3.7.3, p. 83"),
            PremissaDoc("P3",
                "As metas de utilidade saem do algoritmo da tabela-problema: intervalos " *
                "de temperatura deslocados de ΔTmin/2 e cascata de calor entre eles.",
                "Kemp (2007), §3.9.1, pp. 8-9 do capítulo"),
            PremissaDoc("P4",
                "Troca de calor apenas entre correntes do processo e entre processo e " *
                "utilidades; sem perdas para o ambiente e sem mudança de fase não " *
                "declarada nos segmentos.",
                "Kemp (2007), §2.1"),
            PremissaDoc("P5",
                "As metas obtidas são o PISO TERMODINÂMICO: nenhuma rede viável consome " *
                "menos utilidade que elas para o ΔTmin adotado.",
                "Kemp (2007), §3.1"),
        ],

        hipoteses = [
            "ESTE DOCUMENTO NÃO DIMENSIONA EQUIPAMENTO. Ele entrega metas de energia de " *
            "uma REDE — utilidade quente mínima, utilidade fria mínima e temperatura de " *
            "pinch. Não dimensiona trocador casco-e-tubos, não sintetiza a rede de " *
            "trocadores, não faz o encaixe corrente a corrente e não calcula área. Para " *
            "dimensionar um trocador há aplicação própria neste mesmo programa.",

            "ΔTmin é DECLARADO, não otimizado. O ótimo econômico de ΔTmin sai do " *
            "compromisso entre custo de energia e custo de área, e exigiria funções de " *
            "custo que este programa não modela. O que o programa faz é calcular as " *
            "metas para o ΔTmin que o projetista adotar, e a varredura mostra como elas " *
            "se movem ao longo da faixa — o compromisso fica visível, mas quem o resolve " *
            "é quem tem os preços.",

            "Capacidade calorífica de fluxo constante por segmento. Uma corrente cujo CP " *
            "varie com a temperatura é representada por segmentos; dentro de cada " *
            "segmento o CP é constante, e é essa linearização que a tabela-problema " *
            "pressupõe.",

            "Problema-limiar é um desfecho POSSÍVEL, não um erro. Quando uma das duas " *
            "utilidades zera, não há pinch interior — a rede troca calor sem a restrição " *
            "de um estrangulamento intermediário. O documento diz isso explicitamente em " *
            "vez de imprimir travessão na temperatura de pinch e deixar o leitor " *
            "procurando defeito.",

            "As metas são de ENERGIA, não de área nem de número de unidades. Kemp traz " *
            "metas de área e de número de unidades, e nenhuma das duas está " *
            "implementada: exigiriam coeficientes de película por corrente, que este " *
            "módulo não pede.",
        ],

        equacoes = [
            EquacaoDoc("Tab. 2.2", "Carga térmica de cada corrente",
                "Q = CP · (T_saída − T_entrada),   CP = ṁ · c_p",
                [VariavelDoc("Q", "carga térmica da corrente", "kW"),
                 VariavelDoc("CP", "capacidade calorífica de fluxo", "kW/°C"),
                 VariavelDoc("T_entrada", "temperatura de entrada da corrente", "°C"),
                 VariavelDoc("T_saída", "temperatura de saída da corrente", "°C"),
                 VariavelDoc("ṁ", "vazão mássica da corrente", "kg/s"),
                 VariavelDoc("c_p", "calor específico da corrente", "kJ/kg·°C")];
                referencia = "Kemp (2007), Tabela 2.2, p. 21",
                validade = "Uma linha por corrente. Correntes QUENTES cedem calor " *
                           "(temperatura de saída menor que a de entrada) e FRIAS " *
                           "recebem. O CP é constante dentro de cada segmento — ver a " *
                           "hipótese H3 da folha 02."),

            EquacaoDoc("§2.1.4", "Cargas totais disponível e requerida",
                "ΣQ_quente = Σ Q das correntes que cedem calor    " *
                "ΣQ_frio = Σ Q das correntes que recebem calor",
                [VariavelDoc("ΣQ_quente", "carga térmica total disponível na rede", "kW"),
                 VariavelDoc("ΣQ_frio", "carga térmica total requerida pela rede", "kW")];
                referencia = "Kemp (2007), §2.1.4, p. 20",
                validade = "São as somas brutas, ANTES de qualquer recuperação. A " *
                           "diferença entre elas é o que o balanço de entalpia da p. 24 " *
                           "confere contra as metas."),

            EquacaoDoc("§3.7.3", "Diferença mínima de temperatura adotada",
                "ΔT_min : decisão de projeto, uniforme em toda a rede",
                [VariavelDoc("ΔT_min", "diferença mínima de temperatura", "°C")];
                referencia = "Kemp (2007), §3.7.3, p. 83; faixa recomendada em §3.7.2, p. 82",
                validade = "NÃO é otimizado: o ótimo econômico exigiria funções de custo " *
                           "de energia e de área que este módulo não modela. Ver a " *
                           "hipótese H2 da folha 02."),

            EquacaoDoc("§3.9.1", "Algoritmo da tabela-problema — cascata de calor",
                "T* = T_quente − ΔT_min/2 = T_frio + ΔT_min/2;   " *
                "ΔH_i = (ΣCP_quentes − ΣCP_frias)_i · ΔT*_i;   " *
                "QH_min = −min(cascata acumulada);   QC_min = resíduo no pé da cascata factível",
                [VariavelDoc("T*", "temperatura deslocada do intervalo", "°C"),
                 VariavelDoc("ΔT_min", "diferença mínima de temperatura", "°C"),
                 VariavelDoc("ΔH_i", "excedente ou déficit de calor do intervalo i", "kW"),
                 VariavelDoc("ΣCP", "soma das capacidades caloríficas ativas no intervalo", "kW/°C"),
                 VariavelDoc("QH_min", "utilidade quente mínima", "kW"),
                 VariavelDoc("QC_min", "utilidade fria mínima", "kW")];
                referencia = "Kemp (2007), §3.9.1, pp. 8-9 do capítulo",
                validade = "O deslocamento de meio ΔTmin em cada lado é o que permite " *
                           "tratar troca térmica viável como troca a temperatura igual. A " *
                           "temperatura de pinch é a fronteira em que o fluxo líquido da " *
                           "cascata é nulo; quando nenhuma o é, o problema é de limiar e " *
                           "não tem pinch interior."),

            EquacaoDoc("p. 24", "Balanço de entalpia da rede — conferência cruzada",
                "QC_min − QH_min = ΣQ_quente − ΣQ_frio",
                [VariavelDoc("QH_min", "utilidade quente mínima", "kW"),
                 VariavelDoc("QC_min", "utilidade fria mínima", "kW"),
                 VariavelDoc("ΣQ_quente", "carga térmica total disponível", "kW"),
                 VariavelDoc("ΣQ_frio", "carga térmica total requerida", "kW")];
                referencia = "Kemp (2007), p. 24",
                validade = "Vale em QUALQUER ΔTmin, e é conferência genuína e não " *
                           "tautologia: o lado esquerdo vem da cascata de calor e o " *
                           "direito da soma corrente a corrente, por rotas independentes. " *
                           "Um erro de dado numa corrente ou um erro na montagem da " *
                           "cascata quebra a igualdade."),
        ],

        # Não há "Diâmetro", "Comprimento" nem "Área": não há equipamento. O primeiro
        # campo é o escopo, e ele é resultado como os outros — é o que a tela mostra e o
        # que o documento tem de repetir, para que ninguém leia estas metas como o
        # dimensionamento de um trocador.
        resultados = [
            ResultadoDoc("O que esta tela entrega", "—", "—"),
            ResultadoDoc("ΔTmin adotado", "ΔT_min", "§3.7.3"),
            ResultadoDoc("Utilidade quente mínima QHmin", "QH_min", "§3.9.1"),
            ResultadoDoc("Utilidade fria mínima QCmin", "QC_min", "§3.9.1"),
            ResultadoDoc("Calor recuperado na rede", "Q_rec", "§2.1.4"),
            ResultadoDoc("Fração da carga quente recuperada", "Q_rec/ΣQ_quente", "§2.1.4"),
            ResultadoDoc("Situação do pinch", "—", "§3.9.1"),
            ResultadoDoc("T de pinch (deslocada)", "T*_pinch", "§3.9.1"),
            ResultadoDoc("T de pinch, lado quente", "T_pinch,q", "§3.9.1"),
            ResultadoDoc("T de pinch, lado frio", "T_pinch,f", "§3.9.1"),
            ResultadoDoc("Correntes na rede", "N", "Tab. 2.2"),
            ResultadoDoc("Quentes / frias", "—", "Tab. 2.2"),
            ResultadoDoc("Intervalos de temperatura", "n_int", "§3.9.1"),
            ResultadoDoc("Carga quente disponível ΣQ", "ΣQ_quente", "§2.1.4"),
            ResultadoDoc("Carga fria requerida ΣQ", "ΣQ_frio", "§2.1.4"),
            ResultadoDoc("Resíduo do balanço de entalpia", "ε", "p. 24"),
            ResultadoDoc("Cenário governante", "—", "—"),
        ],

        # UMA, e é a única que o motor julga. Não há banda de esbeltez nem teto a
        # conferir: não há equipamento. O que há é um invariante termodinâmico, e ele é
        # conferência de verdade porque os dois lados vêm por rotas independentes.
        verificacoes = [
            VerificacaoDoc("Balanço de entalpia da rede fecha em qualquer ΔTmin",
                           "Resíduo do balanço de entalpia",
                           "(QCmin − QHmin) − (ΣQ_quente − ΣQ_frio) = 0", "kW"),
        ],

        conclusao =
            "As metas da seção 1 são o PISO TERMODINÂMICO da rede para o ΔTmin adotado: " *
            "nenhuma rede de trocadores viável consome menos utilidade quente que QHmin " *
            "nem rejeita menos calor que QCmin. O calor recuperado é a diferença entre a " *
            "carga disponível e a utilidade quente exigida, e a temperatura de pinch " *
            "divide a rede em duas regiões que não devem trocar calor entre si sob pena " *
            "de afastar o projeto da meta. O balanço de entalpia foi conferido e fecha. " *
            "LIMITAÇÃO, e é de natureza e não de precisão: ESTE DOCUMENTO NÃO DIMENSIONA " *
            "EQUIPAMENTO. Não sintetiza a rede de trocadores, não faz o encaixe corrente " *
            "a corrente, não calcula área de troca nem número de unidades, e não " *
            "seleciona utilidades. Ele diz quanta energia a rede precisa, no mínimo — " *
            "não como construí-la. As hipóteses da folha 02, em especial a de que o " *
            "ΔTmin é declarado e não otimizado, devem ser lidas junto com estas metas.",
    )
end
