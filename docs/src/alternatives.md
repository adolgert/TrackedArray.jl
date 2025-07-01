# Alternative Approaches for Dynamic Dependency Tracking

## Goals

TrackedArray.jl aims to enable efficient continuous-time simulation by automatically discovering dependencies between events and state variables. The core requirements are:

- **Dynamic dependency discovery**: Events declare dependencies through actual data access patterns, not pre-wired graphs
- **Fine-grained tracking**: Track reads/writes at the individual field level within mutable structs
- **Container flexibility**: Support vectors and dictionaries of both mutable and immutable objects
- **Runtime efficiency**: Minimal overhead during simulation execution
- **Container resizing**: Handle dynamic addition/removal of elements

## History

**Generalized Stochastic Petri Nets (GSPN)** represented the first generation of dependency-aware simulation. GSPNs required explicit dependency graphs between Places and Transitions, making simulation logic clear but requiring complex upfront "wiring." This approach scaled poorly and obscured simulation choices within graph topology.

**Rule-based simulation engines** emerged as the second generation, using declarative logic systems (Datalog, Prolog, production rules) to automatically infer dependencies. Rules like `enabled(T) :- place(P), marking(P,N), N>0, depends(T,P)` promised automatic dependency discovery, but suffered from:
- Heavy external dependencies on rule engines
- Performance overhead from rule evaluation
- Poor integration with host languages
- Limited expressiveness for continuous-time stochastic processes

**TrackedArray.jl** represents a third-generation approach: automatic dependency discovery through execution tracing in the host language, avoiding both explicit wiring and external rule engines.

## Current Limitations

Analysis of existing TrackedArray.jl implementations reveals fundamental architectural constraints:

**Container Rigidity**: All implementations assume fixed-size containers at construction. Vector resizing (`push!`, `pop!`, `deleteat!`) breaks index-based tracking systems, and dictionary key addition/removal is not properly supported.

**Intrusive Data Structures**: Elements must contain path information (container indices, keys) to enable tracking. This creates tight coupling between elements and their containers, preventing reuse across different container types.

**Mixed Object Type Limitations**: Current focus on mutable struct field modifications provides no mechanism for tracking immutable object replacement within containers.

**Memory Efficiency**: Benchmark data shows 10-20x performance degradation in some approaches (Doubles: 286K+ allocations, Dealer: 475MB memory usage) due to per-element tracking overhead.

## Alternative Approaches

### Function Instrumentation

**Cassette.jl/IRTools.jl Approach**: Transform `fire!` functions to inject tracking calls around state access operations.

```julia
Cassette.@context TrackingCtx
function Cassette.overdub(ctx::TrackingCtx, ::typeof(getproperty), obj, field)
    record_read!(ctx.metadata, obj, field)
    Cassette.fallback(ctx, getproperty, obj, field)
end
```

**Advantages**: Non-intrusive data structures, automatic dependency discovery, works with arbitrary access patterns.

**Critical Limitation**: Multi-step access operations (`physical.agents[5].age += 1`) require tracking through complex call chains. The three-step operation (getproperty → getindex → getproperty/setproperty!) necessitates instrumenting every function that might be called, creating a transitive closure problem. Compound operators (`+=`, `*=`), broadcast operations, and function call boundaries exponentially increase instrumentation complexity.

### Proxy/View-Based Tracking

**Path-Carrying Proxies**: Return enriched objects that know their location in the state hierarchy.

```julia
struct ElementProxy{T}
    element::T
    path::Tuple{Symbol, Int}  # (:agents, 5)
end

# Usage: physical.agents[5] returns ElementProxy, not raw element
```

**Advantages**: Non-intrusive elements, automatic path construction, precise tracking without instrumentation complexity.

**Disadvantages**: Significant memory overhead (every access creates proxy objects), type system complexity (all operations must handle proxy types), poor ergonomics (users see proxy types instead of raw values).

### Ultra-Efficient Storage

**Dense Bitset Tracking**: Store changed/read state as packed bits for maximum efficiency.

```julia
struct UltraTracker{N}
    changed_bits::NTuple{N, UInt64}  # Stack-allocated bit arrays
    read_bits::NTuple{N, UInt64}
end

# 8 bytes per 64 PlaceKeys, branchless bit manipulation
@inline mark_changed!(t, id) = set_bit!(t.changed_bits, id)
```

**Performance Characteristics**: 1-2 CPU cycles per tracking operation, zero allocations, cache-friendly sequential operations.

**Requirement**: PlaceKeys must map to dense integers, determined at compile-time or through perfect hashing schemes.

### Macro-Based Access Transformation

**Syntactic Transformation**: Transform access expressions into explicit tracking + access pairs.

```julia
@track physical physical.agents[5].age += 1
# Expands to:
# record_read!(physical.tracker, AGENTS_5_AGE)
# record_write!(physical.tracker, AGENTS_5_AGE) 
# physical.agents[5].age += 1
```

**Fundamental Limitation**: **Data flow analysis problem**. Macros operate at syntax level but dependency tracking requires semantic analysis:

```julia
velocity = physical.agents[i].velocity    # Tracked: (:agents, i, :velocity)
physical.agents[j].position += velocity   # CANNOT track: velocity dependency lost
```

Intermediate variables, control flow, function boundaries, and aliasing make comprehensive tracking impossible through pure syntactic transformation.

### Copy-on-Write Persistent Structures

**Structural Sharing**: Avoid mutation entirely, track changes through persistent data structure modifications.

**Disadvantages**: High memory overhead, doesn't align with simulation patterns requiring in-place updates, poor performance for frequent small modifications.

## Fundamental Trade-offs

The analysis reveals three core tensions:

**Expressiveness vs. Efficiency**: More flexible data structures require more complex tracking mechanisms. Ultra-efficient approaches (bitsets, intrusive tracking) constrain user expressiveness.

**Non-intrusion vs. Performance**: Approaches that avoid modifying user data structures (instrumentation, proxies) incur significant runtime overhead or implementation complexity.

**Static vs. Dynamic Analysis**: Compile-time optimization opportunities (macro transformation, dense PlaceKey mapping) are limited by runtime data flow patterns that cannot be statically determined.

**The Core Dilemma**: Precise dependency tracking fundamentally requires either intrusive data structures OR comprehensive program analysis. The current TrackedArray.jl approach chooses intrusion for performance, accepting constraints on flexibility and composability.

No approach eliminates all limitations - each represents a different point in the design space trading off performance, flexibility, and implementation complexity.