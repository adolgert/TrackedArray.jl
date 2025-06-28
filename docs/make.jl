using TrackedArray
using Documenter

DocMeta.setdocmeta!(TrackedArray, :DocTestSetup, :(using TrackedArray); recursive=true)

makedocs(;
    modules=[TrackedArray],
    authors="Andrew Dolgert <github@dolgert.com>",
    sitename="TrackedArray.jl",
    format=Documenter.HTML(;
        canonical="https://adolgert.github.io/TrackedArray.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/adolgert/TrackedArray.jl",
    devbranch="main",
)
