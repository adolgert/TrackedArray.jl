using ReTest
using TrackedArray
using Base


TrackedArray.Original.@tracked_struct Person begin
    health::Symbol
    age::Int
    location::Int
end

Base.zero(::Type{Person}) = Person(:neutral, 0, 0)


@testset "validation and contracts" begin
    using TrackedArray.Original
    person = TrackedVector{Person}(undef, 3)
    for i in eachindex(person)
        person[i] = Person(:neutral, 20 * i, i)
    end
    reset_tracking!(person)
    @test person[1] == Person(:neutral, 20, 1)
    @test (1,:health) ∈ gotten(person)
    @test (1,:age) ∈ gotten(person)
    @test (1,:location) ∈ gotten(person)
    @test person[2].health == :neutral
    @test (2, :health) ∈ gotten(person)
    person[3].location = 5
    @test (3, :location) ∉ gotten(person)
    @test (3, :location) ∈ changed(person)
    reset_gotten!(person)
    @test isempty(gotten(person))
    @test (3, :location) ∈ changed(person)
    reset_tracking!(person)
    @test isempty(changed(person))
end


@testset "Construction from minimal specification" begin
    using TrackedArray.Original

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
    physical_state = ConstructState(specification, Dict(:people => 3, :places => 2))
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


@testset "Consistency and correctness" begin
    using Distributions
    using Random
    using TrackedArray.Original
    using TrackedArray.Original: capture_state_changes, capture_state_reads
    rng = Xoshiro(9876234982)

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
    physical_state = ConstructState(specification, Dict(:people => 3, :places => 2))

    # These represent our model of what was read or written.
    read = Set{PlaceType}()
    written = Set{PlaceType}()

    # Convert specification to dicts for easier work.
    dictspec = spec_to_dict(specification)

    initialize_physical!(specification, physical_state)

    for step_idx in 1:5
        activity = rand(rng, 1:2)
        if activity == 1
            empty!(written)
            writeres = capture_state_changes(physical_state) do
                spots = rand(rng, 1:10)
                for spot in 1:spots
                    arr_name = rand(rng, keys(dictspec))
                    arr = getproperty(physical_state, arr_name)
                    elemidx = rand(rng, 1:length(arr))
                    member = rand(rng, keys(dictspec[arr_name]))
                    elemval = rand(rng, DefaultValues[dictspec[arr_name][member]])
                    setproperty!(arr[elemidx], member, elemval)
                    push!(written, (arr_name, elemidx, member))
                end
                nothing
            end
            @test length(writeres.changes) == length(written)
            for elem in written
                @test elem ∈ writeres.changes
            end
        elseif activity == 2
            empty!(read)
            readres = capture_state_reads(physical_state) do
                spots = rand(rng, 1:10)
                for spot in 1:spots
                    arr_name = rand(rng, keys(dictspec))
                    arr = getproperty(physical_state, arr_name)
                    elemidx = rand(rng, 1:length(arr))
                    member = rand(rng, keys(dictspec[arr_name]))
                    elemval = rand(rng, DefaultValues[dictspec[arr_name][member]])
                    getproperty(arr[elemidx], member)
                    push!(read, (arr_name, elemidx, member))
                end
                nothing
            end
            @test length(readres.reads) == length(read)
            for elem in read
                @test elem ∈ readres.reads
            end
        end
    end
end
