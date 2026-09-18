"""
A camada documental do separador trifásico — [`memorial_spec`](@ref) para
[`StewartArnold`](@ref).

Mora num arquivo próprio, e não dentro de `sizing/separator/stewart_arnold.jl`, por
tamanho: são ~15 equações com notação, variáveis, referência e validade, e o arquivo do
método tem 227 linhas das quais 84 já são a discussão das divergências. Misturar as duas
coisas faria a física ficar mais difícil de achar do que a prosa que a descreve.

**Nada aqui é novo.** Cada `numero` é a string que `sizing_constraints` carimba no
rastro, cada `notacao` é a fórmula que `drag.jl`, `beta.jl`, `gas_capacity.jl` e
`stewart_arnold.jl` de fato avaliam, e cada unidade é a que `field_units` entrega. As
hipóteses são as quatro divergências já documentadas no cabeçalho do método — copiadas
para cá porque o memorial vai anexo ao relatório e o comentário do código não.

`test/memorial.jl` verifica a correspondência nos dois sentidos; se alguém mexer numa
equação do motor sem mexer aqui, ou vice-versa, a suíte quebra.
"""

# As unidades repetem-se muito entre os blocos; nomeá-las uma vez evita a classe de erro
# de digitar "cP" num lugar e "cp" noutro, que passaria despercebida no documento.
const _V_DM   = "µm"
const _V_RHO  = "kg/m³"
const _V_MU   = "cP"
const _V_Q    = "m³/h"
const _V_TR   = "min"
const _V_MM   = "mm"
const _V_ADIM = "–"

function memorial_spec(::StewartArnold)
    MemorialSpec(
        sigla       = "SEP",
        equipamento = "SEPARADOR TRIFÁSICO",
        titulo      = "DIMENSIONAMENTO DE SEPARADOR TRIFÁSICO",

        # --------------------------------------------------------------- premissas
        # Cada uma citando onde está escrita. A P3 e a P4 são as que o usuário controla
        # pelo formulário (gotícula e tempo de retenção); aparecem aqui como premissa
        # porque é o que elas são, e o VALOR delas entra pela folha 02, não por aqui.
        premissas = [
            PremissaDoc("P1",
                "Vaso cilíndrico horizontal operando preenchido pela metade de líquido; " *
                "a metade superior é o espaço de gás.",
                "Stewart & Arnold (2008), §3.8 / Fig. 3"),
            PremissaDoc("P2",
                "Separação gravitacional das três fases: gás no topo, óleo sobre a água, " *
                "sem emulsão estável na interface.",
                "Alves & Komesu (2025), §2"),
            PremissaDoc("P3",
                "Critério de gotícula: água > 500 µm decanta na fase óleo; óleo > 200 µm " *
                "ascende na fase água; gotas > 100 µm devem decantar da corrente gasosa.",
                "Stewart & Arnold (2008), §3.8.2"),
            PremissaDoc("P4",
                "Tempos de retenção das fases líquidas fixados por projeto, iguais para " *
                "óleo e água salvo indicação em contrário.",
                "Alves & Komesu (2025), Tabela 1"),
            PremissaDoc("P5",
                "Decantação líquido-líquido pela lei de Stokes, com as gotículas na faixa " *
                "de regime viscoso.",
                "Stewart & Arnold (2008), §3.8.3"),
            PremissaDoc("P6",
                "Esbeltez recomendada 3 ≤ SR ≤ 5, para evitar turbulência e quebra da " *
                "interface líquido-líquido.",
                "Stewart & Arnold (2008), §3.8.4"),
        ],

        # -------------------------------------------------------------- hipóteses
        # As quatro divergências do cabeçalho de `stewart_arnold.jl`, na linguagem de
        # quem lê o documento e não o código. É a seção que o handoff marca como
        # obrigatória: toda simplificação assumida entra aqui.
        hipoteses = [
            "Eq. 22 — coeficiente de capacidade de líquido. O artigo imprime 4,12×10⁴, " *
            "valor inconsistente com a sua própria Tabela 3. Adota-se o coeficiente " *
            "derivado da forma em unidades de campo de Stewart & Arnold, que reproduz a " *
            "Tabela 3 com 0,35 % de desvio, contra 1,9 % do valor impresso.",

            "Viscosidade do gás. Os 0,6 cP da Tabela 1 do artigo são viscosidade de " *
            "líquido (gás natural nas condições do caso fica em ~0,012 cP); as colunas " *
            "da tabela foram trocadas na transcrição. A viscosidade do gás é entrada " *
            "explícita do formulário para que a escolha fique visível. Em nenhum dos " *
            "dois valores a capacidade de gás governa o dimensionamento.",

            "Eq. 21 — cota da camada de água. O artigo divide (h_w)max por β, mas β é a " *
            "altura fracionária da fase ÓLEO; a da água, num vaso meio cheio, é 0,5 − β. " *
            "Segue-se o texto publicado, porque o propósito declarado é reproduzir o " *
            "método do artigo. A variante geométrica é calculada e registrada como " *
            "Eq. 21*, sem decidir nada: sob ela o teto de diâmetro cairia de 16508 para " *
            "3810 mm e o mecanismo governante se inverteria — ou seja, o método " *
            "publicado é não-conservador neste ponto.",

            "Eq. 15 e 23 — comprimento entre costuras. Stewart & Arnold mandam tomar o " *
            "MAIOR entre Leff + d e (4/3)·Leff, que são duas folgas construtivas " *
            "independentes. O artigo usa a relação do bloco que governa o Leff, e é o " *
            "que se segue aqui; nas pontas superiores da grade isso encurta o vaso em " *
            "até 5 % em relação à regra do livro.",
        ],

        # --------------------------------------------------------------- equações
        # Na ORDEM DO CÁLCULO — a mesma em que `sizing_constraints` as resolve —, e não
        # em ordem numérica: um memorial só se lê de cima para baixo. É por isso que a
        # Eq. 20 vem antes da Eq. 18 aqui, como vem no rastro.
        equacoes = [
            # ---------------------------------------------- bloco A: capacidade de gás
            EquacaoDoc("Eq. 9–11", "Coeficiente de arrasto da gotícula de líquido no gás",
                "C_D = 24/Re + 3/√Re + 0,34",
                [VariavelDoc("C_D", "coeficiente de arrasto", _V_ADIM),
                 VariavelDoc("Re", "número de Reynolds da gotícula", _V_ADIM)];
                referencia = "Stewart & Arnold (2008), Eq. 3.6; Alves & Komesu (2025), Eq. 9",
                validade = "Resolvida junto com as Eq. 10 e 11 por substituição sucessiva " *
                           "a partir de C_D = 0,34, com sub-relaxação de 0,5. Fora do " *
                           "regime laminar puro (Re > 1)."),

            EquacaoDoc("Eq. 11", "Velocidade terminal de decantação da gotícula",
                "V_t = 0,0036 · [ ((ρ_l − ρ_g)/ρ_g) · (d_m/C_D) ]^(1/2)",
                [VariavelDoc("V_t", "velocidade terminal da gotícula", "m/s"),
                 VariavelDoc("ρ_l", "massa específica da fase líquida (adotada a do óleo)", _V_RHO),
                 VariavelDoc("ρ_g", "massa específica do gás", _V_RHO),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", _V_DM),
                 VariavelDoc("C_D", "coeficiente de arrasto", _V_ADIM)];
                referencia = "Stewart & Arnold (2008), Eq. 3.7b; Alves & Komesu (2025), Eq. 11",
                validade = "Coeficiente 0,0036 embute a conversão de d_m em µm para o " *
                           "resultado em m/s."),

            EquacaoDoc("Eq. 10", "Número de Reynolds da gotícula",
                "Re = 0,001 · ρ_g · d_m · V_t / µ_g",
                [VariavelDoc("Re", "número de Reynolds da gotícula", _V_ADIM),
                 VariavelDoc("ρ_g", "massa específica do gás", _V_RHO),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", _V_DM),
                 VariavelDoc("V_t", "velocidade terminal da gotícula", "m/s"),
                 VariavelDoc("µ_g", "viscosidade dinâmica do gás", _V_MU)];
                referencia = "Alves & Komesu (2025), Eq. 10",
                validade = "Coeficiente 0,001 embute d_m em µm e µ_g em cP."),

            EquacaoDoc("Eq. 13", "Constante de Souders–Brown",
                "K = [ (ρ_g/(ρ_l − ρ_g)) · (C_D/d_m) ]^(1/2)",
                [VariavelDoc("K", "constante de Souders–Brown", _V_ADIM),
                 VariavelDoc("ρ_g", "massa específica do gás", _V_RHO),
                 VariavelDoc("ρ_l", "massa específica da fase líquida (adotada a do óleo)", _V_RHO),
                 VariavelDoc("C_D", "coeficiente de arrasto convergido", _V_ADIM),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", _V_DM)];
                referencia = "Stewart & Arnold (2008), Eq. 3.1; Alves & Komesu (2025), Eq. 13",
                validade = ""),

            EquacaoDoc("Eq. 14", "Capacidade de gás — produto d·Leff exigido",
                "d · L_eff = 34,5 · [ (T · Z · Q_g) / P ] · K",
                [VariavelDoc("d", "diâmetro interno do vaso", _V_MM),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("T", "temperatura de operação", "K"),
                 VariavelDoc("Z", "fator de compressibilidade do gás", _V_ADIM),
                 VariavelDoc("Q_g", "vazão volumétrica de gás", _V_Q),
                 VariavelDoc("P", "pressão de operação", "kPa"),
                 VariavelDoc("K", "constante de Souders–Brown", _V_ADIM)];
                referencia = "Stewart & Arnold (2008), Eq. 3.8b; Alves & Komesu (2025), Eq. 14",
                validade = "Forma em SI: o coeficiente 34,5 corresponde a d em mm, " *
                           "L_eff em m, T em K, Q_g em m³/h e P em kPa."),

            # ------------------------------------------ bloco B: decantação líquida
            EquacaoDoc("Eq. 16", "Diferença de densidades relativas das fases líquidas",
                "ΔSG = (SG)_w − (SG)_o",
                [VariavelDoc("ΔSG", "diferença de densidades relativas", _V_ADIM),
                 VariavelDoc("(SG)_w", "densidade relativa da água", _V_ADIM),
                 VariavelDoc("(SG)_o", "densidade relativa do óleo", _V_ADIM)];
                referencia = "Alves & Komesu (2025), Eq. 16",
                validade = "Exige ΔSG > 0: sem diferença de densidade não há separação " *
                           "gravitacional líquido-líquido."),

            EquacaoDoc("Eq. 17", "Espessura máxima da camada de óleo (água em óleo)",
                "(h_o)_max = 0,033 · (t_r)_o · ΔSG · d_m² / µ_o",
                [VariavelDoc("(h_o)_max", "espessura máxima da camada de óleo", _V_MM),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", _V_TR),
                 VariavelDoc("ΔSG", "diferença de densidades relativas", _V_ADIM),
                 VariavelDoc("d_m", "diâmetro da gotícula de água", _V_DM),
                 VariavelDoc("µ_o", "viscosidade dinâmica do óleo", _V_MU)];
                referencia = "Stewart & Arnold (2008), §3.8.3; Alves & Komesu (2025), Eq. 17",
                validade = "Lei de Stokes. O coeficiente 0,033 corresponde ao 1,28×10⁻³ " *
                           "em unidades de campo de Stewart & Arnold, com (t_r) em min, " *
                           "d_m em µm, µ em cP e resultado em mm."),

            EquacaoDoc("Eq. 20", "Espessura máxima da camada de água (óleo em água)",
                "(h_w)_max = 0,033 · ΔSG · (t_r)_w · d_m² / µ_w",
                [VariavelDoc("(h_w)_max", "espessura máxima da camada de água", _V_MM),
                 VariavelDoc("ΔSG", "diferença de densidades relativas", _V_ADIM),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", _V_TR),
                 VariavelDoc("d_m", "diâmetro da gotícula de óleo", _V_DM),
                 VariavelDoc("µ_w", "viscosidade dinâmica da água", _V_MU)];
                referencia = "Stewart & Arnold (2008), §3.8.3; Alves & Komesu (2025), Eq. 20",
                validade = "Mesma lei de Stokes da Eq. 17, com a gotícula de óleo " *
                           "ascendendo na fase aquosa."),

            EquacaoDoc("Eq. 18", "Fração da seção transversal ocupada pela água",
                "A_w/A = 0,5 · [ Q_w·(t_r)_w / ( (t_r)_o·Q_o + (t_r)_w·Q_w ) ]",
                [VariavelDoc("A_w/A", "fração de área da fase aquosa", _V_ADIM),
                 VariavelDoc("Q_o", "vazão volumétrica de óleo", _V_Q),
                 VariavelDoc("Q_w", "vazão volumétrica de água", _V_Q),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", _V_TR),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", _V_TR)];
                referencia = "Alves & Komesu (2025), Eq. 18",
                validade = "O fator 0,5 é o vaso meio cheio: a fase aquosa reparte com o " *
                           "óleo apenas a metade inferior da seção."),

            EquacaoDoc("Fig. 3", "Coeficiente β — altura fracionária da camada de óleo",
                "β = h_o/d = 0,5 − h_w/d,  com  A_seg = R²·[ arccos(1 − h/R) − " *
                "(1 − h/R)·√(2h/R − (h/R)²) ]",
                [VariavelDoc("β", "altura fracionária da camada de óleo", _V_ADIM),
                 VariavelDoc("h_o", "altura da camada de óleo", _V_MM),
                 VariavelDoc("h_w", "altura da camada de água", _V_MM),
                 VariavelDoc("d", "diâmetro interno do vaso", _V_MM),
                 VariavelDoc("R", "raio interno do vaso", _V_MM),
                 VariavelDoc("A_seg", "área do segmento circular ocupado pela água", "mm²")];
                referencia = "Stewart & Arnold (2008), Fig. 3 e Eq. 4.17",
                validade = "A Figura 3 é geometria de segmento circular em vaso meio " *
                           "cheio, resolvida analiticamente por bisseção em vez de lida " *
                           "do gráfico. Domínio A_w/A ∈ [0 ; 0,5]."),

            EquacaoDoc("Eq. 19", "Teto de diâmetro pela decantação de água em óleo",
                "(d_max)_{w/o} = (h_o)_max / β",
                [VariavelDoc("(d_max)_{w/o}", "diâmetro máximo admissível pela fase óleo", _V_MM),
                 VariavelDoc("(h_o)_max", "espessura máxima da camada de óleo", _V_MM),
                 VariavelDoc("β", "altura fracionária da camada de óleo", _V_ADIM)];
                referencia = "Alves & Komesu (2025), Eq. 19",
                validade = "Exige β > 0: sem camada de óleo não há cota a limitar."),

            EquacaoDoc("Eq. 21", "Teto de diâmetro pela decantação de óleo em água",
                "(d_max)_{o/w} = (h_w)_max / β",
                [VariavelDoc("(d_max)_{o/w}", "diâmetro máximo admissível pela fase água", _V_MM),
                 VariavelDoc("(h_w)_max", "espessura máxima da camada de água", _V_MM),
                 VariavelDoc("β", "altura fracionária da camada de óleo", _V_ADIM)];
                referencia = "Alves & Komesu (2025), Eq. 21",
                validade = "Forma publicada, adotada neste dimensionamento. Ver a " *
                           "hipótese 3 da folha 02 e a Eq. 21*."),

            EquacaoDoc("Eq. 21*", "Teto de diâmetro pela decantação de óleo em água — " *
                                  "variante geométrica NÃO ADOTADA",
                "(d_max*)_{o/w} = (h_w)_max / (0,5 − β)",
                [VariavelDoc("(d_max*)_{o/w}", "diâmetro máximo pela cota geométrica da água", _V_MM),
                 VariavelDoc("(h_w)_max", "espessura máxima da camada de água", _V_MM),
                 VariavelDoc("β", "altura fracionária da camada de óleo", _V_ADIM),
                 VariavelDoc("0,5 − β", "altura fracionária da camada de água", _V_ADIM)];
                referencia = "Leitura geométrica da Fig. 3; ver hipótese 3 da folha 02",
                validade = "REGISTRO DOCUMENTAL — não participa da escolha do diâmetro. " *
                           "Omitida quando não há água livre (β = 0,5 exato, denominador " *
                           "nulo)."),

            # ------------------------------------------ bloco C: capacidade de líquido
            EquacaoDoc("Eq. 22", "Capacidade de líquido — produto d²·Leff exigido",
                "d² · L_eff = C · [ (t_r)_o·Q_o + (t_r)_w·Q_w ]",
                [VariavelDoc("d", "diâmetro interno do vaso", _V_MM),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("C", "coeficiente de capacidade de líquido", "mm²·m·h/(m³·min)"),
                 VariavelDoc("(t_r)_o", "tempo de retenção do óleo", _V_TR),
                 VariavelDoc("Q_o", "vazão volumétrica de óleo", _V_Q),
                 VariavelDoc("(t_r)_w", "tempo de retenção da água", _V_TR),
                 VariavelDoc("Q_w", "vazão volumétrica de água", _V_Q)];
                referencia = "Stewart & Arnold (2008), §3.8.4; Alves & Komesu (2025), Eq. 22",
                validade = "Coeficiente C derivado da forma em unidades de campo " *
                           "d[in]²·L_eff[ft] = 1,42·(t_r·Q[BPD]) — ver a hipótese 1 da " *
                           "folha 02."),

            # ------------------------------------------ geometria e seleção
            EquacaoDoc("Eq. 15", "Comprimento entre costuras quando o GÁS governa",
                "L_ss = L_eff + d/1000",
                [VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", _V_MM)];
                referencia = "Stewart & Arnold (2008), §3.8.4; Alves & Komesu (2025), Eq. 15",
                validade = "Folga construtiva do trecho de entrada e do extrator de " *
                           "névoa. Aplicada quando a capacidade de gás é a restrição " *
                           "governante."),

            EquacaoDoc("Eq. 23", "Comprimento entre costuras quando o LÍQUIDO governa",
                "L_ss = (4/3) · L_eff",
                [VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m")];
                referencia = "Stewart & Arnold (2008), §3.8.4; Alves & Komesu (2025), Eq. 23",
                validade = "Vaso preenchido a 50 %. Aplicada quando a capacidade de " *
                           "líquido é a restrição governante."),

            EquacaoDoc("Eq. 24", "Esbeltez do vaso",
                "SR = L_ss / (d/1000)",
                [VariavelDoc("SR", "esbeltez (slenderness ratio)", _V_ADIM),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", _V_MM)];
                referencia = "Stewart & Arnold (2008), §3.8.4; Alves & Komesu (2025), Eq. 24",
                validade = "Banda recomendada 3 ≤ SR ≤ 5. É também o critério de escolha " *
                           "do diâmetro: entre os diâmetros admissíveis da grade, o " *
                           "motor toma o de menor |SR − SR_alvo|."),

            # NÃO é do artigo, e o `numero` diz isso: "Geom." em vez de um "Eq. 25" que
            # mandaria o revisor procurar na fonte uma equação que ela não tem. O volume
            # é cilindro reto sobre Lss, e entra no documento porque é o que a tela
            # mostra — não porque Stewart & Arnold o prescrevam.
            EquacaoDoc("Geom.", "Volume do casco entre costuras",
                "V = π · (d/1000)² / 4 · L_ss",
                [VariavelDoc("V", "volume do casco entre costuras", "m³"),
                 VariavelDoc("d", "diâmetro interno do vaso", _V_MM),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m")];
                referencia = "Geometria do cilindro reto — não consta da fonte",
                validade = "Cilindro reto sobre L_ss, que é a medida costura a costura. " *
                           "NÃO inclui os tampos elípticos 2:1 mostrados na elevação, " *
                           "que somariam cerca de 8,5 %."),
        ],

        # ------------------------------------------------------------- resultados
        # `rotulo` casa com o `label` de `result_fields(::AbstractVesselMethod, r)`, em
        # `src/sizing/constraints.jl`. O valor NÃO está aqui — vem de lá.
        resultados = [
            ResultadoDoc("Diâmetro d", "d", "Eq. 24"),
            ResultadoDoc("Comprimento efetivo Leff", "L_eff", "Eq. 14 / Eq. 22"),
            ResultadoDoc("Comprimento real Lss", "L_ss", "Eq. 15 / Eq. 23"),
            ResultadoDoc("Esbeltez SR", "SR", "Eq. 24"),
            ResultadoDoc("Volume (casco, entre tampos)", "V", "Geom."),
            ResultadoDoc("Restrição governante", "—", "Eq. 14 / Eq. 22"),
            ResultadoDoc("Caso governante", "—", "—"),
            ResultadoDoc("Teto de decantação", "d_max", "Eq. 19 / Eq. 21"),
        ],

        # ----------------------------------------------------------- verificações
        # `campo` casa com o mesmo `label`. O veredito ATENDE/NÃO ATENDE sai do `status`
        # daquele campo, calculado pelo motor — nunca escrito aqui.
        verificacoes = [
            VerificacaoDoc("Esbeltez dentro da banda recomendada",
                           "Esbeltez SR", "3 ≤ SR ≤ 5 (ajustável)", _V_ADIM),
            VerificacaoDoc("Diâmetro sob o teto de decantação líquido-líquido",
                           "Teto de decantação", "d ≤ d_max (Eq. 19 / Eq. 21)", _V_MM),
        ],

        conclusao =
            "O vaso indicado na seção 1 atende simultaneamente à capacidade de gás " *
            "(Eq. 14), à capacidade de líquido (Eq. 22) e ao teto de decantação " *
            "líquido-líquido (Eq. 19 / Eq. 21), com esbeltez dentro da banda recomendada " *
            "por Stewart & Arnold. A restrição governante e o caso de operação que a " *
            "impõe estão identificados na seção 1; as verificações da seção 2 registram " *
            "o atendimento de cada critério. As hipóteses assumidas — em especial as " *
            "divergências em relação ao texto publicado — estão declaradas na folha 02 " *
            "e devem ser lidas junto com este resultado.",
    )
end
