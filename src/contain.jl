module Contain
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState, initialize_physical!
import Base
export ConstructState

export Tracker

# This implementation combines the best elements of @src/shared.jl and @src/observed.jl.
#
#  * The `ObservedState` contains a `Tracker{T}` where `T` is a `PlaceKey`.
#  * The user's mutable struct is stored in a Cuddle.
#  * The cuddle is initialized with a pointer to a function `track_entry`.
#    It does NOT have a pointer to a `Tracker{T}`.
#  * An `ObservedVector` contains `data`, `array_name`, and a `track_entry::Function`.
#  * The `ObservedVector` checks at construction that its contained type is a `Cuddle`
#    so that it does not need to check `hasfield` during a `getindex` or `setindex!`.

"""
There will be exactly one Tracker per physical state, and every struct that
may be assigned or read will have a pointer to this tracker.
"""
struct Tracker{T}
    _read::Vector{T}
    _write::Vector{T}
    function Tracker{T}(expected_size::Int=1000) where {T}
        _read = Vector{T}()
        _write = Vector{T}()
        sizehint!(_read, expected_size)
        sizehint!(_write, expected_size)
        new(_read, _write)
    end
end

# There should be NO direct accesses to _read or _write.
@inline track_entry(tr::Tracker, entry, write::Bool) = write ? push!(tr._write, entry) : push!(tr._read, entry)
places_read(tracker::Tracker) = Set(tracker._read)
places_written(tracker::Tracker) = Set(tracker._write)


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
    _track::Function
    Cuddle{D,P,T}(data::D, path::P, track::Function) where {D,P,T} = new(data, path, track)
end

# Convenience constructor that creates a closure for tracking
@inline function Cuddle(data::D, path::P, tracker::Tracker{T}) where {D,P,T}
    track_fn = @inline (entry, write) -> track_entry(tracker, entry, write)
    Cuddle{D,P,T}(data, path, track_fn)
end

# Helper function to create Cuddle with automatic path construction
function cuddle(data::D, parent_path::Tuple, index, tracker::Tracker{T}) where {D,T}
    path = (parent_path..., index)
    P = typeof(path)
    track_fn = (entry, write) -> track_entry(tracker, entry, write)
    Cuddle{D,P,T}(data, path, track_fn)
end

# Create an array of Cuddles with automatic path generation
function cuddle_array(::Type{D}, dims::Dims, base_path::Symbol, tracker::Tracker{T}) where {D,T}
    # Determine the exact path type based on dimensions
    n_dims = length(dims)
    PathType = Tuple{Symbol, ntuple(_ -> Int, n_dims)...}
    arr = Array{Cuddle{D,PathType,T}}(undef, dims)
    track_fn = (entry, write) -> track_entry(tracker, entry, write)
    for idx in CartesianIndices(arr)
        path = (base_path, idx.I...)
        arr[idx] = Cuddle(D(), path, track_fn)
    end
    return arr
end

@inline function Base.getproperty(obj::Cuddle, field::Symbol)
    if field === :_path || field === :_track || field === :_data
        return getfield(obj, field)
    end
    # Combine getfield calls to reduce overhead
    path = getfield(obj, :_path)
    track_fn = getfield(obj, :_track)
    data = getfield(obj, :_data)
    # Create the key by appending the field to the path
    key = (path..., field)
    track_fn(key, false)  # false = read
    return getfield(data, field)
end

@inline function Base.setproperty!(obj::Cuddle, field::Symbol, value)
    if field === :_path || field === :_track || field === :_data
        setfield!(obj, field, value)
        return
    end
    # Combine getfield calls to reduce overhead
    path = getfield(obj, :_path)
    track_fn = getfield(obj, :_track)
    data = getfield(obj, :_data)
    # Create the key by appending the field to the path
    key = (path..., field)
    track_fn(key, true)  # true = write
    setfield!(data, field, value)
end

# Type aliases
const PlaceType = Tuple{Symbol,Int,Symbol}
const PlaceKey = PlaceType

"""
    ObservedVector{T}

A vector that contains Cuddle-wrapped elements and tracks access.
"""
struct ObservedVector{T<:Cuddle} <: AbstractVector{T}
    data::Vector{T}
    array_name::Symbol
    track_entry::Function
    
    function ObservedVector{T}(data::Vector{T}, array_name::Symbol, track_entry::Function) where T<:Cuddle
        new{T}(data, array_name, track_entry)
    end
end

# Implement AbstractArray interface
Base.size(v::ObservedVector) = size(v.data)
Base.IndexStyle(::Type{<:ObservedVector}) = IndexLinear()

@inline function Base.getindex(v::ObservedVector, i::Integer)
    @boundscheck checkbounds(v.data, i)
    @inbounds begin
        element = v.data[i]
        # Update the element's path if it changed positions
        if element._path[2] != i
            new_path = (v.array_name, i)
            new_element = Cuddle(element._data, new_path, element._track)
            v.data[i] = new_element
            return new_element
        end
        return element
    end
end

@inline function Base.setindex!(v::ObservedVector{T}, x::T, i::Integer) where T
    @boundscheck checkbounds(v.data, i)
    # Ensure the element has the correct path
    if x._path[1] != v.array_name || x._path[2] != i
        new_path = (v.array_name, i)
        new_element = Cuddle(x._data, new_path, x._track)
        @inbounds v.data[i] = new_element
    else
        @inbounds v.data[i] = x
    end
    return x
end

# For interface compatibility
getitem(v::ObservedVector, i::Int) = v[i]

"""
    ObservedState

A physical state that maintains centralized tracking of reads and writes.
"""
abstract type ObservedState <: PhysicalState end

# Create a concrete state type with tracking
function create_state_type(field_names::Vector{Symbol}, field_types::Vector)
    state_type_name = gensym("ContainState")
    
    # Build field definitions
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in zip(field_names, field_types)]
    
    state_def = quote
        mutable struct $state_type_name <: ObservedState
            _tracker::Tracker{PlaceKey}
            $(field_defs...)
            
            function $state_type_name(tracker::Tracker{PlaceKey}, $(field_names...))
                new(tracker, $(field_names...))
            end
        end
    end
    
    eval(state_def)
    return eval(state_type_name)
end

# Implement the required interface functions
function changed(state::ObservedState)
    return places_written(getfield(state, :_tracker))
end

function wasread(state::ObservedState)
    return places_read(getfield(state, :_tracker))
end

function accept(state::ObservedState)
    tracker = getfield(state, :_tracker)
    empty!(tracker._read)
    empty!(tracker._write)
    return state
end

function resetread(state::ObservedState)
    tracker = getfield(state, :_tracker)
    empty!(tracker._read)
    return state
end

"""
    ConstructState(specification, counts)

Creates an ObservedState with ObservedVector arrays populated with Cuddle-wrapped structs.
"""
function ConstructState(specification, counts)
    # Estimate expected tracker size
    total_elements = sum(values(counts))
    avg_fields = sum(length(fields) for (_, fields) in specification) / length(specification)
    expected_size = Int(ceil(total_elements * avg_fields * 0.5))
    
    # Create the tracker
    tracker = Tracker{PlaceKey}(expected_size)
    
    # Create the tracking function closure
    track_fn = (entry, write) -> track_entry(tracker, entry, write)
    
    # Generate element types and create ObservedVectors
    fields = []
    
    for (array_name, field_specs) in specification
        # Create the element type
        struct_name = gensym(string(array_name) * "_type")
        
        # Build field expressions
        field_exprs = []
        for (field_name, field_type) in field_specs
            push!(field_exprs, :($field_name::$field_type))
        end
        
        # Create the struct
        struct_def = quote
            mutable struct $struct_name
                $(field_exprs...)
            end
        end
        eval(struct_def)
        
        # Get the count and create elements
        count = counts[array_name]
        DataType = eval(struct_name)
        
        # Determine path type for this array
        PathType = Tuple{Symbol, Int}
        CuddleType = Cuddle{DataType, PathType, PlaceKey}
        
        # Create vector of Cuddles
        vec_data = Vector{CuddleType}(undef, count)
        
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
                    push!(args, field_type())
                end
            end
            data = Base.invokelatest(DataType, args...)
            path = (array_name, i)
            vec_data[i] = Cuddle{DataType, PathType, PlaceKey}(data, path, track_fn)
        end
        
        # Create ObservedVector
        observed_vec = ObservedVector{CuddleType}(vec_data, array_name, track_fn)
        
        push!(fields, array_name => observed_vec)
    end
    
    # Create the state type
    field_names = [pair[1] for pair in fields]
    field_types = [typeof(pair[2]) for pair in fields]
    state_type = create_state_type(field_names, field_types)
    
    # Create state instance
    field_values = [pair[2] for pair in fields]
    physical_state = Base.invokelatest(state_type, tracker, field_values...)
    
    return physical_state
end

function initialize_physical!(specification, physical_state::ObservedState)
    # Implementation if needed
end

end
