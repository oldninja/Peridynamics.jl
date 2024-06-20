"""
    MultibodySetup(bodies)

Setup for a peridynamic simulation with multiple bodies

# Arguments

- `bodies::Dict{Symbol,Body{M,P}}`:

# Throws

- Error if less than 2 bodies are defined
- Error if defined bodies have different material types

# Example

---

!!! warning "Internal use only"
    Please note that the fields are intended for internal use only. They are *not* part of
    the public API of Peridynamics.jl, and thus can be altered (or removed) at any time
    without it being considered a breaking change.

```julia
MultibodySetup{Material,PointParameters}
```

# Type Parameters

- `Material <: AbstractMaterial`: Type of the specified material model
- `PointParameters <: AbstractPointParameters`: Type of the point parameters

# Fields

- `bodies::Dict{Symbol,Body{M,P}}`:
- `srf_contacts::Vector{ShortRangeForceContact}`:

TODO
"""
struct MultibodySetup{B} <: AbstractMultibodySetup
    bodies::B
    body_names::Vector{Symbol}
    body_idxs::Dict{Symbol,Int}
    srf_contacts::Vector{ShortRangeForceContact}
end

function MultibodySetup(bodies_dict::Dict{Symbol,B}) where {B<:AbstractBody}
    n_bodies = length(keys(bodies_dict))
    if n_bodies < 2
        msg = "not enough bodies given!\n"
        msg *= "Please specify 2 or more!\n"
        throw(ArgumentError(msg))
    end
    bodies = Tuple(body for body in values(bodies_dict))
    body_names = [name for name in keys(bodies_dict)]
    body_idxs = Dict{Symbol,Int}()
    for (i, name) in enumerate(body_names)
        body_idxs[name] = i
    end
    srf_contacts = Vector{ShortRangeForceContact}()
    return MultibodySetup(bodies, body_names, body_idxs, srf_contacts)
end

MultibodySetup(body_pairs...) = MultibodySetup(Dict(body_pairs...))

function check_if_bodyname_is_defined(ms::AbstractMultibodySetup, name::Symbol)
    if !haskey(ms.body_idxs, name)
        throw(ArgumentError("there is no body with name $(name)!"))
    end
    return nothing
end

@inline get_body(ms::AbstractMultibodySetup, name::Symbol) = ms.bodies[ms.body_idxs[name]]
@inline get_body(ms::AbstractMultibodySetup, idx::Int) = ms.bodies[idx]
@inline get_body_name(ms::AbstractMultibodySetup, idx::Int) = string(ms.body_names[idx])

@inline each_body(ms::AbstractMultibodySetup) = ms.bodies
@inline each_body_idx(ms::AbstractMultibodySetup) = eachindex(ms.bodies)
@inline each_body_name(ms::AbstractMultibodySetup) = ms.body_names

function pre_submission_check(ms::AbstractMultibodySetup)
    if mpi_run()
        @mpiroot begin
            @error "Multibody simulations with MPI are not yet implemented!\n"
            MPI.Abort(mpi_comm(), 1)
        end
        MPI.Barrier(mpi_comm())
    end

    #TODO: check if everything is defined for job submission!
    return nothing
end

@inline function storage_type(ms::AbstractMultibodySetup, ts::AbstractTimeSolver)
    return storage_type(first(values(ms.bodies)).mat, ts)
end

function log_spatial_setup(options::AbstractOptions, ms::MultibodySetup)
    for body_idx in each_body_idx(ms)
        body = get_body(ms, body_idx)
        name = get_body_name(ms, body_idx)
        log_spatial_setup(options, body; bodyname=name)
    end
    return nothing
end
