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
    beta_coefficient(aw_over_a) -> β

Coeficiente β da Figura 3, para `aw_over_a` ∈ [0, 0.5]. Fora desse domínio o valor é
truncado nos extremos físicos (β = 0,5 sem água; β = 0 com a metade inferior toda de
água).
"""
function beta_coefficient(aw_over_a::Real)
    f = float(aw_over_a)
    f <= 0.0 && return 0.5
    f >= 0.5 && return 0.0

    target = f * π                      # A_seg/R² desejada
    lo, hi = 0.0, 1.0                   # u = h_w/R ∈ [0,1] (meia seção)
    for _ in 1:80                       # bisseção: 80 passos ⇒ ~1e-24 em u
        u = 0.5 * (lo + hi)
        _segment_area(u) < target ? (lo = u) : (hi = u)
    end
    u = 0.5 * (lo + hi)
    return 0.5 - u / 2.0                # β = 0,5 − h_w/d,  h_w/d = u/2
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
