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

Performance comparison from git hash b464082 on 2025-07-02:

| Implementation | Small Random Writes | Small All Writes | Large Random Writes | Large All Writes | Notes |
|---|---|---|---|---|---|
| **Observed** | 0.17ms | 4.13ms | 0.28ms | 46.76ms | **Best overall performance** |
| **Secondary** | 0.16ms | 3.27ms | 0.28ms | 45.55ms | **Fastest, uses BitVectors** |
| **Original** | 0.58ms | 6.05ms | 1.69ms | 68.28ms | Baseline implementation |
| **Shared** | 0.18ms | 3.92ms | 0.30ms | 50.41ms | Shared tracker approach |
| **Doubles** | 2.04ms | 8.00ms | 15.42ms | 129.50ms | Per-field bit tracking |
| **Dealer** | 0.52ms | 12.96ms | 0.60ms | 103.68ms | High memory usage |

*Memory usage ranges from ~160KB (best) to ~8MB (worst) for small tests, and from ~140KB to ~470MB for large tests.*

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