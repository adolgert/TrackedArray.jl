using ReTest
using TrackedArray
using Base
using Logging


@testset "Observed: Construction from minimal specification" begin
    using TrackedArray.Observed

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
    physical_state = TrackedArray.Observed.ConstructState(specification, Dict(:people => 3, :places => 2))
    @assert !(physical_state isa Type)

    # Test structural properties.
    for component_idx in eachindex(specification)
        component, fields = specification[component_idx]
        @test hasfield(typeof(physical_state), component)
        member_type = eltype(getfield(physical_state, component))
        @test ismutabletype(member_type)
        for (field, field_type) in fields
            @test hasfield(member_type, field)
            @test fieldtype(member_type, field) == field_type
        end
    end
end


@testset "Observed: Consistency and correctness" begin
    using Distributions
    using Random
    using TrackedArray.Observed
    rng = Xoshiro(9876234982)

    specification = random_specification(rng)
    counts = Dict(arr_name => rand(rng, 1:10) for (arr_name, _) in specification)
    physical_state = TrackedArray.Observed.ConstructState(specification, counts)

    # These represent our model of what was read or written.
    read = Set{PlaceType}()
    written = Set{PlaceType}()

    # Convert specification to dicts for easier work.
    dictspec = spec_to_dict(specification)
    every_key = all_keys(specification, physical_state)
    initialize_physical!(specification, physical_state)

    logger = ConsoleLogger(stderr, Logging.Info)
    with_logger(logger) do
        @info "Starting test loop with $(length(every_key)) available keys"
        for step_idx in 1:5
            activity = rand(rng, 1:2)
            if activity == 1
                n_keys = rand(rng, 0:length(every_key))
                @info "Step $step_idx: Testing write operation with $n_keys keys"
                result = write_n(physical_state, every_key, n_keys, rng)
                @info "Step $step_idx: Write test result: $result"
                @test result
            elseif activity == 2
                n_keys = rand(rng, 0:length(every_key))
                @info "Step $step_idx: Testing read operation with $n_keys keys"
                result = read_n(physical_state, every_key, n_keys, rng)
                @info "Step $step_idx: Read test result: $result"
                @test result
            end
        end
        @info "Completed test loop successfully"
    end
end