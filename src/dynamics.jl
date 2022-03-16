struct Dynamics{T}
    val 
    jac
    hess
    ny::Int 
    num_state::Int 
    nu::Int
    nw::Int
    nj::Int
    nh::Int
    sp_jac::Vector{Vector{Int}}
    sp_hess::Vector{Vector{Int}}
    val_cache::Vector{T} 
    jac_cache::Vector{T}
    hess_cache::Vector{T}
end

function Dynamics(f::Function, ny::Int, num_state::Int, nu::Int; nw::Int=0, eval_hess=false)
    #TODO: option to load/save methods
    @variables y[1:ny], x[1:num_state], u[1:nu], w[1:nw] 
    val = f(y, x, u, w) 
    jac = Symbolics.sparsejacobian(val, [x; u; y]);
    val_func = eval(Symbolics.build_function(val, y, x, u, w)[2]);
    jac_func = eval(Symbolics.build_function(jac.nzval, y, x, u, w)[2]);
    nj = length(jac.nzval)
    sp_jac = [findnz(jac)[1:2]...]
    if eval_hess
        @variables λ[1:ny] 
        lag_con = dot(λ, val)
        hess = Symbolics.sparsehessian(lag_con, [x; u; y])
        hess_func = eval(Symbolics.build_function(hess.nzval, y, x, u, w, λ)[2])
        sp_hess = [findnz(hess)[1:2]...]
        nh = length(hess.nzval)
    else 
        hess_func = Expr(:null) 
        sp_hess = [Int[]]
        nh = 0
    end
  
    return Dynamics(val_func, jac_func, hess_func, ny, num_state, nu, nw, nj, nh,
        sp_jac, sp_hess, zeros(ny), zeros(nj), zeros(nh))
end

function Dynamics(g::Function, gz::Function, ny::Int, num_state::Int, nu::Int; nw::Int=0)  
    # jacobian function 
    nz = num_state + nu + ny
    jac_func = (nj, y, x, u, w) -> gz(reshape(view(nj, :), ny, nz), y, x, u, w)

    # number of Jacobian elements
    nj = ny * nz

    # Jacobian sparsity
    row = Int[]
    col = Int[]
    for j = 1:nz
        for i = 1:ny 
            push!(row, i) 
            push!(col, j)
        end
    end

    sp_jac = [row, col]
  
    # Hessian
    hess_func = Expr(:null) 
    sp_hess = [Int[]]
    nh = 0
  
    return Dynamics(g, jac_func, hess_func, ny, num_state, nu, nw, nj, nh,
        sp_jac, sp_hess, zeros(ny), zeros(nj), zeros(nh))
end

function eval_con!(c, idx, cons::Vector{Dynamics{T}}, x, u, w) where T
    for (t, con) in enumerate(cons)
        con.val(con.val_cache, x[t+1], x[t], u[t], w[t])
        @views c[idx[t]] .= con.val_cache
        fill!(con.val_cache, 0.0) # TODO: confirm this is necessary 
    end
end

function eval_jac!(j, idx, cons::Vector{Dynamics{T}}, x, u, w) where T
    for (t, con) in enumerate(cons) 
        con.jac(con.jac_cache, x[t+1], x[t], u[t], w[t])
        @views j[idx[t]] .= con.jac_cache
        fill!(con.jac_cache, 0.0) # TODO: confirm this is necessary
    end
end
isempty(ones(1))
function eval_hess_lag!(h, idx, cons::Vector{Dynamics{T}}, x, u, w, λ) where T
    for (t, con) in enumerate(cons) 
        if !isempty(con.hess_cache)
            con.hess(con.hess_cache, x[t+1], x[t], u[t], w[t], λ[t])
            @views h[idx[t]] .+= con.hess_cache
            fill!(con.hess_cache, 0.0) # TODO: confirm this is necessary
        end
    end
end

function sparsity_jacobian(cons::Vector{Dynamics{T}}, num_state::Vector{Int}, nu::Vector{Int}; row_shift=0) where T
    row = Int[]
    col = Int[]
    for (t, con) in enumerate(cons) 
        col_shift = (t > 1 ? (sum(num_state[1:t-1]) + sum(nu[1:t-1])) : 0)
        push!(row, (con.sp_jac[1] .+ row_shift)...) 
        push!(col, (con.sp_jac[2] .+ col_shift)...) 
        row_shift += con.ny
    end
    return collect(zip(row, col))
end

function sparsity_hessian(cons::Vector{Dynamics{T}}, num_state::Vector{Int}, nu::Vector{Int}) where T
    row = Int[]
    col = Int[]
    for (t, con) in enumerate(cons) 
        if !isempty(con.sp_hess[1])
            shift = (t > 1 ? (sum(num_state[1:t-1]) + sum(nu[1:t-1])) : 0)
            push!(row, (con.sp_hess[1] .+ shift)...) 
            push!(col, (con.sp_hess[2] .+ shift)...) 
        end
    end
    return collect(zip(row, col))
end

num_con(cons::Vector{Dynamics{T}}) where T = sum([con.ny for con in cons])
num_xuy(cons::Vector{Dynamics{T}}) where T = sum([con.num_state + con.nu for con in cons]) + cons[end].ny
num_jac(cons::Vector{Dynamics{T}}) where T = sum([con.nj for con in cons])

function constraint_indices(cons::Vector{Dynamics{T}}; shift=0) where T
    [collect(shift + (t > 1 ? sum([cons[s].ny for s = 1:(t-1)]) : 0) .+ (1:cons[t].ny)) for t = 1:length(cons)]
end 

function jacobian_indices(cons::Vector{Dynamics{T}}; shift=0) where T
    [collect(shift + (t > 1 ? sum([cons[s].nj for s = 1:(t-1)]) : 0) .+ (1:cons[t].nj)) for t = 1:length(cons)]
end

function hessian_indices(cons::Vector{Dynamics{T}}, key::Vector{Tuple{Int,Int}}, num_state::Vector{Int}, nu::Vector{Int}) where T
    idx = Vector{Int}[]
    for (t, con) in enumerate(cons) 
        if !isempty(con.sp_hess[1])
            shift = (t > 1 ? (sum(num_state[1:t-1]) + sum(nu[1:t-1])) : 0)
            row = collect(con.sp_hess[1] .+ shift)
            col = collect(con.sp_hess[2] .+ shift)
            rc = collect(zip(row, col))
            push!(idx, [findfirst(x -> x == i, key) for i in rc])
        end
    end
    return idx
end

function x_indices(cons::Vector{Dynamics{T}}) where T 
    [[collect((t > 1 ? sum([cons[s].num_state + cons[s].nu for s = 1:(t-1)]) : 0) .+ (1:cons[t].num_state)) for t = 1:length(cons)]..., 
        collect(sum([cons[s].num_state + cons[s].nu for s = 1:length(cons)]) .+ (1:cons[end].ny))]
end

function u_indices(cons::Vector{Dynamics{T}}) where T 
    [collect((t > 1 ? sum([cons[s].num_state + cons[s].nu for s = 1:(t-1)]) : 0) + cons[t].num_state .+ (1:cons[t].nu)) for t = 1:length(cons)]
end

function xu_indices(cons::Vector{Dynamics{T}}) where T 
    [[collect((t > 1 ? sum([cons[s].num_state + cons[s].nu for s = 1:(t-1)]) : 0) .+ (1:(+ cons[t].num_state + cons[t].nu))) for t = 1:length(cons)]..., 
        collect(sum([cons[s].num_state + cons[s].nu for s = 1:length(cons)]) .+ (1:cons[end].ny))]
end

function xuy_indices(cons::Vector{Dynamics{T}}) where T 
    [collect((t > 1 ? sum([cons[s].num_state + cons[s].nu for s = 1:(t-1)]) : 0) .+ (1:(+ cons[t].num_state + cons[t].nu + cons[t].ny))) for t = 1:length(cons)]
end

function dimensions(dyn::Vector{Dynamics{T}}; w=[0 for t = 1:(length(dyn) + 1)]) where T 
    x = [[d.num_state for d in dyn]..., dyn[end].ny]
    u = [[d.nu for d in dyn]..., 0]
    return x, u, w
end