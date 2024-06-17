mutable struct DynamicRelaxation <: AbstractTimeSolver
    n_steps::Int
    Δt::Float64
    Λ::Float64

    function DynamicRelaxation(; steps::Int, stepsize::Real=1.0,
                               damping_factor::Real=1.0)
        if steps ≤ 0
            msg = "`steps` should be larger than zero!\n"
            throw(ArgumentError(msg))
        end
        if stepsize ≤ 0
            msg = "`stepsize` should be larger than zero!\n"
            throw(ArgumentError(msg))
        end
        if damping_factor ≤ 0
            msg = "`damping_factor` should be larger than zero!\n"
            throw(ArgumentError(msg))
        end
        new(steps, stepsize, damping_factor)
    end
end

function init_time_solver!(dr::DynamicRelaxation, dh::AbstractDataHandler)
    dynamic_relaxation_check(dr)
    return nothing
end

function dynamic_relaxation_check(dr::DynamicRelaxation)
    if dr.n_steps < 0
        error("`n_steps` of DynamicRelaxation smaller than zero!\n")
    end
    if dr.Δt < 0
        error("`Δt` of DynamicRelaxation smaller than zero!\n")
    end
    if dr.Λ < 0
        error("`Λ` of DynamicRelaxation smaller than zero!\n")
    end
    return nothing
end

function solve!(dh::AbstractDataHandler, dr::DynamicRelaxation,
                options::AbstractOptions)
    export_reference_results(dh, options)
    Δt = dr.Δt
    init_mass!(dh, dr)
    if mpi_isroot()
        p = Progress(dr.n_steps; dt=1, desc="TIME INTEGRATION LOOP", color=:normal,
                     barlen=40, enabled=progress_bars())
    end
    for n in 1:dr.n_steps
        relaxation_timestep!(dh, options, Δt, n)
        mpi_isroot() && next!(p)
    end
    mpi_isroot() && finish!(p)
    return nothing
end

function init_mass!(dh::AbstractThreadsDataHandler, dr::DynamicRelaxation)
    @threads :static for chunk in dh.chunks
        _init_mass!(chunk, dr, chunk.paramsetup)
    end
    return nothing
end

function init_mass!(dh::AbstractMPIDataHandler, dr::DynamicRelaxation)
    _init_mass!(dh.chunk, dr, dh.chunk.paramsetup)
    return nothing
end

function _init_mass!(chunk::AbstractBodyChunk, dr::DynamicRelaxation,
                               params::AbstractPointParameters)
    mass = chunk.storage.mass
    for i in each_point_idx(chunk.ch)
        for j in 1:3
            mass[j, i] = dr.Λ * 6 * params.K * dr.Δt^2 / (1 / 3 * params.δ^2)
        end
    end
    return nothing
end

function _init_mass!(chunk::AbstractBodyChunk, dr::DynamicRelaxation,
                               paramsetup::AbstractParameterHandler)
    mass = chunk.storage.mass
    for i in each_point_idx(chunk.ch)
        params = get_params(chunk, i)
        for d in 1:3
            mass[d, i] = dr.Λ * 6 * params.K * dr.Δt^2 / (1 / 3 * params.δ^2)
        end
    end
    return nothing
end

function relaxation_timestep!(dh::AbstractThreadsDataHandler, options::AbstractOptions,
                              Δt::Float64, n::Int)
    t = n * Δt
    @threads :static for chunk_id in eachindex(dh.chunks)
        chunk = dh.chunks[chunk_id]
        apply_bcs!(chunk, t)
        update_disp_and_pos!(chunk, Δt)
    end
    @threads :static for chunk_id in eachindex(dh.chunks)
        exchange_loc_to_halo!(dh, chunk_id)
        calc_force_density!(dh.chunks[chunk_id])
    end
    @threads :static for chunk_id in eachindex(dh.chunks)
        exchange_halo_to_loc!(dh, chunk_id)
        chunk = dh.chunks[chunk_id]
        calc_damage!(chunk)
        cn = calc_damping(chunk, Δt)
        if n == 1
            relaxation_first_step!(chunk, Δt)
        else
            relaxation_step!(chunk, Δt, cn)
        end
        export_results(dh, options, chunk_id, n, t)
    end
    return nothing
end

function calc_damping(chunk::AbstractBodyChunk, Δt::Float64)
    s = chunk.storage
    cn1 = 0.0
    cn2 = 0.0
    for i in each_point_idx(chunk.ch), d in 1:3
        if s.velocity_half_old[d, i] != 0.0
            Δb_int = s.b_int[d, i] - s.b_int_old[d, i]
            temp = Δt * s.mass[d, i] * s.velocity_half_old[d, i]
            cn1 -= s.displacement[d, i]^2 * Δb_int / temp
        end
        cn2 += s.displacement[d, i]^2
    end
    if cn2 != 0.0
        if cn1 / cn2 > 0.0
            cn = 2.0 * sqrt(cn1 / cn2)
        else
            cn = 0.0
        end
    else
        cn = 0.0
    end
    if cn > 2.0
        cn = 1.9
    end
    return cn
end

function relaxation_first_step!(chunk::AbstractBodyChunk, Δt::Float64)
    s = chunk.storage
    for i in each_point_idx(chunk.ch), d in 1:3
        s.velocity_half[d, i] = 0.5 * Δt * (s.b_int[d, i] + s.b_ext[d, i]) / s.mass[d, i]
        relaxation_updates!(s, d, i)
    end
    return nothing
end

function relaxation_step!(chunk::AbstractBodyChunk, Δt::Float64, cn::Float64)
    s = chunk.storage
    for i in each_point_idx(chunk.ch), d in 1:3
        a = (s.b_int[d, i] + s.b_ext[d, i]) / s.mass[d, i]
        v½_old = s.velocity_half_old[d, i]
        s.velocity_half[d, i] = ((2 - cn * Δt) * v½_old + 2 * Δt * a) / (2 + cn * Δt)
        relaxation_updates!(s, d, i)
    end
    return nothing
end

function relaxation_updates!(s::AbstractStorage, d::Int, i::Int)
    s.velocity[d, i] = 0.5 * (s.velocity_half_old[d, i] + s.velocity_half[d, i])
    s.velocity_half_old[d, i] = s.velocity_half[d, i]
    s.b_int_old[d, i] = s.b_int[d, i]
    return nothing
end

function req_point_data_fields_timesolver(::Type{DynamicRelaxation})
    fields = (:position, :displacement, :velocity, :velocity_half, :velocity_half_old,
              :acceleration, :b_int, :b_int_old, :b_ext)
    return fields
end

function req_data_fields_timesolver(::Type{DynamicRelaxation})
    return ()
end

function log_timesolver(options::AbstractOptions, dr::DynamicRelaxation)
    msg = "DYNAMIC RELAXATION TIME SOLVER\n"
    msg *= log_qty("number of time steps", dr.n_steps)
    msg *= log_qty("relaxation time step size", dr.Δt)
    msg *= log_qty("damping factor", dr.Λ)
    msg *= log_qty("relaxation time", dr.n_steps * dr.Δt)
    log_it(options, msg)
    return nothing
end
