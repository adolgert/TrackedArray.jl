module Shared
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
import Base
export ConstructState
export Tracker, TrackedStruct, hascrumb, Cuddle, cuddle_array

"""
There will be exactly one Tracker per physical state, and every struct that
may be assigned or read will have a pointer to this tracker.
"""
struct Tracker{T}
    read::Set{T}
    write::Set{T}
    Tracker{T}() where {T} = new(Set{T}(), Set{T}())
end


"""
Use encapsulation to track reads/writes to a type.

A path is a tuple of symbols and integers that identifies the location
of the object. The tracker type may correspond exactly to that path plus
another symbol, or it may be an abstract class, which is a Tuple.

This will break type dispatch on the contained type.
"""
struct Cuddle{D,P<:Tuple,T}
    _data::D
    _path::P
    _track::Tracker{T}
    Cuddle{D,P,T}(data::D, path::P, track::Tracker{T}) where {D,P,T} = new(data, path, track)
end

# Convenience constructor that infers types
Cuddle(data::D, path::P, tracker::Tracker{T}) where {D,P,T} = 
    Cuddle{D,P,T}(data, path, tracker)

# Helper function to create Cuddle with automatic path construction
function cuddle(data::D, parent_path::Tuple, index, tracker::Tracker{T}) where {D,T}
    path = (parent_path..., index)
    P = typeof(path)
    Cuddle{D,P,T}(data, path, tracker)
end

# Create an array of Cuddles with automatic path generation
function cuddle_array(::Type{D}, dims::Dims, base_path::Symbol, tracker::Tracker{T}) where {D,T}
    # Determine the exact path type based on dimensions
    n_dims = length(dims)
    PathType = Tuple{Symbol, ntuple(_ -> Int, n_dims)...}
    arr = Array{Cuddle{D,PathType,T}}(undef, dims)
    for idx in CartesianIndices(arr)
        path = (base_path, idx.I...)
        arr[idx] = Cuddle(D(), path, tracker)
    end
    return arr
end

function Base.getproperty(obj::Cuddle, field::Symbol)
    if field === :_path || field === :_track || field === :_data
        return getfield(obj, field)
    end
    path = getfield(obj, :_path)
    track = getfield(obj, :_track)
    push!(track.read, (path..., field))
    data = getfield(obj, :_data)
    return getfield(data, field)
end

function Base.setproperty!(obj::Cuddle, field::Symbol, value)
    if field === :_path || field === :_track || field === :_data
        setfield!(obj, field, value)
        return
    end
    path = getfield(obj, :_path)
    track = getfield(obj, :_track)
    push!(track.write, (path..., field))
    data = getfield(obj, :_data)
    setfield!(data, field, value)
end

"""
    ConstructState(specification, counts)

Creates a PhysicalState with TrackedVector arrays populated with tracked structs
based on the specification.

# Arguments
- `specification`: Vector of pairs where each pair is :field_name => [field_defs]
- `counts`: Dict mapping field names to array sizes

# Example
```julia
spec = [:people => [:health => Symbol, :age => Int]]
state = ConstructState(spec, Dict(:people => 3))
```
"""
function ConstructState(specification, counts)
    # Generate struct types and create TrackedVectors
    fields = []
    
    for (array_name, field_specs) in specification
        # Create the tracked struct type dynamically
        struct_name = Symbol(string(array_name) * "_type")
        
        # Build field expressions for the macro
        field_exprs = []
        for (field_name, field_type) in field_specs
            push!(field_exprs, :($field_name::$field_type))
        end
        
        # Create the struct using eval
        struct_def = quote
            @tracked_struct $struct_name begin
                $(field_exprs...)
            end
        end
        eval(struct_def)
        
        # Get the count for this array
        count = counts[array_name]
        
        # Create TrackedVector with uninitialized tracked structs
        tracked_vec = TrackedVector{eval(struct_name)}(undef, count)
        
        push!(fields, array_name => tracked_vec)
    end
    
    # Create anonymous TrackedState struct
    state_type_name = gensym("TrackedState")
    field_names = [pair[1] for pair in fields]
    field_types = [:(TrackedVector{$(Symbol(string(name) * "_type"))}) for name in field_names]
    
    # Create the TrackedState type
    state_def = quote
        struct $state_type_name <: TrackedState
            $([:($name::$typ) for (name, typ) in zip(field_names, field_types)]...)
        end
    end
    eval(state_def)
    
    # Create and return instance
    field_values = [pair[2] for pair in fields]
    return Base.invokelatest(eval(state_type_name), field_values...)
end

end
