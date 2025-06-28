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
