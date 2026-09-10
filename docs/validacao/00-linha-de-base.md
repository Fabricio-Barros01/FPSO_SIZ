# Passo 0 — Linha de base da suíte de testes

Retrato tirado **antes** de qualquer alteração da fase de validação física, para que
toda mudança posterior tenha contra o que ser medida.

- **Commit:** `addf658` ("Equips added"), branch `main`
- **Data:** 2026-09-09
- **Julia:** 1.12.6
- **Comando:** `julia --project=. -e 'using Pkg; Pkg.test()'`

## Resultado global

| | |
|---|---|
| Passam | **1916** |
| Falham | **0** |
| Com erro | **0** |
| Marcados `@test_broken` / `@test_skip` | **0** |
| Tempo do `@testset` | **22,2 s** |
| Tempo de parede (com precompilação) | 25,7 s |
| Código de saída | `0` |

Segunda medição, com `verbose = true` para a quebra por arquivo e sem o overhead de
`Pkg.test()` (ambiente temporário, resolução de manifesto): **18,0 s**. A diferença de
~4 s entre as duas é montagem de ambiente, não teste.

## Quebra por testset

Ordem de [test/runtests.jl](../../test/runtests.jl), que é deliberada: unidades e
geometria primeiro, depois a física, depois os casos-ouro, depois o motor.

| # | Testset | Arquivo | Passam | Tempo |
|---|---|---|---|---|
| 1 | `unidades` | [test/units.jl](../../test/units.jl) | 36 | 1,8 s |
| 2 | `β (Figura 3)` | [test/beta.jl](../../test/beta.jl) | 18 | 0,6 s |
| 3 | `arrasto` | [test/drag.jl](../../test/drag.jl) | 33 | 0,5 s |
| 4 | `casos` | [test/cases.jl](../../test/cases.jl) | 85 | 4,4 s |
| 5 | `caso-ouro 3φ` | [test/golden_alves_komesu.jl](../../test/golden_alves_komesu.jl) | 77 | 0,5 s |
| 6 | `caso-ouro 2φ` | [test/golden_knockout.jl](../../test/golden_knockout.jl) | 68 | 0,8 s |
| 7 | `caso-ouro bomba` | [test/golden_moran.jl](../../test/golden_moran.jl) | 71 | 1,5 s |
| 8 | `caso-ouro trocador` | [test/golden_saari.jl](../../test/golden_saari.jl) | 193 | 2,1 s |
| 9 | `tratador` | [test/treater.jl](../../test/treater.jl) | 120 | 0,7 s |
| 10 | `envelope` | [test/envelope.jl](../../test/envelope.jl) | 300 | 3,1 s |
| 11 | `registro` | [test/registry.jl](../../test/registry.jl) | 90 | 0,8 s |
| 12 | `arquitetura` | [test/architecture.jl](../../test/architecture.jl) | 825 | 1,1 s |
| | **Total** | | **1916** | **18,0 s** |

Os 825 de `arquitetura` são em boa parte varreduras declarativas (todo método declara
todo hook do contrato, todo `ParameterSpec` tem rótulo e faixa, nenhum arquivo de `src/`
importa GUI). Contam como testes e é correto que contem, mas o peso de física da suíte
está nos testsets 1–9, que somam **701**.

## Cobertura por método, na linha de base

| Método | Caso-ouro publicado | Testes de física | Observação |
|---|---|---|---|
| Separador trifásico | **sim** — Tabela 3 de Alves & Komesu (2025), 6 linhas | 77 + 33 (arrasto) + 18 (β) | o mais forte dos cinco |
| Vaso knockout 2φ | **sim** — Tabela 3.4 de Stewart & Arnold, 7 linhas | 68 | fecha a 2 % |
| Bomba centrífuga | **parcial** — Antoine (Tab. 3) e nomograma (Fig. 3) | 71 | sem caso de linha inteira |
| Trocador c&t | **parcial** — Exemplo 4.1 (tubo duplo, `U` dado) | 193 | sem o laço de `U` fechado |
| Tratador eletrostático | **não** | 120 | só coerência interna de coeficientes |

## Testes ausentes — a agenda dos passos 1–5

O que a linha de base **não** cobre. Cada item é uma lacuna a fechar ou a declarar no
relatório do método correspondente.

1. **Faixa de validade das correlações.** O único método com teste de faixa é a bomba, e
   só para o regime de atrito (`@testset "regimes de escoamento"`, que verifica que a
   transição é marcada `confiavel = false`). Não há **nenhum** teste que verifique o que
   o programa *faz* com esse flag, nem faixa alguma testada em Dittus-Boelter, no
   coeficiente de arrasto, em Stokes ou nos coeficientes de Bell-Delaware.
2. **Coerência dimensional derivada.** Os coeficientes dimensionais são conferidos
   contra o valor publicado na fonte (e, nos cinco casos de errata, contra a própria
   fonte se contradizendo). O que não existe é o teste que os deriva **das unidades**,
   independentemente do número impresso. `Units.liquid_capacity_coefficient` é a única
   exceção, e é o modelo a seguir.
3. **Caso-ouro do trocador com o laço de `U` fechado.** Saari não publica um; o Exemplo
   4.1 é tubo duplo com `U` dado. A conferência cruzada LMTD ↔ ε-NTU cobre o balanço,
   não o coeficiente.
4. **Caso-ouro do tratador eletrostático.** Não existe, e a fonte que o fecharia
   (*Emulsions and Oil Treating*) não está em `References/`.

## Reprodução

```
cd test
julia --project=.. -e '
using Test, TOML, FPSOSiz
@testset verbose = true "FPSOSiz" begin
    @testset "unidades"      begin include("units.jl")        end
    # … as doze linhas de test/runtests.jl
end'
```

`include` resolve caminho relativo ao **arquivo** que inclui, não ao diretório de
trabalho: rodar de `test/` é o que faz os doze `include` fecharem.
