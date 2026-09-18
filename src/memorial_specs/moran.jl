"""
A camada documental da bomba centrífuga — [`memorial_spec`](@ref) para
[`MoranPumpSizing`](@ref).

**É o único método deste programa sem nenhuma errata de fonte a contornar.** As sete
equações do artigo estão implementadas como publicadas — a conferência símbolo por
símbolo está em `docs/validacao/01-bomba-moran.md` §1, feita sobre as páginas
rasterizadas, porque as fórmulas são imagem num PDF que concede `print` e nega `copy`.

O que este memorial documenta de diferente dos vasos:

1. **Nem tudo o que o motor calcula tem número de equação, e o documento diz qual é
   qual.** Velocidade (`Q/A`), carga estática e a soma `H = h_est + h_atrito` são
   continuidade e aritmética; o artigo não as numera, e por isso elas saem no rastro com
   `"—"` e **não** aparecem na folha de fórmulas. Dar-lhes um número seria mandar o
   revisor procurar na fonte uma equação que ela não tem.

2. **O fator de atrito cita fontes diferentes conforme o regime.** No turbulento é a
   Eq. (2) do artigo; no laminar é Hagen-Poiseuille, que **não é do artigo** e por isso
   é citada pelo nome, nunca por um número. Ver `friction_equation` em `hydraulics.jl`.

3. **As duas verificações são as que o motor de fato executa** — a banda de velocidade
   com a validade da correlação (`case_admissible`) e a margem de NPSH. Não há
   verificação de esbeltez nem teto de decantação: uma bomba não tem casco.
"""

function memorial_spec(::MoranPumpSizing)
    MemorialSpec(
        sigla       = "BMB",
        equipamento = "BOMBA",
        titulo      = "DIMENSIONAMENTO DE BOMBA",

        premissas = [
            PremissaDoc("P1",
                "Bomba centrífuga em linha de recalque de líquido monofásico, " *
                "especificada pelo par (vazão, carga do sistema) no ponto de operação.",
                "Moran (2016), CEP dez/2016, pp. 38-44"),
            PremissaDoc("P2",
                "A carga do sistema soma a parcela estática (desnível geométrico e " *
                "diferença de pressão entre reservatórios) e a de atrito (trecho reto " *
                "mais acessórios).",
                "Moran (2016), p. 40"),
            PremissaDoc("P3",
                "Perdas localizadas pelo método dos coeficientes k, somados por trecho a " *
                "partir da leitura do fluxograma.",
                "Moran (2016), Eq. (1) e Tabela 1, p. 40"),
            PremissaDoc("P4",
                "Atrito em trecho reto por Darcy-Weisbach, com fator de atrito de " *
                "Colebrook-White no regime turbulento.",
                "Moran (2016), Eq. (2) e (4), p. 41"),
            PremissaDoc("P5",
                "Velocidade recomendada na linha: até 1,5 m/s para fluidos aquosos; " *
                "entre 1 e 1,5 m/s quando há sólidos sedimentáveis.",
                "Moran (2016), p. 39"),
            PremissaDoc("P6",
                "NPSH disponível calculado na sucção, com pressão de vapor pela equação " *
                "de Antoine na forma do NIST, e comparado ao NPSH requerido pela bomba " *
                "mais a margem de projeto.",
                "Moran (2016), Eq. (5) e (6) e Tabela 3, p. 41"),
        ],

        hipoteses = [
            "Diâmetro nominal tratado como diâmetro interno. O artigo faz o mesmo: o " *
            "texto lê a Figura 3 para uma tubulação 'de 25 mm nominais' num eixo " *
            "rotulado Internal Diameter. Em fase conceitual a diferença entre DN e o " *
            "interno de um Sch 40 é da ordem de 5 %, menor que o passo da série " *
            "comercial. Quem precisar do interno real informa-o na grade de diâmetros.",

            "Regime laminar NÃO é do artigo. Moran declara Colebrook-White válida para " *
            "Re > 4.000 e não diz o que fazer abaixo disso — razoável num artigo cuja " *
            "regra de bolso mantém a velocidade em 1–1,5 m/s, onde uma linha de água " *
            "nunca é laminar. Como o programa aceita qualquer viscosidade, adota-se " *
            "f = 64/Re (Hagen-Poiseuille), exata para escoamento plenamente " *
            "desenvolvido em duto circular. Ela é citada pelo NOME, e nunca por um " *
            "número de equação, porque não consta da fonte.",

            "A zona de transição (Re entre 2.300 e 4.000) é RECUSADA, não extrapolada. " *
            "Nenhuma das duas correlações implementadas vale ali, e Colebrook-White " *
            "avaliada fora da faixa devolve um número como qualquer outro — sem nada " *
            "que denuncie. Um ponto fora do domínio de validade não é impossível; é um " *
            "ponto que este modelo não está autorizado a avaliar.",

            "Não há critério econômico. O artigo dá regras de bolso de velocidade, não " *
            "um ótimo de custo. Entre os diâmetros admissíveis escolhe-se o MENOR, que " *
            "é a decisão de menor capital — e é discutível, porque diâmetro menor é mais " *
            "carga e mais energia por toda a vida da bomba. A tabela de varredura mostra " *
            "a carga e a potência em cada diâmetro da banda, de modo que o custo de " *
            "subir um diâmetro é lido em kW.",

            "Os coeficientes de Antoine default são os da ÁGUA (Tabela 3 do artigo, o " *
            "único conjunto que a fonte publica), e o líquido default é água a 30 °C. " *
            "Trocar o líquido sem trocar A, B e C produziria uma pressão de vapor que " *
            "não é de nenhum dos dois, e o NPSH sairia errado sem que nada denunciasse.",

            "As fórmulas do artigo são IMAGEM num PDF cifrado que concede impressão e " *
            "nega cópia. As sete foram lidas sobre as páginas rasterizadas, símbolo por " *
            "símbolo; a conferência linha a linha está registrada na validação física " *
            "deste método.",
        ],

        equacoes = [
            EquacaoDoc("Eq. 5", "Pressão de vapor do líquido",
                "log₁₀ P_v [bar] = A − B / (T + C)",
                raw"\log_{10} P_v = A - \frac{B}{T + C}",
                [VariavelDoc("P_v", "pressão de vapor do líquido", "Pa"),
                 VariavelDoc("A", "coeficiente de Antoine", "–"),
                 VariavelDoc("B", "coeficiente de Antoine", "K"),
                 VariavelDoc("C", "coeficiente de Antoine", "K"),
                 VariavelDoc("T", "temperatura do líquido", "K")];
                referencia = "Moran (2016), Eq. (5) e Tabela 3, p. 41",
                validade = "Forma do NIST, com T ABSOLUTO — o coeficiente C negativo só " *
                           "faz sentido em kelvin. O resultado sai em bar e é convertido " *
                           "a pascal uma única vez. Coeficientes válidos para o líquido " *
                           "a que pertencem: ver a hipótese H5 da folha 02."),

            EquacaoDoc("Eq. 6", "NPSH disponível na sucção",
                "NPSH_d = P₀/(ρ·g) + h₀ − h_f,suc − P_v/(ρ·g)",
                raw"NPSH_d = \frac{P_0}{\rho \cdot g} + h_0 - h_{f,suc} - \frac{P_v}{\rho \cdot g}",
                [VariavelDoc("NPSH_d", "carga líquida positiva de sucção disponível", "m"),
                 VariavelDoc("P₀", "pressão no reservatório de sucção", "Pa"),
                 VariavelDoc("ρ", "massa específica do líquido", "kg/m³"),
                 VariavelDoc("g", "aceleração da gravidade", "m/s²"),
                 VariavelDoc("h₀", "carga estática na sucção", "m"),
                 VariavelDoc("h_f,suc", "perda de carga no trecho de sucção", "m"),
                 VariavelDoc("P_v", "pressão de vapor do líquido", "Pa")];
                referencia = "Moran (2016), Eq. (6), p. 41",
                validade = "Avaliada em duas etapas: a parcela que não depende do " *
                           "diâmetro é calculada antes da varredura, e o termo de atrito " *
                           "na sucção entra depois de escolhido o diâmetro."),

            EquacaoDoc("Eq. 3", "Número de Reynolds do escoamento na linha",
                "Re = ρ · v · D / µ",
                raw"Re = \frac{\rho \cdot v \cdot D}{\mu}",
                [VariavelDoc("Re", "número de Reynolds", "–"),
                 VariavelDoc("ρ", "massa específica do líquido", "kg/m³"),
                 VariavelDoc("v", "velocidade superficial na linha", "m/s"),
                 VariavelDoc("D", "diâmetro interno da tubulação", "m"),
                 VariavelDoc("µ", "viscosidade dinâmica do líquido", "Pa·s")];
                referencia = "Moran (2016), Eq. (3), p. 41",
                validade = "É o Reynolds de escoamento em duto — não confundir com o de " *
                           "uma gotícula em decantação, usado nos vasos deste programa."),

            EquacaoDoc("§ regime", "Classificação do regime de escoamento",
                "laminar: Re ≤ 2.300    transição: 2.300 < Re < 4.000    " *
                "turbulento: Re ≥ 4.000",
                raw"\text{laminar} : Re \le 2.300 \quad \text{transição} : 2.300 < Re < 4.000 " *
                raw"\quad \text{turbulento} : Re \ge 4.000",
                [VariavelDoc("Re", "número de Reynolds", "–")];
                referencia = "Moran (2016), p. 41 — a Eq. (2) é declarada para Re > 4.000; " *
                             "as fronteiras estão nas constantes do método",
                validade = "É a linha que decide QUAL relação de atrito vale. A zona de " *
                           "transição não tem correlação implementada e o ponto é " *
                           "recusado — ver a hipótese H3 da folha 02. O valor registrado " *
                           "é 1 quando a correlação do regime é válida ali e 0 quando não."),

            EquacaoDoc("Eq. 2", "Fator de atrito de Darcy — regime turbulento",
                "1/√f = −2 · log₁₀ [ ε/(3,7·D) + 2,51/(Re·√f) ]",
                raw"\frac{1}{\sqrt{f}} = -2 \cdot \log_{10} \left[ \frac{\varepsilon}{3,7 \cdot D} + " *
                raw"\frac{2,51}{Re \cdot \sqrt{f}} \right]",
                [VariavelDoc("f", "fator de atrito de Darcy", "–"),
                 VariavelDoc("ε", "rugosidade absoluta da parede", "m"),
                 VariavelDoc("D", "diâmetro interno da tubulação", "m"),
                 VariavelDoc("Re", "número de Reynolds", "–")];
                referencia = "Moran (2016), Eq. (2), p. 41 — Colebrook-White",
                validade = "DECLARADA PELA FONTE para Re > 4.000. Implícita em f, " *
                           "resolvida por ponto fixo. É o fator de DARCY, que vale " *
                           "quatro vezes o de Fanning — o próprio artigo dedica um " *
                           "parágrafo ao engano, porque ele erra a perda em 4× sem " *
                           "produzir nada absurdo na tela."),

            EquacaoDoc("Hagen", "Fator de atrito de Darcy — regime laminar",
                "f = 64 / Re",
                raw"f = \frac{64}{Re}",
                [VariavelDoc("f", "fator de atrito de Darcy", "–"),
                 VariavelDoc("Re", "número de Reynolds", "–")];
                referencia = "Hagen-Poiseuille — NÃO CONSTA do artigo; acréscimo " *
                             "declarado deste programa",
                validade = "Exata para escoamento laminar plenamente desenvolvido em " *
                           "duto circular. Citada pelo nome e nunca por um número de " *
                           "equação, porque a fonte não a traz — ver a hipótese H2 da " *
                           "folha 02. Aplicada somente quando Re ≤ 2.300."),

            EquacaoDoc("Eq. 1/4", "Perda de carga por atrito — trecho reto e acessórios",
                "h_f = f · (L/D) · v²/(2g)  +  Σk · v²/(2g)",
                raw"h_f = f \cdot \frac{L}{D} \cdot \frac{v^2}{2g} + \Sigma k \cdot \frac{v^2}{2g}",
                [VariavelDoc("h_f", "perda de carga por atrito", "m"),
                 VariavelDoc("f", "fator de atrito de Darcy", "–"),
                 VariavelDoc("L", "comprimento de trecho reto", "m"),
                 VariavelDoc("D", "diâmetro interno da tubulação", "m"),
                 VariavelDoc("v", "velocidade superficial na linha", "m/s"),
                 VariavelDoc("Σk", "soma dos coeficientes de perda localizada do trecho", "–"),
                 VariavelDoc("g", "aceleração da gravidade", "m/s²")];
                referencia = "Moran (2016), Eq. (4) p. 41 (trecho reto) e Eq. (1) p. 40 " *
                             "(acessórios); coeficientes k na Tabela 1, p. 40",
                validade = "DUAS equações somadas numa linha, e a citação diz as duas: o " *
                           "artigo publica a Eq. (4) em queda de PRESSÃO, e aqui ela " *
                           "aparece dividida por ρ·g — em metros de coluna do próprio " *
                           "fluido, que é a unidade em que o artigo soma tudo e em que a " *
                           "curva do sistema se compara com a da bomba."),

            EquacaoDoc("Eq. 7", "Potência hidráulica de eixo",
                "P = Q · ρ · g · H / (3,6×10⁶ · η)",
                raw"P = \frac{Q \cdot \rho \cdot g \cdot H}{3,6 \times 10^6 \cdot \eta}",
                [VariavelDoc("P", "potência de eixo", "kW"),
                 VariavelDoc("Q", "vazão bombeada", "m³/h"),
                 VariavelDoc("ρ", "massa específica do líquido", "kg/m³"),
                 VariavelDoc("g", "aceleração da gravidade", "m/s²"),
                 VariavelDoc("H", "carga do sistema no ponto de operação", "m"),
                 VariavelDoc("η", "rendimento global do conjunto", "–")];
                referencia = "Moran (2016), Eq. (7), p. 42",
                validade = "O fator 3,6×10⁶ converte Q em m³/h e o resultado em kW. Usa " *
                           "a vazão do caso governante e a carga da envelope, que é a " *
                           "leitura conservadora."),
        ],

        # A velocidade, a carga estática e a soma H não citam equação: são continuidade e
        # aritmética, e a fonte não as numera. O travessão aqui é uma AFIRMAÇÃO — a de
        # que não há onde conferir —, e não um campo por preencher.
        resultados = [
            ResultadoDoc("Diâmetro nominal DN", "DN", "—"),
            ResultadoDoc("Carga do sistema H", "H", "Eq. 1/4"),
            ResultadoDoc("Velocidade v", "v", "—"),
            ResultadoDoc("Carga estática", "h_est", "—"),
            ResultadoDoc("Perda de carga", "h_f", "Eq. 1/4"),
            ResultadoDoc("Reynolds", "Re", "Eq. 3"),
            ResultadoDoc("Fator de atrito f", "f", "Eq. 2 / Hagen"),
            ResultadoDoc("NPSH disponível", "NPSH_d", "Eq. 6"),
            ResultadoDoc("Folga de NPSH", "ΔNPSH", "Eq. 6"),
            ResultadoDoc("Potência de eixo", "P", "Eq. 7"),
            ResultadoDoc("Parcela governante", "—", "—"),
            ResultadoDoc("Caso governante", "—", "—"),
        ],

        # As DUAS que o motor de fato executa, em `case_admissible`. A primeira é ampla
        # de propósito: o status daquele campo carrega as três condições que o motor
        # avalia junto, e descrevê-la só como "banda de velocidade" faria o documento
        # prometer menos conferência do que houve.
        verificacoes = [
            VerificacaoDoc("Ponto admissível: velocidade na banda, NPSH folgado e " *
                           "correlação de atrito dentro da faixa de validade",
                           "Velocidade v",
                           "v_min ≤ v ≤ v_max e Re fora da zona de transição", "m/s"),
            VerificacaoDoc("Margem de NPSH disponível sobre o exigido",
                           "Folga de NPSH",
                           "NPSH_d ≥ NPSH_r + margem (folga ≥ 0)", "m"),
        ],

        conclusao =
            "A linha indicada na seção 1 atende à banda de velocidade recomendada, " *
            "mantém o NPSH disponível acima do requerido pela bomba somado à margem de " *
            "projeto, e opera num regime em que a correlação de atrito implementada é " *
            "válida. A carga do sistema e a potência de eixo no ponto de operação estão " *
            "na seção 1, e é por elas que a bomba deve ser selecionada junto ao " *
            "fabricante. LIMITAÇÃO: este dimensionamento é da LINHA e do ponto de " *
            "operação, não da máquina — não seleciona rotor, não levanta curva " *
            "característica e não aplica critério econômico de diâmetro. A escolha é o " *
            "menor diâmetro admissível; a tabela de varredura mostra o que custa, em " *
            "potência, subir para o diâmetro seguinte. As hipóteses da folha 02 devem " *
            "ser lidas junto com este resultado.",
    )
end
