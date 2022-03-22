# PREAMBLE

# PKG_SETUP

# ## Setup

using LinearAlgebra
using Plots
using DirectTrajectoryOptimization 

# ## horizon 
T = 101 

# ## cartpole 
num_state = 4 
num_action = 1 
num_parameter = 0 

function cartpole(x, u, w)
    mc = 1.0 
    mp = 0.2 
    l = 0.5 
    g = 9.81 

    q = x[1:2]
    qd = x[3:4]

    s = sin(q[2])
    c = cos(q[2])

    H = [mc+mp mp*l*c; mp*l*c mp*l^2]
    Hinv = 1.0 / (H[1, 1] * H[2, 2] - H[1, 2] * H[2, 1]) * [H[2, 2] -H[1, 2]; -H[2, 1] H[1, 2]]
    C = [0 -mp*qd[2]*l*s; 0 0]
    G = [0, mp*g*l*s]
    B = [1, 0]

    qdd = -Hinv * (C*qd + G - B*u[1])

    return [qd; qdd]
end

function rk3_explicit(y, x, u, w)
    h = 0.05 # timestep 

    k1 = h * cartpole(x, u, w)
    k2 = h * cartpole(x + 0.5 * k1, u, w)
    k3 = h * cartpole(x - k1 + 2.0 * k2, u, w)
    
    return y - (x + (k1 + 4.0 * k2 + k3) / 6.0)
end

# ## model
dt = Dynamics(rk3_explicit, num_state, num_state, num_action, num_parameter=num_parameter)
dyn = [dt for t = 1:T-1] 

# ## initialization
x1 = [0.0; 0.0; 0.0; 0.0] 
xT = [0.0; π; 0.0; 0.0] 

# ## objective 
Q = 1.0e-2 
R = 1.0e-1 
Qf = 1.0e2 

ot = (x, u, w) -> 0.5 * Q * dot(x, x) + 0.5 * R * dot(u, u)
oT = (x, u, w) -> 0.5 * Qf * dot(x, x)
ct = Cost(ot, num_state, num_action, 
    num_parameter=num_parameter)
cT = Cost(oT, num_state, 0, 
    num_parameter=num_parameter)
obj = [[ct for t = 1:T-1]..., cT]

# ## constraints
u_bnd = 3.0
bnd1 = Bound(num_state, num_action, 
    state_lower=x1, 
    state_upper=x1, 
    action_lower=[-u_bnd], 
    action_upper=[u_bnd])
bndt = Bound(num_state, num_action,
    action_lower=[-u_bnd], 
    action_upper=[u_bnd])
bndT = Bound(num_state, 0, 
    state_lower=xT, 
    state_upper=xT)
bounds = [bnd1, [bndt for t = 2:T-1]..., bndT]

goal(x, u, w) = x - xT
cons = [[Constraint() for t = 1:T-1]..., Constraint(goal, num_state, 0)]

# ## problem 
p = Solver(dyn, obj, cons, bounds,
    options=Options{Float64}())

# ## initialize
x_interpolation = linear_interpolation(x1, xT, T)
u_guess = [0.01 * ones(num_action) for t = 1:T-1]

initialize_states!(p, x_interpolation)
initialize_controls!(p, u_guess)

# ## solve
@time solve!(p)

# ## solution
x_sol, u_sol = get_trajectory(p)

@show x_sol[1]
@show x_sol[T]

# ## state
plot(hcat(x_sol...)')

# ## control
plot(hcat(u_sol[1:end-1]..., u_sol[end-1])', linetype = :steppost)