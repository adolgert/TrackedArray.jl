"""
This module implements a notification-based tracking system where:
- Each element only stores a reference to its container and index
- Elements notify their array when accessed/modified
- Arrays notify the physical state
- The physical state maintains centralized tracking
"""
module Observed
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
import ..TrackedArray: PlaceType

export TrackedVector, ConstructState
export gotten, changed, reset_tracking!, reset_gotten!

"""
    ObservedVector{T}

A vector that tracks access and changes to its elements and notifies the physical state.
"""
mutable struct ObservedVector{T} <: AbstractVector{T}
    data::Vector{T}
    array_name::Symbol
    physical_state::Any  # Will be set to the actual physical state
    
    function ObservedVector{T}(::UndefInitializer, n::Integer) where T
        new{T}(Vector{T}(undef, n), :unknown, nothing)
    end
end

# Implement AbstractArray interface
Base.size(v::ObservedVector) = size(v.data)
Base.getindex(v::ObservedVector{T}, i::Integer) where T = begin
    element = v.data[i]
    if hasfield(typeof(element), :_container)
        setfield!(element, :_container, v)
        setfield!(element, :_index, i)
    end
    element
end

Base.setindex!(v::ObservedVector{T}, x, i::Integer) where T = begin
    v.data[i] = x
    if hasfield(typeof(x), :_container)
        setfield!(x, :_container, v)
        setfield!(x, :_index, i)
    end
    x
end

# Track property access on elements
function Base.getproperty(v::ObservedVector, field::Symbol)
    if field in (:data, :array_name, :physical_state)
        return getfield(v, field)
    else
        error("Field $field not found in ObservedVector")
    end
end

function Base.setproperty!(v::ObservedVector, field::Symbol, value)
    if field in (:data, :array_name, :physical_state)
        setfield!(v, field, value)
    else
        error("Cannot set field $field in ObservedVector")
    end
end

# Notification methods
function notify_read(v::ObservedVector, index::Int, field::Symbol)
    if v.physical_state !== nothing
        notify_read(v.physical_state, v.array_name, index, field)
    end
end

function notify_write(v::ObservedVector, index::Int, field::Symbol)
    if v.physical_state !== nothing
        notify_write(v.physical_state, v.array_name, index, field)
    end
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
    ObservedState

A physical state that maintains centralized tracking of reads and writes.
"""
abstract type ObservedState <: PhysicalState end

# These will be implemented by the generated state types
function notify_read end
function notify_write end

# Create a concrete state type with tracking
function create_state_type(field_names::Vector{Symbol}, field_types::Vector)
    state_type_name = gensym("ObservedState")
    
    # Build field definitions
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in zip(field_names, field_types)]
    
    state_def = quote
        mutable struct $state_type_name <: ObservedState
            $(field_defs...)
            _reads::Vector{PlaceType}
            _writes::Vector{PlaceType}
            
            function $state_type_name($([fname for fname in field_names]...))
                new($([fname for fname in field_names]...), PlaceType[], PlaceType[])
            end
        end
    end
    
    # Implement notification methods
    notify_read_def = quote
        function notify_read(state::$state_type_name, array_name::Symbol, index::Int, field::Symbol)
            push!(getfield(state, :_reads), (array_name, index, field))
        end
    end
    
    notify_write_def = quote
        function notify_write(state::$state_type_name, array_name::Symbol, index::Int, field::Symbol)
            push!(getfield(state, :_writes), (array_name, index, field))
        end
    end
    
    eval(state_def)
    eval(notify_read_def)
    eval(notify_write_def)
    
    return eval(state_type_name)
end

# Implement the required interface functions
function changed(state::ObservedState)
    return Set(getfield(state, :_writes))
end

function wasread(state::ObservedState)
    return Set(getfield(state, :_reads))
end

function accept(state::ObservedState)
    empty!(getfield(state, :_reads))
    empty!(getfield(state, :_writes))
    return state
end

function resetread(state::ObservedState)
    empty!(getfield(state, :_reads))
    return state
end

"""
    ConstructState(specification, counts)

Creates an ObservedState with ObservedVector arrays populated with observable structs.
"""
function ConstructState(specification, counts)
    # Generate element types and create ObservedVectors
    fields = []
    
    for (array_name, field_specs) in specification
        # Create the element type
        struct_name = gensym(string(array_name) * "_type")
        element_type = create_element_type(struct_name, field_specs)
        
        # Get the count for this array
        count = counts[array_name]
        
        # Create ObservedVector
        observed_vec = ObservedVector{element_type}(undef, count)
        observed_vec.array_name = array_name
        
        push!(fields, array_name => observed_vec)
    end
    
    # Create the state type
    field_names = [pair[1] for pair in fields]
    field_types = [typeof(pair[2]) for pair in fields]
    state_type = create_state_type(field_names, field_types)
    
    # Create state instance
    field_values = [pair[2] for pair in fields]
    physical_state = Base.invokelatest(state_type, field_values...)
    
    # Set back-references from vectors to state
    for (array_name, vec) in fields
        vec.physical_state = physical_state
    end
    
    return physical_state
end

end