using TrackedArray
using Retest


@testset "External:: Construction from minimal specification" begin
    using TrackedArray.External

    mutable struct Person{T}
        health::Float64
        age::Float64
        _track::T
        Person() = new(0.0, 0.0)
    end
    struct PersonState{P,T}
        people::Vector{Person{T}}
        children::Vector{Int}
        _track::P
    end
    mutable struct Car
        horn::Float64
    end
    struct MyState <: PhysicalState
        population::Vector{PersonState}
        cars::Dict{String,Car}
        params::Dict{Symbol,Float64}
        MyState(n) = new([Person() for _ in 1:n], Dict{Symbol,Float64}())
    end

    protocol = tracking_protocol(MyState,
        [:people]
    )

    # The `internal_state` would be held inside the simualation so
    # the user doesn't see it.
    tracker, internal_state = Construct(MyState, protocol)

    # A user would write code against their state.
    fire!(state::MyState) = (state.people[3].health -= 0.2)
    # Inside the simulation step would apply that code against the view.
    simulation_step(tracker, internal_state, state)
end
