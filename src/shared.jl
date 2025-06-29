module Shared
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
import Base
export ConstructState
export Tracker, TrackedStruct, hascrumb, Crumb, Cuddle, cuddle_array

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
A crumb has a path to the object that owns the crumb, where a path is a tuple
of symbols and integers. The tracker type may correspond exactly to that path plus
another symbol, or it may be an abstract class, which is a Tuple.
"""
struct Crumb{P <: Tuple,T}
    path::P
    track::Tracker{T}
end

"""
Use encapsulation to track reads/writes to a type.

This will break type dispatch on the contained type.
"""
struct Cuddle{D,P,T}
    _data::D
    _crumb::Crumb{P,T}
    Cuddle{D,P,T}(data::D, crumb) where {D,P,T} = new(data, crumb)
end

# Convenience constructors
Cuddle(data::D, path::P, tracker::Tracker{T}) where {D,P,T} = 
    Cuddle{D,P,T}(data, Crumb(path, tracker))

# Constructor that infers types from crumb
Cuddle(data::D, crumb::Crumb{P,T}) where {D,P,T} = 
    Cuddle{D,P,T}(data, crumb)

# Helper function to create Cuddle with automatic path construction
function cuddle(data::D, parent_path::Tuple, index, tracker::Tracker{T}) where {D,T}
    path = (parent_path..., index)
    P = typeof(path)
    Cuddle{D,P,T}(data, Crumb(path, tracker))
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
    if field === :_crumb || field === :_data
        return getfield(obj, field)
    end
    crumb = getfield(obj, :_crumb)
    push!(crumb.track.read, (crumb.path..., field))
    return getfield(obj._data, field)
end

function Base.setproperty!(obj::Cuddle, field::Symbol, value)
    if field === :_crumb || field === :_data
        setfield!(obj, field, value)
        return
    end
    crumb = getfield(obj, :_crumb)
    push!(crumb.track.write, (crumb.path..., field))
    setfield!(obj._data, field, value)
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
