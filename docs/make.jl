using Documenter

# Note: Commenting out TrackedArray usage to allow docs to build independently
# using TrackedArray
# DocMeta.setdocmeta!(TrackedArray, :DocTestSetup, :(using TrackedArray); recursive=true)

makedocs(;
    authors="Andrew Dolgert <github@dolgert.com>",
    sitename="TrackedArray.jl",
    checkdocs=:none,
    doctest=false,
    format=Documenter.HTML(;
        canonical="https://adolgert.github.io/TrackedArray.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Implementations" => "implements.md",
        "Alternatives" => "alternatives.md",
    ],
)

deploydocs(;
    repo="github.com/adolgert/TrackedArray.jl",
    devbranch="main",
)
