"""
This module provides tools for tracking access to and changes of data structures.
It includes a macro for creating structs that track access and a vector type that
tracks changes to its elements.

There are two approaches to tracking changes to elements of a vector.

 1. Each element of the vector contains a pointer to the owning vector
    and notifies it when there was a change.

 2. The vector trackes which elements were read and, when asked what
    changed, checkes each element that was read to see if it was also
    modified.
    
"""
module Doubles
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState
using MacroTools

export @tracked_struct, TrackedVector, ConstructState
export gotten, changed, reset_tracking!, reset_gotten!

"""
    @tracked_struct Name begin
        field1::Type1
        field2::Type2
        # ...
    end

Creates a struct that tracks when its fields are accessed or modified.
"""
macro tracked_struct(typename, body)
    @assert body.head == :block "Expected a block for struct body"
    
    fields = []
    for expr in body.args
        if expr isa LineNumberNode
            continue
        elseif expr isa Expr && expr.head == :(::)
            push!(fields, expr)
        end
    end
    
    fieldnames = [field.args[1] for field in fields]
    fieldtypes = [field.args[2] for field in fields]
    
    # Escape field definitions to evaluate in calling module context
    escaped_fields = [Expr(:(::), esc(field.args[1]), esc(field.args[2])) for field in fields]
    escaped_fieldnames = [esc(fname) for fname in fieldnames]
    
    # Create tracking fields for each data field
    track_fields = [Expr(:(::), Symbol(string(fname) * "_track"), Int) for fname in fieldnames]
    escaped_track_fields = [Expr(:(::), esc(Symbol(string(fname) * "_track")), Int) for fname in fieldnames]
    
    # Create the internal struct
    struct_def = quote
        mutable struct $(esc(typename))
            $(escaped_fields...)
            $(escaped_track_fields...)
            _container::Union{Nothing, Any}
            _index::Union{Nothing, Int}
            
            function $(esc(typename))($(escaped_fieldnames...))
                return new($(escaped_fieldnames...), $(zeros(Int, length(fieldnames))...), nothing, nothing)
            end
        end
    end
    
    # Create list of tracking field names for exclusion
    track_field_names = [Symbol(string(fname) * "_track") for fname in fieldnames]
    all_internal_fields = [:_container, :_index, track_field_names...]
    
    getprop_def = quote
        function Base.getproperty(obj::$(esc(typename)), field::Symbol)
            if field in $(all_internal_fields)
                return getfield(obj, field)
            else
                # Update tracking field
                track_field = Symbol(string(field) * "_track")
                current = getfield(obj, track_field)
                setfield!(obj, track_field, current | 1)  # Set read bit
                return getfield(obj, field)
            end
        end
    end
    
    setprop_def = quote
        function Base.setproperty!(obj::$(esc(typename)), field::Symbol, value)
            if field in $(all_internal_fields)
                setfield!(obj, field, value)
            else
                # Update tracking field
                track_field = Symbol(string(field) * "_track")
                current = getfield(obj, track_field)
                setfield!(obj, track_field, current | 2)  # Set write bit
                setfield!(obj, field, value)
            end
        end
    end
    
    propnames_def = quote
        function Base.propertynames(obj::$(esc(typename)), private::Bool=false)
            if private
                return fieldnames($(esc(typename)))
            else
                return $(fieldnames)
            end
        end
    end
    
    # Define equality comparison properly  
    field_comparisons = [:(getproperty(a, $(QuoteNode(fname))) == getproperty(b, $(QuoteNode(fname)))) for fname in fieldnames]
    eq_expr = Expr(:&&, field_comparisons...)
    
    eq_def = quote
        function Base.:(==)(a::$(esc(typename)), b::$(esc(typename)))
            $eq_expr
        end
    end
    
    # Create constants for the field lists to avoid runtime computation
    const_def = quote
        const $(esc(Symbol(string(typename) * "_DATA_FIELDS"))) = $(fieldnames)
        const $(esc(Symbol(string(typename) * "_TRACK_FIELDS"))) = $(track_field_names)
    end
    
    return quote
        $(struct_def)
        $(getprop_def)
        $(setprop_def)
        $(propnames_def)
        $(eq_def)
        $(const_def)
    end
end

"""
    TrackedVector{T}

A vector that tracks access and changes to its elements.
"""
struct TrackedVector{T} <: AbstractVector{T}
    data::Vector{T}
    _accessed::Set{Int}
    
    function TrackedVector{T}(::UndefInitializer, n::Integer) where T
        return new{T}(Vector{T}(undef, n), Set{Int}())
    end
    
    function TrackedVector{T}(v::Vector{T}) where T
        return new{T}(v, Set{Int}())
    end
end

# Implement AbstractArray interface
Base.size(v::TrackedVector) = size(v.data)
Base.getindex(v::TrackedVector{T}, i::Integer) where T = begin
    push!(v._accessed, i)
    element = v.data[i]
    if hasfield(typeof(element), :_container)
        setfield!(element, :_container, v)
        setfield!(element, :_index, i)
    end
    element
end

Base.setindex!(v::TrackedVector{T}, x, i::Integer) where T = begin
    v.data[i] = x
    if hasfield(typeof(x), :_container)
        setfield!(x, :_container, v)
        setfield!(x, :_index, i)
    end
    x
end

# Track property access on elements
function Base.getproperty(v::TrackedVector, field::Symbol)
    if field in (:data, :_accessed)
        return getfield(v, field)
    else
        error("Field $field not found in TrackedVector")
    end
end

function Base.setproperty!(v::TrackedVector, field::Symbol, value)
    if field in (:data, :_accessed)
        setfield!(v, field, value)
    else
        error("Cannot set field $field in TrackedVector")
    end
end

"""
    gotten(obj)

Returns the set of fields that have been accessed.
"""
function gotten(obj::TrackedVector)
    result = Set{Tuple}()
    if isempty(obj._accessed)
        return result
    end
    
    # Get data field names by filtering fieldnames (optimized for performance)
    element = obj.data[first(obj._accessed)]
    element_type = typeof(element)
    all_fields = fieldnames(element_type)
    data_fields = [f for f in all_fields if !endswith(string(f), "_track") && f ∉ (:_container, :_index)]
    
    for i in obj._accessed
        element = obj.data[i]
        for field in data_fields
            track_field = Symbol(string(field) * "_track")
            track_value = getfield(element, track_field)
            if track_value & 1 != 0  # Read bit is set
                push!(result, (i, field))
            end
        end
    end
    result
end

"""
    changed(obj)

Returns the set of fields that have been modified.
"""
function changed(obj::TrackedVector)
    result = Set{Tuple}()
    if isempty(obj._accessed)
        return result
    end
    
    # Get data field names by filtering fieldnames (optimized for performance)
    element = obj.data[first(obj._accessed)]
    element_type = typeof(element)
    all_fields = fieldnames(element_type)
    data_fields = [f for f in all_fields if !endswith(string(f), "_track") && f ∉ (:_container, :_index)]
    
    for i in obj._accessed
        element = obj.data[i]
        for field in data_fields
            track_field = Symbol(string(field) * "_track")
            track_value = getfield(element, track_field)
            if track_value & 2 != 0  # Write bit is set
                push!(result, (i, field))
            end
        end
    end
    result
end

"""
    reset_tracking!(obj)

Reset all tracking information.
"""
function reset_tracking!(obj::TrackedVector)
    empty!(obj._accessed)
    if !isempty(obj.data)
        # Get data field names by filtering fieldnames (optimized for performance)
        element_type = eltype(obj)
        all_fields = fieldnames(element_type)
        data_fields = [f for f in all_fields if !endswith(string(f), "_track") && f ∉ (:_container, :_index)]
        
        for element in obj.data
            # Reset all tracking fields to 0
            for field in data_fields
                track_field = Symbol(string(field) * "_track")
                setfield!(element, track_field, 0)
            end
        end
    end
    obj
end

"""
    reset_gotten!(obj)

Reset the tracking of accessed fields.
"""
function reset_gotten!(obj::TrackedVector)
    if !isempty(obj.data)
        # Get data field names by filtering fieldnames (optimized for performance)
        element_type = eltype(obj)
        all_fields = fieldnames(element_type)
        data_fields = [f for f in all_fields if !endswith(string(f), "_track") && f ∉ (:_container, :_index)]
        
        for element in obj.data
            # Reset only the read bit (bit 1), keep write bit (bit 2)
            for field in data_fields
                track_field = Symbol(string(field) * "_track")
                current = getfield(element, track_field)
                setfield!(element, track_field, current & 2)  # Keep only write bit
            end
        end
    end
    obj
end

# Helper function to check if property exists
function hasproperty(obj, prop::Symbol)
    return prop in fieldnames(typeof(obj))
end


abstract type TrackedState <: PhysicalState end

"""
Iterate over all tracked vectors in the physical state.
"""
function over_tracked_physical_state(fcallback::Function, physical::T) where {T <: TrackedState}
    for field_symbol in fieldnames(T)
        member = getproperty(physical, field_symbol)
        if isa(member, TrackedVector)
            fcallback(field_symbol, member)
        end
    end
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function changed(physical::TrackedState)
    places = Set{Tuple}()
    over_tracked_physical_state(physical) do fieldname, member
        union!(places, [(fieldname, key...) for key in changed(member)])
    end
    return places
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function wasread(physical::TrackedState)
    places = Set{Tuple}()
    over_tracked_physical_state(physical) do fieldname, member
        union!(places, [(fieldname, key...) for key in gotten(member)])
    end
    return places
end

"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function resetread(physical::TrackedState)
    over_tracked_physical_state(physical) do _, member
        reset_gotten!(member)
    end
    return physical
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::TrackedState)
    over_tracked_physical_state(physical) do _, member
        reset_tracking!(member)
    end
    return physical
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