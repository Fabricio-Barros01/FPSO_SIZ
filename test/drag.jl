@testset "iteração do coeficiente de arrasto" begin
    ρl, ρg, dm = 863.0, 17.0, 100.0

    @testset "convergência nos dois regimes da Tabela 1" begin
        # µ_g = 0,012 cP (gás real): regime intermediário, C_D ~ 1,8.
        r = converge_drag(ρl, ρg, dm, 0.012)
        @test r.converged
        @test r.cd ≈ 1.82 rtol = 0.02
        @test 20 < r.re < 35
        @test r.iterations < 200

        # µ_g = 0,6 cP (valor impresso, que é de líquido): quase Stokes, C_D enorme.
        r2 = converge_drag(ρl, ρg, dm, 0.6)
        @test r2.converged
        @test r2.cd > 500
        @test r2.re < 0.1
    end

    @testset "o ponto fixo satisfaz as Eq. 9–11" begin
        for mu in (0.012, 0.05, 0.6)
            r = converge_drag(ρl, ρg, dm, mu)
            @test r.converged
            @test terminal_velocity(ρl, ρg, dm, r.cd) ≈ r.vt rtol = 1e-8
            @test reynolds(ρg, dm, r.vt, mu) ≈ r.re rtol = 1e-8
            @test drag_coefficient(r.re) ≈ r.cd rtol = 1e-6
        end
    end

    @testset "a relaxação não muda o ponto fixo, só o caminho até ele" begin
        # A substituição direta do artigo (ω = 1) converge, e monotonicamente.
        # A sub-relaxação existe por robustez, não por necessidade — então o
        # resultado tem de ser o mesmo, apenas com mais iterações.
        for mu in (0.012, 0.6)
            direta  = converge_drag(ρl, ρg, dm, mu; relax = 1.0, maxiter = 2000)
            amortec = converge_drag(ρl, ρg, dm, mu; relax = 0.5, maxiter = 2000)
            @test direta.converged && amortec.converged
            @test direta.cd ≈ amortec.cd rtol = 1e-6
            @test amortec.iterations > direta.iterations
        end

        # Monotonicidade da substituição direta: a sequência sobe sem oscilar.
        traj = Float64[]
        cd = 0.34
        for _ in 1:12
            vt = terminal_velocity(ρl, ρg, dm, cd)
            cd = drag_coefficient(reynolds(ρg, dm, vt, 0.6))
            push!(traj, cd)
        end
        @test issorted(traj)
    end

    @testset "não-convergência vira diagnóstico, não número errado" begin
        r = converge_drag(ρl, ρg, dm, 0.012; maxiter = 3)
        @test !r.converged
        @test r.iterations == 3
    end

    @testset "não itera indefinidamente" begin
        r = converge_drag(ρl, ρg, dm, 0.012; maxiter = 500)
        @test r.iterations <= 500
    end

    @testset "Souders & Brown (Eq. 13)" begin
        r = converge_drag(ρl, ρg, dm, 0.012)
        K = souders_brown(ρl, ρg, dm, r.cd)
        @test K ≈ sqrt((ρg / (ρl - ρg)) * (r.cd / dm))
        @test K > 0
        # K cresce com C_D e decresce com o diâmetro da gotícula
        @test souders_brown(ρl, ρg, dm, 2 * r.cd) > K
        @test souders_brown(ρl, ρg, 2 * dm, r.cd) < K
    end
end
