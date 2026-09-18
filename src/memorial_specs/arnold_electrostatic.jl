"""
A camada documental do tratador eletrostático — [`memorial_spec`](@ref) para
[`ArnoldElectrostatic`](@ref).

Este é o memorial em que a folha de **hipóteses** carrega mais peso que a de equações, e
por um motivo que precisa estar escrito no documento e não só no código: *a referência
disponível não fecha o campo elétrico*.

O volume da série que o projeto tem — *Gas-Liquid and Liquid-Liquid Separators* — cita
tratadores eletrostáticos de passagem e remete o dimensionamento do campo (gradiente de
tensão, espaçamento e área de eletrodo, consumo do transformador) a *Emulsions and Oil
Treating*, que não está disponível. Sem ele **não há correlação** ligando tensão e
espaçamento ao diâmetro coalescido.

A escolha honesta foi expor o diâmetro de gotícula coalescida como **entrada do
usuário**, com o valor sem tratamento de §4.7.2 (500 µm) como referência, e emitir no
rastro o ganho de decantação `(d_m/500)²` que a hipótese vale. Assim o número que carrega
a premissa aparece no memorial ao lado do resultado que ele produziu, em vez de ficar
escondido num default — quem tiver dado de laboratório põe o dele; quem não tiver, lê no
documento quanto está apostando.

Os três achados ao reproduzir a fonte (a contradição de fator 10 entre a Eq. 4.5b e o
§4.9.3, o erro de digitação da Eq. 4.9b e a ausência da contraparte da Eq. 4.18) estão na
folha 02, com os números que os denunciam.
"""

function memorial_spec(::ArnoldElectrostatic)
    MemorialSpec(
        sigla       = "TRE",
        equipamento = "TRATADOR ELETROSTÁTICO",
        titulo      = "DIMENSIONAMENTO DE TRATADOR ELETROSTÁTICO",

        premissas = [
            PremissaDoc("P1",
                "Vaso cilíndrico horizontal CHEIO de líquido: entra emulsão óleo-água já " *
                "desgaseificada e saem óleo tratado e água. Não há fase gasosa nem céu " *
                "de gás.",
                "Stewart & Arnold (2008), §4.9.6"),
            PremissaDoc("P2",
                "O campo elétrico COALESCE as gotículas de água dispersas no óleo; a " *
                "separação seguinte é gravitacional, por Stokes.",
                "Stewart & Arnold (2008), §4.7.1"),
            PremissaDoc("P3",
                "Diâmetro de gotícula coalescida informado pelo projetista; o ganho de " *
                "decantação em relação à emulsão sem tratamento é registrado no cálculo.",
                "Stewart & Arnold (2008), §4.7.2 — referência de 500 µm sem tratamento"),
            PremissaDoc("P4",
                "Tempos de retenção do óleo e da água fixados por projeto.",
                "Stewart & Arnold (2008), §4.9.5"),
            PremissaDoc("P5",
                "Comprimento entre costuras pelo MAIOR entre as duas folgas construtivas.",
                "Stewart & Arnold (2008), §4.9.1"),
            PremissaDoc("P6",
                "Esbeltez recomendada 3 ≤ SR ≤ 5.",
                "Stewart & Arnold (2008), §4.9.2"),
        ],

        hipoteses = [
            "O QUE ESTE DIMENSIONAMENTO NÃO FAZ. Não dimensiona o eletrodo, a fonte de " *
            "alimentação nem o transformador, e não prevê a coalescência a partir da " *
            "tensão aplicada. A referência disponível remete o dimensionamento do campo a " *
            "outro volume da série, que não está acessível — sem ele não há correlação " *
            "que ligue tensão e espaçamento ao diâmetro coalescido. O campo entra neste " *
            "cálculo por UM ponto e nenhum outro: o diâmetro de gotícula do bloco de " *
            "decantação.",

            "Diâmetro de gotícula coalescida como ENTRADA, não como correlação. O valor " *
            "informado é a hipótese do projetista sobre o que o campo produz. O ganho de " *
            "decantação que ela vale — o quadrado da razão para os 500 µm da emulsão sem " *
            "tratamento, porque Stokes vai com d_m² — é calculado e registrado na folha " *
            "de fórmulas, para que a aposta fique visível ao lado do resultado.",

            "Contradição de fator 10 na fonte, resolvida. A Eq. 4.5b imprime coeficiente " *
            "0,0033; o §4.9.3 passo 3, quatro páginas adiante, imprime 0,033 para a mesma " *
            "equação. Adota-se 0,033: com d_m = 500 µm ele reproduz exatamente a Eq. 4.6b " *
            "do próprio livro e fica a 1,5 % da conversão exata da forma em unidades de " *
            "campo. Com 0,0033 daria dez vezes menos.",

            "Erro de digitação na Eq. 4.9b, contornado. Ela imprime coeficiente 1520 para " *
            "d_m = 200 µm; a forma geral com 0,033 dá 1320, e a conversão exata da forma " *
            "em unidades de campo dá 1300 mm — 1,5 % de 1320 e 17 % de 1520. Usa-se a " *
            "forma geral, que é a que fecha com as outras três equações.",

            "Contraparte da Eq. 4.18 ausente na fonte, suprida pela geometria. O §4.9.6 " *
            "generaliza o teto de água-em-óleo mas não escreve o de óleo-em-água para o " *
            "vaso cheio. Adota-se a leitura geométrica — a espessura máxima de água " *
            "dividida pela fração de altura que a água ocupa — e ela GOVERNA quando for " *
            "menor. É a leitura conservadora, e é decisão oposta à do separador " *
            "trifásico, onde a forma publicada foi mantida para reproduzir a tabela do " *
            "artigo. Aqui não há tabela a reproduzir, então não há motivo para preferir " *
            "uma forma que a geometria contradiz.",
        ],

        equacoes = [
            EquacaoDoc("Eq. 4.16", "Diferença de densidades e fração de área da água",
                "ΔSG = (SG)_w − (SG)_o,   a_w = α · Q_w·(t_r)_w / ( (t_r)_o·Q_o + (t_r)_w·Q_w )",
                raw"\Delta SG = \left( SG \right)_w - \left( SG \right)_o \quad " *
                raw"a_w = \alpha \cdot \frac{Q_w \cdot \left( t_r \right)_w}" *
                raw"{\left( t_r \right)_o \cdot Q_o + \left( t_r \right)_w \cdot Q_w}",
                [VariavelDoc("ΔSG", "diferença de densidades relativas", "–"),
                 VariavelDoc("(SG)_w", "densidade relativa da água", "–"),
                 VariavelDoc("(SG)_o", "densidade relativa do óleo", "–"),
                 VariavelDoc("a_w", "fração da seção ocupada pela água", "–"),
                 VariavelDoc("α", "fração da seção ocupada por líquido (vale 1: vaso cheio)", "–"),
                 VariavelDoc("Q_o", "vazão volumétrica de óleo", "m³/h"),
                 VariavelDoc("Q_w", "vazão volumétrica de água", "m³/h"),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", "min"),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", "min")];
                referencia = "Stewart & Arnold (2008), Eq. 4.16, §4.9.6",
                validade = "Exige ΔSG > 0: sem diferença de densidade o campo coalesce " *
                           "mas não há decantação. `α = 1` porque o vaso é cheio de " *
                           "líquido — é a generalização de §4.9.4-4.9.6 do vaso meio " *
                           "cheio."),

            EquacaoDoc("Eq. 4.2b", "Ganho de decantação da coalescência eletrostática",
                "ganho = ( d_m / 500 µm )²",
                raw"\text{ganho} = \left( \frac{d_m}{500} \right)^2",
                [VariavelDoc("ganho", "razão de velocidade de decantação em relação à emulsão sem tratamento", "×"),
                 VariavelDoc("d_m", "diâmetro da gotícula de água após coalescência", "µm")];
                referencia = "Stewart & Arnold (2008), Eq. 4.2b e §4.7.2",
                validade = "NÃO É CORRELAÇÃO — é a hipótese do projetista tornada " *
                           "visível. O expoente 2 é de Stokes; os 500 µm são a emulsão " *
                           "sem tratamento de §4.7.2. Ver a hipótese H2 da folha 02."),

            EquacaoDoc("Eq. 4.5b", "Espessura máxima da camada de óleo (água em óleo)",
                "(h_o)_max = 0,033 · (t_r)_o · ΔSG · d_m² / µ_o",
                raw"\left( h_o \right)_{max} = 0,033 \cdot \frac{\left( t_r \right)_o \cdot \Delta SG \cdot d_m^2}{\mu_o}",
                [VariavelDoc("(h_o)_max", "espessura máxima da camada de óleo", "mm"),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", "min"),
                 VariavelDoc("ΔSG", "diferença de densidades relativas", "–"),
                 VariavelDoc("d_m", "diâmetro da gotícula de água após coalescência", "µm"),
                 VariavelDoc("µ_o", "viscosidade dinâmica do óleo", "cP")];
                referencia = "Stewart & Arnold (2008), Eq. 4.5b, com o coeficiente de §4.9.3",
                validade = "Lei de Stokes. Coeficiente 0,033, e não o 0,0033 impresso na " *
                           "Eq. 4.5b — ver a hipótese H3 da folha 02."),

            EquacaoDoc("Eq. 4.9b", "Espessura máxima da camada de água (óleo em água)",
                "(h_w)_max = 0,033 · (t_r)_w · ΔSG · d_m² / µ_w",
                raw"\left( h_w \right)_{max} = 0,033 \cdot \frac{\left( t_r \right)_w \cdot \Delta SG \cdot d_m^2}{\mu_w}",
                [VariavelDoc("(h_w)_max", "espessura máxima da camada de água", "mm"),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", "min"),
                 VariavelDoc("ΔSG", "diferença de densidades relativas", "–"),
                 VariavelDoc("d_m", "diâmetro da gotícula de óleo", "µm"),
                 VariavelDoc("µ_w", "viscosidade dinâmica da água", "cP")];
                referencia = "Stewart & Arnold (2008), Eq. 4.9b, na forma geral",
                validade = "Forma geral com 0,033, e não o coeficiente 1520 impresso — " *
                           "ver a hipótese H4 da folha 02."),

            EquacaoDoc("Eq. 4.17", "Altura fracionária do segmento ocupado pela água",
                "β_w : A_seg(β_w) = a_w · A,   com  A_seg = R²·[ arccos(1 − h/R) − " *
                "(1 − h/R)·√(2h/R − (h/R)²) ]",
                raw"\beta_w : A_{seg} \left( \beta_w \right) = a_w \cdot A \quad A_{seg} = R^2 " *
                raw"\left[ \arccos \left( 1 - \frac{h}{R} \right) - \left( 1 - \frac{h}{R} \right) " *
                raw"\sqrt{\frac{2h}{R} - \left( \frac{h}{R} \right)^2} \right]",
                [VariavelDoc("β_w", "altura fracionária da camada de água", "–"),
                 VariavelDoc("a_w", "fração da seção ocupada pela água", "–"),
                 VariavelDoc("A_seg", "área do segmento circular inferior", "mm²"),
                 VariavelDoc("A", "área da seção transversal", "mm²"),
                 VariavelDoc("R", "raio interno do vaso", "mm")];
                referencia = "Stewart & Arnold (2008), Eq. 4.17",
                validade = "O livro a apresenta como relação a resolver por tentativa e " *
                           "erro, com o arco-cosseno em graus. Aqui é bisseção sobre a " *
                           "mesma equação, que é exata. Domínio a_w ∈ [0 ; 1] — o vaso é " *
                           "cheio, ao contrário dos meio cheios, onde vai só até 0,5."),

            EquacaoDoc("Eq. 4.18", "Teto de diâmetro pela decantação de água em óleo",
                "(d_max)_{w/o} = (h_o)_max / (β_l − β_w)",
                raw"\left( d_{max} \right)_{w/o} = \frac{\left( h_o \right)_{max}}{\beta_l - \beta_w}",
                [VariavelDoc("(d_max)_{w/o}", "diâmetro máximo admissível pela fase óleo", "mm"),
                 VariavelDoc("(h_o)_max", "espessura máxima da camada de óleo", "mm"),
                 VariavelDoc("β_l", "altura fracionária de toda a fase líquida (vale 1)", "–"),
                 VariavelDoc("β_w", "altura fracionária da camada de água", "–")];
                referencia = "Stewart & Arnold (2008), Eq. 4.18, §4.9.6",
                validade = "Generaliza a Eq. 4.8 do vaso meio cheio. `β_l − β_w` é a " *
                           "altura fracionária que sobra para o óleo."),

            EquacaoDoc("Eq. 4.18*", "Teto de diâmetro pela decantação de óleo em água — " *
                                    "contraparte geométrica",
                "(d_max)_{o/w} = (h_w)_max / β_w",
                raw"\left( d_{max} \right)_{o/w} = \frac{\left( h_w \right)_{max}}{\beta_w}",
                [VariavelDoc("(d_max)_{o/w}", "diâmetro máximo admissível pela fase água", "mm"),
                 VariavelDoc("(h_w)_max", "espessura máxima da camada de água", "mm"),
                 VariavelDoc("β_w", "altura fracionária da camada de água", "–")];
                referencia = "Leitura geométrica; a fonte não escreve esta contraparte " *
                             "para o vaso cheio — ver hipótese H5 da folha 02",
                validade = "ADOTADA, e governa quando for menor que a Eq. 4.18 — é a " *
                           "leitura conservadora. Omitida quando não há água emulsionada " *
                           "(β_w = 0), caso em que o teto seria infinito e não decidiria " *
                           "nada."),

            EquacaoDoc("Eq. 4.15b", "Capacidade de líquido — produto d²·Leff exigido",
                "d² · L_eff = 21000 · [ (t_r)_o·Q_o + (t_r)_w·Q_w ] / α",
                raw"d^2 \cdot L_{eff} = 21000 \cdot \frac{\left( t_r \right)_o \cdot Q_o + " *
                raw"\left( t_r \right)_w \cdot Q_w}{\alpha}",
                [VariavelDoc("d", "diâmetro interno do vaso", "mm"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", "min"),
                 VariavelDoc("Q_o", "vazão volumétrica de óleo", "m³/h"),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", "min"),
                 VariavelDoc("Q_w", "vazão volumétrica de água", "m³/h"),
                 VariavelDoc("α", "fração da seção ocupada por líquido (vale 1)", "–")];
                referencia = "Stewart & Arnold (2008), Eq. 4.15b, §4.9.5",
                validade = "A divisão por α é a generalização de §4.9.4: um vaso meio " *
                           "cheio (α = 0,5) precisa do dobro do produto d²·L_eff para o " *
                           "mesmo tempo de retenção."),

            EquacaoDoc("§4.9.1", "Comprimento entre costuras — o MAIOR das duas",
                "L_ss = max( L_eff + d/1000 ; (4/3) · L_eff )",
                raw"L_{ss} = \max \left( L_{eff} + \frac{d}{1000} ; \frac{4}{3} \cdot L_{eff} \right)",
                [VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm")];
                referencia = "Stewart & Arnold (2008), §4.9.1",
                validade = "São duas folgas construtivas independentes e o vaso tem de " *
                           "atender às duas."),

            EquacaoDoc("§4.9.2", "Esbeltez do vaso",
                "SR = L_ss / (d/1000)",
                raw"SR = \frac{L_{ss}}{d/1000}",
                [VariavelDoc("SR", "esbeltez (slenderness ratio)", "–"),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm")];
                referencia = "Stewart & Arnold (2008), §4.9.2",
                validade = "Banda recomendada 3 ≤ SR ≤ 5. É também o critério de escolha " *
                           "do diâmetro, entre os admissíveis da grade."),

            EquacaoDoc("Geom.", "Volume do casco entre costuras",
                "V = π · (d/1000)² / 4 · L_ss",
                raw"V = \frac{\pi \cdot \left( d/1000 \right)^2}{4} \cdot L_{ss}",
                [VariavelDoc("V", "volume do casco entre costuras", "m³"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm"),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m")];
                referencia = "Geometria do cilindro reto — não consta da fonte",
                validade = "Cilindro reto sobre L_ss. NÃO inclui os tampos elípticos 2:1 " *
                           "mostrados na elevação, que somariam cerca de 8,5 %."),
        ],

        resultados = [
            ResultadoDoc("Diâmetro d", "d", "§4.9.2"),
            ResultadoDoc("Comprimento efetivo Leff", "L_eff", "Eq. 4.15b"),
            ResultadoDoc("Comprimento real Lss", "L_ss", "§4.9.1"),
            ResultadoDoc("Esbeltez SR", "SR", "§4.9.2"),
            ResultadoDoc("Volume (casco, entre tampos)", "V", "Geom."),
            ResultadoDoc("Restrição governante", "—", "Eq. 4.15b"),
            ResultadoDoc("Caso governante", "—", "—"),
            ResultadoDoc("Teto de decantação", "d_max", "Eq. 4.18 / Eq. 4.18*"),
        ],

        verificacoes = [
            VerificacaoDoc("Esbeltez dentro da banda recomendada",
                           "Esbeltez SR", "3 ≤ SR ≤ 5 (ajustável)", "–"),
            VerificacaoDoc("Diâmetro sob o teto de decantação líquido-líquido",
                           "Teto de decantação", "d ≤ d_max (Eq. 4.18 / Eq. 4.18*)", "mm"),
        ],

        conclusao =
            "O vaso indicado na seção 1 atende ao tempo de retenção das duas fases " *
            "líquidas (Eq. 4.15b) e ao teto de decantação líquido-líquido " *
            "(Eq. 4.18 / Eq. 4.18*), com esbeltez dentro da banda de §4.9.2. Não há bloco " *
            "de capacidade de gás: o vaso é cheio de líquido e não tem fase gasosa a " *
            "separar. ATENÇÃO: este dimensionamento NÃO cobre o campo elétrico — " *
            "eletrodo, fonte e transformador ficam fora do escopo, e o diâmetro de " *
            "gotícula coalescida é hipótese do projetista, cujo ganho de decantação está " *
            "registrado na folha de fórmulas. As hipóteses da folha 02 devem ser lidas " *
            "junto com este resultado.",
    )
end
