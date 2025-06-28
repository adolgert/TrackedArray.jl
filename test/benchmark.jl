using ArgParse
using BenchmarkTools
using Random

using TrackedArray
import TrackedArray.Original as Original


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
    all_benches = [random_writes, all_writes, random_reads, all_reads]
    for spec_size in [:small, :large], benchmark in all_benches
        # benchmark here.
        # print benchmark result.
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
    else
        error("Unknown module: $module_name. Available modules: Original")
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
        all_modules = [Original]
        benchmark_all(all_modules)
    end
end


# Run main if this file is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

