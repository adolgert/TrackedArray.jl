# Individual trackable lines

  Implementation Strategy:

  # 1. Core tracking registry (global state)
  const TRACKING_REGISTRY = Dict{Type, Vector{TrackedFieldSpec}}()

  struct TrackedFieldSpec
      name::Symbol
      original_type::Type
      cuddle_type::Type
      size_spec::Any
      options::Dict{Symbol,Any}
  end

  # 2. Base @trackable macro - minimal, extensible
  macro trackable(struct_def)
      # Extract struct info
      struct_info = parse_struct(struct_def)

      # Process @tracked annotations 
      tracked_fields = process_tracked_annotations!(struct_info)

      # Register for other macros to find
      register_tracked_fields!(struct_info.name, tracked_fields)

      # Transform struct (but leave room for other transformations)
      transformed_struct = transform_trackable_struct(struct_info, tracked_fields)

      esc(quote
          $transformed_struct
          # Export constructor generation function for other macros
          __generate_tracking_constructor(::Type{$(struct_info.name)}) = $(generate_constructor_expr(struct_info.name))
      end)
  end

  # 3. Field annotation processor
  macro tracked(field_expr)
      # Mark this field for tracking - store in AST metadata
      field_info = parse_tracked_field(field_expr)
      return Expr(:tracked_field, field_info...)
  end

# A protocol-based strategy

Option 3: True Protocol-Based (Most Flexible)

  # Define the protocol/trait
  abstract type TrackingProtocol end

  # User's struct remains clean
  struct CarPhysical
      fleet::Vector{Car}
      garage::Matrix{Car}
      params::Dict{Symbol,Float64}
  end

  # Tracking specification is separate
  struct CarPhysicalTracking <: TrackingProtocol
      tracked_fields::Dict{Symbol,FieldSpec}

      function CarPhysicalTracking()
          new(Dict(
              :fleet => FieldSpec(Vector{Car}, (100,), true),
              :garage => FieldSpec(Matrix{Car}, (10, 5), true),
              :params => FieldSpec(Dict{Symbol,Float64}, (), false)
          ))
      end
  end

  # Factory function creates the tracked version
  function create_tracked_state(::Type{CarPhysical}, tracking::CarPhysicalTracking)
      # Dynamically generate type name
      tracked_type_name = Symbol("Tracked", nameof(CarPhysical))

      # Build field definitions based on tracking spec
      field_defs = []
      for (fname, spec) in tracking.tracked_fields
          if spec.is_tracked
              cuddle_type = build_cuddle_type(spec)
              push!(field_defs, :($fname::$cuddle_type))
          else
              push!(field_defs, :($fname::$(spec.type)))
          end
      end

      # Generate the tracked type
      @eval begin
          struct $tracked_type_name <: PhysicalState
              _tracker::Tracker{PlaceKey}
              $(field_defs...)
          end
      end

      # Return constructor
      return (args...) -> build_instance($tracked_type_name, tracking, args...)
  end

  # Usage:
  tracking_spec = CarPhysicalTracking()
  TrackedCarPhysical = create_tracked_state(CarPhysical, tracking_spec)
  state = TrackedCarPhysical()

  Option 4: Registration + Code Generation (Recommended)

  # Step 1: User defines simple struct
  struct CarPhysical
      fleet::Vector{Car}
      garage::Matrix{Car}
      params::Dict{Symbol,Float64}
  end

  # Step 2: Register tracking in a declarative way
  @tracking_for CarPhysical begin
      @tracked :fleet => Vector{Car}[100]
      @tracked :garage => Matrix{Car}[10, 5]
      @untracked :params
  end

  # Step 3: Generate tracked version when needed
  @generate_tracked_type TrackedCarPhysical CarPhysical

  # This generates:
  struct TrackedCarPhysical <: CuddleState
      _tracker::Tracker{PlaceKey}
      fleet::Vector{Cuddle{Car,Tuple{Symbol,Int},PlaceKey}}
      garage::Matrix{Cuddle{Car,Tuple{Symbol,Int,Int},PlaceKey}}
      params::Dict{Symbol,Float64}

      function TrackedCarPhysical(; fleet_size=100, garage_dims=(10,5))
          tracker = Tracker{PlaceKey}()
          fleet = cuddle_array(Car, fleet_size, :fleet, tracker)
          garage = cuddle_array(Car, garage_dims, :garage, tracker)
          params = Dict{Symbol,Float64}()
          new(tracker, fleet, garage, params)
      end
  end

  Why Protocol-Based is Powerful:

  1. Separation of Concerns: The data model (CarPhysical) is separate from tracking behavior
  2. Multiple Protocols: Can apply different tracking strategies to the same type
  3. Clean User Types: User's structs remain simple and unaware of tracking
  4. Flexible Generation: Can generate different tracked versions for different use cases
  5. Extensible: Other protocols can be layered on top

  The key insight is that the protocol approach doesn't modify the original type but instead provides a way to generate tracked versions based
  on specifications. This is particularly powerful for users who want to:
  - Keep their domain models clean
  - Apply different tracking strategies in different contexts
  - Build their own DSLs on top of the tracking system

# Adding a simple way to create this while using protocols

Option 3: True Protocol-Based (Most Flexible)

  # Define the protocol/trait
  abstract type TrackingProtocol end

  # User's struct remains clean
  struct CarPhysical
      fleet::Vector{Car}
      garage::Matrix{Car}
      params::Dict{Symbol,Float64}
  end

  # Tracking specification is separate
  struct CarPhysicalTracking <: TrackingProtocol
      tracked_fields::Dict{Symbol,FieldSpec}

      function CarPhysicalTracking()
          new(Dict(
              :fleet => FieldSpec(Vector{Car}, (100,), true),
              :garage => FieldSpec(Matrix{Car}, (10, 5), true),
              :params => FieldSpec(Dict{Symbol,Float64}, (), false)
          ))
      end
  end

  # Factory function creates the tracked version
  function create_tracked_state(::Type{CarPhysical}, tracking::CarPhysicalTracking)
      # Dynamically generate type name
      tracked_type_name = Symbol("Tracked", nameof(CarPhysical))

      # Build field definitions based on tracking spec
      field_defs = []
      for (fname, spec) in tracking.tracked_fields
          if spec.is_tracked
              cuddle_type = build_cuddle_type(spec)
              push!(field_defs, :($fname::$cuddle_type))
          else
              push!(field_defs, :($fname::$(spec.type)))
          end
      end

      # Generate the tracked type
      @eval begin
          struct $tracked_type_name <: PhysicalState
              _tracker::Tracker{PlaceKey}
              $(field_defs...)
          end
      end

      # Return constructor
      return (args...) -> build_instance($tracked_type_name, tracking, args...)
  end

  # Usage:
  tracking_spec = CarPhysicalTracking()
  TrackedCarPhysical = create_tracked_state(CarPhysical, tracking_spec)
  state = TrackedCarPhysical()

  Option 4: Registration + Code Generation (Recommended)

  # Step 1: User defines simple struct
  struct CarPhysical
      fleet::Vector{Car}
      garage::Matrix{Car}
      params::Dict{Symbol,Float64}
  end

  # Step 2: Register tracking in a declarative way
  @tracking_for CarPhysical begin
      @tracked :fleet => Vector{Car}[100]
      @tracked :garage => Matrix{Car}[10, 5]
      @untracked :params
  end

  # Step 3: Generate tracked version when needed
  @generate_tracked_type CarPhysical

  # This generates:
  struct TrackedCarPhysical <: CuddleState
      _tracker::Tracker{PlaceKey}
      fleet::CuddleVector{Cuddle{Car,Tuple{Symbol,Int},PlaceKey}}
      garage::CuddleMatrix{Cuddle{Car,Tuple{Symbol,Int,Int},PlaceKey}}
      params::Dict{Symbol,Float64}

      function TrackedCarPhysical(; fleet_size=100, garage_dims=(10,5))
          tracker = Tracker{PlaceKey}()
          fleet = cuddle_array(Car, fleet_size, :fleet, tracker)
          garage = cuddle_array(Car, garage_dims, :garage, tracker)
          params = Dict{Symbol,Float64}()
          new(tracker, fleet, garage, params)
      end
  end

  Why Protocol-Based is Powerful:

  1. Separation of Concerns: The data model (CarPhysical) is separate from tracking behavior
  2. Multiple Protocols: Can apply different tracking strategies to the same type
  3. Clean User Types: User's structs remain simple and unaware of tracking
  4. Flexible Generation: Can generate different tracked versions for different use cases
  5. Extensible: Other protocols can be layered on top

  The key insight is that the protocol approach doesn't modify the original type but instead provides a way to generate tracked versions based
  on specifications. This is particularly powerful for users who want to:
  - Keep their domain models clean
  - Apply different tracking strategies in different contexts
  - Build their own DSLs on top of the tracking system
Absolutely! Let's create a streamlined approach that makes "simple things simple" while keeping the power of the protocol-based system. Here's
   a unified design:

  Simple One-Step Construction

  The Simple API: @tracked_state macro

  # Simple case: One macro does everything
  @tracked_state struct CarPhysical
      fleet::Vector{Car}[100]           # Auto-tracked: size specified
      garage::Matrix{Car}[10, 5]        # Auto-tracked: multi-dimensional
      lookup::Dict{String,Car}          # Auto-tracked: no size = dynamic
      params::Dict{Symbol,Float64}      # Untracked: primitive values
      temperature::Float64 = 20.0       # Untracked with default
  end

  # This single macro:
  # 1. Creates the original CarPhysical struct
  # 2. Registers tracking protocol
  # 3. Generates TrackedCarPhysical
  # 4. Creates convenient constructors

  Implementation that Builds on Protocol System

  macro tracked_state(struct_def)
      # Parse the struct definition
      name, fields, parent = parse_struct_def(struct_def)

      # Step 1: Create the simple struct
      simple_struct = create_simple_struct(name, fields, parent)

      # Step 2: Auto-detect what should be tracked
      tracking_spec = auto_detect_tracking(fields)

      # Step 3: Register the protocol
      protocol_registration = register_tracking_protocol(name, tracking_spec)

      # Step 4: Generate tracked version
      tracked_struct = generate_tracked_struct(name, tracking_spec)

      # Step 5: Convenience constructors
      constructors = generate_convenience_constructors(name, tracking_spec)

      esc(quote
          # Original simple struct
          $simple_struct

          # Protocol registration
          $protocol_registration

          # Tracked version
          $tracked_struct

          # Convenience constructors
          $constructors

          # Export both versions
          export $name, $(Symbol("Tracked", name))
      end)
  end

  # Auto-detection rules
  function auto_detect_tracking(fields)
      tracked = []
      untracked = []

      for field in fields
          if should_track(field.type)
              push!(tracked, field)
          else
              push!(untracked, field)
          end
      end

      return (tracked=tracked, untracked=untracked)
  end

  should_track(::Type{<:AbstractArray}) = true
  should_track(::Type{<:AbstractDict}) = true
  should_track(::Type{<:Number}) = false
  should_track(::Type{<:AbstractString}) = false
  should_track(T) = ismutabletype(T)  # Track mutable structs by default

  Convenience Constructors

  # Generated constructor examples:

  # 1. Default constructor using specification sizes
  car_sim = TrackedCarPhysical()  # Uses [100] and [10,5] from definition

  # 2. Override sizes
  car_sim = TrackedCarPhysical(fleet_size=50, garage_dims=(5,3))

  # 3. Copy from simple version
  simple = CarPhysical(fleet, garage, params, temp)
  tracked = TrackedCarPhysical(simple)  # Auto-converts

  # 4. Builder pattern
  tracked = TrackedCarPhysical() do state
      # Initialize with custom logic
      for i in 1:100
          state.fleet[i] = Car(wheels=4, cargo=0)
      end
  end

  Progressive Complexity: When Simple Isn't Enough

  # Level 1: Simplest case (auto-detect everything)
  @tracked_state struct Model1
      agents::Vector{Agent}[1000]
      grid::Matrix{Cell}[100, 100]
      time::Float64
  end

  # Level 2: Explicit tracking control
  @tracked_state struct Model2
      @tracked agents::Vector{Agent}[1000]
      @tracked grid::Matrix{Cell}[100, 100]
      @untracked time::Float64
      @untracked config::Config
  end

  # Level 3: Advanced options
  @tracked_state struct Model3
      @tracked(history=true) agents::Vector{Agent}[1000]
      @tracked(sparse=true) grid::Matrix{Cell}[100, 100]
      @parameter temp::Float64 = 20.0
      @computed total_agents() = length(agents)
  end

  # Level 4: Full protocol control (original approach)
  struct Model4
      agents::Vector{Agent}
      grid::Matrix{Cell}
  end

  @tracking_protocol Model4 begin
      # Full control over tracking behavior
      @track :agents => CuddleVector{Agent}(
          size = 1000,
          notify = [:create, :delete, :modify],
          history = CircularBuffer(100)
      )
  end

  Making it Work with User DSLs

  # The simple macro is actually sugar for the protocol system
  @tracked_state struct CarPhysical ... end

  # Expands to:
  begin
      # 1. Original struct
      struct CarPhysical
          fleet::Vector{Car}
          garage::Matrix{Car}
          params::Dict{Symbol,Float64}
          temperature::Float64
      end

      # 2. Protocol registration (other macros can query this!)
      TrackedArray.register_protocol!(CarPhysical,
          TrackingSpec(
              tracked = [:fleet => (Vector{Car}, (100,)),
                        :garage => (Matrix{Car}, (10, 5))],
              untracked = [:params, :temperature]
          )
      )

      # 3. Generated tracked type
      struct TrackedCarPhysical <: CuddleState
          _tracker::Tracker{PlaceKey}
          fleet::CuddleVector{Cuddle{Car,Tuple{Symbol,Int},PlaceKey}}
          garage::CuddleMatrix{Cuddle{Car,Tuple{Symbol,Int,Int},PlaceKey}}
          params::Dict{Symbol,Float64}
          temperature::Float64
      end

      # 4. Constructors
      # ... constructor implementations ...
  end

  # Other macro writers can then:
  tracking_info = TrackedArray.get_protocol(CarPhysical)
  # And build their own extensions

  Example Usage Patterns

  # Research/Prototyping: Just use the simple macro
  @tracked_state struct QuickModel
      population::Vector{Person}[10000]
      resources::Dict{String,Float64}
  end

  sim = TrackedQuickModel()
  # Everything just works!

  # Production: Can still access protocol for advanced features
  protocol = get_tracking_protocol(QuickModel)
  custom_tracking = modify_protocol(protocol) do p
      p.tracked[:population].history_size = 1000
      p.tracked[:population].compression = :lz4
  end

  # Create custom tracked version
  CustomTracked = generate_tracked_type(QuickModel, custom_tracking)

  This approach gives you:
  1. Simple things are simple: One macro for 90% of use cases
  2. Complex things are possible: Full protocol system underneath
  3. Extensible: Other macro writers can build on the protocol layer
  4. Progressive disclosure: Users can start simple and add complexity as needed


Recommendation: Hybrid Approach

  Implement Approach 2 as the primary interface with Approach 5 as syntactic sugar:

  # Core API (higher-order function)
  ThirdPartyState(
      entities = (Entity, 100),
      particles = (Particle, 50)
  )

  # Macro sugar for DSL builders  
  @tracked_state begin
      entities::Vector{Entity}[100]
      particles::Vector{Particle}[50]
  end

# Me, just me

What if when you access the vector, it returns both the member and the index of that member?
Then when you set a property on the member it also passes in the index.
OK, this is a kind of Proxy/view-based approach.

And there is the OCaml-style, where you do copy-on-write. That's essentially a large tree.

Or make a macro for the moement you read/write values.

## Instrument the fire! function

2. Cassette.jl-style Contextual Dispatch
  using Cassette

  Cassette.@context TrackingCtx

  # Intercept all getproperty calls within fire! functions
  function Cassette.overdub(ctx::TrackingCtx, ::typeof(getproperty), obj, field)
      record_read!(ctx.metadata, obj, field)
      Cassette.fallback(ctx, getproperty, obj, field)
  end

  # Execute fire! with tracking context
  fire_with_tracking!(physical, event) = Cassette.overdub(TrackingCtx(metadata=physical),
  fire!, physical, event)

  3. IRTools.jl for Compiler-level Instrumentation
  using IRTools

  # Transform fire! functions at IR level to inject tracking
  @dynamo function track_fire!(args...)
      ir = IR(args...)
      for (x, stmt) in ir
          if stmt.expr isa Expr && stmt.expr.head == :call
              # Inject tracking around property access
              insert_tracking_call!(ir, x, stmt)
          end
      end
      return ir
  end


# Crazy Dense Trackers

Ultra-Efficient Storage Options

  1. Dense Bitsets for Fixed Schema
  # If you know all possible PlaceKeys at compile time:
  struct BitsetTracker{N}
      changed::NTuple{N, UInt64}  # Pack bits directly in struct
      read::NTuple{N, UInt64}
  end

  # Example for 512 possible PlaceKeys:
  struct DenseTracker
      changed::NTuple{8, UInt64}  # 8 * 64 = 512 bits
      read::NTuple{8, UInt64}
  end

  # Set/check operations are just bit manipulation:
  @inline function mark_changed!(tracker, place_id::Int)
      word_idx = (place_id - 1) ÷ 64 + 1
      bit_idx = (place_id - 1) % 64
      word = tracker.changed[word_idx]
      tracker.changed = Base.setindex(tracker.changed, word | (1 << bit_idx), word_idx)
  end

  2. Sparse IntSet for Dynamic Schema
  # Julia's IntSet is highly optimized for sparse integer collections
  mutable struct SparseTracker
      changed::IntSet
      read::IntSet
  end

  # Extremely fast operations:
  push!(tracker.changed, place_key_id)
  place_key_id in tracker.changed

  3. Hybrid Approach with Tiered Storage
  struct TieredTracker
      # Fast path: first 64 most common PlaceKeys
      fast_changed::UInt64
      fast_read::UInt64

      # Slow path: overflow for rare PlaceKeys  
      overflow_changed::Union{Nothing, IntSet}
      overflow_read::Union{Nothing, IntSet}
  end

  4. Memory-Mapped Bitsets for Huge State Spaces
  struct MMapTracker
      changed::BitVector  # Memory-mapped to file
      read::BitVector     # Shared across processes
  end

  PlaceKey → Integer Mapping Strategy

  For maximum efficiency, PlaceKeys should map to dense integers:

  # Compile-time PlaceKey enumeration
  @enum PlaceKeyEnum begin
      AGENTS_1_AGE = 1
      AGENTS_1_POSITION = 2
      AGENTS_2_AGE = 3
      # ... etc
  end

  # Or dynamic mapping with perfect hashing
  struct PlaceKeyMap
      key_to_id::Dict{PlaceKey, Int32}  # PlaceKey → dense integer
      id_to_key::Vector{PlaceKey}       # Integer → PlaceKey  
      next_id::Ref{Int32}
  end

  Most Efficient Approach

  For absolute maximum efficiency:

  struct UltraTracker{N}
      # Store changed/read as packed bits in stack-allocated tuples
      changed_bits::NTuple{N, UInt64}
      read_bits::NTuple{N, UInt64}

      # Single allocation for PlaceKey mapping
      place_map::Vector{PlaceKey}  # id → PlaceKey lookup
  end

  # Operations are branchless bit manipulation:
  @inline mark_changed!(t, id) = set_bit!(t.changed_bits, id)
  @inline was_changed(t, id) = get_bit(t.changed_bits, id)
  @inline reset!(t) = fill_zero!(t.changed_bits, t.read_bits)
