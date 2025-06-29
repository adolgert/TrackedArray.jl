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
