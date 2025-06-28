using Profile
using Random
using TrackedArray
import TrackedArray.Original as Original
import TrackedArray.Observed as Observed
import TrackedArray.Doubles as Doubles
import TrackedArray.Dealer as Dealer
import TrackedArray.Secondary as Secondary

# Try to load ProfileView for flame graphs
const HAS_PROFILEVIEW = try
    using ProfileView
    using FileIO
    true
catch
    @warn "ProfileView not available. Install with: using Pkg; Pkg.add(\"ProfileView\")"
    false
end

# Initialize profiler with higher sampling frequency
Profile.init(n = 10^7, delay = 0.001)  # More buffer, 1ms delay

"""
Profile the random_writes function for a given implementation module.
"""
function profile_implementation(SUT::Module, name::String)
    println("\n" * "="^60)
    println("Profiling $name implementation")
    println("="^60)
    
    # Set up the same RNG and specs as benchmark
    rng = Random.Xoshiro(9876234982)
    
    # Create large specification (same as benchmark)
    spec_large = TrackedArray.random_specification(
        rng; min_arrays=10, max_arrays=10, min_fields=10, max_fields=10)
    
    # Create physical state
    counts = Dict(arr_name => rand(rng, 5:15) for (arr_name, _) in spec_large)
    physical_state = SUT.ConstructState(spec_large, counts)
    every_key = TrackedArray.all_keys(spec_large, physical_state)
    TrackedArray.initialize_physical!(spec_large, physical_state)
    
    println("Setup complete:")
    println("  Arrays: ", length(spec_large))
    println("  Total keys: ", length(every_key))
    println("  Physical state type: ", typeof(physical_state))
    
    # Define the random_writes function with more iterations for profiling
    function random_writes(every_key, physical, rng_seed)
        rng = Random.Xoshiro(rng_seed)
        for step_idx in 1:10000  # 100x more iterations than benchmark
            n_keys = rand(rng, 0:min(10, length(every_key)))
            TrackedArray.write_n(physical, every_key, n_keys, rng)
        end
    end
    
    # Warm up the function to avoid compilation overhead
    println("\nWarming up...")
    random_writes(every_key, physical_state, 12345)
    
    # Clear any existing profile data
    Profile.clear()
    
    # Profile the function
    println("\nProfiling...")
    @profile random_writes(every_key, physical_state, 12345)
    
    # Save profile data for later analysis
    filename = "$(lowercase(name))_profile.jlprof"
    println("\nSaving profile data to '$filename'...")
    open(filename, "w") do io
        Profile.print(io, format=:tree, sortedby=:count)
    end
    
    # Print summary statistics
    println("\nProfile summary:")
    println("  Total samples: ", Profile.len_data())
    println("  Non-zero samples: ", count(!iszero, Profile.fetch()))
    
    # Show top 5 hottest functions
    println("\nTop 5 hottest functions:")
    
    # Use Profile's built-in flat format for analysis
    io = IOBuffer()
    Profile.print(io, format=:flat, sortedby=:count, noisefloor=2)
    output = String(take!(io))
    
    # Parse the first few lines to show top functions
    lines = split(output, '\n')
    line_count = 0
    for line in lines
        if !isempty(line) && !startswith(line, "Overhead") && !startswith(line, "=")
            line_count += 1
            if line_count <= 5
                println("  $line_count. $line")
            else
                break
            end
        end
    end
    
    # Save profile data if ProfileView is available
    if HAS_PROFILEVIEW
        profile_data_filename = "$(lowercase(name))_profile_data.jlprof"
        println("\nSaving profile data to '$profile_data_filename'...")
        save(profile_data_filename, Profile.retrieve()...)
    end
    
    return nothing
end

# Run profiling for all implementations
function profile_all()
    implementations = [
        (Original, "Original"),
        (Observed, "Observed"),
        (Doubles, "Doubles"),
        (Dealer, "Dealer"),
        (Secondary, "Secondary")
    ]
    
    for (module_impl, name) in implementations
        profile_implementation(module_impl, name)
    end
    
    println("\n" * "="^60)
    println("All profiling complete!")
    println("Profile results saved to:")
    for (_, name) in implementations
        println("  - $(lowercase(name))_profile.jlprof")
    end
    println("="^60)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    profile_all()
end