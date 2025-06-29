using ArgParse
using BenchmarkTools
using Random

using TrackedArray
import TrackedArray.Original as Original
import TrackedArray.Observed as Observed
import TrackedArray.Doubles as Doubles
import TrackedArray.Dealer as Dealer
import TrackedArray.Secondary as Secondary
import TrackedArray.Shared as Shared


function random_writes(every_key, physical, rng_seed)
    rng = Random.Xoshiro(rng_seed)
    for step_idx in 1:100
        n_keys = rand(rng, 0:min(10, length(every_key)))
        result = write_n(physical, every_key, n_keys, rng)
    end
end

function all_writes(every_key, physical, rng_seed)
    rng = Random.Xoshiro(rng_seed)
    for step_idx in 1:100
        result = write_n(physical, every_key, length(every_key), rng)
    end
end

function random_reads(every_key, physical, rng_seed)
    rng = Random.Xoshiro(rng_seed)
    for step_idx in 1:100
        n_keys = rand(rng, 0:min(10, length(every_key)))
        result = read_n(physical, every_key, n_keys, rng)
    end
end

function all_reads(every_key, physical, rng_seed)
    rng = Random.Xoshiro(rng_seed)
    for step_idx in 1:100
        result = read_n(physical, every_key, length(every_key), rng)
    end
end


function make_specifications(rng)
    specs = Dict()
    specs[:small] = random_specification(
        rng; min_arrays=3, max_arrays=3, min_fields=5, max_fields=5)
    specs[:large] = random_specification(
        rng; min_arrays=10, max_arrays=10, min_fields=10, max_fields=10)
    return specs
end


function single_benchmark(SUT::Module, specs, rng)
    all_benches = [
        ("random_writes", random_writes),
        ("all_writes", all_writes), 
        ("random_reads", random_reads),
        ("all_reads", all_reads)
    ]
    
    println("\n=== Benchmarking $(SUT) ===")
    
    for spec_size in [:small, :large]
        specification = specs[spec_size]
        
        # Create physical state for this specification
        counts = Dict(arr_name => rand(rng, 5:15) for (arr_name, _) in specification)
        physical_state = SUT.ConstructState(specification, counts)
        every_key = all_keys(specification, physical_state)
        initialize_physical!(specification, physical_state)
        
        println("\n--- Spec size: $spec_size ($(length(every_key)) keys) ---")
        
        for (bench_name, bench_func) in all_benches
            # Set up benchmark with interpolated variables
            result = @benchmark $bench_func($every_key, $physical_state, 12345) samples=5 seconds=2
            
            # Extract key metrics
            min_time = minimum(result).time / 1e6  # Convert to milliseconds
            median_time = median(result).time / 1e6
            max_time = maximum(result).time / 1e6
            allocations = median(result).allocs
            memory = median(result).memory
            
            # Print formatted results
            println("  $bench_name:")
            println("    Time: $(round(min_time, digits=2))ms - $(round(median_time, digits=2))ms - $(round(max_time, digits=2))ms (min-median-max)")
            println("    Memory: $(Base.format_bytes(memory)) ($(allocations) allocs)")
        end
    end
end


function benchmark_all(sutlist::Vector{Module})
    rng = Random.Xoshiro(9876234982)
    specs = make_specifications(rng)
    for sut in sutlist
        single_benchmark(sut, specs, rng)
    end
end


function local_parse_args()
    settings = ArgParseSettings(
        description = "Benchmark TrackedArray implementations",
        prog = "benchmark.jl"
    )

    @add_arg_table! settings begin
        "module"
            help = "Name of specific module to test (e.g., 'Original')"
            arg_type = String
            required = false
            default = nothing
    end

    return parse_args(settings)
end


function get_module_from_name(module_name::String)
    if module_name == "Original"
        return Original
    elseif module_name == "Observed"
        return Observed
    elseif module_name == "Doubles"
        return Doubles
    elseif module_name == "Dealer"
        return Dealer
    elseif module_name == "Secondary"
        return Secondary
    elseif module_name == "Shared"
        return Shared
    else
        error("Unknown module: $module_name. Available modules: Original, Observed, Doubles, Dealer, Secondary, Shared")
    end
end


function main()
    args = local_parse_args()
    
    if args["module"] !== nothing
        # Test specific module
        module_to_test = get_module_from_name(args["module"])
        println("Benchmarking module: $(args["module"])")
        benchmark_all([module_to_test])
    else
        # Test all available modules
        println("Benchmarking all modules")
        all_modules = [Original, Observed, Doubles, Dealer, Secondary, Shared]
        benchmark_all(all_modules)
    end
end


# Run main if this file is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

