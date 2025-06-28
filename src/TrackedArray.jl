module TrackedArray

# Define the overall interface and testing.
include("abstract.jl")

# Specific systems-under-test.
include("tracked.jl")
end
