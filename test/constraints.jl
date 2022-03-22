@testset "Constraints" begin 
    T = 5
    num_state = 2
    num_action = 1 
    num_parameter = 0
    dim_x = [num_state for t = 1:T] 
    dim_u = [num_action for t = 1:T-1]
    dim_w = [num_parameter for t = 1:T]
    x = [rand(dim_x[t]) for t = 1:T] 
    u = [[rand(dim_u[t]) for t = 1:T-1]..., zeros(0)]
    w = [rand(dim_w[t]) for t = 1:T]

    ct = (x, u, w) -> [-ones(num_state) - x; x - ones(num_state)]
    cT = (x, u, w) -> x

    cont = Constraint(ct, num_state, num_action, num_parameter=num_parameter, indices_inequality=collect(1:2num_state))
    conT = Constraint(cT, num_state, 0, num_parameter=0)

    constraints = [[cont for t = 1:T-1]..., conT]
    nc = DTO.num_constraint(constraints)
    nj = DTO.num_jacobian(constraints)
    idx_c = DTO.constraint_indices(constraints)
    idx_j = DTO.jacobian_indices(constraints)
    c = zeros(nc) 
    j = zeros(nj)
    cont.evaluate(c[idx_c[1]], x[1], u[1], w[1])
    conT.evaluate(c[idx_c[T]], x[T], u[T], w[T])

    DTO.constraints!(c, idx_c, constraints, x, u, w)
    # info = @benchmark DTO.constraints!($c, $idx_c, $constraints, $x, $u, $w)

    @test norm(c - vcat([ct(x[t], u[t], w[t]) for t = 1:T-1]..., cT(x[T], u[T], w[T]))) < 1.0e-8
    DTO.jacobian!(j, idx_j, constraints, x, u, w)
    # info = @benchmark DTO.jacobian!($j, $idx_j, $constraints, $x, $u, $w)

    dct = [-I zeros(num_state, num_action); I zeros(num_state, num_action)]
    dcT = Diagonal(ones(num_state))
    dc = cat([dct for t = 1:T-1]..., dcT, dims=(1,2))
    sp = DTO.sparsity_jacobian(constraints, dim_x, dim_u) 
    j_dense = zeros(nc, sum(dim_x) + sum(dim_u)) 
    for (i, v) in enumerate(sp)
        j_dense[v[1], v[2]] = j[i]
    end
    @test norm(j_dense - dc) < 1.0e-8
end