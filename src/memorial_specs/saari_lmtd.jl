"""
A camada documental do trocador casco-e-tubos — [`memorial_spec`](@ref) para
[`SaariLMTD`](@ref).

**É o maior memorial do programa, e o único com DUAS fontes.** O balanço térmico, o ΔT
médio logarítmico, o fator de correção do arranjo 1-2 e o coeficiente global vêm de
Saari (LUT); o coeficiente do lado do casco vem do método de Bell-Delaware na forma de
Branan. As duas numerações convivem no documento e são distinguíveis à vista: `Eq. 4.x`,
`§x.y` e `Fig. 4.x` são de Saari; `Br. 2-xx` e `Tab. 4.1`, de Branan.

A conferência equação por equação — 12 relações de Saari e 13 de Branan, com página —
está em `docs/validacao/02-trocador-saari-bell-delaware.md` §1. **Cinco divergências**
entre o código e o texto publicado foram encontradas ali, e as cinco estão na folha 02
deste memorial com o número que as denuncia. Três delas são checáveis por dentro (uma
inconsistência dimensional, um fator de 2 que faz uma área sair 6,8× menor, e um
coeficiente que faria um fator de desconto amplificar em 40 %), uma foi verificada por
rota independente, e uma é um sinal de menos ausente numa linha de tabela entre vinte.

Uma só verificação, e é a única que aponta para um status real: a admissibilidade do
ponto (velocidade no tubo, convergência do laço e validade da correlação de Nusselt). Os
limites de diâmetro de casco e de comprimento de tubo da Tabela 3.1 **também** são
impostos, mas por construção — um ponto que os viole nunca é escolhido —, e por isso não
produzem veredito por campo. Ver a conclusão.
"""

function memorial_spec(::SaariLMTD)
    MemorialSpec(
        sigla       = "TRC",
        equipamento = "TROCADOR DE CALOR",
        titulo      = "DIMENSIONAMENTO DE TROCADOR DE CALOR",

        premissas = [
            PremissaDoc("P1",
                "Trocador casco-e-tubos, escoamento em contracorrente, com fator de " *
                "correção para o arranjo de dois passes no tubo.",
                "Saari (LUT), §4.2 e Algoritmo 4.1, p. 33"),
            PremissaDoc("P2",
                "Dimensionamento por varredura do número de tubos por passe: fixado ele, " *
                "ficam determinadas a velocidade no tubo e, por consequência, o " *
                "coeficiente de convecção interno.",
                "Saari (LUT), Algoritmo 4.1 passo 3, p. 33"),
            PremissaDoc("P3",
                "Coeficiente interno por correlação de Nusselt do tipo Dittus-Boelter, " *
                "com expoente de Prandtl distinto para aquecimento e resfriamento.",
                "Saari (LUT), Eq. (6.23), p. 68"),
            PremissaDoc("P4",
                "Coeficiente do lado do casco pelo método de Bell-Delaware: coeficiente " *
                "ideal de banco de tubos corrigido por cinco fatores de construção.",
                "Branan (2012), Eq. (2-18) a (2-29), pp. 42-45"),
            PremissaDoc("P5",
                "Coeficiente global por resistências em série referidas à área externa, " *
                "incluindo incrustação de ambos os lados e a parede do tubo.",
                "Saari (LUT), Eq. (5.4) e (5.7a), pp. 55-56"),
            PremissaDoc("P6",
                "Limites construtivos de casco de chapa, diâmetro de tubo, corte e " *
                "espaçamento de chicana, passo e velocidade conforme a prática tabelada.",
                "Saari (LUT), Tabela 3.1, p. 21"),
        ],

        hipoteses = [
            "Viscosidade de parede NÃO iterada. A correlação do coeficiente ideal do " *
            "casco traz o fator (µ/µ_parede)^0,14, que exige a temperatura da parede e " *
            "portanto um laço adicional. Adota-se o fator igual a 1 — hipótese declarada, " *
            "registrada como linha própria no desenvolvimento do cálculo, e não " *
            "escondida num default. O desvio é pequeno para líquidos de viscosidade " *
            "moderada e cresce com a diferença de temperatura através do filme.",

            "DIVERGÊNCIA 1 — Branan Eq. (2-21), inconsistência dimensional. O texto " *
            "imprime o termo 1,33/(PR/d_o), mas PR é definido três linhas acima como " *
            "ADIMENSIONAL (a razão passo/diâmetro, usualmente 1,25; 1,285; 1,33 ou 1,5). " *
            "Dividi-lo de novo por d_o daria ao termo dimensão de inverso de " *
            "comprimento, e o fator de Colburn passaria a depender de d_o estar em mm ou " *
            "em m. Usa-se 1,33/PR. Checável por dentro.",

            "DIVERGÊNCIA 2 — Branan Eq. (2-26), fator de 2 ausente. O texto imprime o " *
            "ângulo da janela como arco-cosseno simples; sem o fator 2, a área bruta da " *
            "janela sai 6,8 vezes menor que o segmento circular que ela é. Conferido " *
            "contra a geometria de segmento circular que este programa já usava nos " *
            "vasos. Checável por dentro.",

            "DIVERGÊNCIA 3 — Saari Fig. 4.3, razão R invertida. A legenda da figura " *
            "define R como a razão entre a variação de temperatura do lado 1 e a do lado " *
            "2, o que contradiz a Eq. (4.11) e a Eq. (4.12) DO PRÓPRIO TEXTO (R como " *
            "razão de capacidades térmicas, igual à razão inversa das variações) e a " *
            "convenção de Shah & Sekulić, que a mesma figura cita. Segue-se o texto, não " *
            "a legenda. Verificado por rota independente.",

            "DIVERGÊNCIA 4 — Branan Tabela 2-5, sinal ausente. Na linha de arranjo 90° " *
            "com Reynolds de 0 a 10, o expoente do Reynolds aparece sem o sinal de menos " *
            "que as outras dezenove linhas da tabela trazem. O fator de Colburn tem de " *
            "cair com o Reynolds, e é o que as outras quatro faixas do mesmo arranjo " *
            "fazem. Adota-se o expoente negativo. Confirmado na página renderizada: os " *
            "sinais estão nítidos em dezenove linhas e ausentes nessa.",

            "DIVERGÊNCIA 5 — Branan Eq. (2-23), coeficiente do fator de vazamento. O " *
            "texto imprime 0,044 no segundo colchete. O fator de vazamento é um fator " *
            "que DESCONTA: com vazamento nulo ele tem de valer exatamente 1. Com 0,44 " *
            "nos dois lugares dá 1; com o 0,044 impresso daria 1,396 — um fator de " *
            "correção que AMPLIFICA o coeficiente do casco em 40 % justamente onde a " *
            "construção é perfeita. Adota-se 0,44, que é também a forma de Taborek e de " *
            "Shah & Sekulić. Checável por dentro.",

            "Escoamento em PARALELO não implementado, por escolha. A fonte traz a " *
            "expressão das diferenças de temperatura para esse arranjo, mas o método " *
            "aqui é contracorrente com fator de correção — que é o que cobre o arranjo " *
            "1-2 real e o que o Algoritmo 4.1 prescreve.",

            "Este dimensionamento é TÉRMICO e GEOMÉTRICO. Não calcula perda de carga em " *
            "nenhum dos dois lados, não verifica vibração induzida por escoamento, não " *
            "dimensiona espelho, junta de expansão nem bocais, e não trata mudança de " *
            "fase. A velocidade no tubo é limitada pela banda da Tabela 3.1, que é o " *
            "controle indireto de erosão e de incrustação disponível sem o cálculo de " *
            "perda de carga.",
        ],

        equacoes = [
            # ---------------------------------------------------------- balanço
            EquacaoDoc("Eq. 4.5", "Balanço de energia e temperatura de saída do casco",
                "q = (ṁ·c_p)_tubo · (T_saída − T_entrada)_tubo = (ṁ·c_p)_casco · ΔT_casco",
                [VariavelDoc("q", "carga térmica trocada", "W"),
                 VariavelDoc("ṁ", "vazão mássica", "kg/s"),
                 VariavelDoc("c_p", "calor específico à pressão constante", "J/kg·K"),
                 VariavelDoc("T", "temperatura da corrente", "°C")];
                referencia = "Saari (LUT), Eq. (4.5), p. 34",
                validade = "Regime permanente, sem perdas para o ambiente e sem mudança " *
                           "de fase. A temperatura de saída do casco é a incógnita que " *
                           "este balanço fecha."),

            EquacaoDoc("Eq. 4.7", "Diferenças de temperatura nas extremidades — contracorrente",
                "ΔT₁ = T_quente,ent − T_frio,saída    ΔT₂ = T_quente,saída − T_frio,ent",
                [VariavelDoc("ΔT₁", "diferença de temperatura numa extremidade", "K"),
                 VariavelDoc("ΔT₂", "diferença de temperatura na outra extremidade", "K")];
                referencia = "Saari (LUT), Eq. (4.7), p. 36",
                validade = "Forma de CONTRACORRENTE. A forma de escoamento paralelo " *
                           "(Eq. 4.8) não é implementada — ver a hipótese sobre arranjo " *
                           "na folha 02."),

            EquacaoDoc("Eq. 4.6", "Diferença de temperatura média logarítmica",
                "ΔT_lm = (ΔT₁ − ΔT₂) / ln(ΔT₁/ΔT₂)",
                [VariavelDoc("ΔT_lm", "diferença média logarítmica de temperatura", "K"),
                 VariavelDoc("ΔT₁", "diferença de temperatura numa extremidade", "K"),
                 VariavelDoc("ΔT₂", "diferença de temperatura na outra extremidade", "K")];
                referencia = "Saari (LUT), Eq. (4.6), p. 35",
                validade = "Com capacidades térmicas iguais nos dois lados as duas " *
                           "diferenças coincidem e a expressão tem limite removível, " *
                           "igual à própria diferença (§4.2.3)."),

            EquacaoDoc("Fig. 4.3", "Fator de correção do arranjo 1-2",
                "F = √(1+R²)·ln[(1−R·P)/(1−P)] / { (1−R)·ln[ (2−P(1+R−√(1+R²))) / " *
                "(2−P(1+R+√(1+R²))) ] }",
                [VariavelDoc("F", "fator de correção do arranjo", "–"),
                 VariavelDoc("P", "efetividade de temperatura do lado do tubo", "–"),
                 VariavelDoc("R", "razão de capacidades térmicas", "–")];
                referencia = "Saari (LUT), Fig. 4.3, p. 40; P pela Eq. (4.10) e R pelas " *
                             "Eq. (4.11)/(4.12), pp. 38-39",
                validade = "Um casco, dois passes no tubo. Fora do domínio da figura o " *
                           "arranjo 1-2 não fecha com aquelas temperaturas — é o " *
                           "cruzamento interno do segundo passe que não é viável, e o " *
                           "caso é recusado com essa explicação. A razão R segue o TEXTO " *
                           "e não a legenda da figura: ver a divergência 3 da folha 02."),

            EquacaoDoc("§4.2.1", "Fator de correção em contracorrente puro",
                "F = 1",
                [VariavelDoc("F", "fator de correção do arranjo", "–")];
                referencia = "Saari (LUT), §4.2.1, p. 36",
                validade = "Vale quando há um único passe no tubo: não há cruzamento de " *
                           "correntes a corrigir. É a alternativa à Fig. 4.3, e apenas " *
                           "uma das duas é avaliada em cada dimensionamento."),

            EquacaoDoc("Eq. 4.9", "Produto coeficiente global × área exigido",
                "U · A = q / (F · ΔT_lm)",
                [VariavelDoc("U", "coeficiente global de troca", "W/m²·K"),
                 VariavelDoc("A", "área de troca referida ao diâmetro externo", "m²"),
                 VariavelDoc("q", "carga térmica trocada", "W"),
                 VariavelDoc("F", "fator de correção do arranjo", "–"),
                 VariavelDoc("ΔT_lm", "diferença média logarítmica de temperatura", "K")];
                referencia = "Saari (LUT), Eq. (4.9), p. 38",
                validade = "É a exigência TÉRMICA do serviço, e não depende da geometria " *
                           "escolhida — por isso é calculada uma vez, antes da varredura."),

            # ---------------------------------------------------------- tubo
            EquacaoDoc("§6.1.1", "Número de Prandtl das correntes",
                "Pr = c_p · µ / k",
                [VariavelDoc("Pr", "número de Prandtl", "–"),
                 VariavelDoc("c_p", "calor específico à pressão constante", "J/kg·K"),
                 VariavelDoc("µ", "viscosidade dinâmica", "Pa·s"),
                 VariavelDoc("k", "condutividade térmica", "W/m·K")];
                referencia = "Saari (LUT), §6.1.1, p. 62",
                validade = "Avaliado para o fluido do tubo e, quando o método de " *
                           "Bell-Delaware está ativo, também para o do casco."),

            EquacaoDoc("§3.2.2", "Diâmetro interno e velocidade no tubo",
                "d_i = d_o − 2·e        v = ṁ / ( ρ · n · π·d_i²/4 )",
                [VariavelDoc("d_i", "diâmetro interno do tubo", "mm"),
                 VariavelDoc("d_o", "diâmetro externo do tubo", "mm"),
                 VariavelDoc("e", "espessura de parede do tubo", "mm"),
                 VariavelDoc("v", "velocidade média no tubo", "m/s"),
                 VariavelDoc("ṁ", "vazão mássica do lado do tubo", "kg/s"),
                 VariavelDoc("ρ", "massa específica do fluido do tubo", "kg/m³"),
                 VariavelDoc("n", "número de tubos por passe", "–")];
                referencia = "Saari (LUT), §3.2.2, p. 19",
                validade = "A velocidade é o que a varredura de fato move: fixado o " *
                           "número de tubos por passe, ela fica determinada, e com ela o " *
                           "coeficiente interno."),

            EquacaoDoc("§6.3", "Número de Reynolds no tubo",
                "Re = ρ · v · d_i / µ",
                [VariavelDoc("Re", "número de Reynolds no tubo", "–"),
                 VariavelDoc("ρ", "massa específica do fluido do tubo", "kg/m³"),
                 VariavelDoc("v", "velocidade média no tubo", "m/s"),
                 VariavelDoc("d_i", "diâmetro interno do tubo", "m"),
                 VariavelDoc("µ", "viscosidade dinâmica do fluido do tubo", "Pa·s")];
                referencia = "Saari (LUT), §6.3, p. 66",
                validade = "É o Reynolds que decide se a correlação de Nusselt do tubo " *
                           "vale: um ponto fora da faixa dela é recusado, não " *
                           "extrapolado."),

            EquacaoDoc("Eq. 6.23", "Coeficiente de convecção interno",
                "Nu = 0,024 · Re^0,8 · Pr^0,4  (aquecimento)    " *
                "Nu = 0,026 · Re^0,8 · Pr^0,3  (resfriamento)    " *
                "h_i = Nu · k / d_i",
                [VariavelDoc("Nu", "número de Nusselt", "–"),
                 VariavelDoc("Re", "número de Reynolds no tubo", "–"),
                 VariavelDoc("Pr", "número de Prandtl do fluido do tubo", "–"),
                 VariavelDoc("h_i", "coeficiente de convecção interno", "W/m²·K"),
                 VariavelDoc("k", "condutividade térmica do fluido do tubo", "W/m·K"),
                 VariavelDoc("d_i", "diâmetro interno do tubo", "m")];
                referencia = "Saari (LUT), Eq. (6.23), p. 68 — tipo Dittus-Boelter",
                validade = "O expoente de Prandtl distingue aquecimento de resfriamento " *
                           "do fluido do tubo. Correlação para escoamento turbulento " *
                           "plenamente desenvolvido."),

            # ---------------------------------------------------------- casco
            EquacaoDoc("Br. 2-20", "Número de Reynolds do lado do casco",
                "Re_s = d_o · W_s / ( µ_s · A_s )",
                [VariavelDoc("Re_s", "número de Reynolds do casco", "–"),
                 VariavelDoc("d_o", "diâmetro externo do tubo", "m"),
                 VariavelDoc("W_s", "vazão mássica do lado do casco", "kg/s"),
                 VariavelDoc("µ_s", "viscosidade dinâmica do fluido do casco", "Pa·s"),
                 VariavelDoc("A_s", "área de escoamento cruzado na linha de centro", "m²")];
                referencia = "Branan (2012), Eq. (2-20), p. 43",
                validade = "A área de escoamento cruzado tem duas formas conforme o " *
                           "arranjo e a razão passo/diâmetro, e as duas estão " *
                           "implementadas com os limiares publicados (p. 42)."),

            EquacaoDoc("Br. 2-19", "Coeficiente ideal de banco de tubos",
                "h_ideal = J · c_ps · (W_s/A_s) · [ k_s/(c_ps·µ_s) ]^(2/3) · " *
                "(µ_s/µ_s,parede)^0,14",
                [VariavelDoc("h_ideal", "coeficiente ideal do banco de tubos", "W/m²·K"),
                 VariavelDoc("J", "fator de Colburn do banco ideal", "–"),
                 VariavelDoc("c_ps", "calor específico do fluido do casco", "J/kg·K"),
                 VariavelDoc("W_s", "vazão mássica do lado do casco", "kg/s"),
                 VariavelDoc("A_s", "área de escoamento cruzado", "m²"),
                 VariavelDoc("k_s", "condutividade térmica do fluido do casco", "W/m·K"),
                 VariavelDoc("µ_s", "viscosidade dinâmica do fluido do casco", "Pa·s")];
                referencia = "Branan (2012), Eq. (2-19), p. 42; fator de Colburn pela " *
                             "Eq. (2-21) e Tabela 2-5, pp. 42-43",
                validade = "O fator (µ/µ_parede)^0,14 é adotado igual a 1 — ver a " *
                           "hipótese H1 da folha 02. O fator de Colburn e os vinte " *
                           "conjuntos de coeficientes da Tabela 2-5 carregam as " *
                           "divergências 1 e 4 da folha 02."),

            EquacaoDoc("Br. 2-22", "Fator de correção do corte e espaçamento de chicana",
                "J_c = 0,55 + 0,72 · F_c,   " *
                "F_c = (1/π)·[ π + 2φ·sen(arccos φ) − 2·arccos φ ],   " *
                "φ = (D_s − 2·l_c)/D_otl",
                [VariavelDoc("J_c", "fator de corte e espaçamento de chicana", "–"),
                 VariavelDoc("F_c", "fração de tubos em escoamento cruzado", "–"),
                 VariavelDoc("D_s", "diâmetro interno do casco", "m"),
                 VariavelDoc("l_c", "altura do corte de chicana", "m"),
                 VariavelDoc("D_otl", "diâmetro do limite externo do feixe", "m")];
                referencia = "Branan (2012), Eq. (2-22), p. 43",
                validade = "Corrige o coeficiente ideal pela fração do feixe que está " *
                           "efetivamente em escoamento cruzado."),

            EquacaoDoc("Br. 2-23", "Fator de correção do vazamento nas chicanas",
                "J_l = 0,44·(1 − r_a) + [ 1 − 0,44·(1 − r_a) ] · exp(−2,2 · r_b)",
                [VariavelDoc("J_l", "fator de vazamento casco-chicana e tubo-chicana", "–"),
                 VariavelDoc("r_a", "razão entre a área de vazamento casco-chicana e a total de vazamento", "–"),
                 VariavelDoc("r_b", "razão entre a área total de vazamento e a de escoamento cruzado", "–")];
                referencia = "Branan (2012), Eq. (2-23), p. 43; áreas de vazamento pelas " *
                             "Eq. (2-24) a (2-26), p. 44; folgas TEMA R na Tabela 2-7",
                validade = "COEFICIENTE 0,44 nos dois lugares, e não o 0,044 impresso no " *
                           "segundo colchete: ver a divergência 5 da folha 02. Com " *
                           "vazamento nulo o fator vale exatamente 1, como um fator de " *
                           "desconto deve valer. A área da janela usada aqui carrega a " *
                           "divergência 2."),

            EquacaoDoc("Br. 2-27", "Fator de correção do desvio pelo vão feixe-casco",
                "J_b = exp[ −C · r_c · (1 − (2z)^(1/3)) ]  para z < 1/2;   J_b = 1  para z ≥ 1/2",
                [VariavelDoc("J_b", "fator de desvio pelo vão entre feixe e casco", "–"),
                 VariavelDoc("C", "coeficiente do regime (1,35 até Re 100; 1,25 acima)", "–"),
                 VariavelDoc("r_c", "razão entre a área do vão e a de escoamento cruzado", "–"),
                 VariavelDoc("z", "razão entre tiras de selagem e fileiras em escoamento cruzado", "–")];
                referencia = "Branan (2012), Eq. (2-27), p. 44",
                validade = "Com tiras de selagem suficientes o desvio é bloqueado e o " *
                           "fator satura em 1."),

            EquacaoDoc("Br. 2-28", "Fator de correção das pontas de chicana alargadas",
                "J_s = [ n_b − 1 + L_i^(1−n) + L_o^(1−n) ] / [ n_b − 1 + L_i + L_o ]",
                [VariavelDoc("J_s", "fator das pontas de chicana", "–"),
                 VariavelDoc("n_b", "número de chicanas", "–"),
                 VariavelDoc("L_i", "razão entre o espaçamento de entrada e o central", "–"),
                 VariavelDoc("L_o", "razão entre o espaçamento de saída e o central", "–"),
                 VariavelDoc("n", "expoente do regime de escoamento", "–")];
                referencia = "Branan (2012), Eq. (2-28), p. 45",
                validade = "Corrige o efeito dos vãos maiores nas extremidades, onde " *
                           "estão os bocais."),

            EquacaoDoc("Br. 2-29", "Fator de correção do gradiente adverso em regime laminar",
                "J_r = (10/n_r,cc)^0,18 até Re 20;   J_r = 1 acima de Re 100;   " *
                "interpolação linear entre os dois",
                [VariavelDoc("J_r", "fator de gradiente adverso de temperatura", "–"),
                 VariavelDoc("n_r,cc", "número de fileiras de tubos em escoamento cruzado", "–"),
                 VariavelDoc("Re", "número de Reynolds do casco", "–")];
                referencia = "Branan (2012), Eq. (2-29), p. 45",
                validade = "Só atua em regime laminar e de transição; acima de Reynolds " *
                           "100 o fator vale 1 e não corrige nada."),

            EquacaoDoc("Br. 2-18", "Coeficiente do lado do casco corrigido",
                "h_o = h_ideal · J_c · J_l · J_b · J_s · J_r",
                [VariavelDoc("h_o", "coeficiente de convecção do lado do casco", "W/m²·K"),
                 VariavelDoc("h_ideal", "coeficiente ideal do banco de tubos", "W/m²·K"),
                 VariavelDoc("J_c", "fator de corte e espaçamento de chicana", "–"),
                 VariavelDoc("J_l", "fator de vazamento", "–"),
                 VariavelDoc("J_b", "fator de desvio", "–"),
                 VariavelDoc("J_s", "fator das pontas de chicana", "–"),
                 VariavelDoc("J_r", "fator de gradiente adverso", "–")];
                referencia = "Branan (2012), Eq. (2-18), p. 42",
                validade = "É o método de Bell-Delaware: o coeficiente do banco ideal " *
                           "descontado pelas cinco imperfeições de construção. A linha de " *
                           "hipótese registrada neste bloco é o fator de viscosidade de " *
                           "parede adotado igual a 1."),

            EquacaoDoc("Tab. 4.1", "Coeficiente do lado do casco informado",
                "h_o = valor de projeto informado",
                [VariavelDoc("h_o", "coeficiente de convecção do lado do casco", "W/m²·K")];
                referencia = "Saari (LUT), Tabela 4.1, p. 32 — faixas típicas por serviço",
                validade = "ALTERNATIVA ao método de Bell-Delaware, usada quando ele está " *
                           "desligado nas constantes do método. Apenas um dos dois " *
                           "caminhos é avaliado em cada dimensionamento."),

            # ---------------------------------------------------- global e geometria
            EquacaoDoc("Eq. 5.7a", "Coeficiente global por resistências em série",
                "U = [ 1/h_o + R\"_f,o + A_o·R_w + (A_o/A_i)·R\"_f,i + (A_o/A_i)/h_i ]^(−1)",
                [VariavelDoc("U", "coeficiente global referido à área externa", "W/m²·K"),
                 VariavelDoc("h_o", "coeficiente de convecção do lado do casco", "W/m²·K"),
                 VariavelDoc("h_i", "coeficiente de convecção interno", "W/m²·K"),
                 VariavelDoc("R\"_f", "resistência de incrustação por unidade de área", "m²·K/W"),
                 VariavelDoc("R_w", "resistência da parede do tubo", "K/W"),
                 VariavelDoc("A_o/A_i", "razão entre as áreas externa e interna", "–")];
                referencia = "Saari (LUT), Eq. (5.7a), p. 56; resistência de parede pela " *
                             "Eq. (5.4), p. 55",
                validade = "Referido à área EXTERNA — é por isso que os termos do lado " *
                           "interno aparecem multiplicados pela razão de áreas. A " *
                           "resistência de parede é a do cilindro, logarítmica no " *
                           "diâmetro."),

            EquacaoDoc("Eq. 4.4", "Área de troca exigida",
                "A = q / ( U · F · ΔT_lm )",
                [VariavelDoc("A", "área de troca referida ao diâmetro externo", "m²"),
                 VariavelDoc("q", "carga térmica trocada", "W"),
                 VariavelDoc("U", "coeficiente global de troca", "W/m²·K"),
                 VariavelDoc("F", "fator de correção do arranjo", "–"),
                 VariavelDoc("ΔT_lm", "diferença média logarítmica de temperatura", "K")];
                referencia = "Saari (LUT), Eq. (4.4), p. 34, com o fator F da Eq. (4.9)",
                validade = "Fecha o Algoritmo 4.1: é desta área que sai o comprimento de " *
                           "tubo, e é ela que o critério de escolha minimiza."),

            EquacaoDoc("Br. 2-13", "Diâmetro do feixe de tubos",
                "d_feixe = √( 4 · N · A_célula / π )",
                [VariavelDoc("d_feixe", "diâmetro do feixe de tubos", "mm"),
                 VariavelDoc("N", "número total de tubos", "–"),
                 VariavelDoc("A_célula", "área ocupada por um tubo no arranjo", "m²")];
                referencia = "Branan (2012), Eq. (2-13) e (2-14), p. 41 — área por tubo " *
                             "conforme o arranjo, triangular ou quadrado",
                validade = "A área por tubo depende do arranjo: triangular nos layouts de " *
                           "30° e 60°, quadrada nos de 45° e 90° (Tabela 2-6, p. 43)."),

            EquacaoDoc("Br. 2-17", "Diâmetro interno do casco",
                "D_s = d_feixe + 2·d_o",
                [VariavelDoc("D_s", "diâmetro interno do casco", "mm"),
                 VariavelDoc("d_feixe", "diâmetro do feixe de tubos", "mm"),
                 VariavelDoc("d_o", "diâmetro externo do tubo", "mm")];
                referencia = "Branan (2012), Eq. (2-17), p. 41",
                validade = "É o casco MÍNIMO para acomodar o feixe. É este número, e não " *
                           "o diâmetro do feixe, que é comparado ao limite construtivo da " *
                           "Tabela 3.1 de Saari."),
        ],

        # `Tubos por passe` e `Comprimento do tubo L` não citam equação: o primeiro é o
        # ponto escolhido pelo critério de menor área, e o segundo é a área distribuída
        # pela superfície de um tubo. Nenhum dos dois é equação da fonte.
        resultados = [
            ResultadoDoc("Tubos por passe", "n", "—"),
            ResultadoDoc("Comprimento do tubo L", "L", "Eq. 4.4"),
            ResultadoDoc("Área de troca A", "A", "Eq. 4.4"),
            ResultadoDoc("Tubos no total", "N", "—"),
            ResultadoDoc("Diâmetro do feixe", "d_feixe", "Br. 2-13"),
            ResultadoDoc("Diâmetro do casco", "D_s", "Br. 2-17"),
            ResultadoDoc("Esbeltez do feixe L/D", "L/D_s", "—"),
            ResultadoDoc("Velocidade no tubo", "v", "§3.2.2"),
            ResultadoDoc("Reynolds no tubo", "Re", "§6.3"),
            ResultadoDoc("Coeficiente interno h_i", "h_i", "Eq. 6.23"),
            ResultadoDoc("Coeficiente do casco h_o", "h_o", "Br. 2-18 / Tab. 4.1"),
            ResultadoDoc("Correção de Bell-Delaware", "J_c·J_l·J_b·J_s·J_r", "Br. 2-18"),
            ResultadoDoc("Coeficiente global U", "U", "Eq. 5.7a"),
            ResultadoDoc("Carga térmica q", "q", "Eq. 4.5"),
            ResultadoDoc("ΔT médio logarítmico", "ΔT_lm", "Eq. 4.6"),
            ResultadoDoc("Fator de correção F", "F", "Fig. 4.3 / §4.2.1"),
            ResultadoDoc("Caso governante", "—", "—"),
        ],

        # UMA verificação. Os limites de diâmetro de casco e de comprimento de tubo da
        # Tabela 3.1 também são impostos, mas POR CONSTRUÇÃO — um ponto que os viole
        # nunca é escolhido —, e não produzem veredito por campo. Declará-los aqui faria
        # a folha 04 imprimir travessão numa linha de verificação. Ver a conclusão.
        verificacoes = [
            VerificacaoDoc("Ponto admissível: velocidade no tubo na banda recomendada, " *
                           "laço do casco convergido e correlação de Nusselt na faixa",
                           "Velocidade no tubo",
                           "v_min ≤ v ≤ v_max (Tabela 3.1)", "m/s"),
        ],

        conclusao =
            "O trocador indicado na seção 1 entrega a carga térmica do serviço com a " *
            "área de troca da seção 1, obtida pelo Algoritmo 4.1: fixado o número de " *
            "tubos por passe, ficam determinadas a velocidade, o coeficiente interno e, " *
            "com o coeficiente do casco, o coeficiente global — e dele a área e o " *
            "comprimento. Entre os pontos admissíveis escolhe-se o de MENOR ÁREA, que é " *
            "o que paga o equipamento. Os limites construtivos de diâmetro de casco e " *
            "comprimento de tubo da Tabela 3.1 são impostos por construção: um ponto que " *
            "os violasse não seria escolhido, de modo que o resultado existir já é o " *
            "atendimento deles — por isso não aparecem como linha de verificação, que " *
            "exigiria um veredito por campo que o motor não emite. LIMITAÇÃO: este " *
            "dimensionamento é térmico e geométrico. Não calcula perda de carga em " *
            "nenhum dos dois lados, não verifica vibração induzida por escoamento, não " *
            "dimensiona espelho, junta de expansão ou bocais, e não trata mudança de " *
            "fase. As cinco divergências em relação ao texto publicado estão na folha 02 " *
            "e devem ser lidas junto com este resultado.",
    )
end
