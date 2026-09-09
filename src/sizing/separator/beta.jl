"""
Coeficiente β — Figura 3 de Stewart & Arnold (2008), reproduzida analiticamente.

**β é geometria pura, não precisa ser digitalizado.** A Figura 3 relaciona a fração da
seção transversal ocupada pela água (`Aw/A`) com a altura fracionária da camada de
óleo (`β = h_o/d`), para um vaso cilíndrico horizontal **preenchido pela metade**.
Lendo a figura com atenção: o eixo vertical é **invertido** (0,0 no topo, 0,5 na base)
e a curva vai de `(Aw/A = 0 , β = 0,5)` a `(Aw/A = 0,5 , β = 0)`.

Isso é exatamente o que a geometria manda:

* se não há água (`Aw/A = 0`), o óleo ocupa toda a metade inferior → `h_o = d/2` → `β = 0,5`;
* se a água ocupa toda a metade inferior (`Aw/A = 0,5`), não sobra óleo → `β = 0`.

Como o vaso está meio cheio, `h_o + h_w = d/2`, então

    β = h_o/d = 0,5 − h_w/d

e `h_w` é a altura do segmento circular cuja área vale `(Aw/A)·πR²`. A área do segmento
de altura `h` num círculo de raio `R` é

    A_seg = R²·[ acos(1 − h/R) − (1 − h/R)·√(2h/R − (h/R)²) ]

Resolvemos para `h` por bisseção. O resultado casa com a Figura 3 nos pontos de
controle e nos intermediários (ver `test/beta.jl`): `Aw/A = 0,1 → β ≈ 0,344`;
`0,25 → β ≈ 0,202`; `0,4131 → β ≈ 0,0685`.

Vantagem sobre digitalizar a curva: exato, sem erro de leitura, e derivável — o que
importa quando o motor de envelope avalia β dezenas de milhares de vezes.
"""

"Área do segmento circular de altura relativa `u = h/R`, normalizada por `R²`."
function _segment_area(u::Float64)
    u <= 0 && return 0.0
    u >= 2 && return π
    c = 1.0 - u
    return acos(clamp(c, -1.0, 1.0)) - c * sqrt(max(2u - u^2, 0.0))
end

"""
    segment_height_fraction(a) -> h/d

Altura fracionária do segmento circular inferior que ocupa a fração `a` da **seção
inteira**, para `a` ∈ [0, 1]. Truncada nos extremos físicos fora desse domínio.

É a Eq. (4.17) de Stewart & Arnold §4.9.6 — lá escrita como uma relação a resolver "por
tentativa e erro", com o arco-cosseno em graus (`1/180`) no lugar do `1/π`. Aqui é
bisseção sobre a mesma equação, que é exata e não depende de ler uma figura.

Existe separada de [`beta_coefficient`](@ref) porque a relação área↔altura não é do vaso
meio cheio: é do círculo. O separador trifásico a usa com `a ≤ 0,5` porque só a metade
inferior tem líquido; um tratador **cheio de líquido** a usa com `a` até 1.
"""
function segment_height_fraction(a::Real)
    f = float(a)
    f <= 0.0 && return 0.0
    f >= 1.0 && return 1.0

    target = f * π                      # A_seg/R² desejada
    lo, hi = 0.0, 2.0                   # u = h/R ∈ [0,2] (seção inteira)
    for _ in 1:80                       # bisseção: 80 passos ⇒ ~1e-24 em u
        u = 0.5 * (lo + hi)
        _segment_area(u) < target ? (lo = u) : (hi = u)
    end
    return 0.5 * (lo + hi) / 2.0        # h/d = u/2
end

"""
    beta_coefficient(aw_over_a) -> β

Coeficiente β da Figura 3, para `aw_over_a` ∈ [0, 0.5]. Fora desse domínio o valor é
truncado nos extremos físicos (β = 0,5 sem água; β = 0 com a metade inferior toda de
água).

`β = 0,5 − h_w/d` porque o vaso está meio cheio: o que sobra para o óleo é a metade
inferior menos a camada de água. A altura da água é geometria de círculo, e vem de
[`segment_height_fraction`](@ref).
"""
function beta_coefficient(aw_over_a::Real)
    f = float(aw_over_a)
    # Os dois extremos saem EXATOS, e não pela bisseção: `0,5 − h(0,5)` devolve 1,1e-16
    # em vez de zero, e um β de 1e-16 é a diferença entre "sem óleo" e "com uma camada
    # de óleo de espessura nula, dividindo `(h_o)max` por ela" — que é `Inf` no teto.
    f <= 0.0 && return 0.5
    f >= 0.5 && return 0.0
    return 0.5 - segment_height_fraction(f)
end

"""
    water_area_fraction(q_o, q_w, tr_o, tr_w) -> Aw/A

Eq. (18): `Aw/A = 0,5 · Qw·(tr)w / ((tr)o·Qo + (tr)w·Qw)`.

Vazões em m³/h e tempos de retenção em min (as unidades se cancelam; o que importa é
serem consistentes entre si).
"""
function water_area_fraction(q_o::Real, q_w::Real, tr_o::Real, tr_w::Real)
    denom = tr_o * q_o + tr_w * q_w
    denom <= 0 && return 0.0
    return 0.5 * (q_w * tr_w) / denom
end
