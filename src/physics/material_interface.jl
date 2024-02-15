
#---- mandatory interface functions ----#

function point_param_type(mat::AbstractMaterial)
    throw(MethodError(point_param_type, mat))
end

function allowed_material_kwargs(mat::AbstractMaterial)
    throw(MethodError(allowed_material_kwargs, mat))
end

function get_point_params(mat::AbstractMaterial, ::Dict{Symbol,Any})
    throw(MethodError(get_point_params, mat))
end

function discretization_type(mat::AbstractMaterial)
    throw(MethodError(discretization_type, mat))
end

function storage_type(mat::AbstractMaterial)
    throw(MethodError(storage_type, mat))
end

#---- optional interface functions ----#

@inline function default_export_fields(::Type{M}) where {M<:AbstractMaterial}
    return (:displacement, :damage)
end
