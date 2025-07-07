"""
This module implements a notification-based tracking system similar to Observed, but:
- ObservedVector stores a typed reference to Tracker{T} instead of Any
- Elements notify their array when accessed/modified
- Arrays notify the tracker directly
- The physical state maintains the tracker

The user definition of:
```
@tracked struct Entity{Q}
    quality::Q
    speed::Float64
end
```
produces
```
mutable struct Entity{Q,Tracker,Index}
    quality::Q
    speed::Float64
    _tracker::Tracker
    _index::Index
end
```
The same goes for:
```
@tracked struct Fly
    speed::Float64
end
```
Then we make:
```
@physical_state BoardState
    entities::Vector{Entity{Int}}
    flies::Dict{Tuple{Int,Int},Fly}
    params::Dict{Symbol,Float64}
end
```
The `@physical_state` macro loops through the containers to see that the keys
are `Tuple{Symbol,Int,Symbol}` for the vector and `Tuple{Symbol,Tuple{Int,Int},Symbol}` for the
dictionary. It does a `typejoin` on them to determine that it should use
either a Tuple or a Union of the two tuples as the data type for the Tracker.
Let's choose Tuple.
This creates
```
struct BoardState
    entites::TrackedVector{Entity{Int,Tracker{Tuple},Tuple{Symbol,Int}}}
    flies::TrackedDict{Fly{Tracker{Tuple},Tuple{Symbol,Tuple{Int,Int}}}}
    _tracker::Tracker{Tuple}
end
```

"""
module ThirdParty
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
import ..TrackedArray: PlaceType

export TrackedVector, ConstructState
export gotten, changed, reset_tracking!, reset_gotten!

# Type aliases
const PlaceKey = PlaceType  # Tuple{Symbol,Int,Symbol}

"""
Tracker for centralized read/write tracking
"""
struct Tracker{T}
    _reads::Vector{T}
    _writes::Vector{T}
    
    function Tracker{T}(expected_size::Int=1000) where T
        reads = Vector{T}()
        writes = Vector{T}()
        sizehint!(reads, expected_size)
        sizehint!(writes, expected_size)
        new(reads, writes)
    end
end

# Access functions for tracker
places_read(tracker::Tracker) = Set(tracker._reads)
places_written(tracker::Tracker) = Set(tracker._writes)
# Modification functions for tracker
add_read(tracker::Tracker, key) = (push!(tracker._reads, key); nothing)
add_write(tracker::Tracker, key) = (push!(tracker._writes, key); nothing)
clear_read(tracker::Tracker) = (empty!(tracker._reads); nothing)
clear_all(tracker::Tracker) = (empty!(tracker._reads); empty!(tracker._writes); nothing)


"""
    ObservedVector{T,TK}

A vector that tracks access and changes to its elements and notifies the tracker.
TK is the tracker type to maintain type safety.
"""
mutable struct ObservedVector{T,TK<:Tracker} <: AbstractVector{T}
    data::Vector{T}
    array_name::Symbol
    tracker::TK
    
    function ObservedVector{T,TK}(::UndefInitializer, n::Integer, array_name::Symbol, tracker::TK) where {T,TK<:Tracker}
        new{T,TK}(Vector{T}(undef, n), array_name, tracker)
    end
end

# Implement AbstractArray interface
Base.size(v::ObservedVector) = size(v.data)
Base.getindex(v::ObservedVector{T,TK}, i::Integer) where {T,TK} = begin
    element = v.data[i]
    if hasfield(typeof(element), :_container)
        setfield!(element, :_container, v)
        setfield!(element, :_index, i)
    end
    element
end

Base.setindex!(v::ObservedVector{T,TK}, x, i::Integer) where {T,TK} = begin
    v.data[i] = x
    if hasfield(typeof(x), :_container)
        setfield!(x, :_container, v)
        setfield!(x, :_index, i)
    end
    x
end

# Track property access on elements
function Base.getproperty(v::ObservedVector, field::Symbol)
    if field in (:data, :array_name, :tracker)
        return getfield(v, field)
    else
        error("Field $field not found in ObservedVector")
    end
end

function Base.setproperty!(v::ObservedVector, field::Symbol, value)
    if field in (:data, :array_name, :tracker)
        setfield!(v, field, value)
    else
        error("Cannot set field $field in ObservedVector")
    end
end

# Notification methods - directly push to tracker
function notify_read(v::ObservedVector, index::Int, field::Symbol)
    key = (v.array_name, index, field)
    add_read(v.tracker, key)
end

function notify_write(v::ObservedVector, index::Int, field::Symbol)
    key = (v.array_name, index, field)
    add_write(v.tracker, key)
end

# For compatibility with existing interface
gotten(v::ObservedVector) = Set{Tuple}()  # Tracking is at state level
changed(v::ObservedVector) = Set{Tuple}()  # Tracking is at state level
reset_tracking!(v::ObservedVector) = v
reset_gotten!(v::ObservedVector) = v

# Use TrackedVector as alias for compatibility
const TrackedVector = ObservedVector

"""
Creates an element type with notification capability
"""
function create_element_type(type_name::Symbol, fields::Vector)
    field_names = [field[1] for field in fields]
    field_types = [field[2] for field in fields]
    
    # Build the struct definition with fields
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in fields]
    
    struct_def = quote
        mutable struct $type_name
            $(field_defs...)
            _container::Union{Nothing, ObservedVector}
            _index::Union{Nothing, Int}
            
            function $type_name($([fname for fname in field_names]...))
                new($([fname for fname in field_names]...), nothing, nothing)
            end
        end
    end
    
    # Create getproperty that notifies on read
    getprop_def = quote
        function Base.getproperty(obj::$type_name, field::Symbol)
            if field in (:_container, :_index)
                return getfield(obj, field)
            else
                container = getfield(obj, :_container)
                if container !== nothing && getfield(obj, :_index) !== nothing
                    notify_read(container, getfield(obj, :_index), field)
                end
                return getfield(obj, field)
            end
        end
    end
    
    # Create setproperty that notifies on write
    setprop_def = quote
        function Base.setproperty!(obj::$type_name, field::Symbol, value)
            if field in (:_container, :_index)
                setfield!(obj, field, value)
            else
                container = getfield(obj, :_container)
                if container !== nothing && getfield(obj, :_index) !== nothing
                    notify_write(container, getfield(obj, :_index), field)
                end
                setfield!(obj, field, value)
            end
        end
    end
    
    # Create propertynames for introspection
    propnames_def = quote
        function Base.propertynames(obj::$type_name, private::Bool=false)
            if private
                return fieldnames($type_name)
            else
                return $(field_names)
            end
        end
    end
    
    # Create equality comparison
    field_comparisons = [:(getproperty(a, $(QuoteNode(fname))) == getproperty(b, $(QuoteNode(fname)))) for fname in field_names]
    eq_expr = length(field_comparisons) > 0 ? Expr(:&&, field_comparisons...) : true
    
    eq_def = quote
        function Base.:(==)(a::$type_name, b::$type_name)
            $eq_expr
        end
    end
    
    # Evaluate all definitions
    eval(struct_def)
    eval(getprop_def)
    eval(setprop_def)
    eval(propnames_def)
    eval(eq_def)
    
    return eval(type_name)
end

"""
    ThirdPartyState

A physical state that maintains centralized tracking of reads and writes.
"""
abstract type ThirdPartyState <: PhysicalState end

# Create a concrete state type with tracking
function create_state_type(field_names::Vector{Symbol}, field_types::Vector, tracker_type::Type)
    state_type_name = gensym("ThirdPartyState")
    
    # Build field definitions
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in zip(field_names, field_types)]
    
    state_def = quote
        mutable struct $state_type_name <: ThirdPartyState
            _tracker::$tracker_type
            $(field_defs...)
            
            function $state_type_name(tracker::$tracker_type, $(field_names...))
                new(tracker, $(field_names...))
            end
        end
    end
    
    eval(state_def)
    return eval(state_type_name)
end

# Implement the required interface functions
function changed(state::ThirdPartyState)
    return places_written(getfield(state, :_tracker))
end

function wasread(state::ThirdPartyState)
    return places_read(getfield(state, :_tracker))
end

function accept(state::ThirdPartyState)
    tracker = getfield(state, :_tracker)
    clear_all(tracker)
    return state
end

function resetread(state::ThirdPartyState)
    tracker = getfield(state, :_tracker)
    clear_read(tracker)
    return state
end

"""
    ConstructState(specification, counts)

Creates a ThirdPartyState with ObservedVector arrays populated with observable structs.
"""
function ConstructState(specification, counts)
    # Estimate expected tracker size
    total_elements = sum(values(counts))
    avg_fields = sum(length(fields) for (_, fields) in specification) / length(specification)
    expected_size = Int(ceil(total_elements * avg_fields * 0.5))
    
    # Create the tracker
    tracker = Tracker{PlaceKey}(expected_size)
    tracker_type = typeof(tracker)
    
    # Generate element types and create ObservedVectors
    fields = []
    
    for (array_name, field_specs) in specification
        # Create the element type
        struct_name = gensym(string(array_name) * "_type")
        element_type = create_element_type(struct_name, field_specs)
        
        # Get the count for this array
        count = counts[array_name]
        
        # Create ObservedVector with typed tracker
        observed_vec = ObservedVector{element_type,tracker_type}(undef, count, array_name, tracker)
        
        push!(fields, array_name => observed_vec)
    end
    
    # Create the state type
    field_names = [pair[1] for pair in fields]
    field_types = [typeof(pair[2]) for pair in fields]
    state_type = create_state_type(field_names, field_types, tracker_type)
    
    # Create state instance
    field_values = [pair[2] for pair in fields]
    physical_state = Base.invokelatest(state_type, tracker, field_values...)
    
    return physical_state
end

end