"""
Bloco de capacidade de gás — compartilhado pelos vasos da família Stewart & Arnold.

A equação é **literalmente a mesma** no separador trifásico e no vaso bifásico:

    d·Leff = 34,5 · [T·Z·Qg/P] · K,   K = [(ρg/(ρl−ρg))·(C_D/dm)]^0,5

Ela aparece como Eq. 14 em Alves & Komesu (2025) e como Eq. 3.8b em Stewart & Arnold
(2008) — o artigo reproduz o livro, coeficiente por coeficiente. Duplicá-la em dois
arquivos criaria duas versões de uma física só, que é o que este projeto evita em toda
parte: a formatação PT-BR existe uma vez, o memorial existe uma vez, e o bloco A
também.

O que muda entre os dois **não é o cálculo, é a citação**: cada método cita a fonte que
o usuário vai conferir. Um memorial de vaso bifásico dizendo "Eq. 14" mandaria o leitor
a um artigo sobre separadores trifásicos. Daí `eqs`, e só isso, ser parametrizado.
"""

"Numeração do bloco de gás em Alves & Komesu (2025) — o separador trifásico."
const EQS_GAS_ALVES = (cd = "Eq. 9–11", vt = "Eq. 11", re = "Eq. 10",
                       ksb = "Eq. 13", dleff = "Eq. 14")

"Numeração em Stewart & Arnold (2008) — o vaso bifásico. Re é texto corrido no livro."
const EQS_GAS_LIVRO = (cd = "Eq. 3.6", vt = "Eq. 3.7b", re = "S&A §3.7",
                       ksb = "Eq. 3.1", dleff = "Eq. 3.8b")

"""
    gas_capacity_dleff(s, dm_gas, coef, cd0, relax, trace; eqs) -> (ok, d_leff, msg)

O produto `d·Leff` [mm·m] exigido pela capacidade de gás, com o rastro de cálculo
escrito em `trace`. `coef` é o 34,5 da forma SI, lido do TOML **do método** — nenhuma
chave de configuração é citada aqui, para que os dois vasos possam nomeá-la como
quiserem nos seus arquivos.

Não lança: `ok = false` traz a mensagem diagnóstica, como todo o resto do core.
"""
function gas_capacity_dleff(s::StreamState, dm_gas::Real, coef::Real,
                            cd0::Real, relax::Real, trace::CalcTrace;
                            eqs = EQS_GAS_ALVES)
    fu = field_units(s)

    drag = converge_drag(fu.rho_o, fu.rho_g, dm_gas, fu.mu_g; cd0, relax)
    trace!(trace, :gas, eqs.cd, "C_D",
           "iteração sub-relaxada de 24/Re + 3/√Re + 0,34", drag.cd, "–")
    trace!(trace, :gas, eqs.vt, "V_t",
           "0,0036·[((ρl−ρg)/ρg)·(dm/C_D)]^0,5", drag.vt, "m/s")
    trace!(trace, :gas, eqs.re, "Re", "0,001·ρg·dm·V_t/µg", drag.re, "–")

    drag.converged || return (false, NaN,
        "O coeficiente de arrasto não convergiu em $(drag.iterations) iterações. " *
        "Verifique a viscosidade do gás (µ_g = $(round(fu.mu_g, digits = 4)) cP).")

    K = souders_brown(fu.rho_o, fu.rho_g, dm_gas, drag.cd)
    trace!(trace, :gas, eqs.ksb, "K", "[(ρg/(ρl−ρg))·(C_D/dm)]^0,5", K, "–")

    d_leff_gas = coef * (fu.t_k * fu.z * fu.q_g / fu.p_kpa) * K
    trace!(trace, :gas, eqs.dleff, "d·Leff", "34,5·[T·Z·Qg/P]·K", d_leff_gas, "mm·m")

    return (true, d_leff_gas, "")
end
