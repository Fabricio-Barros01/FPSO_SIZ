using Test
using TOML
using FPSOSiz

@testset "FPSOSiz" begin
    # Ordem deliberada: unidades e geometria primeiro (se estas quebram, tudo o mais
    # é ruído), depois a física, depois o caso-ouro, depois o motor de envelope.
    @testset "unidades"      begin include("units.jl")        end
    @testset "β (Figura 3)"  begin include("beta.jl")         end
    @testset "arrasto"       begin include("drag.jl")         end
    @testset "casos"         begin include("cases.jl")        end
    @testset "caso-ouro 3φ"  begin include("golden_alves_komesu.jl") end
    @testset "caso-ouro 2φ"  begin include("golden_knockout.jl")     end
    @testset "caso-ouro bomba"    begin include("golden_moran.jl")  end
    @testset "caso-ouro trocador" begin include("golden_saari.jl")  end
    @testset "tratador"      begin include("treater.jl")      end
    @testset "envelope"      begin include("envelope.jl")     end
    @testset "registro"      begin include("registry.jl")     end
    @testset "arquitetura"   begin include("architecture.jl") end
end
