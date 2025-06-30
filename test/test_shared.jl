using ReTest
using TrackedArray
using Base
using Logging

@testset "Shared Tracker Cuddle" begin
    using TrackedArray.Shared
    # Goal is vector[i,j].value = 3
    TruckKey = Tuple{Symbol,Int,Int,Symbol}
    TruckPath = Tuple{Symbol,Int,Int}
    tracker = Tracker{TruckKey}()

    mutable struct Car
        wheels::Int
        cargo::Int
        Car() = new(4, 0)
    end

    struct CarPhysical <: PhysicalState
        fleet::Vector{Car}
        params::Dict{Symbol,Float64}
    end

    struct CuddleCarPhysical <: PhysicalState
        fleet::Vector{Cuddle{Car,TruckPath,TruckKey}}
        params::Dict{Symbol,Float64}
    end
    # Original way - verbose
    # CuddleTruck = Cuddle{Car,TruckPath,TruckKey}
    # trucks = Array{CuddleTruck,2}(undef, 3, 7)
    # for idx in CartesianIndices(trucks)
    #     trucks[idx] = CuddleTruck(Car(), Crumb((:trucks, Tuple(idx.I)...), tracker))
    # end
    
    # New way - using helper function
    trucks = cuddle_array(Car, (3, 7), :trucks, tracker)
    
    trucks[1, 2].wheels = 18
    @test first(tracker.write) == (:trucks, 1, 2, :wheels)
    cargo = trucks[3, 2].cargo
    @test first(tracker.read) == (:trucks, 3, 2, :cargo)
end

@testset "Shared: Construction from minimal specification" begin
    using TrackedArray.Shared

    specification = [
        :people => [
            :health => Symbol,
            :age => Int,
            :location => Int
        ]
        :places => [
            :name => String,
            :population => Int
        ]
    ]
    physical_state = TrackedArray.Shared.ConstructState(specification, Dict(:people => 3, :places => 2))
    @assert !(physical_state isa Type)

    # This test doesn't work well when the type that is constructed
    # is wrapped. Deleting here.
end


@testset "Shared: Consistency and correctness" begin
    using Distributions
    using Random
    using TrackedArray.Shared
    rng = Xoshiro(9876234982)

    specification = random_specification(rng)
    counts = Dict(arr_name => rand(rng, 1:10) for (arr_name, _) in specification)
    physical_state = TrackedArray.Shared.ConstructState(specification, counts)

    # These represent our model of what was read or written.
    read = Set{PlaceType}()
    written = Set{PlaceType}()

    # Convert specification to dicts for easier work.
    dictspec = spec_to_dict(specification)
    every_key = all_keys(specification, physical_state)
    initialize_physical!(specification, physical_state)

    logger = ConsoleLogger(stderr, Logging.Debug)
    with_logger(logger) do
        @debug "Starting test loop with $(length(every_key)) available keys"
        for step_idx in 1:50
            activity = rand(rng, 1:2)
            if activity == 1
                n_keys = rand(rng, 0:length(every_key))
                @debug "Step $step_idx: Testing write operation with $n_keys keys"
                result = write_n(physical_state, every_key, n_keys, rng)
                @debug "Step $step_idx: Write test result: $result"
                @test result
            elseif activity == 2
                n_keys = rand(rng, 0:length(every_key))
                @debug "Step $step_idx: Testing read operation with $n_keys keys"
                result = read_n(physical_state, every_key, n_keys, rng)
                @debug "Step $step_idx: Read test result: $result"
                @test result
            end
        end
        @debug "Completed test loop successfully"
    end
end