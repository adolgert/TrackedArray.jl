module External
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


# This version uses a View of the physical state that notifies
# the tracker when a state is read or writte.
# The protocol is how the user says which parts of the physical
# state should be tracked.
function capture_state_changes(f::Function, tracker, physical_view)
    clear_all(tracker)
    result = f(physical_view)
    changes = places_written(tracker)
    return (;result, changes)
end


function capture_state_reads(f::Function, tracker, physical_view)
    clear_read(tracker)
    result = f(physical_view)
    reads = places_read(tracker)
    return (;result, reads)
end


struct TrackedView{S}
    physical::S
    # The specification tells the TrackedView
    #  a) Which structs within the physical state are/aren't tracked.
    #  b) When a particular struct access is at the leaf node of access.
    #     If it's physical.people[i].health, the view needs to know that
    #     health is the last struct member so it can tell the tracker.
    specification
end

# Custom getproperty
# Custom getindex


function ConstructState(obj::PhysicalState, protocol)
    tracker_type = typejoin_to_find_tracker_type(typeof(obj), protocol)
    tracker = Tracker{tracker_type}()
    # The tracked_view will use the type of the physical state
    # and the protocol specified by the user to create a wrapper
    # on the physical object.
    physical_view = TrackedView(physical, protocol, tracker)

    return tracker, physical_view
end


# This is an example of how a simulation step might work internally.
function simulation_step(tracker, physical_view, firing_function)
    res = capture_state_changes(firing_function, tracker, physical_view)
    @assert length(res.changes) > 0
end


end
