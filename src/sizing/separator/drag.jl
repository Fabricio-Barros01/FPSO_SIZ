"""
Coeficiente de arrasto e velocidade terminal — Eq. (9), (10) e (11).

O artigo instrui: "inicialmente adota-se `C_D = 0,34` e realiza-se um processo de
tentativa e erro (através das Eq. 9, 10 e 11) até se encontrar o valor do coeficiente".

A substituição direta converge — e **monotonicamente**, não por oscilação: para o
caso-ouro com `µ_g = 0,6 cP` a sequência é 0,34 → 22,5 → 166 → 443 → 719 → … → 1154.
São 22 iterações com `µ_g = 0,012 cP` e 36 com `0,6 cP`. Mantemos ainda assim a opção
de sub-relaxação (`x ← x + ω(f(x) − x)`), com `ω = 0,5` por padrão: o motor de
envelope avalia dezenas de combinações de propriedades que ninguém inspecionou uma a
uma, e o custo do amortecimento é irrisório (55 iterações em vez de 22). `converged`
é devolvido junto com o resultado justamente para que uma combinação patológica vire
diagnóstico na tela em vez de um número silenciosamente errado.

O ponto fixo importa: para o caso-ouro, `C_D` converge para ~1,82 com `µ_g = 0,012 cP`
e ~1154 com o `µ_g = 0,6 cP` impresso na Tabela 1 do artigo (que é viscosidade de
líquido — ver a nota em `stewart_arnold.jl`). A Tabela 2 do artigo corresponde a uma
iteração **interrompida antes de convergir**: reproduzi-la exige `C_D ≈ 1,25`, valor
intermediário entre a 2ª e a 3ª iteração.
"""

"""
    terminal_velocity(rho_l, rho_g, dm, cd) -> V_t [m/s]

Eq. (11): `V_t = 0,0036·[((ρl − ρg)/ρg)·(dm/C_D)]^{1/2}`.
Densidades em kg/m³, `dm` em µm.
"""
terminal_velocity(rho_l, rho_g, dm, cd) =
    0.0036 * sqrt(((rho_l - rho_g) / rho_g) * (dm / cd))

"""
    reynolds(rho_g, dm, vt, mu_g) -> Re

Eq. (10): `Re = 0,001·ρg·dm·V_t/µg`. `dm` em µm, `V_t` em m/s, `µ_g` em cP.
"""
reynolds(rho_g, dm, vt, mu_g) = 0.001 * rho_g * dm * vt / mu_g

"""
    drag_coefficient(re) -> C_D

Eq. (9): `C_D = 24/Re + 3/√Re + 0,34`, válida fora do regime laminar puro.
"""
drag_coefficient(re) = 24.0 / re + 3.0 / sqrt(re) + 0.34

"""
    converge_drag(rho_l, rho_g, dm, mu_g; cd0, relax, tol, maxiter)
        -> (cd, vt, re, iterations, converged)

Resolve o sistema Eq. (9)–(11) por substituição a partir de `cd0 = 0,34`, como
prescreve Stewart & Arnold. `relax = 1` é a substituição direta do artigo; o padrão
`0,5` amortece, custando mais iterações em troca de robustez.

Devolve também `converged`, para que o chamador possa registrar a não-convergência no
resultado em vez de propagar um número silenciosamente errado.
"""
function converge_drag(rho_l::Real, rho_g::Real, dm::Real, mu_g::Real;
                       cd0::Real = 0.34, relax::Real = 0.5,
                       tol::Real = 1e-10, maxiter::Int = 500)
    cd = float(cd0)
    vt = re = 0.0
    converged = false
    iters = 0
    for i in 1:maxiter
        iters = i
        vt = terminal_velocity(rho_l, rho_g, dm, cd)
        re = reynolds(rho_g, dm, vt, mu_g)
        re <= 0 && break
        cd_new = drag_coefficient(re)
        cd_next = cd + relax * (cd_new - cd)
        if abs(cd_next - cd) <= tol * max(abs(cd), 1.0)
            cd = cd_next
            vt = terminal_velocity(rho_l, rho_g, dm, cd)
            re = reynolds(rho_g, dm, vt, mu_g)
            converged = true
            break
        end
        cd = cd_next
    end
    return (; cd, vt, re, iterations = iters, converged)
end

"""
    souders_brown(rho_l, rho_g, dm, cd) -> K

Eq. (13): `K = [(ρg/(ρl − ρg))·(C_D/dm)]^{1/2}`. `dm` em µm.
"""
souders_brown(rho_l, rho_g, dm, cd) =
    sqrt((rho_g / (rho_l - rho_g)) * (cd / dm))
