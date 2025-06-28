"""
This module implements an "Arithmetic Registry" tracking system.
- At construction, it lays out all trackable places contiguously in memory
  and builds a reverse mapping from an integer index to a place identifier.
- Read/write status for all places is stored in two large, pre-allocated
  BitVectors.
- Accessing an element's field triggers a fast arithmetic calculation to find
  the correct bit to flip in the BitVector, avoiding a slow global dictionary
  lookup.
- This design has a higher upfront cost but provides extremely fast tracking, querying, and state-reset operations.
"""
module Secondary
import ..TrackedArray: accept, changed, resetread, wasread, PhysicalState, PlaceType

export TrackedVector, ConstructState
# For compatibility, export the vector-level functions, though they are no-ops.
export gotten, changed, reset_tracking!, reset_gotten!

# Forward declarations for notification methods
function notify_read end
function notify_write end

"""
    SecondaryVector{T}

A vector that notifies a central state when its elements are accessed.
It holds a reference to the parent state and its own array name.
"""
mutable struct SecondaryVector{T} <: AbstractVector{T}
    data::Vector{T}
    array_name::Symbol
    physical_state::Any # Will be set to the actual physical state by ConstructState
    base_idx::Int       # 0-based index for the start of this vector's data in the global BitVector
    field_map::Dict{Symbol, Int} # Maps field name to a 0-based offset
    num_fields::Int     # The number of tracked fields in each element

    function SecondaryVector{T}(::UndefInitializer, n::Integer) where T
        # Remaining fields are initialized by ConstructState
        new{T}(Vector{T}(undef, n), :unknown, nothing, 0, Dict{Symbol,Int}(), 0)
    end
end

# --- AbstractArray Interface ---
Base.size(v::SecondaryVector) = size(v.data)

function Base.getindex(v::SecondaryVector{T}, i::Integer) where T
    @boundscheck checkbounds(v.data, i)
    element = v.data[i]
    # Set back-references on the element. This is crucial for notifications.
    # We can skip `hasfield` checks as we control the element's type generation.
    setfield!(element, :_container, v)
    setfield!(element, :_index, i)
    return element
end

function Base.setindex!(v::SecondaryVector{T}, x, i::Integer) where T
    @boundscheck checkbounds(v.data, i)
    v.data[i] = x
    setfield!(x, :_container, v)
    setfield!(x, :_index, i)
    return x
end

# --- Notification Forwarding ---
function notify_element_read(v::SecondaryVector, index::Int, field::Symbol)
    if v.physical_state !== nothing
        field_offset = get(v.field_map, field, -1)
        if field_offset != -1
            bit_idx = v.base_idx + (index - 1) * v.num_fields + field_offset + 1
            notify_read(v.physical_state, bit_idx)
        end
    end
end

function notify_element_write(v::SecondaryVector, index::Int, field::Symbol)
    if v.physical_state !== nothing
        field_offset = get(v.field_map, field, -1)
        if field_offset != -1
            bit_idx = v.base_idx + (index - 1) * v.num_fields + field_offset + 1
            notify_write(v.physical_state, bit_idx)
        end
    end
end

# --- Compatibility Stubs ---
# In this "push" model, tracking is centralized in the state object, not the
# vector. These functions are no-ops for API compatibility.
gotten(v::SecondaryVector) = Set{Tuple}()
changed(v::SecondaryVector) = Set{Tuple}()
reset_tracking!(v::SecondaryVector) = v
reset_gotten!(v::SecondaryVector) = v

# Alias for compatibility with benchmark code
const TrackedVector = SecondaryVector

"""
    create_element_type(name, fields)

Dynamically creates a mutable struct definition for array elements.
The generated struct will have the specified data fields plus internal fields
`_container` and `_index` for notifications. It also overloads `getproperty`
and `setproperty!` to trigger the notification mechanism.
"""
function create_element_type(type_name::Symbol, fields::Vector)
    field_defs = [Expr(:(::), fname, ftype) for (fname, ftype) in fields]
    field_names = [f[1] for f in fields]

    struct_def = quote
        mutable struct $type_name
            $(field_defs...)
            _container::Union{Nothing, SecondaryVector}
            _index::Union{Nothing, Int}

            # Constructor for full initialization
            function $type_name($([fname for fname in field_names]...))
                new($([fname for fname in field_names]...), nothing, nothing)
            end
            # Constructor for `undef` initialization
            function $type_name(::UndefInitializer)
                new()
            end
        end
    end

    # Overload getproperty to notify on read
    getprop_def = quote
        function Base.getproperty(obj::$type_name, field::Symbol)
            if field in (:_container, :_index)
                return getfield(obj, field)
            else
                container = getfield(obj, :_container)
                if container !== nothing
                    notify_element_read(container, getfield(obj, :_index), field)
                end
                return getfield(obj, field)
            end
        end
    end

    # Overload setproperty! to notify on write
    setprop_def = quote
        function Base.setproperty!(obj::$type_name, field::Symbol, value)
            if field in (:_container, :_index)
                setfield!(obj, field, value)
            else
                container = getfield(obj, :_container)
                if container !== nothing
                    notify_element_write(container, getfield(obj, :_index), field)
                end
                setfield!(obj, field, value)
            end
        end
    end

    # Hide internal fields from `propertynames`
    propnames_def = quote
        function Base.propertynames(obj::$type_name, private::Bool=false)
            private ? fieldnames($type_name) : tuple($(map(QuoteNode, field_names)...))
        end
    end

    # Equality should only compare data fields
    eq_comparisons = [:(a.$fname == b.$fname) for fname in field_names]
    eq_expr = !isempty(eq_comparisons) ? Expr(:&&, eq_comparisons...) : true
    eq_def = quote
        Base.:(==)(a::$type_name, b::$type_name) = $eq_expr
    end

    # Evaluate all definitions in the module's scope
    @eval begin
        $struct_def
        $getprop_def
        $setprop_def
        $propnames_def
        $eq_def
    end

    return @eval($type_name)
end


"""
    SecondaryState

An abstract type for the physical state in the Registry model.
"""
abstract type SecondaryState <: PhysicalState end

"""
    ConstructState(specification, counts)

Creates a `PhysicalState` instance using the Registry (Bit-Array) model.
This involves dynamically generating a concrete state type and its associated
element types, and pre-calculating the mapping from places to bit indices.
"""
function ConstructState(specification, counts)
    # --- 1. Build Mappings and Calculate Layout ---
    total_places = sum(length(field_specs) * counts[arr_name] for (arr_name, field_specs) in specification)
    reverse_map = Vector{PlaceType}(undef, total_places)
    
    vectors = []
    state_field_names = Symbol[]
    state_field_types = []
    
    current_base_idx = 0

    for (array_name, field_specs) in specification
        num_elements = counts[array_name]
        num_fields = length(field_specs)

        # Create field_map for this vector type
        local_field_map = Dict{Symbol, Int}()
        sizehint!(local_field_map, num_fields)

        # Populate reverse_map and local_field_map
        for (field_idx, (field_name, _)) in enumerate(field_specs)
            field_offset = field_idx - 1 # 0-based
            local_field_map[field_name] = field_offset
            for elem_idx in 1:num_elements
                # bit_idx is 1-based
                bit_idx = current_base_idx + (elem_idx - 1) * num_fields + field_offset + 1
                reverse_map[bit_idx] = (array_name, elem_idx, field_name)
            end
        end

        # --- 2. Generate Types and Create Vector ---
        # Dynamically create the struct type for the elements of this array
        element_type_name = gensym(string(array_name) * "_type")
        element_type = create_element_type(element_type_name, field_specs)

        # Create the vector for this array
        vec = SecondaryVector{element_type}(undef, num_elements)
        vec.array_name = array_name
        vec.base_idx = current_base_idx
        vec.field_map = local_field_map
        vec.num_fields = num_fields

        push!(vectors, vec)
        push!(state_field_names, array_name)
        push!(state_field_types, typeof(vec))

        # Update base index for the next array
        current_base_idx += num_elements * num_fields
    end

    # --- 3. Dynamically Generate the State Struct and its Methods ---
    state_type_name = gensym("SecondaryState")
    state_field_defs = [Expr(:(::), name, type) for (name, type) in zip(state_field_names, state_field_types)]

    # The state struct holds the arrays and the tracking machinery
    state_def = quote
        mutable struct $state_type_name <: SecondaryState
            $(state_field_defs...)
            const _reverse_map::Vector{PlaceType}
            _reads::BitVector
            _writes::BitVector

            function $state_type_name($(state_field_names...), rev_map, reads, writes)
                new($(state_field_names...), rev_map, reads, writes)
            end
        end
    end

    # Notification methods that operate on this specific state type
    notify_read_def = quote
        function notify_read(state::$state_type_name, bit_idx::Int)
            if 1 <= bit_idx <= length(state._reads)
                state._reads[bit_idx] = true
            end
        end
    end

    notify_write_def = quote
        function notify_write(state::$state_type_name, bit_idx::Int)
            if 1 <= bit_idx <= length(state._writes)
                state._writes[bit_idx] = true
            end
        end
    end

    # Interface methods
    changed_def = quote
        function changed(state::$state_type_name)
            # findall is efficient on BitVectors
            indices = findall(state._writes)
            # Use the pre-computed reverse map to build the result set
            return Set(state._reverse_map[i] for i in indices)
        end
    end

    wasread_def = quote
        function wasread(state::$state_type_name)
            indices = findall(state._reads)
            return Set(state._reverse_map[i] for i in indices)
        end
    end

    accept_def = quote
        function accept(state::$state_type_name)
            # fill! is a very fast operation on BitVectors
            fill!(state._reads, false)
            fill!(state._writes, false)
            return state
        end
    end

    resetread_def = quote
        function resetread(state::$state_type_name)
            fill!(state._reads, false)
            return state
        end
    end

    # Evaluate all the generated definitions
    @eval begin
        $state_def
        $notify_read_def
        $notify_write_def
        $changed_def
        $wasread_def
        $accept_def
        $resetread_def
    end
    
    # --- 4. Instantiate and Connect Everything ---
    state_type = @eval($state_type_name)
    
    # Prepare arguments for the state constructor
    read_bits = falses(total_places)
    write_bits = falses(total_places)
    constructor_args = (vectors..., reverse_map, read_bits, write_bits)
    
    # Use invokelatest for type stability with dynamically generated types
    physical_state = Base.invokelatest(state_type, constructor_args...)

    # Set the back-reference from each vector to the state object
    for vec in vectors
        vec.physical_state = physical_state
    end

    return physical_state
end

end # module Secondary