"""
A camada documental do vaso de knockout bifásico — [`memorial_spec`](@ref) para
[`StewartArnoldTwoPhase`](@ref).

**A fonte é o livro, e a numeração também.** O trifásico cita Alves & Komesu porque é o
artigo que ele reproduz; este cita Stewart & Arnold (2008) cap. 3 diretamente. O bloco de
capacidade de gás é *literalmente o mesmo código* nos dois — `gas_capacity_dleff` —, e o
que muda é só a citação: um memorial de knockout dizendo "Eq. 14" mandaria o leitor
conferir a conta num artigo sobre separadores trifásicos.

Três diferenças documentais em relação ao separador, e as três são do equipamento:

1. **não há bloco B.** Sem duas fases líquidas não há gotícula de água a decantar no óleo
   nem de óleo a subir na água, então nada impõe teto de diâmetro. Não há Eq. 16–21, não
   há `d_max` calculado, e **não há verificação de teto** — declará-la faria a folha 04
   imprimir uma conferência que este vaso não faz;
2. **o `Lss` é o MAIOR das duas regras** (§3.8.4), e não o do bloco que governa. Cita-se
   a **seção**, que é onde a regra do maior está escrita, e não as duas equações: a
   coluna de equação do memorial `.txt` tem 10 caracteres e `"Eq. 3.10b / 3.11"` tem 16.
   As duas equações aparecem na referência da folha de fórmulas. Ver `lss_trace` em
   `two_phase.jl`;
3. **a banda de esbeltez é 3–4**, não 3–5 (§3.8.5).
"""

function memorial_spec(::StewartArnoldTwoPhase)
    MemorialSpec(
        sigla       = "VKO",
        equipamento = "VASO KNOCKOUT / FLASH",
        titulo      = "DIMENSIONAMENTO DE VASO KNOCKOUT / FLASH",

        premissas = [
            PremissaDoc("P1",
                "Vaso cilíndrico horizontal operando preenchido pela metade de líquido; " *
                "a metade superior é o espaço de gás.",
                "Stewart & Arnold (2008), §3.8.1"),
            PremissaDoc("P2",
                "Duas fases apenas — gás e uma fase líquida única (condensado ou óleo). " *
                "Não há interface líquido-líquido a dimensionar.",
                "Stewart & Arnold (2008), §3.8"),
            PremissaDoc("P3",
                "Critério de gotícula: a gota de líquido arrastada deve decantar da " *
                "corrente gasosa antes de alcançar o extrator de névoa.",
                "Stewart & Arnold (2008), §3.8.2"),
            PremissaDoc("P4",
                "Tempo de retenção do líquido fixado por projeto, conforme o grau API e " *
                "a tendência a espuma da corrente.",
                "Stewart & Arnold (2008), Tabela 3.2"),
            PremissaDoc("P5",
                "Comprimento entre costuras pelo MAIOR entre as duas folgas construtivas " *
                "— distribuição na entrada com extrator de névoa, e nível de líquido.",
                "Stewart & Arnold (2008), §3.8.4"),
            PremissaDoc("P6",
                "Esbeltez recomendada 3 ≤ SR ≤ 4, banda mais estreita que a do vaso " *
                "trifásico.",
                "Stewart & Arnold (2008), §3.8.5"),
        ],

        hipoteses = [
            "Fase líquida na posição do óleo. A estrutura de corrente do programa tem " *
            "três posições (óleo, água, gás) porque foi desenhada para o separador " *
            "trifásico; aqui a fase líquida única ocupa a posição do óleo e a da água não " *
            "é informada. Os rótulos do formulário são reescritos para dizer 'líquido' — " *
            "num knockout de linha de gás o líquido é condensado.",

            "A viscosidade do líquido NÃO é pedida, porque não entra em conta nenhuma " *
            "deste vaso: o bloco de gás usa a densidade do líquido e a viscosidade do " *
            "GÁS (no Reynolds), e o bloco de líquido usa só a vazão. Pedir um dado que " *
            "não é usado faria o usuário acreditar ter informado algo.",

            "Erratum da fonte, encontrado ao reproduzi-la. O Exemplo 3.2 do livro imprime " *
            "d·Leff = 55,04 in·ft, mas a Tabela 3.4 do próprio exemplo só fecha com " *
            "39,85 — que é o que a Eq. 3.8a dá com os dados dados. As sete linhas da " *
            "tabela conferem com 39,85 a menos de 6 %, e com 55,04 erram 38 %. O texto " *
            "está errado e a tabela certa; segue-se a tabela.",

            "Coeficiente da Eq. 3.9b conforme IMPRESSO no livro (42441). A forma em " *
            "unidades de campo convertida para SI dá 42406,6 — 0,08 % de diferença, que " *
            "não caracteriza inconsistência. Segue-se a fonte; ao contrário do separador " *
            "trifásico, aqui não há o que resolver.",
        ],

        equacoes = [
            EquacaoDoc("Eq. 3.6", "Coeficiente de arrasto da gotícula de líquido no gás",
                "C_D = 24/Re + 3/√Re + 0,34",
                [VariavelDoc("C_D", "coeficiente de arrasto", "–"),
                 VariavelDoc("Re", "número de Reynolds da gotícula", "–")];
                referencia = "Stewart & Arnold (2008), Eq. 3.6",
                validade = "Resolvida junto com a Eq. 3.7b e o Reynolds de §3.7 por " *
                           "substituição sucessiva a partir de C_D = 0,34, com " *
                           "sub-relaxação de 0,5."),

            EquacaoDoc("Eq. 3.7b", "Velocidade terminal de decantação da gotícula",
                "V_t = 0,0036 · [ ((ρ_l − ρ_g)/ρ_g) · (d_m/C_D) ]^(1/2)",
                [VariavelDoc("V_t", "velocidade terminal da gotícula", "m/s"),
                 VariavelDoc("ρ_l", "massa específica da fase líquida", "kg/m³"),
                 VariavelDoc("ρ_g", "massa específica do gás", "kg/m³"),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", "µm"),
                 VariavelDoc("C_D", "coeficiente de arrasto", "–")];
                referencia = "Stewart & Arnold (2008), Eq. 3.7b",
                validade = "Coeficiente 0,0036 embute a conversão de d_m em µm para o " *
                           "resultado em m/s."),

            EquacaoDoc("S&A §3.7", "Número de Reynolds da gotícula",
                "Re = 0,001 · ρ_g · d_m · V_t / µ_g",
                [VariavelDoc("Re", "número de Reynolds da gotícula", "–"),
                 VariavelDoc("ρ_g", "massa específica do gás", "kg/m³"),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", "µm"),
                 VariavelDoc("V_t", "velocidade terminal da gotícula", "m/s"),
                 VariavelDoc("µ_g", "viscosidade dinâmica do gás", "cP")];
                referencia = "Stewart & Arnold (2008), §3.7 — texto corrido, sem número",
                validade = "Coeficiente 0,001 embute d_m em µm e µ_g em cP."),

            EquacaoDoc("Eq. 3.1", "Constante de Souders–Brown",
                "K = [ (ρ_g/(ρ_l − ρ_g)) · (C_D/d_m) ]^(1/2)",
                [VariavelDoc("K", "constante de Souders–Brown", "–"),
                 VariavelDoc("ρ_g", "massa específica do gás", "kg/m³"),
                 VariavelDoc("ρ_l", "massa específica da fase líquida", "kg/m³"),
                 VariavelDoc("C_D", "coeficiente de arrasto convergido", "–"),
                 VariavelDoc("d_m", "diâmetro da gotícula de líquido no gás", "µm")];
                referencia = "Stewart & Arnold (2008), Eq. 3.1",
                validade = ""),

            EquacaoDoc("Eq. 3.8b", "Capacidade de gás — produto d·Leff exigido",
                "d · L_eff = 34,5 · [ (T · Z · Q_g) / P ] · K",
                [VariavelDoc("d", "diâmetro interno do vaso", "mm"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("T", "temperatura de operação", "K"),
                 VariavelDoc("Z", "fator de compressibilidade do gás", "–"),
                 VariavelDoc("Q_g", "vazão volumétrica de gás", "m³/h"),
                 VariavelDoc("P", "pressão de operação", "kPa"),
                 VariavelDoc("K", "constante de Souders–Brown", "–")];
                referencia = "Stewart & Arnold (2008), Eq. 3.8b",
                validade = "Forma em SI: o coeficiente 34,5 corresponde a d em mm, " *
                           "L_eff em m, T em K, Q_g em m³/h e P em kPa. É a MESMA " *
                           "equação que o separador trifásico resolve como Eq. 14."),

            EquacaoDoc("Eq. 3.9b", "Capacidade de líquido — produto d²·Leff exigido",
                "d² · L_eff = 42441 · t_r · Q_l",
                [VariavelDoc("d", "diâmetro interno do vaso", "mm"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("t_r", "tempo de retenção do líquido", "min"),
                 VariavelDoc("Q_l", "vazão volumétrica de líquido", "m³/h")];
                referencia = "Stewart & Arnold (2008), Eq. 3.9b",
                validade = "Uma fase líquida só. Coeficiente conforme impresso no livro " *
                           "— ver a hipótese H4 da folha 02."),

            EquacaoDoc("§3.8.4", "Comprimento entre costuras — o MAIOR das duas",
                "L_ss = max( L_eff + d/1000 ; (4/3) · L_eff )",
                [VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("L_eff", "comprimento efetivo de separação", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm")];
                referencia = "Stewart & Arnold (2008), Eq. 3.10b e 3.11, §3.8.4",
                validade = "São DUAS folgas construtivas independentes — distribuição na " *
                           "entrada com extrator de névoa, e nível de líquido — e o vaso " *
                           "tem de atender às duas. Por isso a maior, e não a do bloco " *
                           "que governa o L_eff."),

            EquacaoDoc("§3.8.5", "Esbeltez do vaso",
                "SR = L_ss / (d/1000)",
                [VariavelDoc("SR", "esbeltez (slenderness ratio)", "–"),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm")];
                referencia = "Stewart & Arnold (2008), §3.8.5",
                validade = "Banda recomendada 3 ≤ SR ≤ 4 para vaso bifásico — mais " *
                           "estreita que a do trifásico. É também o critério de escolha " *
                           "do diâmetro, entre os admissíveis da grade."),

            EquacaoDoc("Geom.", "Volume do casco entre costuras",
                "V = π · (d/1000)² / 4 · L_ss",
                [VariavelDoc("V", "volume do casco entre costuras", "m³"),
                 VariavelDoc("d", "diâmetro interno do vaso", "mm"),
                 VariavelDoc("L_ss", "comprimento entre costuras", "m")];
                referencia = "Geometria do cilindro reto — não consta da fonte",
                validade = "Cilindro reto sobre L_ss. NÃO inclui os tampos elípticos 2:1 " *
                           "mostrados na elevação, que somariam cerca de 8,5 %."),
        ],

        # Sem "Teto de decantação": este vaso não tem um, e a linha sairia em travessão
        # em todo documento emitido.
        resultados = [
            ResultadoDoc("Diâmetro d", "d", "§3.8.5"),
            ResultadoDoc("Comprimento efetivo Leff", "L_eff", "Eq. 3.8b / Eq. 3.9b"),
            ResultadoDoc("Comprimento real Lss", "L_ss", "§3.8.4"),
            ResultadoDoc("Esbeltez SR", "SR", "§3.8.5"),
            ResultadoDoc("Volume (casco, entre tampos)", "V", "Geom."),
            ResultadoDoc("Restrição governante", "—", "Eq. 3.8b / Eq. 3.9b"),
            ResultadoDoc("Caso governante", "—", "—"),
        ],

        # UMA verificação, e não duas: sem bloco B não há teto de decantação a conferir.
        # Declará-la faria a folha 04 registrar uma conferência que este vaso não faz.
        verificacoes = [
            VerificacaoDoc("Esbeltez dentro da banda recomendada",
                           "Esbeltez SR", "3 ≤ SR ≤ 4 (ajustável)", "–"),
        ],

        conclusao =
            "O vaso indicado na seção 1 atende simultaneamente à capacidade de gás " *
            "(Eq. 3.8b) e à capacidade de líquido (Eq. 3.9b), com comprimento entre " *
            "costuras pelo maior das duas folgas construtivas de §3.8.4 e esbeltez dentro " *
            "da banda de §3.8.5. Não há teto de decantação a verificar: sem segunda fase " *
            "líquida, nada limita o diâmetro por cima. A restrição governante e o caso de " *
            "operação que a impõe estão identificados na seção 1. As hipóteses assumidas " *
            "— em especial o erratum do Exemplo 3.2 — estão declaradas na folha 02 e " *
            "devem ser lidas junto com este resultado.",
    )
end
