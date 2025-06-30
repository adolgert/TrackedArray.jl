# TrackedArray

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://adolgert.github.io/TrackedArray.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://adolgert.github.io/TrackedArray.jl/dev/)
[![Build Status](https://github.com/adolgert/TrackedArray.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/adolgert/TrackedArray.jl/actions/workflows/CI.yml?query=branch%3Amain)

We can NOT save the pointer to the owning struct.

 * getproperty() on the main struct returns a type that has both the array and a pointer to the appropriate vectors to update.
 * propagate that vector list to the moment the element is set or getted.
