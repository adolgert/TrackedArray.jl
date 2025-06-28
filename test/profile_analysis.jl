using Printf

"""
Analyze and compare profiling results from all implementations.
This script reads the profile summary from the console output and provides insights.
"""

# Profile data from the run
profile_data = Dict(
    "Original" => (samples=22174, nonzero=19514),
    "Observed" => (samples=6176, nonzero=5368),
    "Doubles" => (samples=338914, nonzero=295164),
    "Dealer" => (samples=5941, nonzero=5163),
    "Secondary" => (samples=6968, nonzero=6058)
)

# Calculate relative performance (lower is better)
min_samples = minimum(p.samples for p in values(profile_data))

println("TrackedArray Implementation Performance Analysis")
println("=" ^ 60)
println("\nProfile Summary (10,000 iterations of random_writes on large dataset):")
println("-" ^ 60)
println(@sprintf("%-12s %10s %10s %8s %s", "Implementation", "Samples", "Non-zero", "Relative", "Notes"))
println("-" ^ 60)

for (name, data) in sort(collect(profile_data), by=x->x[2].samples)
    relative = data.samples / min_samples
    note = if relative < 1.5
        "🟢 Excellent"
    elseif relative < 3.0
        "🟡 Good"
    elseif relative < 10.0
        "🟠 Moderate"
    else
        "🔴 Poor"
    end
    
    println(@sprintf("%-12s %10d %10d %8.2fx %s", name, data.samples, data.nonzero, relative, note))
end

println("\n" * "=" ^ 60)
println("\nDetailed Analysis:")
println("-" ^ 60)

println("\n1. Performance Rankings (best to worst):")
println("   1. Dealer     - 1.00x baseline (5,941 samples)")
println("   2. Observed   - 1.04x (6,176 samples)")
println("   3. Secondary  - 1.17x (6,968 samples)")
println("   4. Original   - 3.73x (22,174 samples)")
println("   5. Doubles    - 57.05x (338,914 samples)")

println("\n2. Key Observations:")

println("\n   a) Dealer (Hybrid Immutable) - FASTEST")
println("      - Uses immutable tracking state with structural sharing")
println("      - Minimal allocations due to functional update approach")
println("      - Bitfield compression reduces memory overhead")
println("      - invokelatest overhead is minimal compared to benefits")

println("\n   b) Observed (Notification-based) - EXCELLENT")
println("      - Push-based model reduces tracking overhead")
println("      - Elements notify containers on access")
println("      - Centralized tracking in physical state")
println("      - Dictionary operations still visible but manageable")

println("\n   c) Secondary (Arithmetic Registry) - VERY GOOD")
println("      - Pre-allocated BitVectors for tracking")
println("      - Fast arithmetic calculations for bit indices")
println("      - Higher upfront cost but efficient runtime")
println("      - Slightly slower than Dealer/Observed but still excellent")

println("\n   d) Original (Basic Tracking) - MODERATE")
println("      - Simple Set-based tracking per vector")
println("      - Higher overhead from Set operations")
println("      - No optimization for tracking patterns")
println("      - 3.7x slower than best implementations")

println("\n   e) Doubles (Bitfield in Elements) - POOR")
println("      - Tracking state stored in each element")
println("      - Massive overhead from individual element tracking")
println("      - Symbol operations and field access dominate profile")
println("      - 57x slower - not suitable for production use")

println("\n3. Architectural Insights:")

println("\n   - Centralized tracking (Dealer, Observed, Secondary) vastly")
println("     outperforms distributed tracking (Original, Doubles)")
println("   - Immutable/functional approaches (Dealer) can match or beat")
println("     mutable approaches with proper design")
println("   - Pre-computation (Secondary) trades memory for speed effectively")
println("   - Notification patterns (Observed) minimize unnecessary tracking")

println("\n4. Recommendations:")

println("\n   For production use:")
println("   - Use Dealer for best overall performance")
println("   - Use Observed if you prefer simpler mental model")
println("   - Use Secondary if you have memory to spare")
println("   - Avoid Doubles for any serious workload")

println("\n" * "=" ^ 60)