module Shared
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState, initialize_physical!
import Base
export ConstructState
export Tracker, TrackedStruct, hascrumb, Cuddle, cuddle_array

"""
There will be exactly one Tracker per physical state, and every struct that
may be assigned or read will have a pointer to this tracker.
"""
struct Tracker{T}
    read::Vector{T}
    write::Vector{T}
    function Tracker{T}(expected_size::Int=1000) where {T}
        read = Vector{T}()
        write = Vector{T}()
        sizehint!(read, expected_size)
        sizehint!(write, expected_size)
        new(read, write)
    end
end

places_read(tracker::Tracker) = Set(tracker.read)
places_written(tracker::Tracker) = Set(tracker.write)

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

@inline function Base.getproperty(obj::Cuddle, field::Symbol)
    if field === :_path || field === :_track || field === :_data
        return getfield(obj, field)
    end
    path = getfield(obj, :_path)
    track = getfield(obj, :_track)
    # Create the key by appending the field to the path
    key = (path..., field)
    push!(track.read, key)
    data = getfield(obj, :_data)
    return getfield(data, field)
end

@inline function Base.setproperty!(obj::Cuddle, field::Symbol, value)
    if field === :_path || field === :_track || field === :_data
        setfield!(obj, field, value)
        return
    end
    path = getfield(obj, :_path)
    track = getfield(obj, :_track)
    # Create the key by appending the field to the path
    key = (path..., field)
    push!(track.write, key)
    data = getfield(obj, :_data)
    setfield!(data, field, value)
end


# Type aliases for the tracker
const PlaceType = Tuple{Symbol,Int,Symbol}
const PlaceKey = PlaceType  # Union{PlaceType,Tuple}

"""
    ConstructState(specification, counts)

Creates a PhysicalState with CuddleVector arrays populated with Cuddle-wrapped structs
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
    # Estimate expected tracker size based on total elements and fields
    total_elements = sum(values(counts))
    avg_fields = sum(length(fields) for (_, fields) in specification) / length(specification)
    expected_size = Int(ceil(total_elements * avg_fields * 0.5))  # Assume 50% access rate
    
    # Create the tracker that will be shared by all elements
    tracker = Tracker{PlaceKey}(expected_size)
    
    # Generate struct types and create CuddleVectors
    fields = []
    
    for (array_name, field_specs) in specification
        # Create the basic struct type dynamically
        struct_name = Symbol(string(array_name) * "_type")
        
        # Build field expressions
        field_exprs = []
        for (field_name, field_type) in field_specs
            push!(field_exprs, :($field_name::$field_type))
        end
        
        # Create the struct using eval
        struct_def = quote
            mutable struct $struct_name
                $(field_exprs...)
            end
        end
        eval(struct_def)
        
        # Get the count for this array
        count = counts[array_name]
        DataType = eval(struct_name)
        
        # Create CuddleVector with Cuddle-wrapped elements
        CuddleType = Cuddle{DataType, Tuple{Symbol,Int}, PlaceKey}
        vec = CuddleVector{CuddleType}(undef, count)
        
        # Initialize each element with a Cuddle wrapper
        for i in 1:count
            # Build constructor arguments with default values
            args = []
            for (field_name, field_type) in field_specs
                if field_type == Int
                    push!(args, 0)
                elseif field_type == Symbol
                    push!(args, :none)
                elseif field_type == String
                    push!(args, "")
                elseif field_type == Float64
                    push!(args, 0.0)
                else
                    # Try to construct a default value
                    push!(args, field_type())
                end
            end
            data = Base.invokelatest(DataType, args...)
            path = (array_name, i)
            vec[i] = Cuddle(data, path, tracker)
        end
        
        push!(fields, array_name => vec)
    end
    
    # Create anonymous CuddleState struct
    state_type_name = gensym("CuddleState")
    field_names = [pair[1] for pair in fields]
    field_types = [:(CuddleVector{Cuddle{$(Symbol(string(name) * "_type")), Tuple{Symbol,Int}, PlaceKey}}) for name in field_names]
    
    # Create the CuddleState type
    state_def = quote
        mutable struct $state_type_name <: CuddleState
            _tracker::Tracker{PlaceKey}
            $([:($name::$typ) for (name, typ) in zip(field_names, field_types)]...)
        end
    end
    eval(state_def)
    
    # Create and return instance
    field_values = [pair[2] for pair in fields]
    return Base.invokelatest(eval(state_type_name), tracker, field_values...)
end

# CuddleVector implementation
struct CuddleVector{T} <: AbstractVector{T}
    data::Vector{T}
    CuddleVector{T}(::UndefInitializer, n::Int) where T = new(Vector{T}(undef, n))
end

Base.size(cv::CuddleVector) = size(cv.data)
@inline Base.getindex(cv::CuddleVector, i::Int) = @inbounds cv.data[i]
@inline Base.setindex!(cv::CuddleVector, v, i::Int) = (@inbounds cv.data[i] = v)
Base.IndexStyle(::Type{<:CuddleVector}) = IndexLinear()

# getitem for interface compatibility
@inline getitem(cv::CuddleVector, i::Int) = @inbounds cv.data[i]

# CuddleState implementation
abstract type CuddleState <: PhysicalState end

function accept(state::CuddleState)
    empty!(state._tracker.read)
    empty!(state._tracker.write)
end

changed(state::CuddleState) = places_written(state._tracker)

function resetread(state::CuddleState)
    empty!(state._tracker.read)
end

wasread(state::CuddleState) = places_read(state._tracker)

function initialize_physical!(specification, physical_state::CuddleState) end

end
