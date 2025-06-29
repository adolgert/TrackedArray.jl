module TrackedArray

# Define the overall interface and testing.
include("abstract.jl")

# Specific systems-under-test.
include("tracked.jl")
include("observed.jl")
include("doubles.jl")
include("dealer.jl")
include("secondary.jl")
include("shared.jl")
end
