"""
This module implements an immutable tracking system using bitfields and structural sharing
for efficient memory usage and functional programming style.
"""
module Dealer
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
import ..TrackedArray: PlaceType

export TrackedVector, ConstructState
export gotten, changed, reset_tracking!, reset_gotten!

# Compact representation of tracking state using bitfields
# Bit 0: read, Bit 1: written
const READ_BIT = UInt8(1)
const WRITE_BIT = UInt8(2)

"""
    TrackingState

Immutable structure holding tracking information for a single array.
Uses a Dict for sparse storage of tracking bits.
"""
struct TrackingState
    bits::Dict{Tuple{Int,Symbol}, UInt8}  # (index, field) => read/write bits
    
    TrackingState() = new(Dict{Tuple{Int,Symbol}, UInt8}())
    TrackingState(bits::Dict) = new(bits)
end

# Functional operations on TrackingState
function mark_read(state::TrackingState, index::Int, field::Symbol)
    new_bits = copy(state.bits)
    key = (index, field)
    new_bits[key] = get(new_bits, key, UInt8(0)) | READ_BIT
    return TrackingState(new_bits)
end

function mark_write(state::TrackingState, index::Int, field::Symbol)
    new_bits = copy(state.bits)
    key = (index, field)
    new_bits[key] = get(new_bits, key, UInt8(0)) | WRITE_BIT
    return TrackingState(new_bits)
end

function get_reads(state::TrackingState)
    result = Set{Tuple{Int,Symbol}}()
    for ((idx, field), bits) in state.bits
        if bits & READ_BIT != 0
            push!(result, (idx, field))
        end
    end
    return result
end

function get_writes(state::TrackingState)
    result = Set{Tuple{Int,Symbol}}()
    for ((idx, field), bits) in state.bits
        if bits & WRITE_BIT != 0
            push!(result, (idx, field))
        end
    end
    return result
end

function clear_all(state::TrackingState)
    return TrackingState()
end

function clear_reads(state::TrackingState)
    new_bits = Dict{Tuple{Int,Symbol}, UInt8}()
    for (key, bits) in state.bits
        new_val = bits & ~READ_BIT
        if new_val != 0
            new_bits[key] = new_val
        end
    end
    return TrackingState(new_bits)
end

"""
    TrackedElement{T}

Wrapper for array elements that intercepts property access.
Immutable except for the physical reference fields.
"""
mutable struct TrackedElement{T}
    const value::T
    const array_ref::Ref{Any}  # Reference to containing array
    const index::Int
end

function Base.getproperty(elem::TrackedElement, field::Symbol)
    if field === :value || field === :array_ref || field === :index
        return getfield(elem, field)
    else
        # Notify array of read access
        arr = elem.array_ref[]
        if arr !== nothing
            notify_element_read(arr, elem.index, field)
        end
        return getproperty(elem.value, field)
    end
end

function Base.setproperty!(elem::TrackedElement, field::Symbol, val)
    if field === :value || field === :array_ref || field === :index
        error("Cannot modify immutable fields of TrackedElement")
    else
        # Notify array of write access
        arr = elem.array_ref[]
        if arr !== nothing
            notify_element_write(arr, elem.index, field)
        end
        setproperty!(elem.value, field, val)
    end
end

Base.:(==)(a::TrackedElement, b::TrackedElement) = a.value == b.value

"""
    DealerVector{T}

Immutable tracked vector that maintains tracking state functionally.
"""
mutable struct DealerVector{T} <: AbstractVector{T}
    const data::Vector{TrackedElement{T}}
    array_name::Symbol
    tracking::TrackingState
    physical_state::Any  # Mutable reference to physical state
    
    function DealerVector{T}(::UndefInitializer, n::Integer) where T
        elements = Vector{TrackedElement{T}}(undef, n)
        arr_ref = Ref{Any}(nothing)
        for i in 1:n
            elements[i] = TrackedElement{T}(Base.invokelatest(T, undef), arr_ref, i)
        end
        vec = new{T}(elements, :unknown, TrackingState(), nothing)
        # Set the array reference for all elements
        for elem in elements
            elem.array_ref[] = vec
        end
        return vec
    end
    
    function DealerVector{T}(::UndefInitializer, n::Integer, name::Symbol) where T
        elements = Vector{TrackedElement{T}}(undef, n)
        arr_ref = Ref{Any}(nothing)
        for i in 1:n
            elements[i] = TrackedElement{T}(Base.invokelatest(T, undef), arr_ref, i)
        end
        vec = new{T}(elements, name, TrackingState(), nothing)
        # Set the array reference for all elements
        for elem in elements
            elem.array_ref[] = vec
        end
        return vec
    end
end

# AbstractArray interface
Base.size(v::DealerVector) = size(v.data)

function Base.getindex(v::DealerVector{T}, i::Integer) where T
    elem = v.data[i].value
    # Set container reference for tracking
    if hasfield(typeof(elem), :_container) && hasfield(typeof(elem), :_index)
        setfield!(elem, :_container, v)
        setfield!(elem, :_index, i)
    end
    return elem
end

function Base.setindex!(v::DealerVector{T}, x, i::Integer) where T
    # Create new element wrapper
    v.data[i] = TrackedElement{T}(x, Ref{Any}(v), i)
    return x
end

# Notification handlers
function notify_element_read(v::DealerVector, index::Int, field::Symbol)
    # Update tracking state immutably
    v.tracking = mark_read(v.tracking, index, field)
    
    # Notify physical state if connected
    if v.physical_state !== nothing
        notify_read(v.physical_state, v.array_name, index, field)
    end
end

function notify_element_write(v::DealerVector, index::Int, field::Symbol)
    # Update tracking state immutably
    v.tracking = mark_write(v.tracking, index, field)
    
    # Notify physical state if connected
    if v.physical_state !== nothing
        notify_write(v.physical_state, v.array_name, index, field)
    end
end

# Tracking interface
function gotten(v::DealerVector)
    return get_reads(v.tracking)
end

function changed(v::DealerVector)
    return get_writes(v.tracking)
end

function reset_tracking!(v::DealerVector)
    v.tracking = clear_all(v.tracking)
    return v
end

function reset_gotten!(v::DealerVector)
    v.tracking = clear_reads(v.tracking)
    return v
end

# Property access
function Base.getproperty(v::DealerVector, field::Symbol)
    if field in (:data, :array_name, :tracking, :physical_state)
        return getfield(v, field)
    else
        error("Field $field not found in DealerVector")
    end
end

function Base.setproperty!(v::DealerVector, field::Symbol, value)
    if field === :tracking || field === :physical_state
        setfield!(v, field, value)
    elseif field === :array_name
        setfield!(v, field, value)
    else
        error("Cannot set field $field in DealerVector")
    end
end

# Alias for compatibility
const TrackedVector = DealerVector

"""
    DealerState

Physical state with centralized tracking using immutable data structures.
"""
abstract type DealerState <: PhysicalState end

# These will be implemented by the generated state types
function notify_read end
function notify_write end

"""
    create_element_type(name, fields)

Creates a mutable struct type for array elements with tracking support.
"""
function create_element_type(type_name::Symbol, fields::Vector)
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in fields]
    field_names = [f[1] for f in fields]
    
    struct_def = quote
        mutable struct $type_name
            $(field_defs...)
            _container::Union{Nothing, DealerVector}
            _index::Union{Nothing, Int}
            
            # Constructor for normal initialization
            function $type_name($([fname for fname in field_names]...))
                new($([fname for fname in field_names]...), nothing, nothing)
            end
            
            # Constructor for undef initialization
            function $type_name(::UndefInitializer)
                new()
            end
        end
    end
    
    # Create getproperty that tracks reads
    getprop_def = quote
        function Base.getproperty(obj::$type_name, field::Symbol)
            if field in (:_container, :_index)
                return getfield(obj, field)
            else
                container = getfield(obj, :_container)
                if container !== nothing && getfield(obj, :_index) !== nothing
                    notify_element_read(container, getfield(obj, :_index), field)
                end
                return getfield(obj, field)
            end
        end
    end
    
    # Create setproperty that tracks writes
    setprop_def = quote
        function Base.setproperty!(obj::$type_name, field::Symbol, value)
            if field in (:_container, :_index)
                setfield!(obj, field, value)
            else
                container = getfield(obj, :_container)
                if container !== nothing && getfield(obj, :_index) !== nothing
                    notify_element_write(container, getfield(obj, :_index), field)
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
    
    # Create a simple equality operator
    eq_comparisons = [:(getproperty(a, $(QuoteNode(fname))) == getproperty(b, $(QuoteNode(fname)))) for fname in field_names]
    eq_expr = length(eq_comparisons) > 0 ? Expr(:&&, eq_comparisons...) : true
    
    eq_def = quote
        Base.:(==)(a::$type_name, b::$type_name) = $eq_expr
    end
    
    eval(struct_def)
    eval(getprop_def)
    eval(setprop_def)
    eval(propnames_def)
    eval(eq_def)
    
    return eval(type_name)
end

"""
    ConstructState(specification, counts)

Creates a DealerState with tracked arrays.
"""
function ConstructState(specification, counts)
    # Create arrays
    arrays = []
    field_names = Symbol[]
    field_types = []
    
    for (array_name, field_specs) in specification
        # Create element type
        type_name = gensym(string(array_name) * "_type")
        element_type = create_element_type(type_name, field_specs)
        
        # Create tracked vector
        count = counts[array_name]
        vec = DealerVector{element_type}(undef, count, array_name)
        
        push!(arrays, vec)
        push!(field_names, array_name)
        push!(field_types, DealerVector{element_type})
    end
    
    # Create a custom state type
    state_type_name = gensym("DealerState")
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in zip(field_names, field_types)]
    
    state_def = quote
        mutable struct $state_type_name <: DealerState
            $(field_defs...)
            _reads::Set{PlaceType}
            _writes::Set{PlaceType}
            
            function $state_type_name($(field_names...))
                new($(field_names...), Set{PlaceType}(), Set{PlaceType}())
            end
        end
    end
    
    # Create property access methods
    getprop_def = quote
        function Base.getproperty(s::$state_type_name, field::Symbol)
            if field === :_reads || field === :_writes
                return getfield(s, field)
            else
                return getfield(s, field)
            end
        end
    end
    
    # Create notification methods for this specific type
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
    
    # Create interface methods
    changed_def = quote
        changed(state::$state_type_name) = getfield(state, :_writes)
    end
    
    wasread_def = quote
        wasread(state::$state_type_name) = getfield(state, :_reads)
    end
    
    accept_def = quote
        function accept(state::$state_type_name)
            empty!(getfield(state, :_reads))
            empty!(getfield(state, :_writes))
            return state
        end
    end
    
    resetread_def = quote
        function resetread(state::$state_type_name)
            empty!(getfield(state, :_reads))
            return state
        end
    end
    
    # Evaluate all definitions
    eval(state_def)
    eval(getprop_def)
    eval(notify_read_def)
    eval(notify_write_def)
    eval(changed_def)
    eval(wasread_def)
    eval(accept_def)
    eval(resetread_def)
    
    # Create state instance
    state = Base.invokelatest(eval(state_type_name), arrays...)
    
    # Connect arrays to state
    for (i, vec) in enumerate(arrays)
        vec.physical_state = state
    end
    
    return state
end

end