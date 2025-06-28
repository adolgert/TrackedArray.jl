using Profile
using Random
using TrackedArray
using ProfileView
import TrackedArray.Observed as Observed

# Try to load FileIO for saving profile data
const HAS_FILEIO = try
    using FileIO
    true
catch
    @warn "FileIO not available. Install with: using Pkg; Pkg.add(\"FileIO\") to save profile data"
    false
end

# Initialize profiler with higher sampling frequency
Profile.init(n = 10^7, delay = 0.001)  # More buffer, 1ms delay

"""
Profile the random_writes function for the Observed implementation with large dataset.
This focuses on the actual tracking operations, not the construction time.
"""
function profile_observed_random_writes()
    # Set up the same RNG and specs as benchmark
    rng = Random.Xoshiro(9876234982)
    
    # Create large specification (same as benchmark)
    spec_large = TrackedArray.random_specification(
        rng; min_arrays=10, max_arrays=10, min_fields=10, max_fields=10)
    
    # Create physical state
    counts = Dict(arr_name => rand(rng, 5:15) for (arr_name, _) in spec_large)
    physical_state = Observed.ConstructState(spec_large, counts)
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
    
    # Print profile results
    println("\nProfile results:")
    Profile.print(format=:tree, sortedby=:count)
    
    # Alternative: Print flat profile
    println("\n\nFlat profile (top 20 functions by count):")
    Profile.print(format=:flat, sortedby=:count, maxdepth=20)
    
    # Save profile data for later analysis if needed
    println("\nSaving profile data to 'observed_profile.jlprof'...")
    open("observed_profile.jlprof", "w") do io
        Profile.print(io, format=:tree, sortedby=:count)
    end
    
    # Additional analysis
    println("\nProfile summary:")
    println("  Total samples: ", Profile.len_data())
    println("  Non-zero samples: ", count(!iszero, Profile.fetch()))
    
    # Show hottest functions
    println("\n\nHottest functions (with significant samples):")
    # Use Profile's built-in flat format to extract top functions
    io = IOBuffer()
    Profile.print(io, format=:flat, sortedby=:count, noisefloor=2, maxdepth=20)
    output = String(take!(io))
    
    # Parse and display top functions
    lines = split(output, '\n')
    line_count = 0
    for line in lines
        if !isempty(line) && !startswith(line, "Count") && !startswith(line, "=") && 
           !startswith(line, "Total") && contains(line, "TrackedArray")
            line_count += 1
            if line_count <= 10
                println("  $line_count. $line")
            else
                break
            end
        end
    end
    
    # Generate a flame graph if ProfileView is available
    println("\nGenerating flame graph...")
    
    # Save profile data in .jlprof format for later viewing
    if HAS_FILEIO
        println("Saving profile data to 'observed_profile_data.jlprof'...")
        save("observed_profile_data.jlprof", Profile.retrieve()...)
    end
    
    # Create and display the flame graph
    fg = ProfileView.view()
    
    # Instructions for viewing
    println("\nFlame graph window opened.")
    println("\nTo save as an image:")
    println("  - Use the save icon in the ProfileView toolbar")
    println("  - Or install ProfileSVG.jl for programmatic SVG export")
    println("\nTo keep the window open after script ends:")
    println("  julia -i --project=. test/profile.jl")
    println("\nTo reload saved profile data later:")
    println("  using ProfileView, FileIO")
    println("  data, lidict = load(\"observed_profile_data.jlprof\")")
    println("  ProfileView.view(data; lidict=lidict)")
    
    return nothing
end

# Run the profiling if this file is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    profile_observed_random_writes()
end
