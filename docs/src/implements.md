# TrackedArray.jl Implementations

## Interface

TrackedArray.jl provides a common interface for tracking reads and writes to arrays of mutable structs. The core interface consists of:

### Creating a PhysicalState
```julia
physical = ConstructState(specification, counts)
```

### Accessing Values
- **Read**: `getproperty(getitem(getproperty(physical, :arraysymbol), index), :member)`
- **Write**: `setproperty!(getitem(getproperty(physical, :arraysymbol), index), :member, value)`

### Tracking Interface  
- `changed(physical)` - Returns an iterable of PlaceKey tuples `(array_symbol, index, member_symbol)` that were written
- `wasread(physical)` - Returns an iterable of PlaceKey tuples that were read
- `accept(physical)` - Clears memory of writes and reads
- `resetread(physical)` - Clears only read memory

## Benchmark Summary

Performance comparison from git hash e524770-dirty on 2025-07-02:

| Implementation | Small Random Writes | Small All Writes | Large Random Writes | Large All Writes | Notes |
|---|---|---|---|---|---|
| **Observed** | 0.15ms | 3.36ms | 0.28ms | 47.56ms | **Best overall performance** |
| **Secondary** | 0.19ms | 3.78ms | 0.29ms | 47.92ms | **Fastest with BitVectors** |
| **ThirdParty** | 0.20ms | 5.24ms | 0.32ms | 57.23ms | **Typed tracker references** |
| **Shared** | 0.20ms | 4.15ms | 0.28ms | 50.75ms | Shared tracker approach |
| **ContainOptimized** | 0.27ms | 7.82ms | 0.32ms | 49.20ms | Optimized Cuddle structs |
| **Original** | 0.60ms | 6.35ms | 1.62ms | 67.65ms | Baseline implementation |
| **Dealer** | 0.51ms | 12.48ms | 0.62ms | 111.47ms | High memory usage |
| **Doubles** | 2.11ms | 8.66ms | 15.11ms | 131.39ms | Per-field bit tracking |

*Memory usage ranges from ~140KB (best) to ~8MB (worst) for small tests, and from ~140KB to ~475MB for large tests.*

## Implementation History

1. **`src/tracked.jl`** (2025-06-28 06:55:07) - Original implementation using Set-based tracking in each element with `@tracked_struct` macro and container back-references.

2. **`src/observed.jl`** (2025-06-28 10:58:44) - Notification-based system where elements notify their container vectors, which notify a centralized physical state using Vector storage.

3. **`src/doubles.jl`** (2025-06-28 11:22:15) - Bit-field approach storing read/write bits directly in each struct field using `field_name_track` integers with bitwise operations.

4. **`src/dealer.jl`** (2025-06-28 11:47:37) - Immutable functional approach using `TrackingState` with Dict storage, `TrackedElement` wrappers, and structural sharing.

5. **`src/secondary.jl`** (2025-06-28 12:23:56) - "Arithmetic Registry" model using pre-allocated BitVectors and arithmetic calculations to map element field access to bit indices.

6. **`src/shared.jl`** (2025-06-29 07:28:44) - Shared tracker approach using `Cuddle` wrappers that encapsulate data with path information and a shared `Tracker{T}` instance.

7. **`src/contain.jl`** (2025-06-30 08:25:25) - Hybrid combining Shared and Observed concepts with `Cuddle` wrappers using function pointers instead of direct tracker references.

8. **`src/contain_optimized.jl`** (2025-06-30 08:32:02) - Optimized version of Contain eliminating closure allocations by storing tracker directly in `CuddleOpt` structs.

9. **`src/thirdparty.jl`** (2025-06-30 08:49:09) - Enhanced Observed-style implementation with typed tracker references and improved type safety in `ObservedVector{T,TK}`.