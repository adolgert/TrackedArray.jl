module ContainOptimized
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState, initialize_physical!
import Base
export ConstructState

export Tracker

# This implementation eliminates closure allocations by storing the tracker directly
# and using a type parameter to avoid type instability.

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

# Direct access functions for performance
@inline track_read!(tr::Tracker, entry) = push!(tr._read, entry)
@inline track_write!(tr::Tracker, entry) = push!(tr._write, entry)
places_read(tracker::Tracker) = Set(tracker._read)
places_written(tracker::Tracker) = Set(tracker._write)

"""
Optimized Cuddle that stores the tracker directly instead of a closure.
"""
struct CuddleOpt{D,P<:Tuple,T,TR<:Tracker{T}}
    _data::D
    _path::P
    _tracker::TR
end

# Constructor
@inline CuddleOpt(data::D, path::P, tracker::TR) where {D,P,T,TR<:Tracker{T}} = 
    CuddleOpt{D,P,T,TR}(data, path, tracker)

@inline function Base.getproperty(obj::CuddleOpt, field::Symbol)
    if field === :_path || field === :_tracker || field === :_data
        return getfield(obj, field)
    end
    # Combine getfield calls to reduce overhead
    path = getfield(obj, :_path)
    tracker = getfield(obj, :_tracker)
    data = getfield(obj, :_data)
    # Create the key by appending the field to the path
    key = (path..., field)
    track_read!(tracker, key)
    return getfield(data, field)
end

@inline function Base.setproperty!(obj::CuddleOpt, field::Symbol, value)
    if field === :_path || field === :_tracker || field === :_data
        setfield!(obj, field, value)
        return
    end
    # Combine getfield calls to reduce overhead
    path = getfield(obj, :_path)
    tracker = getfield(obj, :_tracker)
    data = getfield(obj, :_data)
    # Create the key by appending the field to the path
    key = (path..., field)
    track_write!(tracker, key)
    setfield!(data, field, value)
end

# Type aliases
const PlaceType = Tuple{Symbol,Int,Symbol}
const PlaceKey = PlaceType

"""
    ObservedVector{T}

A vector that contains CuddleOpt-wrapped elements and tracks access.
"""
struct ObservedVector{T<:CuddleOpt} <: AbstractVector{T}
    data::Vector{T}
    array_name::Symbol
    
    function ObservedVector{T}(data::Vector{T}, array_name::Symbol) where T<:CuddleOpt
        new{T}(data, array_name)
    end
end

# Implement AbstractArray interface
Base.size(v::ObservedVector) = size(v.data)
Base.IndexStyle(::Type{<:ObservedVector}) = IndexLinear()

@inline function Base.getindex(v::ObservedVector, i::Integer)
    @boundscheck checkbounds(v.data, i)
    @inbounds v.data[i]
end

@inline function Base.setindex!(v::ObservedVector{T}, x::T, i::Integer) where T
    @boundscheck checkbounds(v.data, i)
    @inbounds v.data[i] = x
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
    state_type_name = gensym("ContainOptState")
    
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

Creates an ObservedState with ObservedVector arrays populated with CuddleOpt-wrapped structs.
"""
function ConstructState(specification, counts)
    # Estimate expected tracker size
    total_elements = sum(values(counts))
    avg_fields = sum(length(fields) for (_, fields) in specification) / length(specification)
    expected_size = Int(ceil(total_elements * avg_fields * 0.5))
    
    # Create the tracker
    tracker = Tracker{PlaceKey}(expected_size)
    
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
        TrackerType = typeof(tracker)
        CuddleType = CuddleOpt{DataType, PathType, PlaceKey, TrackerType}
        
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
            vec_data[i] = CuddleOpt(data, path, tracker)
        end
        
        # Create ObservedVector
        observed_vec = ObservedVector{CuddleType}(vec_data, array_name)
        
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