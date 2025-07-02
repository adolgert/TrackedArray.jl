using ReTest
using TrackedArray

@testset "Interface: Construction from minimal specification" begin
    using TrackedArray.ThirdParty

@tracked_struct Entity begin
    height::Float64
    cars::Int
end

@tracked_struct Particle begin
    velocity::Tuple{Float64,Float64,Float64}
    color::Int
end


@tracked_state Physical begin
    entities::ObservedVector{Entity}
    particles::ObservedVector{Particle}

    params::Dict{Symbol,Float64}
    time_step::Float64
end

function Physical(; entitiescnt=80, particlescnt=100)
    Physical(TrackedVector{Entity})
end

end
