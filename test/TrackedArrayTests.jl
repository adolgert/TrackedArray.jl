
module TrackedArrayTests
using TrackedArray
using ReTest

continuous_integration() = get(ENV, "CI", "false") == "true"

# Include test files directly at module level so @testset blocks are properly registered
include("test_tracked.jl")
include("test_observed.jl")
include("test_doubles.jl")
include("test_dealer.jl")
include("test_secondary.jl")
include("test_shared.jl")
include("test_contain.jl")
include("test_contain_optimized.jl")

retest(args...; kwargs...) = ReTest.retest(args...; kwargs...)

end
