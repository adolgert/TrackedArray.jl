using Random
using StatsBase

export PlaceType, DefaultValues
export spec_to_dict, all_keys, initialize_physical!, write_to_key, read_from_key, random_specification
export write_n, read_n, PhysicalState, accept, resetread, changed, wasread
export capture_state_changes, capture_state_reads


# Define the interface to the lower level.
"""
The `PhysicalState` may contain other properties, but those defined with
`TrackedVectors` are used to compute the next event in the simulation.
"""
abstract type PhysicalState end

function accept end
function resetread end
function changed end
function wasread end


"""
    capture_state_changes(f::Function, physical_state)

The callback function `f` will modify the physical state. This function
records which parts of the state were modified. The callback should have
no arguments and may return a result.
"""
function capture_state_changes(f::Function, physical)
    accept(physical)
    result = f()
    changes = changed(physical)
    return (;result, changes)
end


"""
    capture_state_reads(f::Function, physical_state)

The callback function `f` will read the physical state. This function
records which parts of the state were read. The callback should have
no arguments and may return a result.
"""
function capture_state_reads(f::Function, physical)
    resetread(physical)
    result = f()
    reads = wasread(physical)
    return (;result, reads)
end


const PlaceType=Tuple{Symbol,Int,Symbol}
const DefaultValues = Dict(
        Symbol => [:none, :what, :infected, :dead, :moving, :staying],
        Int => [1, 7, 3, 6, 9, 11],
        String => ["hi", "Bob", "fl", "wy", "ar"],
        Float64 => [1.0, 2.0, 3.14, 2.71828, 1.618]
        )

"""
Sample input:
```
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
```
"""
function spec_to_dict(specification)
    # Convert specification to dicts for easier work.
    dictspec = Dict{Symbol,Dict{Symbol,DataType}}()
    for component_idx in eachindex(specification)
        component_name, fields = specification[component_idx]
        for (field, field_type) in fields
            if !haskey(dictspec, component_name)
                dictspec[component_name] = Dict{Symbol,DataType}()
            end
            dictspec[component_name][field] = field_type
        end
    end
    return dictspec
end


function all_keys(specification, physical_state)
    lengths = Dict{Symbol,Int}()
    for (arr_name, _) in specification
        lengths[arr_name] = length(getfield(physical_state, arr_name))
    end

    keys = Vector{Tuple{PlaceType,DataType}}()
    for (arr_name, members) in specification
        for (mem_name, dtype) in members
            for i in 1:lengths[arr_name]
                push!(keys, ((arr_name, i, mem_name), dtype))
            end
        end
    end
    return keys
end


function initialize_physical!(specification, physical_state)
    for component_idx in eachindex(specification)
        component_name, fields = specification[component_idx]
        component = getfield(physical_state, component_name)
        element_type = eltype(component)
        for elem_idx in eachindex(component)
            # Initialize element with zero values first
            field_names = [field for (field, _) in fields]
            field_values = [field_type == Symbol ? :none : 
                           field_type == Int ? 0 : 
                           field_type == String ? "" : 
                           field_type == Float64 ? 0.0 : 
                           zero(field_type) for (_, field_type) in fields]
            component[elem_idx] = element_type(field_values...)
        end
    end
end


function write_to_key(physical_state, key::PlaceType, value)
    arr_name, elemidx, member = key
    arr = getproperty(physical_state, arr_name)
    setproperty!(arr[elemidx], member, value)
end


function read_from_key(physical_state, key::PlaceType)
    arr_name, elemidx, member = key
    arr = getproperty(physical_state, arr_name)
    return getproperty(arr[elemidx], member)
end


"""
Creates a specification that looks like:
```
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
```
"""
function random_specification(rng; min_arrays=1, max_arrays=20, min_fields=1, max_fields=20)
    available_types = [Symbol, Int, String, Float64]
    field_name_options = [
        :id, :name, :health, :age, :location, :status, :value, :count, :type,
        :level, :state, :size, :weight, :score, :time, :rate, :flag, :category,
        :priority, :color]
    
    num_arrays = rand(rng, min_arrays:max_arrays)
    specification = []

    for i in 1:num_arrays
        # Generate unique array name
        base_name = gensym("arr")
        array_name = i == 1 ? base_name : Symbol(string(base_name) * string(i))
        
        # Generate fields for this array
        num_fields = rand(rng, min_fields:max_fields)
        fields = []
        used_field_names = Set{Symbol}()
        
        field_names = sample(rng, field_name_options, num_fields; replace=false)
        for j in 1:num_fields
            # Pick a unique field name
            field_name = field_names[j]
            counter = 1
            while field_name in used_field_names
                field_name = Symbol(string(rand(rng, field_name_options)) * string(counter))
                counter += 1
            end
            push!(used_field_names, field_name)
            
            # Pick a random type
            field_type = rand(rng, available_types)
            push!(fields, field_name => field_type)
        end
        
        push!(specification, array_name => fields)
    end
    
    return specification
end


function write_n(physical_state, every_key, n, rng)
    written = Set{PlaceType}()
    chosen_keys = rand(rng, every_key, n)
    writeres = capture_state_changes(physical_state) do
        for (key, key_type) in chosen_keys
            write_to_key(physical_state, key, rand(rng, DefaultValues[key_type]))
            push!(written, key)
        end
        nothing
    end
    return issetequal(writeres.changes, written)
end


function read_n(physical_state, every_key, n, rng)
    read = Set{PlaceType}()
    chosen_keys = rand(rng, every_key, n)
    readres = capture_state_reads(physical_state) do
        for (key, key_type) in chosen_keys
            read_from_key(physical_state, key)
            push!(read, key)
        end
        nothing
    end
    return issetequal(readres.reads, read)
end
